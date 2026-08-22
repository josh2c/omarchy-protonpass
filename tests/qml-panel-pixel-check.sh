#!/usr/bin/env bash
# Screenshots one panel state and prints the item dump beside it, so the two can
# be checked against each other.
#
#   tests/qml-panel-pixel-check.sh LOCKED /tmp/locked.png /tmp/locked.txt
#
# This exists because the structural dump is not ground truth. It reads item
# positions through mapToItem, and at some surface sizes that resolves against a
# parent chain still mid-polish and reports geometry that never rendered -- two
# differently sized Row children sharing an x, a Column's children sharing a y.
# A dump carrying exactly that signature was once mistaken for a layout
# regression in shipped code. tests/panel-harness.qml now rejects impossible
# geometry, but when a dump and your expectation disagree, a screenshot settles
# it and shares no logic with the thing under suspicion.
#
# Requires quickshell, Hyprland and grim. Skips cleanly when any is missing.
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=${1:-LOCKED}
PNG=${2:-/tmp/panel-pixel-check.png}
DUMP=${3:-/tmp/panel-pixel-check.txt}

for tool in qs Hyprland grim; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "pixel check skipped ($tool not installed)"
    exit 0
  fi
done
SHELL_TREE=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if [[ ! -d $SHELL_TREE/Ui ]]; then
  echo "pixel check skipped (Omarchy shell tree not found at $SHELL_TREE)"
  exit 0
fi

# shellcheck source=tests/lib-nested-display.sh
. "$(dirname "$0")/lib-nested-display.sh"

sandbox=$(mktemp -d)
qs_pid=""
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null
  stop_nested_display
  rm -rf "$sandbox"
}
trap cleanup EXIT

mkdir -p "$sandbox/cfg/plugin" "$sandbox/state"
cp -r "$SHELL_TREE/Commons" "$SHELL_TREE/Ui" "$SHELL_TREE/services" "$sandbox/cfg/"
cp Panel.qml Service.qml Keybinds.js "$sandbox/cfg/plugin/"
cp tests/panel-harness.qml "$sandbox/cfg/harness.qml"

# Keep only the requested scenario, and hold the surface up after emitting
# instead of quitting, so there is something left to photograph.
python3 - "$sandbox/cfg/harness.qml" "$STATE" <<'EOF'
import re, sys
path, state = sys.argv[1], sys.argv[2]
s = open(path).read()
m = re.search(r'\{label: "%s".*?\}\},\n' % re.escape(state), s, re.S)
if not m:
    sys.stderr.write("unknown scenario: %s\n" % state)
    raise SystemExit(2)
s = re.sub(r'readonly property var scenarios: \[.*?\n  \]',
           'readonly property var scenarios: [\n    ' + m.group(0).rstrip().rstrip(',') + '\n  ]',
           s, flags=re.S)
s = s.replace('emitLines(scenarios[stateIndex].label, lines)\n        advance()',
              'emitLines(scenarios[stateIndex].label, lines)\n        console.log("FROZEN")')
open(path, 'w').write(s)
EOF

cat >"$sandbox/silent-helper" <<'HELPER'
#!/usr/bin/env bash
sleep 300
HELPER
chmod +x "$sandbox/silent-helper"

start_nested_display "$sandbox" || exit 1

env WAYLAND_DISPLAY="$NESTED_DISPLAY" QT_QPA_PLATFORM=wayland \
  XDG_STATE_HOME="$sandbox/state" \
  OMARCHY_PROTONPASS_HELPER="$sandbox/silent-helper" \
  qs -p "$sandbox/cfg/harness.qml" >"$sandbox/qs.log" 2>&1 &
qs_pid=$!

for _ in $(seq 1 60); do
  sleep 0.5
  grep -q "FROZEN" "$sandbox/qs.log" && break
done
if ! grep -q "FROZEN" "$sandbox/qs.log"; then
  echo "FAIL: panel never reached $STATE" >&2
  tail -20 "$sandbox/qs.log" >&2
  exit 1
fi

WAYLAND_DISPLAY="$NESTED_DISPLAY" grim "$PNG"
sed -n 's/^.*DEBUG.*qml.*: \(SNAPSHOT\|| \)/\1/p' "$sandbox/qs.log" \
  | sed 's/\x1b\[[0-9;]*m//g' >"$DUMP"

echo "pixel check written: $PNG (screenshot) and $DUMP (dump)" >&2
