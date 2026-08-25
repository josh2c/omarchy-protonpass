#!/usr/bin/env bash

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Contract shapes shared with the mocks; see tests/fixtures/contracts.sh.
# shellcheck disable=SC1091
source "$TEST_ROOT/tests/fixtures/contracts.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected=$1 actual=$2 message=$3
  [[ $actual == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_jq() {
  local expression=$1 json=$2 message=$3
  jq -e "$expression" <<<"$json" >/dev/null || fail "$message"
}

assert_file_eq() {
  local expected=$1 actual=$2 message=$3
  cmp "$expected" "$actual" || fail "$message"
}

assert_file_contains() {
  local file=$1 text=$2 message=$3
  grep -Fq -- "$text" "$file" || fail "$message"
}

make_test_sandbox() {
  TEST_SANDBOX=$(mktemp -d /tmp/omarchy-protonpass-tests.XXXXXX)
  TEST_BIN="$TEST_SANDBOX/bin"
  XDG_RUNTIME_DIR="$TEST_SANDBOX/runtime"
  XDG_STATE_HOME="$TEST_SANDBOX/state"
  mkdir -p "$TEST_BIN" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"

  ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"
  ln -s "$TEST_ROOT/tests/mocks/wl-copy" "$TEST_BIN/wl-copy"
  ln -s "$TEST_ROOT/tests/mocks/wl-paste" "$TEST_BIN/wl-paste"

  local utility utility_path
  for utility in bash cat chmod cmp cut date dirname find grep head jq ln mkdir mktemp mv od readlink rm sha256sum sleep stat tail timeout; do
    utility_path=$(command -v "$utility") || fail "required test utility is missing: $utility"
    ln -s "$utility_path" "$TEST_BIN/$utility"
  done

  MOCK_CALLS_LOG="$TEST_SANDBOX/pass-cli-calls.jsonl"
  MOCK_WL_COPY_LOG="$TEST_SANDBOX/wl-copy-calls.jsonl"
  MOCK_WL_PASTE_LOG="$TEST_SANDBOX/wl-paste-calls.jsonl"
  MOCK_FIXTURES_DIR="$TEST_ROOT/tests/fixtures"
  : >"$MOCK_CALLS_LOG"
  : >"$MOCK_WL_COPY_LOG"
  : >"$MOCK_WL_PASTE_LOG"

  export TEST_SANDBOX TEST_BIN MOCK_CALLS_LOG MOCK_WL_COPY_LOG MOCK_WL_PASTE_LOG MOCK_FIXTURES_DIR
  export XDG_RUNTIME_DIR XDG_STATE_HOME
  export PATH="$TEST_BIN"
}

cleanup_test_sandbox() {
  if [[ -n ${TEST_SANDBOX:-} && -d $TEST_SANDBOX ]]; then
    rm -rf -- "$TEST_SANDBOX"
  fi
}
