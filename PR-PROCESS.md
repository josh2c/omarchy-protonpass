# Pull request process

How a change from outside (or inside) reaches `main`. Four gates, each with an
owner. None is skipped. The plugin copies passwords; a merge is a trust decision.

## Gate 0: intake (maintainer, minutes)

1. Scope. The README's out-of-scope list and PLAN.md §1.3 are the reference. A
   change that reverses a recorded decision (for example: metadata at rest, a
   disk index, secret display, in-panel auth) is a design question for the
   maintainer first, never a merge.
2. Leave-alone list. Anything that touches `_validatedResponse`, generation
   fencing, `unset` discipline, `printf x` capture, the `/dev/fd` template path,
   TOCTOU double reads, rejection sampling, mode and symlink checks, the dynamic
   security suite, or the CI mutation gates is flagged and reviewed as a
   security change, not a cleanup. Redundant secret hygiene in the helper is
   mechanism, not clutter; a PR that removes it because "the other check already
   covers it" is declined on that point.
3. Attribution. Every commit message and the PR body are scanned for AI tool
   attributions and session links. They never enter history; the change is
   squashed with a rewritten message. The contributor stays the author.
4. CI. Fork PRs are held at "action required". Approve the run only after 1-3.
   Read the result by run ID, never by watching the kickoff.

## Gate 1: independent review (one fresh engineer session per PR)

The reviewer reads the code, not the description.

- Correctness of the change against the current tree.
- Every claimed test is mutation checked: revert the fix, the new test must go
  red. A test that stays green proves nothing.
- `tools/envelope-matrix.sh` (this branch) before and after: any moved line is
  a behaviour change the PR must name.
- Fork contributors cannot run the QML harnesses (no Quickshell). Any QML touch
  gets the snapshot harness at both viewports and a live shell load with zero
  "Plugin widget failed" journal lines, on our side, before merge.
- ShellCheck clean, all offline suites green, `budget-test.sh` included.

## Gate 2: red team by asset (same or second session)

For each PR, one line per asset: secret values, Proton session, clipboard,
availability of the shell process, integrity of the helper path, data at rest.
State what surface the diff adds. For every new untrusted input, say how type,
size, cardinality and rate stay bounded. A PR with no new surface says so
explicitly. Hypothesis-scoped reviews ("does a secret leak?") are not enough;
the DoS that a marketplace reviewer found in 1.4.1 passed three of those.

## Gate 3: merge and release (maintainer)

- Squash. Commit message in repo style: imperative title, plain prose body that
  says what changed and why. Contributor as author. No trailers.
- Batch into a release. Version bump, annotated tag (no signing key exists),
  CI green by run ID, SECURITY.md grep recipes re-run against the fresh clone.
- Marketplace: open a `[Verify]` issue on omacom/omarchy-plugin-marketplace for
  the new commit. The listing stays on the old snapshot until then.
- Update the maintainer's own install and restart the shell.

## Replying to contributors

Say what was accepted, what was changed and why, and what was declined with the
recorded decision it conflicts with. Credit findings. Do not ask contributors to
run harnesses they cannot run.
