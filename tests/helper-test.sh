#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
trap cleanup_test_sandbox EXIT
make_test_sandbox

PASS_CLI="$TEST_BIN/pass-cli"
FIXTURES="$TEST_ROOT/tests/fixtures"

# Harness self-tests. Everything else the mocks do is asserted through the
# helper's own responses further down; these three properties are not
# observable there: the mock must stay interruptible, must deliver hostile
# metadata without executing it, and must never record clipboard content.

set +e
MOCK_SCENARIO=timeout-sleeps MOCK_SLEEP_SECONDS=1 timeout 0.02 "$PASS_CLI" vault list --output json >/dev/null
timeout_status=$?
set -e
assert_eq "124" "$timeout_status" "timeout-sleeps remains interruptible"

unicode_items=$(MOCK_SCENARIO=unicode-titles "$PASS_CLI" item list --share-id share_fixture_1 --filter-type login --filter-state active --output json)
# shellcheck disable=SC2016
assert_jq '(.items|length) == 5 and any(.items[]; .title == "Quote \"login\"") and any(.items[]; .title == "Line\nbreak") and any(.items[]; .title == "Emoji 🔐") and any(.items[]; .title == "RTL مثال") and any(.items[]; .title|contains("$(touch /tmp/never-run)"))' "$unicode_items" "unicode and metacharacter titles"
[[ ! -e /tmp/never-run ]] || fail "shell metacharacters from a title were executed"

printf 'clipboard-marker' | "$TEST_BIN/wl-copy" --sensitive -o
assert_jq '(.args == ["--sensitive","-o"]) and (.sha256|type == "string")' "$(tail -n1 "$MOCK_WL_COPY_LOG")" "wl-copy argv and hash log"
if grep -Fq -- 'clipboard-marker' "$MOCK_WL_COPY_LOG"; then fail "wl-copy log contains clipboard content"; fi

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
assert_invalid_helper create create
assert_invalid_helper create create --share-id
assert_invalid_helper create create --share-id share --share-id other
assert_invalid_helper create create --share-id 'bad id'
assert_invalid_helper create create --unknown value
assert_invalid_helper lock lock extra
assert_invalid_helper lock lock --unknown
assert_invalid_helper logout logout extra
assert_invalid_helper clear-now clear-now extra
assert_invalid_helper recents recents
assert_invalid_helper recents recents load extra
assert_invalid_helper recents recents clear extra
assert_invalid_helper recents recents note --share-id share --item-id item
assert_invalid_helper recents recents unknown
calls_after_invalid=$(jq -sc 'length' "$MOCK_CALLS_LOG")
assert_eq "$calls_before_invalid" "$calls_after_invalid" "validation completes before pass-cli execution"

long_id=$(printf '%0257d' 0)
assert_invalid_helper copy copy --share-id "$long_id" --item-id item --field password --clear-seconds 45
# shellcheck disable=SC2016
assert_invalid_helper copy copy --share-id '$(touch /tmp/helper-never-run)' --item-id item --field password --clear-seconds 45
[[ ! -e /tmp/helper-never-run ]] || fail "invalid helper argument was executed"

index_ready=$(MOCK_SCENARIO=ready "$HELPER" index --exclude-vaults '')
assert_jq '.schemaVersion == 1 and .command == "index" and .state == "ready" and (.message|type) == "string" and .items == [{itemId:"item_fixture_1",shareId:"share_fixture_1",vaultName:"Personal",title:"T0 Synthetic Login",createTime:"2026-08-20T22:44:15"}] and .warnings == [] and .vaults == [{shareId:"share_fixture_1",name:"Personal"}]' "$index_ready" "index ready contract"

assert_invalid_create_input() {
  local body=$1 label=$2 output status
  set +e
  output=$(printf '%s' "$body" | "$HELPER" create --share-id share_fixture_1 \
    2>"$TEST_SANDBOX/create-invalid.stderr")
  status=$?
  set -e
  assert_eq "0" "$status" "invalid create input handled for $label"
  assert_jq '.schemaVersion == 1 and .command == "create" and .state == "invalid-input" and (.message|type) == "string"' \
    "$output" "invalid create input envelope for $label"
  [[ ! -s $TEST_SANDBOX/create-invalid.stderr ]] || fail "invalid create input wrote stderr for $label"
}

calls_before_invalid_create=$(jq -sc 'length' "$MOCK_CALLS_LOG")
assert_invalid_create_input '' empty
assert_invalid_create_input '{not json' malformed
assert_invalid_create_input '[]' array
assert_invalid_create_input '{}' missing-fields
assert_invalid_create_input '{"title":"Login","username":"user","extra":true}' unknown-key
assert_invalid_create_input '{"title":"Login","username":"user","email":"mail@example.test"}' both-identifiers
assert_invalid_create_input '{"title":"Login"}' missing-identifier
assert_invalid_create_input '{"title":"","username":"user"}' empty-title
assert_invalid_create_input '{"title":7,"username":"user"}' non-string-title
assert_invalid_create_input '{"title":"Login","username":null}' non-string-username
long_create_value=$(printf '%0501d' 0)
assert_invalid_create_input "$(jq -cn --arg value "$long_create_value" '{title:$value,username:"user"}')" long-title
assert_invalid_create_input "$(jq -cn --arg value "$long_create_value" '{title:"Login",username:$value}')" long-username
assert_invalid_create_input "$(jq -cn --arg value "$long_create_value" '{title:"Login",email:$value}')" long-email
calls_after_invalid_create=$(jq -sc 'length' "$MOCK_CALLS_LOG")
assert_eq "$calls_before_invalid_create" "$calls_after_invalid_create" \
  "invalid create input reached pass-cli"

rm -f -- "$XDG_STATE_HOME/omarchy-protonpass/recents.json"
: >"$MOCK_CALLS_LOG"
create_username_body='{"title":"T20 Synthetic Login","username":"test-user@example.test"}'
create_username=$(printf '%s' "$create_username_body" | \
  MOCK_SCENARIO=create-username "$HELPER" create --share-id share_fixture_1)
assert_jq '.schemaVersion == 1 and .command == "create" and .state == "created" and
  .itemId == "item_created_1" and .shareId == "share_fixture_1" and (.message|type) == "string"' \
  "$create_username" "username create contract"
assert_jq '. == [["item","create","login","--share-id","share_fixture_1","--from-template","-"]]' \
  "$(jq -sc '.' "$MOCK_CALLS_LOG")" "create uses metadata-free fixed argv"
[[ $(<"$MOCK_CALLS_LOG") != *'T20 Synthetic Login'* ]] || fail "create title entered argv log"
[[ $(<"$MOCK_CALLS_LOG") != *'test-user@example.test'* ]] || fail "create username entered argv log"
create_recents=$("$HELPER" recents load)
assert_jq '.state == "ok" and .recents[0].shareId == "share_fixture_1" and
  .recents[0].itemId == "item_created_1"' "$create_recents" \
  "created login is appended to recents"

: >"$MOCK_CALLS_LOG"
create_email_body='{"title":"T20 Email Login","email":"mailbox@example.test"}'
create_email=$(printf '%s' "$create_email_body" | \
  MOCK_SCENARIO=create-email "$HELPER" create --share-id share_fixture_1)
assert_jq '.state == "created" and .itemId == "item_created_1" and .shareId == "share_fixture_1"' \
  "$create_email" "email create contract"
assert_jq 'all(.[]; (join(" ") | contains("T20 Email Login") | not) and
  (join(" ") | contains("mailbox@example.test") | not))' \
  "$(jq -sc '.' "$MOCK_CALLS_LOG")" "email create metadata absent from argv"

copy_contract=$("$HELPER" copy --clear-seconds 0000 --field totp --item-id item_1 --share-id share/1= --paste-once)
assert_jq '.schemaVersion == 1 and .command == "copy" and .state == "copied" and .field == "totp" and .fallbackUsed == false and .clearSeconds == 0' "$copy_contract" "copy contract"
lock_stub=$("$HELPER" lock)
assert_jq '.schemaVersion == 1 and .command == "lock" and .state == "locked" and (.message|type) == "string"' "$lock_stub" "lock contract"
logout_stub=$("$HELPER" logout)
assert_jq '.schemaVersion == 1 and .command == "logout" and .state == "logged-out-ok" and (.message|type) == "string"' "$logout_stub" "logout contract"
clear_now_empty=$("$HELPER" clear-now)
assert_jq '.schemaVersion == 1 and .command == "clear-now" and .state == "not-owner" and (.message|type) == "string"' "$clear_now_empty" "clear-now empty contract"
rm -f -- "$XDG_STATE_HOME/omarchy-protonpass/recents.json"
recents_empty=$("$HELPER" recents load)
assert_jq '.schemaVersion == 1 and .command == "recents" and .state == "ok" and .recents == [] and (.message|type) == "string"' "$recents_empty" "recents empty contract"
recents_clear_empty=$("$HELPER" recents clear)
assert_jq '.schemaVersion == 1 and .command == "recents" and .state == "ok" and (has("recents")|not)' "$recents_clear_empty" "recents clear absent store"

# Source only the helper's core functions; its guarded main must not execute.
# shellcheck disable=SC1090
source "$HELPER"

declare -A generated_passwords=()
for generation_run in {1..25}; do
  generate_password || fail "password generation failed on run $generation_run"
  [[ ${#GENERATED_PASSWORD} -eq $FIXTURE_PASSWORD_LENGTH ]] || \
    fail "generated password length on run $generation_run"
  [[ $GENERATED_PASSWORD =~ $FIXTURE_PASSWORD_CHARSET_REGEX ]] || \
    fail "generated password charset on run $generation_run"
  [[ $GENERATED_PASSWORD =~ [A-Z] && $GENERATED_PASSWORD =~ [a-z] &&
     $GENERATED_PASSWORD =~ [0-9] && $GENERATED_PASSWORD =~ $FIXTURE_PASSWORD_SYMBOL_REGEX ]] || \
    fail "generated password class coverage on run $generation_run"
  [[ -z ${generated_passwords[$GENERATED_PASSWORD]:-} ]] || \
    fail "generated password repeated on run $generation_run"
  generated_passwords[$GENERATED_PASSWORD]=1
  GENERATED_PASSWORD=""
done
(( ${#RANDOM_POOL[@]} == 0 )) || fail "random pool retained words after generation"
[[ -z ${RANDOM_WORD:-} ]] || fail "random pool retained its last word after generation"
unset GENERATED_PASSWORD generated_passwords

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

for capture_run in {1..25}; do
  capture_stdout=""
  capture_stderr=""
  capture_status=0
  run_pass_cli_captured false capture_stdout capture_stderr capture_status 1 --version
  assert_eq "0" "$capture_status" "captured runner stress status $capture_run"
  assert_eq "Proton Pass CLI 2.3.2 (mock)" "$capture_stdout" \
    "captured runner stress stdout $capture_run"
  assert_eq "" "$capture_stderr" "captured runner stress stderr $capture_run"

  capture_value=""
  capture_secret_stderr=""
  capture_secret_status=0
  run_pass_cli_captured true capture_value capture_secret_stderr capture_secret_status 1 \
    item view --share-id share_fixture_1 --item-id item_fixture_1 --field password
  assert_eq "0" "$capture_secret_status" "secret runner stress status $capture_run"
  assert_eq "synthetic-value" "$capture_value" "secret runner stress value $capture_run"
  assert_eq "" "$capture_secret_stderr" "secret runner stress stderr $capture_run"
done

# The scratch file carries stderr only, and only for the length of one call.
[[ -f $STDERR_CAPTURE_FILE && ! -L $STDERR_CAPTURE_FILE ]] || \
  fail "captured stderr scratch file is missing or unsafe"
assert_eq "600" "$(stat -c '%a' "$STDERR_CAPTURE_FILE")" "captured stderr scratch file mode"
[[ ! -s $STDERR_CAPTURE_FILE ]] || fail "captured stderr scratch file retained content"

set +e
MOCK_SCENARIO=timeout-sleeps MOCK_SLEEP_SECONDS=1 run_pass_cli 0.02 vault list --output json >/dev/null 2>&1
runner_timeout_status=$?
set -e
assert_eq "124" "$runner_timeout_status" "pass-cli timeout wrapper"

: >"$MOCK_CALLS_LOG"
multivault_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and (.items|length) == 2 and ([.items[].vaultName]|sort) == ["Personal","Work"] and ([.items[].title]|unique) == ["T0 Synthetic Login"] and .warnings == [] and .vaults == [{shareId:"share_fixture_1",name:"Personal"},{shareId:"share_fixture_2",name:"Work"}]' "$multivault_index" "index multi-vault merge with duplicate titles"
multivault_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 3 and .[0] == ["vault","list","--output","json"] and (.[1:]|all(.[0] == "item" and .[1] == "list" and .[4:] == ["--filter-type","login","--filter-state","active","--output","json"]))' "$multivault_calls" "index pass-cli argv"

: >"$MOCK_CALLS_LOG"
excluded_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults '  Work , Missing  ')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and .warnings == [] and .vaults == [{shareId:"share_fixture_1",name:"Personal"}]' "$excluded_index" "trim-aware vault exclusion"
excluded_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 2 and all(.[]; (join(" ")|contains("Work")|not) and (join(" ")|contains("Personal")|not)) and .[1][3] == "share_fixture_1"' "$excluded_calls" "vault names absent from argv"

case_sensitive_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults 'work')
assert_jq '(.items|length) == 2' "$case_sensitive_index" "vault exclusion is case-sensitive"
all_excluded_index=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults ' Personal, Work ')
assert_jq '.state == "ready" and .items == [] and .warnings == [] and .vaults == []' "$all_excluded_index" "all vaults excluded"

empty_vault_index=$(MOCK_SCENARIO=empty-vault "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and (.items|length) == 1 and .warnings == [] and (.vaults|length) == 2 and any(.vaults[]; .shareId == "share_fixture_2" and .name == "Work")' "$empty_vault_index" "empty vault index"
zero_login_index=$(MOCK_SCENARIO=zero-logins "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and .items == [] and .warnings == [] and .vaults == [{shareId:"share_fixture_1",name:"Personal"},{shareId:"share_fixture_2",name:"Work"}]' "$zero_login_index" "zero-login index retains creation vaults"
zero_vault_index=$(MOCK_SCENARIO=zero-vaults "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and .items == [] and .warnings == [] and .vaults == []' "$zero_vault_index" "zero vault index"
malformed_vault_entry_index=$(MOCK_SCENARIO=malformed-vault-entry "$HELPER" index --exclude-vaults '')
assert_jq '.state == "error" and .items == [] and .warnings == [] and .vaults == []' \
  "$malformed_vault_entry_index" "empty vault names do not enter the contract"

: >"$MOCK_CALLS_LOG"
unicode_index=$(MOCK_SCENARIO=unicode-titles "$HELPER" index --exclude-vaults '')
# shellcheck disable=SC2016
assert_jq '(.items|length) == 5 and any(.items[]; .title == "Quote \"login\"") and any(.items[]; .title == "Line\nbreak") and any(.items[]; .title == "Emoji 🔐") and any(.items[]; .title == "RTL مثال") and any(.items[]; .title|contains("$(touch /tmp/never-run)"))' "$unicode_index" "index preserves unicode and metacharacter titles"
[[ ! -e /tmp/never-run ]] || fail "index executed title metacharacters"
unicode_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
# shellcheck disable=SC2016
assert_jq 'all(.[]; (join(" ")|contains("Quote \"login\"")|not) and (join(" ")|contains("Emoji 🔐")|not) and (join(" ")|contains("$(touch /tmp/never-run)")|not))' "$unicode_calls" "item titles absent from argv"

: >"$MOCK_CALLS_LOG"
oversized_index=$(MOCK_SCENARIO=oversized-title "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and (.items|length) == 2 and .warnings == []' \
  "$oversized_index" "an oversized title does not hide the rest of the vault"
assert_jq '[.items[] | select(.itemId == "item_oversized") | .title]
  == [("T" * 256)]' \
  "$oversized_index" "oversized title truncated to the display limit"
assert_jq '(.items[] | select(.itemId == "item_fixture_1") | .title) == "T0 Synthetic Login"' \
  "$oversized_index" "normal title untouched"
assert_jq 'all(.items[]; .vaultName == ("V" * 256))' \
  "$oversized_index" "oversized vault name truncated to the display limit"
assert_jq '.vaults == [{shareId:"share_fixture_1",name:("V" * 256)}]' \
  "$oversized_index" "oversized vault name truncated in the vault contract"

: >"$MOCK_CALLS_LOG"
partial_index=$(MOCK_SCENARIO=ready-multivault MOCK_FAIL_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and .warnings == ["A vault could not be loaded"] and (.vaults|length) == 2 and (.message|contains("Some vaults"))' "$partial_index" "index partial failure"
partial_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq 'length == 3 and any(.[]; index("share_fixture_2"))' "$partial_calls" "index continues through per-vault failure"

malformed_vault_index=$(MOCK_SCENARIO=malformed-json "$HELPER" index --exclude-vaults '')
assert_jq '.state == "error" and .items == [] and .warnings == [] and .vaults == [] and (.message|contains("pass-cli"))' "$malformed_vault_index" "malformed vault JSON"
malformed_item_index=$(MOCK_SCENARIO=ready-multivault MOCK_MALFORMED_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '')
assert_jq '.state == "ready" and [.items[].vaultName] == ["Personal"] and (.warnings|length) == 1 and (.vaults|length) == 2' "$malformed_item_index" "malformed per-vault JSON"

expired_index=$(MOCK_SCENARIO=expired "$HELPER" index --exclude-vaults '')
assert_jq '.message == "Session expired — sign in again" and (tostring|contains("non-existent session")|not)' "$expired_index" "index sanitizes revoked-session stderr"

rm "$TEST_BIN/pass-cli"
missing_cli_index=$("$HELPER" index --exclude-vaults '')
assert_jq '.state == "cli-missing" and .items == [] and .warnings == [] and .message == "Proton Pass CLI not found"' "$missing_cli_index" "index missing pass-cli"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

hash_value() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

RECENTS_FILE="$XDG_STATE_HOME/omarchy-protonpass/recents.json"
CLIP_HASH_FILE="$XDG_RUNTIME_DIR/omarchy-protonpass.clip"

# `recents note` was a public subcommand with no callers (R-C); the store is
# exercised through the copy path, its only remaining writer.
note_via_copy() {
  local share_id=$1 item_id=$2 label=$3 response
  response=$(MOCK_SCENARIO=ready "$HELPER" copy \
    --share-id "$share_id" --item-id "$item_id" \
    --field password --clear-seconds 0)
  assert_jq '.state == "copied"' "$response" "$label"
}

for recent_number in {1..9}; do
  note_via_copy "share_recent_$recent_number" "item_recent_$recent_number" \
    "recents note $recent_number"
done
recents_loaded=$("$HELPER" recents load)
assert_jq '.state == "ok" and (.recents|length) == 8 and
  .recents[0].shareId == "share_recent_9" and .recents[0].itemId == "item_recent_9" and
  .recents[7].shareId == "share_recent_2" and
  all(.recents[]; '"$FIXTURE_RECENTS_ENTRY_SHAPE"')' \
  "$recents_loaded" "recents prunes to eight most-recent entries"
assert_eq "600" "$(stat -c '%a' "$RECENTS_FILE")" "recents file mode"
assert_jq 'keys == ["recents"] and (.recents|length) == 8 and
  all(.recents[]; '"$FIXTURE_RECENTS_ENTRY_SHAPE"')' "$(<"$RECENTS_FILE")" \
  "recents file contains only opaque ids and timestamps"

note_via_copy share_recent_4 item_recent_4 "recents promote existing item"
promoted_recents=$("$HELPER" recents load)
assert_jq '(.recents|length) == 8 and .recents[0].shareId == "share_recent_4" and
  .recents[0].itemId == "item_recent_4" and
  ([.recents[] | select(.shareId == "share_recent_4" and .itemId == "item_recent_4")]|length) == 1' \
  "$promoted_recents" "recents promotion is unique"

recents_cleared=$("$HELPER" recents clear)
assert_jq '.state == "ok" and (has("recents")|not)' "$recents_cleared" "recents clear contract"
[[ ! -e $RECENTS_FILE && ! -L $RECENTS_FILE ]] || fail "recents clear left the store behind"

symlink_target="$TEST_SANDBOX/recents-symlink-target"
printf '%s\n' 'keep' >"$symlink_target"
ln -s "$symlink_target" "$RECENTS_FILE"
symlink_cleared=$("$HELPER" recents clear)
assert_jq '.state == "ok"' "$symlink_cleared" "recents clear removes a link, not its target"
[[ ! -L $RECENTS_FILE ]] || fail "recents clear left a symlink store behind"
assert_eq "keep" "$(<"$symlink_target")" "recents clear preserved symlink target"

printf '{"recents":[{"shareId":"share","itemId":"item","ts":1,"title":"forbidden"}]}\n' >"$RECENTS_FILE"
malformed_recents=$("$HELPER" recents load)
assert_jq '.state == "error" and .recents == []' "$malformed_recents" "recents rejects extra metadata"
rm -f -- "$RECENTS_FILE"

: >"$MOCK_CALLS_LOG"
: >"$MOCK_WL_COPY_LOG"
password_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.schemaVersion == 1 and .command == "copy" and .state == "copied" and .field == "password" and .fallbackUsed == false and .clearSeconds == 0 and (keys|sort) == ["clearSeconds","command","fallbackUsed","field","message","schemaVersion","state"]' "$password_copy" "password copy contract"
if [[ $password_copy == *synthetic-value* ]]; then fail "copy response contains secret value"; fi
password_hash=$(hash_value synthetic-value)
assert_jq ". == {args:[\"--sensitive\"],sha256:\"$password_hash\"}" "$(tail -n1 "$MOCK_WL_COPY_LOG")" "password copy bytes and sensitive argv"
assert_eq "$password_hash" "$(<"$CLIP_HASH_FILE")" "copy writes clipboard ownership hash"
assert_eq "600" "$(stat -c '%a' "$CLIP_HASH_FILE")" "clipboard hash file mode"
if ! grep -Eq '^[0-9a-f]{64}$' "$CLIP_HASH_FILE"; then fail "clipboard hash file contains non-hash data"; fi
assert_jq '.recents == [{shareId:"share_fixture_1",itemId:"item_fixture_1",ts:.recents[0].ts}] and
  (.recents[0].ts|type) == "number"' "$(<"$RECENTS_FILE")" "copy records recent ids only"
password_calls=$(jq -sc '.' "$MOCK_CALLS_LOG")
assert_jq '. == [["item","view","--share-id","share_fixture_1","--item-id","item_fixture_1","--field","password"]]' "$password_calls" "password pass-cli argv"

clear_now_match=$(MOCK_WL_PASTE_VALUE=synthetic-value "$HELPER" clear-now)
assert_jq '.schemaVersion == 1 and .command == "clear-now" and .state == "cleared"' \
  "$clear_now_match" "clear-now matching clipboard"
[[ ! -e $CLIP_HASH_FILE ]] || fail "clear-now left clipboard hash file"
assert_jq '.[-1].args == ["--clear"]' "$(jq -sc '.' "$MOCK_WL_COPY_LOG")" \
  "clear-now clears matching clipboard"
clear_now_again=$("$HELPER" clear-now)
assert_jq '.state == "not-owner"' "$clear_now_again" "clear-now without ownership"

: >"$MOCK_WL_COPY_LOG"
mismatch_setup=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "copied"' "$mismatch_setup" "clear-now mismatch setup"
clear_now_mismatch=$(MOCK_WL_PASTE_VALUE='newer clipboard value' "$HELPER" clear-now)
assert_jq '.state == "not-owner"' "$clear_now_mismatch" "clear-now preserves newer clipboard"
assert_jq 'length == 1 and .[0].args == ["--sensitive"]' "$(jq -sc '.' "$MOCK_WL_COPY_LOG")" \
  "clear-now does not clear mismatched clipboard"
assert_eq "$password_hash" "$(<"$CLIP_HASH_FILE")" "mismatched clear retains ownership record"

: >"$MOCK_WL_COPY_LOG"
clear_now_failure=$(MOCK_WL_PASTE_VALUE=synthetic-value MOCK_WL_COPY_EXIT=1 "$HELPER" clear-now)
assert_jq '.state == "error"' "$clear_now_failure" "clear-now wl-copy failure"
[[ -f $CLIP_HASH_FILE ]] || fail "failed clear-now removed clipboard hash file"

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

: >"$MOCK_WL_COPY_LOG"
wl_copy_failure=$(MOCK_SCENARIO=ready MOCK_WL_COPY_EXIT=1 "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "error" and .message == "Copy failed — check connection and try again"' "$wl_copy_failure" "wl-copy failure"

: >"$MOCK_WL_COPY_LOG"
missing_runtime_copy=$(XDG_RUNTIME_DIR="$TEST_SANDBOX/not-a-runtime-dir" MOCK_SCENARIO=ready \
  "$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "error"' "$missing_runtime_copy" "copy requires runtime hash storage"
[[ ! -s $MOCK_WL_COPY_LOG ]] || fail "copy offered a secret without runtime hash ownership"

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
[[ ! -e $CLIP_HASH_FILE ]] || fail "timed clear left clipboard hash file"

: >"$MOCK_WL_COPY_LOG"
: >"$MOCK_WL_PASTE_LOG"
newer_copy=$(MOCK_SCENARIO=ready MOCK_WL_PASTE_VALUE='newer clipboard value' \
  "$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 1)
assert_jq '.state == "copied"' "$newer_copy" "newer-content copy setup"
sleep 1.1
assert_jq 'length == 1 and .[0].args == ["--sensitive"]' "$(jq -sc '.' "$MOCK_WL_COPY_LOG")" "newer clipboard content survives expiry"
assert_eq "$password_hash" "$(<"$CLIP_HASH_FILE")" "newer clipboard keeps prior ownership hash"

: >"$MOCK_WL_COPY_LOG"
: >"$MOCK_WL_PASTE_LOG"
zero_clear_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_fixture_1 --item-id item_fixture_1 \
  --field password --clear-seconds 0)
assert_jq '.state == "copied" and .clearSeconds == 0' "$zero_clear_copy" "zero clear seconds"
sleep 0.1
[[ ! -s $MOCK_WL_PASTE_LOG ]] || fail "clearer spawned when clear seconds is zero"
assert_eq "$password_hash" "$(<"$CLIP_HASH_FILE")" "zero-expiry copy retains clear-now ownership"

: >"$MOCK_CALLS_LOG"
locked_response=$(MOCK_SCENARIO=ready "$HELPER" lock)
assert_jq '.schemaVersion == 1 and .command == "lock" and .state == "locked" and .message == "Session locked"' "$locked_response" "lock success"
assert_jq '. == [["session","lock"]]' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "lock pass-cli argv"
no_lock_response=$(MOCK_SCENARIO=no-lock "$HELPER" lock)
assert_jq '.state == "no-lock" and (.message|contains("create-lock")) and (tostring|contains("Session has no lock")|not)' "$no_lock_response" "lock without configured lock"
offline_lock=$(MOCK_SCENARIO=offline "$HELPER" lock)
assert_jq ".state == \"unreachable\" and .message == \"Can't reach Proton\"" "$offline_lock" "offline lock"

: >"$MOCK_CALLS_LOG"
logout_response=$(MOCK_SCENARIO=ready "$HELPER" logout)
assert_jq '.schemaVersion == 1 and .command == "logout" and .state == "logged-out-ok"' \
  "$logout_response" "logout success"
assert_jq '. == [["logout"]]' "$(jq -sc '.' "$MOCK_CALLS_LOG")" "logout fixed pass-cli argv"
already_logged_out=$(MOCK_SCENARIO=already-logged-out "$HELPER" logout)
assert_jq '.state == "logged-out-ok"' "$already_logged_out" "logout is idempotent"
offline_logout=$(MOCK_SCENARIO=offline "$HELPER" logout)
assert_jq '.state == "unreachable"' "$offline_logout" "offline logout"
failed_logout=$(MOCK_SCENARIO=logout-error "$HELPER" logout)
assert_jq '.state == "error" and (tostring|contains("Synthetic logout failure")|not)' \
  "$failed_logout" "logout sanitizes generic stderr"
failed_create=$(printf '%s' "$create_username_body" | \
  MOCK_SCENARIO=create-error "$HELPER" create --share-id share_fixture_1)
assert_jq '.state == "error" and (tostring|contains("Synthetic create failure")|not)' \
  "$failed_create" "create sanitizes generic stderr"

rm "$TEST_BIN/pass-cli"
missing_copy_cli=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
assert_jq '.state == "cli-missing"' "$missing_copy_cli" "copy missing pass-cli"
missing_lock_cli=$("$HELPER" lock)
assert_jq '.state == "cli-missing"' "$missing_lock_cli" "lock missing pass-cli"
missing_logout_cli=$("$HELPER" logout)
assert_jq '.state == "cli-missing"' "$missing_logout_cli" "logout missing pass-cli"
missing_create_cli=$(printf '%s' "$create_username_body" | \
  "$HELPER" create --share-id share_fixture_1)
assert_jq '.state == "cli-missing"' "$missing_create_cli" "create missing pass-cli"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

rm "$TEST_BIN/wl-copy"
missing_wl_copy=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
assert_jq '.state == "error" and (.message|contains("Copy failed"))' "$missing_wl_copy" "copy missing wl-copy"
ln -s "$TEST_ROOT/tests/mocks/wl-copy" "$TEST_BIN/wl-copy"

rm "$TEST_BIN/wl-paste"
missing_wl_paste=$("$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 1)
assert_jq '.state == "error" and (.message|contains("Copy failed"))' "$missing_wl_paste" "timed copy missing wl-paste"
missing_wl_paste_clear=$("$HELPER" clear-now)
assert_jq '.state == "error"' "$missing_wl_paste_clear" "clear-now missing wl-paste"
ln -s "$TEST_ROOT/tests/mocks/wl-paste" "$TEST_BIN/wl-paste"

# The success envelope is emitted before recents bookkeeping (R-H). With the
# clock the bookkeeping needs made deliberately slow, the envelope still
# arrives immediately, and the store is still written before the helper exits.
real_date=$(readlink -f "$TEST_BIN/date")
rm "$TEST_BIN/date"
cat >"$TEST_BIN/date" <<SLOW_DATE
#!/usr/bin/env bash
sleep 1
exec "$real_date" "\$@"
SLOW_DATE
chmod +x "$TEST_BIN/date"

rm -f -- "$RECENTS_FILE"
order_start=$EPOCHREALTIME
IFS= read -r order_envelope < <(MOCK_SCENARIO=ready "$HELPER" copy \
  --share-id share_order_1 --item-id item_order_1 \
  --field password --clear-seconds 0)
order_end=$EPOCHREALTIME
order_elapsed=$(jq -n --arg start "$order_start" --arg end "$order_end" \
  '($end|tonumber) - ($start|tonumber)')
assert_jq '.state == "copied"' "$order_envelope" "ordered copy response"
assert_jq '. < 0.75' "$order_elapsed" "copy response precedes recents bookkeeping"

for _ in {1..40}; do
  if [[ -f $RECENTS_FILE ]] &&
     jq -e '.recents[0].itemId == "item_order_1"' "$RECENTS_FILE" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
assert_jq '.recents[0].shareId == "share_order_1" and .recents[0].itemId == "item_order_1"' \
  "$(<"$RECENTS_FILE")" "deferred bookkeeping still records the copy"

rm "$TEST_BIN/date"
ln -s "$real_date" "$TEST_BIN/date"

# Rapid successive copies must still leave the store ordered newest-first.
rm -f -- "$RECENTS_FILE"
for rapid_number in {1..5}; do
  rapid_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
    --share-id "share_rapid_$rapid_number" --item-id "item_rapid_$rapid_number" \
    --field password --clear-seconds 0)
  assert_jq '.state == "copied"' "$rapid_copy" "rapid copy $rapid_number"
done
rapid_recents=$("$HELPER" recents load)
assert_jq '[.recents[].itemId] ==
  ["item_rapid_5","item_rapid_4","item_rapid_3","item_rapid_2","item_rapid_1"]' \
  "$rapid_recents" "rapid successive copies stay ordered"

# Callers may read the helper through a pipe rather than a command
# substitution; capture must not depend on the caller's fd layout, and stdin
# stays closed so nothing downstream waits on input.
for piped_run in {1..5}; do
  piped_copy=$(MOCK_SCENARIO=ready "$HELPER" copy \
    --share-id share_fixture_1 --item-id item_fixture_1 \
    --field password --clear-seconds 0 2>&1 </dev/null | tail -n1)
  assert_jq '.state == "copied" and .field == "password"' "$piped_copy" \
    "piped copy invocation $piped_run"
done
piped_index=$(MOCK_SCENARIO=ready "$HELPER" index --exclude-vaults '' 2>&1 </dev/null | tail -n1)
assert_jq '.state == "ready"' "$piped_index" "piped index invocation"
piped_clear=$(MOCK_WL_PASTE_VALUE=synthetic-value "$HELPER" clear-now 2>&1 </dev/null | tail -n1)
assert_jq '.command == "clear-now"' "$piped_clear" "piped clear-now invocation"
piped_lock=$(MOCK_SCENARIO=offline "$HELPER" lock 2>&1 </dev/null | tail -n1)
assert_jq '.state == "unreachable"' "$piped_lock" "piped lock invocation"

# Every command x scenario pair goes through here: the envelope contract, the
# exit status, the silent stderr, and each command's payload for that state.
run_shared_matrix_case() {
  local command_name=$1 scenario=$2 expected_state=$3
  local output_file="$TEST_SANDBOX/matrix-$command_name-$scenario.stdout"
  local stderr_file="$TEST_SANDBOX/matrix-$command_name-$scenario.stderr"
  local status payload='true'
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

  # Payload the command must still carry in this state.
  case "$command_name" in
    index)
      [[ $expected_state == ready ]] ||
        payload='.items == [] and .warnings == [] and .vaults == []'
      ;;
    copy) payload='.field == "password" and .fallbackUsed == false and .clearSeconds == 0' ;;
  esac

  assert_eq "0" "$status" "$command_name $scenario handled exit status"
  [[ ! -s $stderr_file ]] || fail "$command_name $scenario wrote stderr"
  assert_jq ".schemaVersion == 1 and .command == \"$command_name\" and .state == \"$expected_state\"
    and (.message|type) == \"string\" and ($payload)" \
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

for create_row in \
  'ready:created' \
  'logged-out:logged-out' \
  'expired:logged-out' \
  'locked:locked' \
  'offline:unreachable' \
  'timeout-sleeps:unreachable'; do
  IFS=: read -r create_scenario create_state <<<"$create_row"
  if [[ $create_scenario == timeout-sleeps ]]; then
    create_matrix=$(printf '%s' "$create_username_body" | \
      MOCK_SCENARIO=$create_scenario MOCK_TIMEOUT_EXIT=1 \
      "$HELPER" create --share-id share_fixture_1)
  else
    create_matrix=$(printf '%s' "$create_username_body" | \
      MOCK_SCENARIO=$create_scenario "$HELPER" create --share-id share_fixture_1)
  fi
  assert_jq ".schemaVersion == 1 and .command == \"create\" and .state == \"$create_state\"" \
    "$create_matrix" "create $create_scenario matrix contract"
done

for logout_row in \
  'ready:logged-out-ok' \
  'logged-out:logged-out-ok' \
  'expired:logged-out-ok' \
  'locked:error' \
  'offline:unreachable' \
  'timeout-sleeps:unreachable'; do
  IFS=: read -r logout_scenario logout_state <<<"$logout_row"
  if [[ $logout_scenario == timeout-sleeps ]]; then
    logout_matrix=$(MOCK_SCENARIO=$logout_scenario MOCK_TIMEOUT_EXIT=1 "$HELPER" logout)
  else
    logout_matrix=$(MOCK_SCENARIO=$logout_scenario "$HELPER" logout)
  fi
  assert_jq ".schemaVersion == 1 and .command == \"logout\" and .state == \"$logout_state\"" \
    "$logout_matrix" "logout $logout_scenario matrix contract"
done

printf 'helper and mock harness tests passed\n'
