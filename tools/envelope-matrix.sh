#!/usr/bin/env bash
# Dumps every command x scenario JSON envelope for a given checkout of the
# helper, so a refactor can be diffed byte-for-byte against its baseline.
# Usage: envelope-matrix.sh <repo-root> > envelopes.txt
set -uo pipefail
shopt -s extglob

# The mock wl-copy reads stdin even for --clear; keep the matrix independent of
# whatever stdin the caller has open.
exec </dev/null

REPO=$(cd "$1" && pwd)
# shellcheck disable=SC1091
source "$REPO/tests/lib.sh"
TEST_ROOT=$REPO
trap cleanup_test_sandbox EXIT
make_test_sandbox

HELPER="$REPO/omarchy-protonpass"

emit() {
  local label=$1
  shift
  local out status
  out=$("$@" 2>"$TEST_SANDBOX/err")
  status=$?
  # Recents timestamps are wall-clock; normalise them so runs are comparable.
  out=${out//\"ts\":+([0-9])/\"ts\":0}
  printf '%s\t%s\t%s\tstderr=%s\n' "$label" "$status" "$out" "$(<"$TEST_SANDBOX/err")"
}

run_helper() {
  local label=$1
  shift
  emit "$label" "$HELPER" "$@"
}

scenario_helper() {
  local label=$1 scenario=$2
  shift 2
  local out status
  out=$(MOCK_SCENARIO=$scenario "$HELPER" "$@" 2>"$TEST_SANDBOX/err")
  status=$?
  out=${out//\"ts\":+([0-9])/\"ts\":0}
  printf '%s\t%s\t%s\tstderr=%s\n' "$label" "$status" "$out" "$(<"$TEST_SANDBOX/err")"
}

reset_state() {
  rm -f -- "$XDG_STATE_HOME/omarchy-protonpass/recents.json" "$XDG_RUNTIME_DIR/omarchy-protonpass.clip"
}

COPY_ARGS=(copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0)
CREATE_BODY='{"title":"T20 Synthetic Login","username":"test-user@example.test"}'

# --- argument errors -------------------------------------------------------
run_helper "argv:none"
run_helper "argv:unknown" frobnicate
run_helper "argv:doctor-extra" doctor extra
run_helper "argv:index-none" index
run_helper "argv:index-dup" index --exclude-vaults a --exclude-vaults b
run_helper "argv:copy-missing-clear" copy --share-id share --item-id item --field password
run_helper "argv:copy-bad-id" copy --share-id 'bad id' --item-id item --field password --clear-seconds 45
run_helper "argv:copy-bad-field" copy --share-id share --item-id item --field secret --clear-seconds 45
run_helper "argv:copy-bad-clear" copy --share-id share --item-id item --field password --clear-seconds 301
run_helper "argv:create-none" create
run_helper "argv:create-bad-id" create --share-id 'bad id'
run_helper "argv:lock-extra" lock extra
run_helper "argv:logout-extra" logout extra
run_helper "argv:clear-now-extra" clear-now extra
run_helper "argv:recents-none" recents
run_helper "argv:recents-unknown" recents unknown
run_helper "argv:recents-note-removed" recents note --share-id share --item-id item

# --- doctor ----------------------------------------------------------------
run_helper "doctor:ready" doctor
out=$(MOCK_PASS_CLI_VERSION=3.0.0 "$HELPER" doctor 2>&1)
printf 'doctor:major\t0\t%s\tstderr=\n' "$out"
rm "$TEST_BIN/pass-cli"
run_helper "doctor:no-cli" doctor
run_helper "index:no-cli" index --exclude-vaults ''
run_helper "copy:no-cli" "${COPY_ARGS[@]}"
run_helper "lock:no-cli" lock
run_helper "logout:no-cli" logout
out=$(printf '%s' "$CREATE_BODY" | "$HELPER" create --share-id share_fixture_1 2>&1)
printf 'create:no-cli\t0\t%s\tstderr=\n' "$out"
ln -s "$TEST_ROOT/tests/mocks/pass-cli" "$TEST_BIN/pass-cli"

rm "$TEST_BIN/wl-copy"
run_helper "copy:no-wl-copy" "${COPY_ARGS[@]}"
ln -s "$TEST_ROOT/tests/mocks/wl-copy" "$TEST_BIN/wl-copy"
rm "$TEST_BIN/wl-paste"
run_helper "copy:no-wl-paste" copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 5
run_helper "clear-now:no-wl-paste" clear-now
ln -s "$TEST_ROOT/tests/mocks/wl-paste" "$TEST_BIN/wl-paste"

# --- index -----------------------------------------------------------------
for scenario in ready ready-multivault empty-vault zero-logins zero-vaults \
                malformed-vault-entry malformed-json unicode-titles \
                logged-out expired locked offline; do
  scenario_helper "index:$scenario" "$scenario" index --exclude-vaults ''
done
scenario_helper "index:excluded" ready-multivault index --exclude-vaults '  Work , Missing  '
scenario_helper "index:all-excluded" ready-multivault index --exclude-vaults ' Personal, Work '
out=$(MOCK_SCENARIO=ready-multivault MOCK_FAIL_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '' 2>&1)
printf 'index:partial-fail\t0\t%s\tstderr=\n' "$out"
out=$(MOCK_SCENARIO=ready-multivault MOCK_MALFORMED_SHARE_ID=share_fixture_2 "$HELPER" index --exclude-vaults '' 2>&1)
printf 'index:partial-malformed\t0\t%s\tstderr=\n' "$out"
out=$(MOCK_SCENARIO=timeout-sleeps MOCK_TIMEOUT_EXIT=1 "$HELPER" index --exclude-vaults '' 2>&1)
printf 'index:timeout\t0\t%s\tstderr=\n' "$out"

# --- copy ------------------------------------------------------------------
reset_state
for scenario in ready logged-out expired locked offline; do
  reset_state
  scenario_helper "copy:$scenario" "$scenario" "${COPY_ARGS[@]}"
done
reset_state
out=$(MOCK_SCENARIO=timeout-sleeps MOCK_TIMEOUT_EXIT=1 "$HELPER" "${COPY_ARGS[@]}" 2>&1)
printf 'copy:timeout\t0\t%s\tstderr=\n' "$out"
reset_state
scenario_helper "copy:username" ready copy --share-id share_fixture_1 --item-id item_fixture_1 --field username --clear-seconds 0
reset_state
scenario_helper "copy:email-fallback" ready copy --share-id share_fixture_1 --item-id item_email_1 --field username --clear-seconds 0
reset_state
out=$(MOCK_SCENARIO=ready MOCK_EMPTY_FIELD=username "$HELPER" copy --share-id share_fixture_1 --item-id item_empty_username --field username --clear-seconds 0 2>&1)
printf 'copy:empty-username-fallback\t0\t%s\tstderr=\n' "$out"
reset_state
scenario_helper "copy:no-username" no-username copy --share-id share_fixture_1 --item-id item_email_1 --field username --clear-seconds 0
reset_state
out=$(MOCK_SCENARIO=ready MOCK_EMPTY_FIELD=password "$HELPER" "${COPY_ARGS[@]}" 2>&1)
printf 'copy:empty-password\t0\t%s\tstderr=\n' "$out"
reset_state
scenario_helper "copy:paste-once" ready copy --share-id share_fixture_1 --item-id item_fixture_1 --field password --clear-seconds 0 --paste-once
reset_state
scenario_helper "copy:trailing-newlines" value-with-trailing-newlines "${COPY_ARGS[@]}"
for variant in canonical canonical-multiple canonical-reversed custom uri-only empty broken; do
  reset_state
  out=$(MOCK_SCENARIO=ready MOCK_TOTP_VARIANT=$variant "$HELPER" copy --share-id share_fixture_1 --item-id item_fixture_1 --field totp --clear-seconds 0 2>&1)
  printf 'copy:totp-%s\t0\t%s\tstderr=\n' "$variant" "$out"
done
reset_state
scenario_helper "copy:no-totp" no-totp copy --share-id share_fixture_1 --item-id item_fixture_1 --field totp --clear-seconds 0
reset_state
out=$(MOCK_SCENARIO=ready MOCK_WL_COPY_EXIT=1 "$HELPER" "${COPY_ARGS[@]}" 2>&1)
printf 'copy:wl-copy-fails\t0\t%s\tstderr=\n' "$out"
reset_state
out=$(XDG_RUNTIME_DIR="$TEST_SANDBOX/not-a-runtime-dir" MOCK_SCENARIO=ready "$HELPER" "${COPY_ARGS[@]}" 2>&1)
printf 'copy:no-runtime-dir\t0\t%s\tstderr=\n' "$out"

# --- clear-now -------------------------------------------------------------
reset_state
run_helper "clear-now:empty" clear-now
scenario_helper "copy:for-clear" ready "${COPY_ARGS[@]}" >/dev/null
out=$(MOCK_WL_PASTE_VALUE=synthetic-value "$HELPER" clear-now 2>&1)
printf 'clear-now:match\t0\t%s\tstderr=\n' "$out"
scenario_helper "copy:for-clear2" ready "${COPY_ARGS[@]}" >/dev/null
out=$(MOCK_WL_PASTE_VALUE='newer clipboard value' "$HELPER" clear-now 2>&1)
printf 'clear-now:mismatch\t0\t%s\tstderr=\n' "$out"
out=$(MOCK_WL_PASTE_VALUE=synthetic-value MOCK_WL_COPY_EXIT=1 "$HELPER" clear-now 2>&1)
printf 'clear-now:copy-fails\t0\t%s\tstderr=\n' "$out"

# --- create ----------------------------------------------------------------
create_with() {
  local label=$1 scenario=$2 body=$3
  local out status
  out=$(printf '%s' "$body" | MOCK_SCENARIO=$scenario "$HELPER" create --share-id share_fixture_1 2>"$TEST_SANDBOX/err")
  status=$?
  printf '%s\t%s\t%s\tstderr=%s\n' "$label" "$status" "$out" "$(<"$TEST_SANDBOX/err")"
}
reset_state
create_with "create:username" create-username "$CREATE_BODY"
reset_state
create_with "create:email" create-email '{"title":"T20 Email Login","email":"mailbox@example.test"}'
for scenario in ready logged-out expired locked offline create-error; do
  reset_state
  create_with "create:$scenario" "$scenario" "$CREATE_BODY"
done
for body in '' '{not json' '[]' '{}' '{"title":"Login","username":"user","extra":true}' \
            '{"title":"Login","username":"user","email":"m@example.test"}' '{"title":"Login"}' \
            '{"title":"","username":"user"}' '{"title":7,"username":"user"}' '{"title":"Login","username":null}'; do
  create_with "create:invalid:${body:-empty}" ready "$body"
done

# --- lock / logout ---------------------------------------------------------
for scenario in ready no-lock logged-out expired locked offline; do
  scenario_helper "lock:$scenario" "$scenario" lock
done
out=$(MOCK_SCENARIO=timeout-sleeps MOCK_TIMEOUT_EXIT=1 "$HELPER" lock 2>&1)
printf 'lock:timeout\t0\t%s\tstderr=\n' "$out"
for scenario in ready already-logged-out logged-out expired locked offline logout-error; do
  scenario_helper "logout:$scenario" "$scenario" logout
done
out=$(MOCK_SCENARIO=timeout-sleeps MOCK_TIMEOUT_EXIT=1 "$HELPER" logout 2>&1)
printf 'logout:timeout\t0\t%s\tstderr=\n' "$out"

# --- recents ---------------------------------------------------------------
reset_state
run_helper "recents:load-empty" recents load
run_helper "recents:clear-empty" recents clear
for number in 1 2 3 4 5 6 7 8 9; do
  scenario_helper "recents:note-$number" ready copy --share-id "share_recent_$number" \
    --item-id "item_recent_$number" --field password --clear-seconds 0
done
run_helper "recents:load-full" recents load
scenario_helper "recents:note-promote" ready copy --share-id share_recent_4 \
  --item-id item_recent_4 --field password --clear-seconds 0
run_helper "recents:load-promoted" recents load
run_helper "recents:clear" recents clear
mkdir -p -- "$XDG_STATE_HOME/omarchy-protonpass"
printf '{"recents":[{"shareId":"share","itemId":"item","ts":1,"title":"forbidden"}]}\n' \
  >"$XDG_STATE_HOME/omarchy-protonpass/recents.json"
run_helper "recents:load-malformed" recents load
reset_state
