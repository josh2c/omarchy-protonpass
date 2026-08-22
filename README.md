# omarchy-protonpass — development documents

This is an orphan branch. It shares no history with `main` and contains no
plugin code. It holds the development process documents that used to sit in the
repository root, where `omarchy plugin add` copied them into every user's
config directory.

- [`PLAN.md`](PLAN.md) — the v1 implementation plan: product, architecture,
  security, and scope decisions, with the audit log of every revision.
- [`T12-ACCEPTANCE.md`](T12-ACCEPTANCE.md) — the combined v1.0 + v1.1 + v1.2
  manual acceptance checklist, run against a real account before signing a tag.

Both files were on `main` through `dba51c8`; their history is still there.

`PLAN.md` is no longer used as a changelog. Release notes go in the annotated
release tags.

## `tools/`

Verification harnesses written for the v1.3.0 "prune" refactor (R-G / R-H).
None of them are part of the test suite: they compare two checkouts, or hunt
for a defect class the suite cannot express. Each takes the path to a checkout
of the plugin (a worktree is fine) and uses that checkout's own mocks and
fixtures, in a throwaway sandbox.

- [`tools/envelope-matrix.sh`](tools/envelope-matrix.sh) — dumps the JSON
  envelope, exit status and stderr for every command × mock scenario (122
  cases: argv errors, all TOTP variants, the username→email fallback, missing
  dependencies, timeouts, recents rotation). Run it against a checkout before
  and after a refactor and `diff` the two files; any line that moves is a
  behaviour change. Recents timestamps are normalised so runs compare.
  `tools/envelope-matrix.sh <checkout> > before.txt`
- [`tools/spawn-count.sh`](tools/spawn-count.sh) — counts the external commands
  one helper invocation executes, by putting a logging wrapper in front of
  every utility on the sandbox PATH, and prints the per-utility breakdown. Mock
  overhead is included, so only compare like with like.
  `tools/spawn-count.sh <checkout> copy --share-id … --field password --clear-seconds 0`
  (`SPAWN_STDIN=…` feeds stdin, for `create`.)
- [`tools/copy-latency.sh`](tools/copy-latency.sh) — mean time from invoking a
  mock copy to its success envelope being *readable*, over N runs. It reads one
  line from a pipe rather than waiting for exit, so it measures the response,
  not the process.
  `tools/copy-latency.sh <checkout> 30`
- [`tools/stress.sh`](tools/stress.sh) — hang hunt: 8 sequential helper+security
  pairs, 6 piped runs, then 18 runs concurrently under one busy loop per core.
  Reports any run that exceeds its timeout as a hang. This is the shape that
  caught the `clear-now` stdin wedge staying dead.
  `tools/stress.sh <checkout>`
