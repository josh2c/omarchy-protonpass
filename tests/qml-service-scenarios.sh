#!/usr/bin/env bash
# Drives the real Service through the real helper against every mock scenario
# and prints the state each one settles in, one line per scenario. Diff two runs
# -- before and after a Service change -- to prove the state machine is
# unchanged.
#
#   tests/qml-service-scenarios.sh before.txt
#   git stash && tests/qml-service-scenarios.sh after.txt && git stash pop
#   diff before.txt after.txt
#
# The last line covers the invariant the audit names: an auth transition landing
# while an index request is in flight clears the model, and the in-flight
# response cannot repopulate it.
#
# Headless (offscreen) -- the Service has no UI. Skips cleanly without quickshell.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-/dev/stdout}

if ! command -v qs >/dev/null 2>&1; then
  echo "service scenarios skipped (quickshell not installed)"
  exit 0
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/cfg/plugin" "$sandbox/rt" "$sandbox/state" "$sandbox/nocli"
cp Service.qml "$sandbox/cfg/plugin/"
cp omarchy-protonpass "$sandbox/cfg/plugin/"
cp tests/service-scenario-harness.qml "$sandbox/cfg/harness.qml"

# The missing-cli case needs pass-cli to be genuinely absent, not shadowed --
# the helper decides with `command -v`. Two wrong ways to do this: falling back
# to the ambient PATH reaches a real pass-cli on a developer machine and talks
# to a real account, and an empty PATH breaks the helper itself (no jq, no
# sha256sum) so it reports a program error instead of a missing CLI. Mirror the
# normal PATH minus that one binary.
ln -s "$PWD/tests/mocks/wl-copy" "$sandbox/nocli/wl-copy"
ln -s "$PWD/tests/mocks/wl-paste" "$sandbox/nocli/wl-paste"
IFS=: read -ra path_dirs <<<"$PATH"
for path_dir in "${path_dirs[@]}"; do
  [[ -d $path_dir ]] || continue
  for entry in "$path_dir"/*; do
    [[ -f $entry && -x $entry ]] || continue
    name=${entry##*/}
    [[ $name == pass-cli ]] && continue
    [[ -e $sandbox/nocli/$name ]] || ln -s "$entry" "$sandbox/nocli/$name" 2>/dev/null || true
  done
done
if [[ -e $sandbox/nocli/pass-cli ]]; then
  echo "FAIL: could not build a pass-cli-free PATH" >&2
  exit 1
fi

# The helper's environment is fixed once it starts, so the scenario is chosen
# per invocation by a wrapper that reads it from a file the harness rewrites.
cat >"$sandbox/helper-wrapper" <<HELPER
#!/usr/bin/env bash
scenario=\$(cat "\$SCENARIO_FILE" 2>/dev/null || printf 'ready')
if [ "\$scenario" = "missing-cli" ]; then
  export PATH="$sandbox/nocli"
else
  export MOCK_SCENARIO="\$scenario"
  export PATH="$PWD/tests/mocks:\$PATH_WITHOUT_MOCKS"
fi
exec "$PWD/omarchy-protonpass" "\$@"
HELPER
chmod +x "$sandbox/helper-wrapper"
printf 'ready' >"$sandbox/scenario"

out=$(env QT_QPA_PLATFORM=offscreen \
  XDG_RUNTIME_DIR="$sandbox/rt" XDG_STATE_HOME="$sandbox/state" \
  PATH_WITHOUT_MOCKS="$PATH" \
  SCENARIO_FILE="$sandbox/scenario" \
  OMARCHY_PROTONPASS_HELPER="$sandbox/helper-wrapper" \
  timeout 180 qs -p "$sandbox/cfg/harness.qml" 2>&1 || true)

if ! grep -q "HARNESS-DONE" <<<"$out"; then
  echo "FAIL: service scenario harness did not complete" >&2
  sed -n '1,40p' <<<"$out" >&2
  exit 1
fi
if grep -q "UNSETTLED" <<<"$out"; then
  echo "FAIL: a scenario never settled" >&2
  grep "UNSETTLED" <<<"$out" >&2
  exit 1
fi

sed -n 's/^.*DEBUG.*qml.*: \(SCENARIO \)/\1/p' <<<"$out" | sed 's/\x1b\[[0-9;]*m//g' >"$OUT"
echo "service scenarios written" >&2
