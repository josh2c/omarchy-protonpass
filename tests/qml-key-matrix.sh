#!/usr/bin/env bash
# Presses every keyboard binding in both focus contexts and prints what the
# panel did, one line per case. Diff two runs -- before and after a key-handling
# change -- to prove the behaviour matrix is unchanged.
#
#   tests/qml-key-matrix.sh before.txt
#   git stash && tests/qml-key-matrix.sh after.txt && git stash pop
#   diff before.txt after.txt
#
# Set MATRIX_KEYBINDS to exercise a user remap, e.g.
#   MATRIX_KEYBINDS='ctrl+shift+c:copy-password,j:refresh' tests/qml-key-matrix.sh
#
# The keys are real compositor events, not synthesised QML calls, so the whole
# path -- Keys.onPressed wiring, chord parsing, focus transfer -- is covered.
# They are delivered inside a throwaway nested Hyprland on its own Wayland
# display, so nothing can be typed into the developer's own session.
#
# Requires quickshell, wtype and Hyprland. Skips cleanly when any is missing.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-/dev/stdout}

for tool in qs wtype Hyprland; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "key matrix skipped ($tool not installed)"
    exit 0
  fi
done
SHELL_TREE=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if [[ ! -d $SHELL_TREE/Ui ]]; then
  echo "key matrix skipped (Omarchy shell tree not found at $SHELL_TREE)"
  exit 0
fi

# shellcheck source=tests/lib-nested-display.sh
. "$(dirname "$0")/lib-nested-display.sh"

sandbox=$(mktemp -d)
trap 'stop_nested_display; rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/cfg/plugin" "$sandbox/state"
cp -r "$SHELL_TREE/Commons" "$SHELL_TREE/Ui" "$SHELL_TREE/services" "$sandbox/cfg/"
cp Panel.qml Service.qml Keybinds.js "$sandbox/cfg/plugin/"
cp tests/key-matrix-harness.qml "$sandbox/cfg/harness.qml"

# The stub helper records what it was asked to do and then never answers, so
# the panel state the harness reads back is the state the keypress left behind.
cat >"$sandbox/silent-helper" <<'HELPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MATRIX_LOG"
printf '%s\n' "$$" >>"$MATRIX_PIDS"
sleep 120
HELPER
chmod +x "$sandbox/silent-helper"
: >"$sandbox/helper.log"
: >"$sandbox/helper.pids"

start_nested_display "$sandbox" || exit 1

out=$(env WAYLAND_DISPLAY="$NESTED_DISPLAY" QT_QPA_PLATFORM=wayland \
  XDG_STATE_HOME="$sandbox/state" \
  MATRIX_KEYBINDS="${MATRIX_KEYBINDS:-}" MATRIX_LOG="$sandbox/helper.log" MATRIX_PIDS="$sandbox/helper.pids" \
  OMARCHY_PROTONPASS_HELPER="$sandbox/silent-helper" \
  timeout 180 qs -p "$sandbox/cfg/harness.qml" 2>&1 || true)

if grep -q "MATRIX-SETUP-FAILED" <<<"$out"; then
  echo "FAIL: panel never took focus in the nested compositor" >&2
  exit 1
fi
if ! grep -q "MATRIX-DONE" <<<"$out"; then
  echo "FAIL: key matrix did not complete" >&2
  sed -n '1,40p' <<<"$out" >&2
  exit 1
fi
if grep -q "INPUT-UNRELIABLE" <<<"$out"; then
  echo "FAIL: the compositor kept dropping modifiers -- rerun" >&2
  grep "INPUT-UNRELIABLE" <<<"$out" >&2
  exit 1
fi
if grep -q "FOCUS-LOST" <<<"$out"; then
  echo "FAIL: panel lost focus mid-run -- rerun" >&2
  grep "FOCUS-LOST" <<<"$out" >&2
  exit 1
fi

sed -n 's/^.*DEBUG.*qml.*: \(CASE \)/\1/p' <<<"$out" | sed 's/\x1b\[[0-9;]*m//g' >"$OUT"
echo "key matrix written" >&2
