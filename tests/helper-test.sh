#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
trap cleanup_test_sandbox EXIT
make_test_sandbox

PASS_CLI="$TEST_BIN/pass-cli"
FIXTURES="$TEST_ROOT/tests/fixtures"

run_error_scenario() {
  local scenario=$1 fixture=$2
  local stdout_file="$TEST_SANDBOX/$scenario.stdout"
  local stderr_file="$TEST_SANDBOX/$scenario.stderr"
  local status
  set +e
  MOCK_SCENARIO=$scenario "$PASS_CLI" vault list --output json >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  assert_eq "$(<"$FIXTURES/$fixture.exit")" "$status" "$scenario exit status"
  assert_file_eq "$FIXTURES/$fixture.stderr" "$stderr_file" "$scenario stderr"
  [[ ! -s $stdout_file ]] || fail "$scenario wrote stdout"
}

assert_eq "Proton Pass CLI 2.3.2 (mock)" "$($PASS_CLI --version)" "mock version"

ready=$(MOCK_SCENARIO=ready "$PASS_CLI" vault list --output json)
assert_jq 'type == "object" and (.vaults|type) == "array" and (.vaults[0]|keys|sort) == ["name","share_id","vault_id"]' "$ready" "ready vault-list shape"

ready_items=$(MOCK_SCENARIO=ready "$PASS_CLI" item list --share-id share_fixture_1 --filter-type login --filter-state active --output json)
assert_jq 'type == "object" and (.items|length) == 1 and (.items[0]|has("id") and has("share_id") and has("title") and has("item_type"))' "$ready_items" "ready item-list shape"

multivault=$(MOCK_SCENARIO=ready-multivault "$PASS_CLI" vault list --output json)
assert_jq '(.vaults|length) == 2' "$multivault" "multi-vault list"
work_items=$(MOCK_SCENARIO=ready-multivault "$PASS_CLI" item list --share-id share_fixture_2 --filter-type login --filter-state active --output json)
assert_jq '(.items|length) == 1 and .items[0].share_id == "share_fixture_2"' "$work_items" "multi-vault item routing"

empty_items=$(MOCK_SCENARIO=empty-vault "$PASS_CLI" item list --share-id share_fixture_2 --filter-type login --filter-state active --output json)
assert_jq '.items == []' "$empty_items" "empty vault"
zero_vaults=$(MOCK_SCENARIO=zero-vaults "$PASS_CLI" vault list --output json)
assert_jq '.vaults == []' "$zero_vaults" "zero vaults"

run_error_scenario logged-out logged-out
run_error_scenario locked locked
run_error_scenario expired invalidated
run_error_scenario offline network-down

set +e
MOCK_SCENARIO=no-lock "$PASS_CLI" session lock >"$TEST_SANDBOX/no-lock.stdout" 2>"$TEST_SANDBOX/no-lock.stderr"
no_lock_status=$?
set -e
assert_eq "1" "$no_lock_status" "no-lock exit status"
assert_file_eq "$FIXTURES/no-lock.stderr" "$TEST_SANDBOX/no-lock.stderr" "no-lock stderr"

set +e
MOCK_SCENARIO=no-totp "$PASS_CLI" item totp --share-id share_fixture_1 --item-id item_email_1 --output json >"$TEST_SANDBOX/no-totp.stdout" 2>"$TEST_SANDBOX/no-totp.stderr"
no_totp_status=$?
set -e
assert_eq "1" "$no_totp_status" "no-totp exit status"
assert_file_eq "$FIXTURES/no-totp.stderr" "$TEST_SANDBOX/no-totp.stderr" "no-totp stderr"

for field in username email; do
  set +e
  MOCK_SCENARIO=no-username "$PASS_CLI" item view --share-id share_fixture_1 --item-id item_email_1 --field "$field" >"$TEST_SANDBOX/no-$field.stdout" 2>"$TEST_SANDBOX/no-$field.stderr"
  field_status=$?
  set -e
  assert_eq "1" "$field_status" "missing $field exit status"
  assert_file_eq "$FIXTURES/no-$field.stderr" "$TEST_SANDBOX/no-$field.stderr" "missing $field stderr"
done

malformed=$(MOCK_SCENARIO=malformed-json "$PASS_CLI" vault list --output json)
if jq -e . <<<"$malformed" >/dev/null 2>&1; then fail "malformed-json scenario returned valid JSON"; fi

set +e
MOCK_SCENARIO=timeout-sleeps MOCK_SLEEP_SECONDS=1 timeout 0.02 "$PASS_CLI" vault list --output json >/dev/null
timeout_status=$?
set -e
assert_eq "124" "$timeout_status" "timeout-sleeps remains interruptible"

trailing_hash=$(MOCK_SCENARIO=value-with-trailing-newlines "$PASS_CLI" item view --share-id share_fixture_1 --item-id item_username_1 --field password | sha256sum | cut -d' ' -f1)
expected_trailing_hash=$(printf 'synthetic-value\n\n\n' | sha256sum | cut -d' ' -f1)
assert_eq "$expected_trailing_hash" "$trailing_hash" "trailing-newline bytes"

unicode_items=$(MOCK_SCENARIO=unicode-titles "$PASS_CLI" item list --share-id share_fixture_1 --filter-type login --filter-state active --output json)
assert_jq '(.items|length) == 5 and any(.items[]; .title == "Quote \"login\"") and any(.items[]; .title == "Line\nbreak") and any(.items[]; .title == "Emoji 🔐") and any(.items[]; .title == "RTL مثال") and any(.items[]; .title|contains("$(touch /tmp/never-run)"))' "$unicode_items" "unicode and metacharacter titles"
[[ ! -e /tmp/never-run ]] || fail "shell metacharacters from a title were executed"

set +e
MOCK_SCENARIO=ready-multivault MOCK_FAIL_SHARE_ID=share_fixture_2 "$PASS_CLI" item list --share-id share_fixture_2 --output json >"$TEST_SANDBOX/partial.stdout" 2>"$TEST_SANDBOX/partial.stderr"
partial_status=$?
set -e
assert_eq "1" "$partial_status" "per-vault failure exit status"
assert_file_contains "$TEST_SANDBOX/partial.stderr" "Synthetic per-vault failure" "per-vault failure stderr"

printf 'clipboard-marker' | "$TEST_BIN/wl-copy" --sensitive -o
assert_jq '(.args == ["--sensitive","-o"]) and (.sha256|type == "string")' "$(tail -n1 "$MOCK_WL_COPY_LOG")" "wl-copy argv and hash log"
if rg -F --quiet 'clipboard-marker' "$MOCK_WL_COPY_LOG"; then fail "wl-copy log contains clipboard content"; fi

paste_value=$(MOCK_WL_PASTE_VALUE='configured paste value' "$TEST_BIN/wl-paste" --no-newline)
assert_eq "configured paste value" "$paste_value" "wl-paste configured value"
assert_jq '. == ["--no-newline"]' "$(tail -n1 "$MOCK_WL_PASTE_LOG")" "wl-paste argv log"

assert_jq 'length > 0 and all(.[]; type == "array")' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "pass-cli argv log is JSON arrays"

printf 'mock harness tests passed\n'
