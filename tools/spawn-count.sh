#!/usr/bin/env bash
# Counts the external commands one helper invocation executes, by putting a
# logging wrapper in front of every utility on the sandbox PATH.
# Usage: spawn-count.sh <repo-root> [helper args...]
set -euo pipefail

REPO=$(cd "$1" && pwd)
shift

SANDBOX=$(mktemp -d /tmp/omarchy-protonpass-spawns.XXXXXX)
trap 'rm -rf -- "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
REAL="$SANDBOX/real"
LOG="$SANDBOX/spawns.log"
mkdir -p "$BIN" "$REAL" "$SANDBOX/runtime" "$SANDBOX/state"
: >"$LOG"

wrap() {
  local name=$1 target=$2
  ln -sf "$target" "$REAL/$name"
  cat >"$BIN/$name" <<EOF
#!/bin/sh
printf '%s\n' "$name" >>"$LOG"
exec "$REAL/$name" "\$@"
EOF
  chmod +x "$BIN/$name"
}

wrap pass-cli "$REPO/tests/mocks/pass-cli"
wrap wl-copy "$REPO/tests/mocks/wl-copy"
wrap wl-paste "$REPO/tests/mocks/wl-paste"
for utility in bash cat chmod cut date find grep jq ln mkdir mktemp mv od readlink rm sha256sum sleep stat tail timeout tr; do
  wrap "$utility" "$(command -v "$utility")"
done

SAVED_PATH=$PATH
export PATH="$BIN"
export XDG_RUNTIME_DIR="$SANDBOX/runtime" XDG_STATE_HOME="$SANDBOX/state"
export MOCK_FIXTURES_DIR="$REPO/tests/fixtures"
export MOCK_SCENARIO=${MOCK_SCENARIO:-ready}

if [[ -n ${SPAWN_STDIN:-} ]]; then
  printf '%s' "$SPAWN_STDIN" | "$REPO/omarchy-protonpass" "$@" >/dev/null 2>&1 || true
else
  "$REPO/omarchy-protonpass" "$@" </dev/null >/dev/null 2>&1 || true
fi

PATH=$SAVED_PATH
printf 'total spawns: %s\n' "$(wc -l <"$LOG")"
sort "$LOG" | uniq -c | sort -rn
