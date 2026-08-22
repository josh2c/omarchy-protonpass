#!/usr/bin/env bash
# Renders the real Panel.qml through every panel state and prints a structural
# snapshot of the visible item tree (type, geometry, text, colour, font, a11y
# name) per state. Diff two runs to prove a presentational refactor changed
# nothing: identical structure and geometry means identical pixels.
#
# Needs a live Wayland session -- KeyboardPanel is a layer-shell surface and
# will not lay out under the offscreen platform. Skips cleanly without one.
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
ROOT=$PWD
OUT=${1:-/dev/stdout}

if ! command -v qs >/dev/null 2>&1; then
  echo "panel snapshot skipped (quickshell not installed)"
  exit 0
fi
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  echo "panel snapshot skipped (no Wayland session)"
  exit 0
fi
SHELL_TREE=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if [[ ! -d $SHELL_TREE/Ui ]]; then
  echo "panel snapshot skipped (Omarchy shell tree not found at $SHELL_TREE)"
  exit 0
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

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

# XDG_RUNTIME_DIR is deliberately NOT sandboxed: the Wayland socket lives
# there, and a layer-shell surface is the whole point of this harness.
out=$(env QT_QPA_PLATFORM=wayland XDG_STATE_HOME="$sandbox/state" \
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
