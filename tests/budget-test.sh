#!/usr/bin/env bash
# Resource budget contract for the index path.
#
# Item metadata is authored by whoever can edit a vault, and an accepted shared
# vault means that is not always the user. pass-cli is a trusted channel; what
# arrives over it is not trusted data. Every other suite here asks whether a
# secret escapes. This one asks whether a hostile vault can exhaust the shared
# Quickshell process the plugin lives inside -- a bar-wide outage, not a leak.
#
# Offline and account-free like the rest of the suite: the hostile CLI is a
# generator, so a bound can move without regenerating a fixture.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
HELPER="$ROOT/omarchy-protonpass"

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# Budgets are read from the helper rather than restated here, so this suite
# cannot drift from the source it guards.
budget() { grep -E "^readonly $1=" "$HELPER" | cut -d= -f2; }
MAX_VAULTS=$(budget INDEX_MAX_VAULTS)
MAX_PER_VAULT=$(budget INDEX_MAX_ITEMS_PER_VAULT)
MAX_TOTAL=$(budget INDEX_MAX_ITEMS_TOTAL)
DEADLINE=$(budget INDEX_DEADLINE_SECONDS)
for name in MAX_VAULTS MAX_PER_VAULT MAX_TOTAL DEADLINE; do
  [[ -n ${!name} ]] || { printf 'FAIL could not read %s from the helper\n' "$name"; exit 1; }
done

# Reading the budgets from the helper keeps the behavioural assertions from
# drifting, but it also means a raised budget raises the expectation with it --
# a suite that can only ever agree with the source proves nothing. These
# ceilings are hard-coded here on purpose: moving a budget within reason is a
# decision, moving it past these is a mistake, and only a fixed number can tell
# the two apart.
readonly CEILING_VAULTS=500
readonly CEILING_ITEMS_TOTAL=50000
readonly CEILING_DEADLINE=300
assert_ceiling() {
  local name=$1 value=$2 ceiling=$3
  if (( value > 0 && value <= ceiling )); then
    pass "$name=$value is within the sane ceiling $ceiling"
  else
    fail "$name=$value exceeds the sane ceiling $ceiling"
  fi
}
assert_ceiling INDEX_MAX_VAULTS "$MAX_VAULTS" "$CEILING_VAULTS"
assert_ceiling INDEX_MAX_ITEMS_TOTAL "$MAX_TOTAL" "$CEILING_ITEMS_TOTAL"
assert_ceiling INDEX_DEADLINE_SECONDS "$DEADLINE" "$CEILING_DEADLINE"

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
bin="$sandbox/bin"
mkdir -p "$bin" "$sandbox/run" "$sandbox/state"
for utility in bash cat cut date dirname find grep head jq mktemp printf readlink rm seq sleep sort timeout wc; do
  path=$(command -v "$utility") || continue
  ln -sf "$path" "$bin/$utility"
done
ln -sf "$ROOT/tests/mocks/hostile-pass-cli" "$bin/pass-cli"
chmod +x "$ROOT/tests/mocks/hostile-pass-cli"

run_index() {
  env -i PATH="$bin" HOME="$sandbox" \
    XDG_RUNTIME_DIR="$sandbox/run" XDG_STATE_HOME="$sandbox/state" \
    HOSTILE_CASE="$1" ${2:+HOSTILE_STALL="$2"} \
    bash "$HELPER" index --exclude-vaults ""
}

# --- 1. a vault flood is capped, and says so -------------------------------
out=$(run_index vaults)
count=$(jq '.vaults | length' <<<"$out" 2>/dev/null)
if [[ $count == "$MAX_VAULTS" ]]; then
  pass "vault count capped at $MAX_VAULTS"
else
  fail "vault count was ${count:-unparseable}, expected $MAX_VAULTS"
fi
if jq -e '.warnings | any(test("vaults were indexed"))' <<<"$out" >/dev/null 2>&1; then
  pass "vault truncation is visible in warnings"
else
  fail "vault truncation was silent"
fi

# --- 2. one enormous vault cannot exceed the per-vault or total ceiling ----
out=$(run_index items)
count=$(jq '.items | length' <<<"$out" 2>/dev/null)
ceiling=$(( MAX_PER_VAULT < MAX_TOTAL ? MAX_PER_VAULT : MAX_TOTAL ))
if [[ -n $count ]] && (( count <= ceiling )); then
  pass "single-vault items capped at $count (ceiling $ceiling)"
else
  fail "single-vault items was ${count:-unparseable}, expected <= $ceiling"
fi
if jq -e '.warnings | any(test("more logins than"))' <<<"$out" >/dev/null 2>&1; then
  pass "item truncation is visible in warnings"
else
  fail "item truncation was silent"
fi

# --- 3. items spread across many vaults still hit the global ceiling -------
out=$(run_index flood)
count=$(jq '.items | length' <<<"$out" 2>/dev/null)
if [[ -n $count ]] && (( count <= MAX_TOTAL )); then
  pass "total items capped at $count (ceiling $MAX_TOTAL)"
else
  fail "total items was ${count:-unparseable}, expected <= $MAX_TOTAL"
fi

# --- 4. an oversized single response is refused, not swallowed -------------
out=$(run_index giant)
if jq -e '.state == "ready"' <<<"$out" >/dev/null 2>&1; then
  pass "oversized response left the envelope valid"
else
  fail "oversized response broke the envelope"
fi
if jq -e '.warnings | any(test("too large|could not be loaded"))' <<<"$out" >/dev/null 2>&1; then
  pass "oversized response is reported"
else
  fail "oversized response was silent"
fi

# --- 5. the walk obeys one deadline, not one timeout per vault -------------
# 200 stalling vaults at the per-request timeout would run for well over an
# hour. The bound must come from the aggregate deadline instead.
started=$(date +%s)
out=$(HOSTILE_VAULTS=200 run_index slow 2)
elapsed=$(( $(date +%s) - started ))
# Grace is bounded by the fixed ceiling too, so a raised deadline cannot buy
# the walk unlimited wall clock.
grace=$(( DEADLINE + 30 ))
if (( grace > CEILING_DEADLINE + 30 )); then
  grace=$(( CEILING_DEADLINE + 30 ))
fi
if (( elapsed <= grace )); then
  pass "aggregate deadline held: ${elapsed}s (budget ${DEADLINE}s, grace ${grace}s)"
else
  fail "walk ran ${elapsed}s, expected <= ${grace}s"
fi
if jq -e '.warnings | any(test("time limit"))' <<<"$out" >/dev/null 2>&1; then
  pass "deadline truncation is visible in warnings"
else
  fail "deadline truncation was silent"
fi

# --- 6. nothing outlives the helper but the clipboard hash ----------------
# Mirrors the residue contract in security-test.sh. The index accumulates to a
# scratch file, so this is the assertion that catches a missed cleanup path.
residue=$(find "$sandbox/run" -type f ! -name omarchy-protonpass.clip -print 2>/dev/null)
if [[ -z $residue ]]; then
  pass "no scratch files outlived the helper"
else
  fail "helper left scratch files behind: $residue"
fi

printf '\n'
if (( failures > 0 )); then
  printf '%d budget assertion(s) failed\n' "$failures"
  exit 1
fi
printf 'budget contract holds\n'
