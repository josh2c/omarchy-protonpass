#!/usr/bin/env bash

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Contract shapes shared with the mocks; see tests/fixtures/contracts.sh.
# shellcheck disable=SC1091
source "$TEST_ROOT/tests/fixtures/contracts.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  # The EXIT trap can belong to the helper rather than this suite; see
  # arm_test_sandbox_cleanup. Clean up here so a failing assertion never
  # depends on which trap is installed.
  cleanup_test_sandbox
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
  # A suite that sources the helper also gets the helper's scratch-file removal
  # in this shell. Run it first so re-arming this cleanup does not drop the
  # helper's own contract. The scratch files live inside the sandbox too, so
  # this is belt and braces.
  if [[ $(type -t remove_scratch_files) == function ]]; then
    remove_scratch_files || true
    # Blank the two paths the helper reads back in remove_scratch_files. Its
    # trap can still run after this cleanup, and by then the sandbox it looks
    # in, including the rm it resolves through PATH, is gone.
    # shellcheck disable=SC2034
    STDERR_CAPTURE_FILE=""
    # shellcheck disable=SC2034
    INDEX_SCRATCH_FILE=""
  fi
  if [[ -n ${TEST_SANDBOX:-} && -d $TEST_SANDBOX ]]; then
    rm -rf -- "$TEST_SANDBOX"
  fi
}

# Bash holds one EXIT trap. The helper installs its own with
# open_stderr_capture, so a suite that sources the helper and then calls its
# internals loses the sandbox cleanup silently, and every later exit leaks the
# sandbox. A suite must re-arm the cleanup after it stops calling helper
# internals, and assert it is still armed before the suite ends.
arm_test_sandbox_cleanup() {
  trap cleanup_test_sandbox EXIT
}

assert_sandbox_cleanup_armed() {
  local message=${1:-"sandbox cleanup is not armed at the end of the suite"}
  local installed
  installed=$(trap -p EXIT)
  [[ $installed == *cleanup_test_sandbox* ]] || fail "$message (EXIT trap is: ${installed:-none})"
}
