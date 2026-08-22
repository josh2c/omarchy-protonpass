#!/usr/bin/env bash
# Headless integration test: the real Service drives the real helper (mock
# pass-cli) through a full create. Guards the stdin-EOF contract: the helper
# reads the template with $(cat) and hangs forever if Service never closes
# stdin. Requires quickshell; skips cleanly where it is absent (hosted CI).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v qs >/dev/null 2>&1; then
  echo "qml create test skipped (quickshell not installed)"
  exit 0
fi
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
# Quickshell only resolves directory imports inside its config folder, so
# stage the harness and the real Service.qml together in the sandbox.
mkdir -p "$sandbox/cfg" "$sandbox/rt" "$sandbox/state"
cp Service.qml tests/create-harness.qml "$sandbox/cfg/"
out=$(env QT_QPA_PLATFORM=offscreen PATH="$PWD/tests/mocks:$PATH" \
  XDG_RUNTIME_DIR="$sandbox/rt" XDG_STATE_HOME="$sandbox/state" \
  MOCK_SCENARIO=ready OMARCHY_PROTONPASS_HELPER="$PWD/omarchy-protonpass" \
  timeout 20 qs -p "$sandbox/cfg/create-harness.qml" 2>&1 || true)
if grep -q "CREATE-DONE" <<<"$out" && ! grep -q "HANG-TIMEOUT" <<<"$out"; then
  echo "qml create test passed"
else
  echo "FAIL: create did not complete (stdin EOF contract broken?)" >&2
  grep -E "STATE:|CREATE|HANG" <<<"$out" >&2 || true
  exit 1
fi
