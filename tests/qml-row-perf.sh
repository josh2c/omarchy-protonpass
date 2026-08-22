#!/usr/bin/env bash
# Fills the panel with a synthetic 500-item vault and reports what typing costs
# and whether the subtitle clock tick throws the delegate list away.
#
#   tests/qml-row-perf.sh before.txt
#   git stash && tests/qml-row-perf.sh after.txt && git stash pop
#   diff before.txt after.txt
#
# Timings are wall clock on a live session and will wobble; the number that is
# a contract rather than a measurement is delegateSurvived.
#
# It runs inside a throwaway nested Hyprland on its own Wayland display. That is
# not optional: the panel is a layer-shell surface that primes exclusive
# keyboard focus, so running it on your own session steals the keyboard for the
# length of the run and your typing lands in the panel's search field.
#
# Usage: tests/qml-row-perf.sh [output-file]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-/dev/stdout}

for tool in qs Hyprland; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "row perf skipped ($tool not installed)"
    exit 0
  fi
done
SHELL_TREE=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if [[ ! -d $SHELL_TREE/Ui ]]; then
  echo "row perf skipped (Omarchy shell tree not found at $SHELL_TREE)"
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
cp tests/row-perf-harness.qml "$sandbox/cfg/harness.qml"

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
  echo "FAIL: row perf harness did not complete" >&2
  sed -n '1,60p' <<<"$out" >&2
  exit 1
fi
if grep -q "PERF-SETUP-FAILED" <<<"$out"; then
  echo "FAIL: panel did not open (surface never mapped?) -- rerun" >&2
  exit 1
fi

# Strip quickshell's log decoration so two runs diff cleanly.
sed -n 's/^.*DEBUG.*qml.*: \(PERF \)/\1/p' <<<"$out" | sed 's/\x1b\[[0-9;]*m//g' >"$OUT"
echo "row perf written" >&2
