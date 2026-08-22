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

sandbox=$(mktemp -d)
nested_pid=""
cleanup() {
  [[ -n $nested_pid ]] && kill "$nested_pid" 2>/dev/null
  rm -rf "$sandbox"
}
trap cleanup EXIT

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

cat >"$sandbox/hypr.conf" <<'HYPR'
monitor=,1200x900@60,0x0,1
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
  force_default_wallpaper = 0
}
animations { enabled = false }
decoration { blur { enabled = false } }
HYPR

Hyprland -c "$sandbox/hypr.conf" >"$sandbox/hypr.log" 2>&1 &
nested_pid=$!

# Identify the nested display by the lock file the compositor itself holds
# open. Two tempting alternatives are wrong: diffing the socket directory
# breaks when an earlier run left a stale socket behind, and asking the
# compositor through exec-once reports the *host* display, because Hyprland
# does not rewrite WAYLAND_DISPLAY in the environment its children inherit.
# Getting this wrong would aim the synthetic keystrokes at the real session.
nested_display=""
for _ in $(seq 1 80); do
  sleep 0.5
  lock=$(ls -l /proc/"$nested_pid"/fd 2>/dev/null |
    grep -o "/run/user/$(id -u)/wayland-[0-9]*\.lock" | head -1)
  if [[ -n $lock ]]; then
    nested_display=$(basename "$lock" .lock)
    break
  fi
  kill -0 "$nested_pid" 2>/dev/null || break
done
if [[ -z $nested_display ]]; then
  echo "FAIL: nested compositor did not start" >&2
  tail -20 "$sandbox/hypr.log" >&2
  exit 1
fi
# Refuse to type into the session running this script, whatever went wrong above.
if [[ $nested_display == "${WAYLAND_DISPLAY:-}" ]]; then
  echo "FAIL: refusing to run -- detected display $nested_display is this session" >&2
  exit 1
fi
sleep 2

out=$(env WAYLAND_DISPLAY="$nested_display" QT_QPA_PLATFORM=wayland \
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
if grep -q "FOCUS-LOST" <<<"$out"; then
  echo "FAIL: panel lost focus mid-run -- rerun" >&2
  grep "FOCUS-LOST" <<<"$out" >&2
  exit 1
fi

sed -n 's/^.*DEBUG.*qml.*: \(CASE \)/\1/p' <<<"$out" | sed 's/\x1b\[[0-9;]*m//g' >"$OUT"
echo "key matrix written" >&2
