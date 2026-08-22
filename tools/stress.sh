#!/usr/bin/env bash
# Hang hunt: the suite under sequential, concurrent, piped and load-saturated
# invocation. Any run that exceeds the timeout is reported as a hang.
set -uo pipefail
WT=$1
hangs=0; fails=0; runs=0
record() {
  local status=$1 label=$2
  runs=$((runs + 1))
  if (( status == 124 )); then hangs=$((hangs + 1)); printf 'HANG: %s\n' "$label"
  elif (( status != 0 )); then fails=$((fails + 1)); printf 'FAIL(%s): %s\n' "$status" "$label"; fi
}
for i in $(seq 1 8); do
  timeout 300 "$WT/tests/helper-test.sh" >/dev/null 2>&1; record $? "sequential helper $i"
  timeout 300 "$WT/tests/security-test.sh" >/dev/null 2>&1; record $? "sequential security $i"
done
for i in $(seq 1 6); do
  timeout 300 "$WT/tests/helper-test.sh" 2>&1 | tail -n1 >/dev/null; record ${PIPESTATUS[0]} "piped helper $i"
done
# Load-saturated concurrency: one busy loop per core plus six parallel suites.
for c in $(seq 1 "$(nproc)"); do ( while :; do :; done ) & done
load_pids=$(jobs -p)
for round in 1 2 3; do
  pids=()
  for i in $(seq 1 6); do
    timeout 300 "$WT/tests/helper-test.sh" >/dev/null 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid"; record $? "concurrent round $round"; done
done
# shellcheck disable=SC2086
kill $load_pids 2>/dev/null
printf 'runs=%s hangs=%s fails=%s\n' "$runs" "$hangs" "$fails"
