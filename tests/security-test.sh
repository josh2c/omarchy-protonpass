#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
trap cleanup_test_sandbox EXIT

ROOT=${SECURITY_TEST_ROOT:-$TEST_ROOT}
HELPER="$ROOT/omarchy-protonpass"
MARKER=OMPP-T7-MARKER-7f43d2a9

security_sources=("$HELPER")
while IFS= read -r qml_file; do
  security_sources+=("$qml_file")
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.qml' -print)

fail_on_match() {
  local expression=$1 message=$2
  if grep -En -- "$expression" "${security_sources[@]}" >/dev/null; then
    fail "$message"
  fi
}

fail_on_match '(^|[^[:alnum:]_])eval([[:space:](]|$)' \
  "runtime source contains eval"
fail_on_match '(^|[[:space:]])(ba|da|k|z)?sh[[:space:]]+-c([[:space:]]|$)' \
  "runtime source launches a shell command string"
fail_on_match 'export[[:space:]]+(-[A-Za-z]+[[:space:]]+)*val([[:space:]=]|$)' \
  "the secret variable can be exported"
fail_on_match 'property[[:space:]]+(string|var)[[:space:]]+_?(secret|password|username|totp)(value|text|code|data)?[[:space:]:]' \
  "QML declares a property that could retain a secret"

if grep -Fn -- '--show-secrets' "${security_sources[@]}" >/dev/null; then
  fail "runtime source enables pass-cli secret display"
fi
if grep -Fn -- '`' "${security_sources[@]}" >/dev/null; then
  fail "runtime source contains backtick interpolation"
fi

make_test_sandbox

proc_file_contains_marker() {
  local file=$1 part content=""
  [[ -r $file ]] || return 1
  while IFS= read -r -d '' part; do
    content+=$part
  done <"$file" 2>/dev/null || true
  [[ $content == *"$MARKER"* ]]
}

regular_file_contains_marker() {
  local file=$1 content=""
  [[ -r $file ]] || return 1
  content=$(<"$file")
  [[ $content == *"$MARKER"* ]]
}

MOCK_SCENARIO=security-marker \
MOCK_WL_COPY_SLEEP_SECONDS=1 \
MOCK_WL_PASTE_VALUE='clipboard content copied afterward' \
  "$HELPER" copy \
    --share-id share_fixture_1 \
    --item-id item_fixture_1 \
    --field password \
    --clear-seconds 1 \
    >"$TEST_SANDBOX/security.stdout" \
    2>"$TEST_SANDBOX/security.stderr" &
helper_pid=$!

sleep 0.1
kill -0 "$helper_pid" 2>/dev/null || fail "copy helper exited before process inspection"

for cmdline in /proc/[0-9]*/cmdline; do
  if proc_file_contains_marker "$cmdline"; then
    fail "secret marker appeared in a process command line"
  fi
done
if proc_file_contains_marker "/proc/$helper_pid/environ"; then
  fail "secret marker appeared in the helper environment"
fi

wait "$helper_pid"
[[ ! -s $TEST_SANDBOX/security.stderr ]] || fail "copy helper wrote stderr"
if regular_file_contains_marker "$TEST_SANDBOX/security.stdout"; then
  fail "secret marker appeared in helper output"
fi
assert_jq '.state == "copied" and .field == "password"' \
  "$(<"$TEST_SANDBOX/security.stdout")" "security copy response"

# The clearer must see the newer clipboard value and leave it untouched.
sleep 1.2
wl_copy_calls=$(jq -sc '.' "$MOCK_WL_COPY_LOG")
assert_jq 'length == 1 and .[0].args == ["--sensitive"]' "$wl_copy_calls" \
  "clearer removed newer clipboard content"
expected_hash=$(printf '%s' "$MARKER" | sha256sum | cut -d' ' -f1)
assert_jq ".[0].sha256 == \"$expected_hash\"" "$wl_copy_calls" \
  "wl-copy did not receive the exact secret bytes"

while IFS= read -r -d '' sandbox_file; do
  if regular_file_contains_marker "$sandbox_file"; then
    fail "secret marker appeared in a sandbox file"
  fi
done < <(find "$TEST_SANDBOX" -type f -print0)

printf 'security tests passed\n'
