#!/usr/bin/env bash
# Renders the real Panel.qml through every panel state and prints a structural
# snapshot of the visible item tree (type, geometry, text, colour, font, a11y
# name) per state. Diff two runs to prove a presentational refactor changed
# nothing: identical structure and geometry means identical pixels.
#
# It runs inside a throwaway nested Hyprland on its own Wayland display. That is
# not optional: the panel is a layer-shell surface that primes exclusive
# keyboard focus, so running it on your own session steals the keyboard for the
# length of the run and your typing lands in the panel's search field.
#
#   tests/qml-panel-snapshot.sh after.txt
#   git stash && tests/qml-panel-snapshot.sh before.txt && git stash pop
#   diff before.txt after.txt
#
# tests/baselines/panel-snapshot.txt is the committed dump for the current
# release. It records this machine's font metrics, so geometry will differ on a
# host with different fonts -- compare two runs from one machine, and refresh
# the baseline deliberately when a change is meant to alter rendering.
#
# Usage: tests/qml-panel-snapshot.sh [output-file]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-/dev/stdout}

for tool in qs Hyprland; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "panel snapshot skipped ($tool not installed)"
    exit 0
  fi
done
SHELL_TREE=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if [[ ! -d $SHELL_TREE/Ui ]]; then
  echo "panel snapshot skipped (Omarchy shell tree not found at $SHELL_TREE)"
  exit 0
fi

# shellcheck source=tests/lib-nested-display.sh
. "$(dirname "$0")/lib-nested-display.sh"

sandbox=$(mktemp -d)
trap 'stop_nested_display; rm -rf "$sandbox"' EXIT

# Quickshell resolves qs.Ui / qs.Commons relative to the config root, so the
# harness runs inside a private copy of the shell tree with the plugin staged
# in a subdirectory -- the same layout the installed plugin sees.
mkdir -p "$sandbox/cfg/plugin" "$sandbox/state"
cp -r "$SHELL_TREE/Commons" "$SHELL_TREE/Ui" "$SHELL_TREE/services" "$sandbox/cfg/"
cp Panel.qml Service.qml Keybinds.js "$sandbox/cfg/plugin/"
cp tests/panel-harness.qml "$sandbox/cfg/harness.qml"

# A helper that never answers keeps the Service from overwriting the state the
# harness sets: the index request stays in flight for the whole run.
cat >"$sandbox/silent-helper" <<'HELPER'
#!/usr/bin/env bash
sleep 300
HELPER
chmod +x "$sandbox/silent-helper"

start_nested_display "$sandbox" || exit 1

out=$(env WAYLAND_DISPLAY="$NESTED_DISPLAY" QT_QPA_PLATFORM=wayland \
  XDG_STATE_HOME="$sandbox/state" \
  OMARCHY_PROTONPASS_HELPER="$sandbox/silent-helper" \
  timeout 60 qs -p "$sandbox/cfg/harness.qml" 2>&1 || true)

if ! grep -q "HARNESS-DONE" <<<"$out"; then
  echo "FAIL: panel harness did not complete" >&2
  sed -n '1,60p' <<<"$out" >&2
  exit 1
fi
# The layer-shell surface occasionally fails to map; an empty tree would
# otherwise diff clean against another empty tree and prove nothing.
if grep -qE "SNAPSHOT [A-Z_]+ (EMPTY|MISSING-CONTENT)" <<<"$out"; then
  echo "FAIL: panel did not render (surface never mapped?) -- rerun" >&2
  grep -E "SNAPSHOT [A-Z_]+ (EMPTY|MISSING-CONTENT)" <<<"$out" >&2
  exit 1
fi

# Strip quickshell's log decoration so two runs diff cleanly.
sed -n 's/^.*DEBUG.*qml.*: \(SNAPSHOT\|HARNESS\|| \)/\1/p' <<<"$out" \
  | sed 's/\x1b\[[0-9;]*m//g' >"$OUT"
echo "panel snapshot written" >&2
