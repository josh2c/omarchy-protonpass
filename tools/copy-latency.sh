#!/usr/bin/env bash
# Time from invoking copy to the success envelope being readable, over N runs.
set -uo pipefail
REPO=$(cd "$1" && pwd)
RUNS=${2:-20}
source "$REPO/tests/lib.sh"
TEST_ROOT=$REPO
trap cleanup_test_sandbox EXIT
make_test_sandbox
exec </dev/null
HELPER="$REPO/omarchy-protonpass"
total=0
for ((run = 1; run <= RUNS; run++)); do
  start=$EPOCHREALTIME
  IFS= read -r line < <(MOCK_SCENARIO=ready "$HELPER" copy \
    --share-id "share_lat_$run" --item-id "item_lat_$run" \
    --field password --clear-seconds 0)
  end=$EPOCHREALTIME
  [[ $line == *'"state":"copied"'* ]] || { printf 'unexpected envelope: %s\n' "$line" >&2; exit 1; }
  total=$(jq -n --arg t "$total" --arg s "$start" --arg e "$end" '($t|tonumber) + (($e|tonumber) - ($s|tonumber))')
done
# Bookkeeping runs after the envelope, so let the last copy finish before the
# sandbox goes away.
sleep 0.3

jq -n --arg t "$total" --arg n "$RUNS" '{runs: ($n|tonumber), mean_ms: ((($t|tonumber) / ($n|tonumber)) * 1000 * 1000 | round / 1000)}'
