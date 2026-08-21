#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

jq -e . "$MANIFEST" >/dev/null || fail "manifest.json is not valid JSON"
jq -e '.version == "1.2.0"' "$MANIFEST" >/dev/null || \
  fail "manifest version is not prepared for the 1.2.0 release"

while IFS= read -r entry_point; do
  [[ -f "$ROOT/$entry_point" ]] || fail "referenced entry point does not exist: $entry_point"
done < <(jq -r '.entryPoints | to_entries[].value' "$MANIFEST")

link=$(find "$ROOT" -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "repository contains a symlink: $link"

printf 'manifest tests passed\n'
