#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

jq -e . "$MANIFEST" >/dev/null || fail "manifest.json is not valid JSON"
# Releases bump the version; the test asserts the shape, never a pinned value,
# so a release commit can never turn the suite red by construction.
jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$MANIFEST" >/dev/null || \
  fail "manifest version is not plain semver"

while IFS= read -r entry_point; do
  [[ -f "$ROOT/$entry_point" ]] || fail "referenced entry point does not exist: $entry_point"
done < <(jq -r '.entryPoints | to_entries[].value' "$MANIFEST")

link=$(find "$ROOT" -name .git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "repository contains a symlink: $link"

printf 'manifest tests passed\n'
