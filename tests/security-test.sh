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
done < <(find "$ROOT" -maxdepth 1 -type f \( -name '*.qml' -o -name '*.js' \) -print)

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
if grep -En -- '^[[:space:]]*export([[:space:]]|$)' "$HELPER" >/dev/null; then
  fail "helper exports environment variables"
fi
fail_on_match 'property[[:space:]]+(string|var)[[:space:]]+_?(secret|password|username|totp)(value|text|code|data)?[[:space:]:]' \
  "QML declares a property that could retain a secret"

if grep -Fn -- '--show-secrets' "${security_sources[@]}" >/dev/null; then
  fail "runtime source enables pass-cli secret display"
fi
if grep -Fn -- '--generate-password' "${security_sources[@]}" >/dev/null; then
  fail "runtime source delegates generation through the incompatible argv path"
fi
if grep -Fn -- '--password' "${security_sources[@]}" >/dev/null; then
  fail "runtime source places a password option in argv"
fi
# The pinned text is helper source, not an expansion.
# shellcheck disable=SC2016
grep -Fq -- '--share-id "$CREATE_SHARE_ID" --from-template -' "$HELPER" ||
  fail "create does not use the fixed stdin-template command"
grep -Fq -- 'od -An -N256 -tu4 /dev/urandom' "$HELPER" ||
  fail "create password generation does not read /dev/urandom"
grep -Fq -- 'unset password CREATE_INPUT' "$HELPER" ||
  fail "create does not wipe its password variable after the stdin pipe closes"
if grep -Fn -- '`' "${security_sources[@]}" >/dev/null; then
  fail "runtime source contains backtick interpolation"
fi

make_test_sandbox

proc_file_contains_marker() {
  local file=$1 marker=${2:-$MARKER} part content=""
  [[ -r $file ]] || return 1
  while IFS= read -r -d '' part; do
    content+=$part
  done <"$file" 2>/dev/null || true
  [[ $content == *"$marker"* ]]
}

regular_file_contains_marker() {
  local file=$1 marker=${2:-$MARKER} content=""
  [[ -r $file ]] || return 1
  content=$(<"$file")
  [[ $content == *"$marker"* ]]
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
for internal_name in CLIP_HASH RECENTS_DATA STDERR_CAPTURE_FILE; do
  if grep -Fzq -- "$internal_name=" "/proc/$helper_pid/environ" 2>/dev/null; then
    fail "helper exported internal storage variable: $internal_name"
  fi
done

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

clip_hash_file="$XDG_RUNTIME_DIR/omarchy-protonpass.clip"
[[ -f $clip_hash_file && ! -L $clip_hash_file ]] || fail "clipboard hash file is missing or unsafe"
assert_eq "600" "$(stat -c '%a' "$clip_hash_file")" "clipboard hash file mode"
assert_eq "$expected_hash" "$(<"$clip_hash_file")" "clipboard hash file content"
if ! grep -Eq '^[0-9a-f]{64}$' "$clip_hash_file"; then
  fail "clipboard ownership file contains data besides one hash"
fi

# Bookkeeping now runs after the success envelope (R-H) but still inside the
# helper, so waiting for the process above is enough to sequence this.
recents_file="$XDG_STATE_HOME/omarchy-protonpass/recents.json"
[[ -f $recents_file && ! -L $recents_file ]] || fail "recents file is missing or unsafe"
assert_eq "600" "$(stat -c '%a' "$recents_file")" "recents file mode"
assert_jq 'keys == ["recents"] and (.recents|length) == 1 and
  all(.recents[]; '"$FIXTURE_RECENTS_ENTRY_SHAPE"')' "$(<"$recents_file")" \
  "recents file contains only ids and timestamps"

# stderr capture uses a scratch file for the length of one call; nothing may
# outlive the helper in the runtime directory but the clipboard hash.
while IFS= read -r runtime_file; do
  [[ ${runtime_file##*/} == omarchy-protonpass.clip ]] ||
    fail "helper left a scratch file behind: $runtime_file"
done < <(find "$XDG_RUNTIME_DIR" -type f -print)

: >"$MOCK_CALLS_LOG"
logout_response=$(MOCK_SCENARIO=ready "$HELPER" logout)
assert_jq '.command == "logout" and .state == "logged-out-ok"' "$logout_response" \
  "logout security contract"
assert_jq '. == [["logout"]]' "$(jq -sc '.' "$MOCK_CALLS_LOG")" \
  "logout uses fixed argv"

CREATE_TITLE_MARKER=OMPP-CREATE-TITLE-5bb63d1e
CREATE_USERNAME_MARKER=OMPP-CREATE-USERNAME-8e301a4c
create_body=$(jq -cn \
  --arg title "$CREATE_TITLE_MARKER" \
  --arg username "$CREATE_USERNAME_MARKER" \
  '{title:$title,username:$username}')
: >"$MOCK_CALLS_LOG"
printf '%s' "$create_body" | \
  MOCK_SCENARIO=security-create MOCK_CREATE_SLEEP_SECONDS=1 \
  "$HELPER" create --share-id share_fixture_1 \
    >"$TEST_SANDBOX/create-security.stdout" \
    2>"$TEST_SANDBOX/create-security.stderr" &
create_helper_pid=$!

sleep 0.1
kill -0 "$create_helper_pid" 2>/dev/null || fail "create helper exited before process inspection"
for cmdline in /proc/[0-9]*/cmdline; do
  if proc_file_contains_marker "$cmdline" "$CREATE_TITLE_MARKER" ||
     proc_file_contains_marker "$cmdline" "$CREATE_USERNAME_MARKER"; then
    fail "create metadata appeared in a process command line"
  fi
done
if proc_file_contains_marker "/proc/$create_helper_pid/environ" "$CREATE_TITLE_MARKER" ||
   proc_file_contains_marker "/proc/$create_helper_pid/environ" "$CREATE_USERNAME_MARKER"; then
  fail "create metadata appeared in the helper environment"
fi

wait "$create_helper_pid"
create_body=""
unset create_body
[[ ! -s $TEST_SANDBOX/create-security.stderr ]] || fail "create helper wrote stderr"
assert_jq '.command == "create" and .state == "created" and
  .itemId == "item_created_1" and .shareId == "share_fixture_1"' \
  "$(<"$TEST_SANDBOX/create-security.stdout")" "security create response"
assert_jq '. == [["item","create","login","--share-id","share_fixture_1","--from-template","-"]]' \
  "$(jq -sc '.' "$MOCK_CALLS_LOG")" "create uses fixed metadata-free argv"
if grep -Fq -- "$CREATE_TITLE_MARKER" "$MOCK_CALLS_LOG" ||
   grep -Fq -- "$CREATE_USERNAME_MARKER" "$MOCK_CALLS_LOG"; then
  fail "create metadata entered the pass-cli argv log"
fi

# The state directory is the only place the helper writes anything that
# outlives a command, so it is the place a disk-persisted index would land.
# PLAN 1.3 defers such an index and PLAN 3.7 records that item metadata is
# never at rest; SECURITY.md promises the recents store holds ids and no
# names. The scan terms are read from the fixtures the mock serves rather
# than kept by hand, so a fixture change cannot quietly empty the list.
state_residue_terms=("$MARKER" "$CREATE_TITLE_MARKER" "$CREATE_USERNAME_MARKER")
while IFS= read -r residue_term; do
  [[ -n $residue_term ]] || continue
  state_residue_terms+=("$residue_term")
done < <(
  jq -r '.items[].title' "$MOCK_FIXTURES_DIR/item-list.json"
  jq -r '.vaults[].name' "$MOCK_FIXTURES_DIR/vault-list.json"
  jq -r '.vaults[].name' "$MOCK_FIXTURES_DIR/vault-list-multiple.json"
  cat "$MOCK_FIXTURES_DIR/field-output-newline.txt"
)
(( ${#state_residue_terms[@]} >= 6 )) ||
  fail "state residue terms did not load from the mock fixtures"

STATE_FILES_SCANNED=0
assert_state_dir_clean() {
  local context=$1 state_file residue_term
  STATE_FILES_SCANNED=0
  while IFS= read -r -d '' state_file; do
    STATE_FILES_SCANNED=$(( STATE_FILES_SCANNED + 1 ))
    for residue_term in "${state_residue_terms[@]}"; do
      if regular_file_contains_marker "$state_file" "$residue_term"; then
        fail "vault data appeared in a state directory file after $context: $state_file"
      fi
    done
  done < <(find "$XDG_STATE_HOME" -type f -print0)
}

# Vault names and item titles reach the helper only through the index walk, so
# the walk has to run before the state directory can be judged clean. The
# multi-vault scenario is used because it carries two vault names.
index_response=$(MOCK_SCENARIO=ready-multivault "$HELPER" index --exclude-vaults '')
assert_jq '.command == "index" and .state == "ready" and
  (.items | length) > 0 and (.vaults | length) > 0' "$index_response" \
  "index walk ran before the state residue scan"
index_response=""
unset index_response

# Both the copy and the create above record a recent item, so the store now
# holds two entries and still nothing but ids and timestamps.
recents_loaded=$("$HELPER" recents load)
assert_jq '.command == "recents" and .state == "ok" and
  (.recents | length) == 2 and
  ([.recents[].itemId] | sort) == ["item_created_1", "item_fixture_1"] and
  all(.recents[]; '"$FIXTURE_RECENTS_ENTRY_SHAPE"')' "$recents_loaded" \
  "recents load returns ids and timestamps only"

assert_state_dir_clean "the copy, create, index and recents paths"
(( STATE_FILES_SCANNED > 0 )) ||
  fail "state residue scan found no files to read"

# Clearing removes the recents store. Anything still on disk afterwards
# outlived the only state the helper admits to keeping.
recents_cleared=$("$HELPER" recents clear)
assert_jq '.command == "recents" and .state == "ok" and (has("recents") | not)' \
  "$recents_cleared" "recents clear removed the store"
assert_state_dir_clean "clearing the recents store"

while IFS= read -r -d '' sandbox_file; do
  if regular_file_contains_marker "$sandbox_file"; then
    fail "secret marker appeared in a sandbox file"
  fi
  if regular_file_contains_marker "$sandbox_file" "$CREATE_TITLE_MARKER" ||
     regular_file_contains_marker "$sandbox_file" "$CREATE_USERNAME_MARKER"; then
    fail "create template metadata appeared in a sandbox file"
  fi
done < <(find "$TEST_SANDBOX" -type f -print0)

printf 'security tests passed\n'
