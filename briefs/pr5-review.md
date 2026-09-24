# Build lane: PR 5, land with two amendments

Branch `pr5-controls` from `origin/main` in a scratch worktree. Fetch the
contributor's branch: `git fetch origin pull/5/head:pr5-upstream`.

Context. PR 5 strips C0/C1 controls (except tab and newline), DEL and the
Unicode bidi and zero-width format characters from item titles and vault
names before the 256-character cap, with `(untitled login)` /
`(unnamed vault)` fallbacks when a name empties. An independent read found it
correct and its three scenarios honest. Two gaps to close before merge.

Task, on top of the contributor's commit, contributor kept as author:
1. Complete the character set. Missing today: U+061C (Arabic letter mark,
   Bidi_Control), U+2060 to U+2064 (word joiner and invisible operators),
   U+2028 and U+2029 (line and paragraph separators), U+00AD (soft hyphen),
   and the tag block U+E0000 to U+E007F. Add them and extend the
   `control-characters` scenario so each class is represented and the property
   assertion (no indexed title carries a control or format character) covers
   it. Confirm jq slices by code point so the cap stays 256 characters.
2. Exclusion matching. The `excludeVaults` comparison still uses the raw vault
   name, so a vault whose real name carries a hidden character displays clean
   but cannot be excluded by typing what the user sees. Match on the sanitised
   name. Add a scenario.

Measure the cost: run `tests/budget-test.sh` and report the index wall time
against the hostile mock before and after; the stripping runs over up to
10,000 items inside the 60-second aggregate deadline.

Acceptance. All offline suites, `budget-test.sh` and ShellCheck green. Every
new assertion red with the strip reverted, green with it. Envelope matrix
before and after: only the intended lines move. Commits in repo style, no
trailers. Push the branch; do not open a PR.

Fill the questions column of the implementation table before coding, re-emit
it at every stop point, and end the report with it plus the branch name and
the CI run ID once it exists.
