#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
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
# shellcheck disable=SC2016
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

HELPER="$TEST_ROOT/omarchy-protonpass"

assert_invalid_helper() {
  local expected_command=$1
  shift
  local output status
  set +e
  output=$("$HELPER" "$@" 2>"$TEST_SANDBOX/helper-invalid.stderr")
  status=$?
  set -e
  assert_eq "2" "$status" "invalid helper argv exit status"
  assert_jq ".schemaVersion == 1 and .command == \"$expected_command\" and .state == \"error\" and (.message|type) == \"string\"" "$output" "invalid helper envelope for $expected_command"
  [[ ! -s $TEST_SANDBOX/helper-invalid.stderr ]] || fail "invalid helper argv wrote stderr"
}

doctor=$(
  MOCK_ASSERT_SAFE_ENV=1 \
  PROTON_PASS_KEY_PROVIDER=fixture-provider \
  PROTON_PASS_SESSION_DIR=/tmp/fixture-session \
  PROTON_PASS_PERSONAL_ACCESS_TOKEN=fixture-credential \
  PROTON_PASS_DISABLE_TELEMETRY=fixture-telemetry \
    "$HELPER" doctor
)
assert_jq '.schemaVersion == 1 and .command == "doctor" and .state == "ok" and .message == "Dependencies are available" and .passCli == {present:true,version:"2.3.2"} and .wlClipboard == {present:true}' "$doctor" "doctor ready contract"

major_warning=$(MOCK_PASS_CLI_VERSION=3.0.0 "$HELPER" doctor)
assert_jq '.state == "ok" and .passCli.version == "3.0.0" and (.message|contains("expected 2.x"))' "$major_warning" "doctor major-version warning"

rm "$TEST_BIN/pass-cli"
missing_pass=$("$HELPER" doctor)
assert_jq '.state == "missing-deps" and .passCli == {present:false,version:""} and .wlClipboard.present == true' "$missing_pass" "doctor missing pass-cli"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

rm "$TEST_BIN/wl-paste"
missing_clipboard=$("$HELPER" doctor)
assert_jq '.state == "missing-deps" and .passCli.present == true and .wlClipboard.present == false' "$missing_clipboard" "doctor missing wl-paste"
ln -s "$TEST_ROOT/tests/mocks/wl-paste" "$TEST_BIN/wl-paste"

calls_before_invalid=$(jq -sc 'length' "$MOCK_CALLS_LOG")
assert_invalid_helper unknown
assert_invalid_helper unknown frobnicate
assert_invalid_helper doctor doctor extra
assert_invalid_helper doctor doctor --unknown
assert_invalid_helper index index
assert_invalid_helper index index --exclude-vaults one --exclude-vaults two
assert_invalid_helper index index --unknown value
assert_invalid_helper copy copy --share-id share --item-id item --field password
assert_invalid_helper copy copy --share-id share --item-id item --field password --clear-seconds -1
assert_invalid_helper copy copy --share-id share --item-id 'bad item' --field password --clear-seconds 45
assert_invalid_helper copy copy --share-id 'bad id' --item-id item --field password --clear-seconds 45
assert_invalid_helper copy copy --share-id share --item-id item --field secret --clear-seconds 45
assert_invalid_helper copy copy --share-id share --item-id item --field password --clear-seconds 301
assert_invalid_helper copy copy --share-id share --item-id item --field password --clear-seconds nope
assert_invalid_helper copy copy --share-id share --item-id item --field password --clear-seconds 45 --paste-once --paste-once
assert_invalid_helper copy copy --share-id share --item-id item --field password --clear-seconds 45 --unknown
assert_invalid_helper lock lock extra
assert_invalid_helper lock lock --unknown
calls_after_invalid=$(jq -sc 'length' "$MOCK_CALLS_LOG")
assert_eq "$calls_before_invalid" "$calls_after_invalid" "validation completes before pass-cli execution"

long_id=$(printf '%0257d' 0)
assert_invalid_helper copy copy --share-id "$long_id" --item-id item --field password --clear-seconds 45
# shellcheck disable=SC2016
assert_invalid_helper copy copy --share-id '$(touch /tmp/helper-never-run)' --item-id item --field password --clear-seconds 45
[[ ! -e /tmp/helper-never-run ]] || fail "invalid helper argument was executed"

index_ready=$(MOCK_SCENARIO=ready "$HELPER" index --exclude-vaults '')
assert_jq '.schemaVersion == 1 and .command == "index" and .state == "ready" and (.message|type) == "string" and .items == [{itemId:"item_fixture_1",shareId:"share_fixture_1",vaultName:"Personal",title:"T0 Synthetic Login"}] and .warnings == []' "$index_ready" "index ready contract"
copy_contract=$("$HELPER" copy --clear-seconds 0000 --field totp --item-id item_1 --share-id share/1= --paste-once)
assert_jq '.schemaVersion == 1 and .command == "copy" and .state == "copied" and .field == "totp" and .fallbackUsed == false and .clearSeconds == 0' "$copy_contract" "copy contract"
lock_stub=$("$HELPER" lock)
assert_jq '.schemaVersion == 1 and .command == "lock" and .state == "locked" and (.message|type) == "string"' "$lock_stub" "lock contract"

# Source only the helper's core functions; its guarded main must not execute.
# shellcheck disable=SC1090
source "$HELPER"

assert_classifier() {
  local command_name=$1 status=$2 stderr_blob=$3 expected_state=$4 expected_kind=$5 expected_message=$6
  classify_failure "$command_name" "$status" "$stderr_blob"
  assert_eq "$expected_state" "$CLASSIFIED_STATE" "classifier state for $expected_kind"
  assert_eq "$expected_kind" "$CLASSIFIED_KIND" "classifier kind for $expected_kind"
  assert_eq "$expected_message" "$CLASSIFIED_MESSAGE" "classifier message for $expected_kind"
}

assert_classifier index 1 "$(<"$FIXTURES/logged-out.stderr")" logged-out logged-out "Not signed in to Proton Pass"
assert_classifier index 1 "$(<"$FIXTURES/invalidated.stderr")" logged-out session-expired "Session expired — sign in again"
assert_classifier index 1 "$(<"$FIXTURES/locked.stderr")" locked locked "Session locked"
assert_classifier index 1 "$(<"$FIXTURES/network-down.stderr")" unreachable network "Can't reach Proton"
assert_classifier lock 1 "$(<"$FIXTURES/no-lock.stderr")" no-lock no-lock "No session lock configured — run pass-cli session create-lock"
assert_classifier copy 1 "$(<"$FIXTURES/no-username.stderr")" no-field no-field "Requested field is not available"
assert_classifier copy 1 "$(<"$FIXTURES/no-email.stderr")" no-field no-field "Requested field is not available"
assert_classifier copy 1 "$(<"$FIXTURES/no-totp.stderr")" no-field no-field "Requested field is not available"
assert_classifier index 1 "$(<"$FIXTURES/plan-ineligible.stderr")" error unknown "Something went wrong talking to pass-cli"
assert_classifier index 1 'prefix WITHOUT an Error: marker: NO ACTIVE SESSION' logged-out logged-out "Not signed in to Proton Pass"
assert_classifier index 1 'Session has been invalidated. Please log in again.' logged-out session-expired "Session expired — sign in again"
assert_classifier lock 1 'Session is not locked' no-lock no-lock "No session lock configured — run pass-cli session create-lock"
assert_classifier index 1 'DNS error: temporary failure in name resolution' unreachable network "Can't reach Proton"
assert_classifier index 124 '' unreachable timeout "Proton Pass CLI timed out"
assert_classifier index 124 'unexpected timeout output' error unknown "Something went wrong talking to pass-cli"

rm "$TEST_BIN/pass-cli"
assert_classifier index 127 '' cli-missing cli-missing "Proton Pass CLI not found"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

runner_version=$(
  MOCK_ASSERT_SAFE_ENV=1 \
  PROTON_PASS_KEY_PROVIDER=fixture-provider \
  PROTON_PASS_SESSION_DIR=/tmp/fixture-session \
  PROTON_PASS_PERSONAL_ACCESS_TOKEN=fixture-credential \
  PROTON_PASS_DISABLE_TELEMETRY=fixture-telemetry \
    run_pass_cli 1 --version
)
assert_eq "Proton Pass CLI 2.3.2 (mock)" "$runner_version" "pass-cli wrapper environment"

set +e
MOCK_SCENARIO=timeout-sleeps MOCK_SLEEP_SECONDS=1 run_pass_cli 0.02 vault list --output json >/dev/null 2>&1
runner_timeout_status=$?
set -e
assert_eq "124" "$runner_timeout_status" "pass-cli timeout wrapper"

: >"$MOCK_CALLS_LOG"
multivault_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and (.items|length) == 2 and ([.items[].vaultName]|sort) == ["Personal","Work"] and ([.items[].title]|unique) == ["T0 Synthetic Login"] and .warnings == []' "$multivault_index" "index multi-vault merge with duplicate titles"
multivault_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 3 and .[0] == ["vault","list","--output","json"] and (.[1:]|all(.[0] == "item" and .[1] == "list" and .[4:] == ["--filter-type","login","--filter-state","active","--output","json"]))' "$multivault_calls" "index pass-cli argv"

: >"$MOCK_CALLS_LOG"
excluded_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults '  Work , Missing  ')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and .warnings == []' "$excluded_index" "trim-aware vault exclusion"
excluded_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 2 and all(.[]; (join(" ")|contains("Work")|not) and (join(" ")|contains("Personal")|not)) and .[1][3] == "share_fixture_1"' "$excluded_calls" "vault names absent from argv"

case_sensitive_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults 'work')
assert_jq '(.items|length) == 2' "$case_sensitive_index" "vault exclusion is case-sensitive"
all_excluded_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults ' Personal, Work ')
assert_jq '.state == "ready" and .items == [] and .warnings == []' "$all_excluded_index" "all vaults excluded"

empty_vault_index=$(MOCK_SCENARIO=empty-vault "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and (.items|length) == 1 and .warnings == []' "$empty_vault_index" "empty vault index"
zero_vault_index=$(MOCK_SCENARIO=zero-vaults "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and .items == [] and .warnings == []' "$zero_vault_index" "zero vault index"

: >"$MOCK_CALLS_LOG"
unicode_index=$(MOCK_SCENARIO=unicode-titles "$HELPER" index --exclude-vaults '')
# shellcheck disable=SC2016
assert_jq '(.items|length) == 5 and any(.items[]; .title == "Quote \"login\"") and any(.items[]; .title == "Line\nbreak") and any(.items[]; .title == "Emoji 🔐") and any(.items[]; .title == "RTL مثال") and any(.items[]; .title|contains("$(touch /tmp/never-run)"))' "$unicode_index" "index preserves unicode and metacharacter titles"
[[ ! -e /tmp/never-run ]] || fail "index executed title metacharacters"
unicode_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
# shellcheck disable=SC2016
assert_jq 'all(.[]; (join(" ")|contains("Quote \"login\"")|not) and (join(" ")|contains("Emoji 🔐")|not) and (join(" ")|contains("$(touch /tmp/never-run)")|not))' "$unicode_calls" "item titles absent from argv"

: >"$MOCK_CALLS_LOG"
partial_index=$(MOCK_SCENARIO=ready-multivault MOCK_FAIL_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and .warnings == ["A vault could not be loaded"] and (.message|contains("Some vaults"))' "$partial_index" "index partial failure"
partial_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 3 and any(.[]; index("share_fixture_2"))' "$partial_calls" "index continues through per-vault failure"

malformed_vault_index=$(MOCK_SCENARIO=malformed-json "$HELPER" index --exclude-vaults '')
assert_jq '.state == "error" and .items == [] and .warnings == [] and (.message|contains("pass-cli"))' "$malformed_vault_index" "malformed vault JSON"
malformed_item_index=$(MOCK_SCENARIO=ready-multivault MOCK_MALFORMED_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and (.warnings|length) == 1' "$malformed_item_index" "malformed per-vault JSON"

for scenario_state in 'logged-out:logged-out' 'expired:logged-out' 'locked:locked' 'offline:unreachable' 'timeout-sleeps:unreachable'; do
  scenario=${scenario_state%%:*}
  expected_state=${scenario_state#*:}
  if [[ $scenario == timeout-sleeps ]]; then
    classified_index=$(MOCK_SCENARIO=$scenario MOCK_TIMEOUT_EXIT=1 "$HELPER" index --exclude-vaults '')
  else
    classified_index=$(MOCK_SCENARIO=$scenario "$HELPER" index --exclude-vaults '')
  fi
  assert_jq ".state == \"$expected_state\" and .items == [] and .warnings == [] and (.message|type) == \"string\"" "$classified_index" "index state for $scenario"
done

expired_index=$(MOCK_SCENARIO=expired "$HELPER" index --exclude-vaults '')
assert_jq '.message == "Session expired — sign in again" and (tostring|contains("non-existent session")|not)' "$expired_index" "index sanitizes revoked-session stderr"

rm "$TEST_BIN/pass-cli"
missing_cli_index=$("$HELPER" index --exclude-vaults '')
assert_jq '.state == "cli-missing" and .items == [] and .warnings == [] and .message == "Proton Pass CLI not found"' "$missing_cli_index" "index missing pass-cli"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

hash_value() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

: >"$MOCK_CALLS_LOG"
: >"$MOCK_WL_COPY_LOG"
password_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.schemaVersion == 1 and .command == "copy" and .state == "copied" and .field == "password" and .fallbackUsed == false and .clearSeconds == 0 and (keys|sort) == ["clearSeconds","command","fallbackUsed","field","message","schemaVersion","state"]' "$password_copy" "password copy contract"
if [[ $password_copy == *synthetic-value* ]]; then fail "copy response contains secret value"; fi
password_hash=$(hash_value synthetic-value)
assert_jq ". == {args:[\"--sensitive\"],sha256:\"$password_hash\"}" "$(tail -n1 "$MOCK_WL_COPY_LOG")" "password copy bytes and sensitive argv"
password_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq '. == [["item","view","--share-id","share_fixture_1","--item-id","item_fixture_1","--field","password"]]' "$password_calls" "password pass-cli argv"

: >"$MOCK_WL_COPY_LOG"
paste_once_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0 --paste-once)
assert_jq '.state == "copied"' "$paste_once_copy" "paste-once copy"
assert_jq '.args == ["--sensitive","-o"]' "$(tail -n1 "$MOCK_WL_COPY_LOG")" "paste-once wl-copy argv"

: >"$MOCK_WL_COPY_LOG"
trailing_copy=$(MOCK_SCENARIO=value-with-trailing-newlines "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "copied"' "$trailing_copy" "trailing-newline copy"
expected_secret_hash=$(printf 'synthetic-value\n\n' | sha256sum | cut -d' ' -f1)
assert_jq ".sha256 == \"$expected_secret_hash\"" "$(tail -n1 "$MOCK_WL_COPY_LOG")" "sentinel strips exactly one trailing newline"

: >"$MOCK_CALLS_LOG"
username_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field username --clear-seconds 0)
assert_jq '.state == "copied" and .fallbackUsed == false' "$username_copy" "username copy"
assert_jq 'length == 1 and .[0][-1] == "username"' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "username single fetch"

: >"$MOCK_CALLS_LOG"
email_fallback_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_email_1 \
  --field username --clear-seconds 0)
assert_jq '.state == "copied" and .field == "username" and .fallbackUsed == true' "$email_fallback_copy" "email fallback copy"
assert_jq 'length == 2 and .[0][-1] == "username" and .[1][-1] == "email"' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "email fallback argv"

: >"$MOCK_CALLS_LOG"
empty_username_fallback=$(MOCK_SCENARIO=ready MOCK_EMPTY_FIELD=username "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_empty_username \
  --field username --clear-seconds 0)
assert_jq '.state == "copied" and .fallbackUsed == true' "$empty_username_fallback" "zero-length username fallback"
assert_jq 'length == 2 and .[1][-1] == "email"' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "zero-length fallback fetches email"

: >"$MOCK_WL_COPY_LOG"
missing_username_copy=$(MOCK_SCENARIO=no-username "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_email_1 \
  --field username --clear-seconds 0)
assert_jq '.state == "no-field" and .message == "No username or email on this item" and .fallbackUsed == false' "$missing_username_copy" "missing username and email"
[[ ! -s $MOCK_WL_COPY_LOG ]] || fail "missing username copied to clipboard"

missing_totp_copy=$(MOCK_SCENARIO=no-totp "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field totp --clear-seconds 0)
assert_jq '.state == "no-field" and .message == "No TOTP on this item"' "$missing_totp_copy" "missing TOTP"

: >"$MOCK_WL_COPY_LOG"
empty_password_copy=$(MOCK_SCENARIO=ready MOCK_EMPTY_FIELD=password "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "no-field" and .message == "No password on this item"' "$empty_password_copy" "zero-length password"
[[ ! -s $MOCK_WL_COPY_LOG ]] || fail "zero-length password copied to clipboard"

for variant_hash in \
  'canonical-multiple:123456' \
  'canonical-reversed:123456' \
  'custom:234567' \
  'uri-only:345678'; do
  variant=${variant_hash%%:*}
  expected_code=${variant_hash#*:}
  : >"$MOCK_CALLS_LOG"
  : >"$MOCK_WL_COPY_LOG"
  totp_copy=$(MOCK_SCENARIO=ready MOCK_TOTP_VARIANT=$variant "$HELPER" copy \
    --share-id share_fixture_1 --item-id item_fixture_1 \
    --field totp --clear-seconds 0)
  assert_jq '.state == "copied" and .field == "totp"' "$totp_copy" "TOTP extraction for $variant"
  expected_code_hash=$(hash_value "$expected_code")
  assert_jq ".sha256 == \"$expected_code_hash\"" "$(tail -n1 "$MOCK_WL_COPY_LOG")" "TOTP bytes for $variant"
  assert_jq 'length == 1 and .[0][0:2] == ["item","totp"] and (.[0]|index("--field")|not)' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "field-less TOTP argv for $variant"
done

: >"$MOCK_WL_COPY_LOG"
empty_totp_copy=$(MOCK_SCENARIO=ready MOCK_TOTP_VARIANT=empty "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field totp --clear-seconds 0)
assert_jq '.state == "error" and (.message|contains("Copy failed"))' "$empty_totp_copy" "empty TOTP map"
[[ ! -s $MOCK_WL_COPY_LOG ]] || fail "malformed TOTP copied to clipboard"

for scenario_state in 'logged-out:logged-out' 'expired:logged-out' 'locked:locked' 'offline:unreachable' 'timeout-sleeps:unreachable'; do
  scenario=${scenario_state%%:*}
  expected_state=${scenario_state#*:}
  if [[ $scenario == timeout-sleeps ]]; then
    failed_copy=$(MOCK_SCENARIO=$scenario MOCK_TIMEOUT_EXIT=1 "$HELPER" copy \
      --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
  else
    failed_copy=$(MOCK_SCENARIO=$scenario "$HELPER" copy \
      --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
  fi
  assert_jq ".state == \"$expected_state\" and .field == \"password\" and .fallbackUsed == false and .clearSeconds == 0" "$failed_copy" "copy state for $scenario"
done

: >"$MOCK_WL_COPY_LOG"
wl_copy_failure=$(MOCK_SCENARIO=ready MOCK_WL_COPY_EXIT=1 "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "error" and .message == "Copy failed — check connection and try again"' "$wl_copy_failure" "wl-copy failure"

: >"$MOCK_WL_COPY_LOG"
: >"$MOCK_WL_PASTE_LOG"
prompt_start=$EPOCHREALTIME
prompt_copy=$(MOCK_SCENARIO=ready \
  MOCK_WL_COPY_SLEEP_SECONDS=0.05 \
  MOCK_WL_PASTE_VALUE=synthetic-value \
  "$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 1)
prompt_end=$EPOCHREALTIME
prompt_elapsed=$(jq -n --arg start "$prompt_start" --arg end "$prompt_end" \
  '($end|tonumber) - ($start|tonumber)')
assert_jq '.state == "copied" and .clearSeconds == 1' "$prompt_copy" "timed-clear copy response"
assert_jq '. < 0.75' "$prompt_elapsed" "copy response returns before clearer sleeps"
sleep 1.2
matched_clear_calls=$(jq -sc '.' "$MOCK_WL_COPY_LOG")
assert_jq 'length == 2 and .[0].args == ["--sensitive"] and .[1].args == ["--clear"]' "$matched_clear_calls" "matching clipboard is cleared"
assert_jq 'length == 1 and .[0] == ["--no-newline"]' "$(jq -sc '.' "$MOCK_WL_PASTE_LOG")" "clearer reads clipboard without newline"

: >"$MOCK_WL_COPY_LOG"
: >"$MOCK_WL_PASTE_LOG"
newer_copy=$(MOCK_SCENARIO=ready MOCK_WL_PASTE_VALUE='newer clipboard value' \
  "$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 1)
assert_jq '.state == "copied"' "$newer_copy" "newer-content copy setup"
sleep 1.1
assert_jq 'length == 1 and .[0].args == ["--sensitive"]' "$(jq -sc '.' "$MOCK_WL_COPY_LOG")" "newer clipboard content survives expiry"

: >"$MOCK_WL_COPY_LOG"
: >"$MOCK_WL_PASTE_LOG"
zero_clear_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "copied" and .clearSeconds == 0' "$zero_clear_copy" "zero clear seconds"
sleep 0.1
[[ ! -s $MOCK_WL_PASTE_LOG ]] || fail "clearer spawned when clear seconds is zero"

: >"$MOCK_CALLS_LOG"
locked_response=$(MOCK_SCENARIO=ready "$HELPER" lock)
assert_jq '.schemaVersion == 1 and .command == "lock" and .state == "locked" and .message == "Session locked"' "$locked_response" "lock success"
assert_jq '. == [["session","lock"]]' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "lock pass-cli argv"
no_lock_response=$(MOCK_SCENARIO=no-lock "$HELPER" lock)
assert_jq '.state == "no-lock" and (.message|contains("create-lock")) and (tostring|contains("Session has no lock")|not)' "$no_lock_response" "lock without configured lock"
offline_lock=$(MOCK_SCENARIO=offline "$HELPER" lock)
assert_jq ".state == \"unreachable\" and .message == \"Can't reach Proton\"" "$offline_lock" "offline lock"

rm "$TEST_BIN/pass-cli"
missing_copy_cli=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
assert_jq '.state == "cli-missing"' "$missing_copy_cli" "copy missing pass-cli"
missing_lock_cli=$("$HELPER" lock)
assert_jq '.state == "cli-missing"' "$missing_lock_cli" "lock missing pass-cli"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

rm "$TEST_BIN/wl-copy"
missing_wl_copy=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
assert_jq '.state == "error" and (.message|contains("Copy failed"))' "$missing_wl_copy" "copy missing wl-copy"
ln -s "$TEST_ROOT/tests/mocks/wl-copy" "$TEST_BIN/wl-copy"

rm "$TEST_BIN/wl-paste"
missing_wl_paste=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 1)
assert_jq '.state == "error" and (.message|contains("Copy failed"))' "$missing_wl_paste" "timed copy missing wl-paste"
ln -s "$TEST_ROOT/tests/mocks/wl-paste" "$TEST_BIN/wl-paste"

run_shared_matrix_case() {
  local command_name=$1 scenario=$2 expected_state=$3
  local output_file="$TEST_SANDBOX/matrix-$command_name-$scenario.stdout"
  local stderr_file="$TEST_SANDBOX/matrix-$command_name-$scenario.stderr"
  local status
  local -a args

  case "$command_name" in
    index) args=(index --exclude-vaults '') ;;
    copy) args=(copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0) ;;
    lock) args=(lock) ;;
    *) fail "unsupported matrix command: $command_name" ;;
  esac

  set +e
  if [[ $scenario == timeout-sleeps ]]; then
    MOCK_SCENARIO=$scenario MOCK_TIMEOUT_EXIT=1 \
      "$HELPER" "${args[@]}" >"$output_file" 2>"$stderr_file"
  else
    MOCK_SCENARIO=$scenario \
      "$HELPER" "${args[@]}" >"$output_file" 2>"$stderr_file"
  fi
  status=$?
  set -e

  assert_eq "0" "$status" "$command_name $scenario handled exit status"
  [[ ! -s $stderr_file ]] || fail "$command_name $scenario wrote stderr"
  assert_jq ".schemaVersion == 1 and .command == \"$command_name\" and .state == \"$expected_state\"" \
    "$(<"$output_file")" "$command_name $scenario matrix contract"
}

for matrix_row in \
  'ready:ready:copied:locked' \
  'logged-out:logged-out:logged-out:logged-out' \
  'expired:logged-out:logged-out:logged-out' \
  'locked:locked:locked:locked' \
  'offline:unreachable:unreachable:unreachable' \
  'timeout-sleeps:unreachable:unreachable:unreachable'; do
  IFS=: read -r matrix_scenario index_state copy_state lock_state <<<"$matrix_row"
  run_shared_matrix_case index "$matrix_scenario" "$index_state"
  run_shared_matrix_case copy "$matrix_scenario" "$copy_state"
  run_shared_matrix_case lock "$matrix_scenario" "$lock_state"
done

printf 'helper and mock harness tests passed\n'
