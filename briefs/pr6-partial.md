# Build lane: PR 6, adopt with a different umask posture

Branch `pr6-umask` from `origin/main` in a scratch worktree. Fetch the
contributor's branch: `git fetch origin pull/6/head:pr6-upstream`.

Task. Community PR 6 has two commits. Adopt the second as written; replace
the first with a different fix, keeping the contributor as author of both.

1. Umask. The PR is right that four `umask 077` calls leak a per-process
   setting into the rest of the helper and every child. It resolves that by
   scoping two into subshells and deleting two. The deletion is declined:
   redundant secret hygiene in this helper is mechanism (leave-alone list,
   REFACTOR.md audit §10), and a user-only default for every file the helper
   or its `pass-cli` child creates is a benefit, not a bug. Do this instead:
   one deliberate `umask 077` at the top of `main()`, with a comment saying
   every file this process and its children create is user-only by default,
   and remove the four per-site calls. Every existing mode assertion (scratch
   600, clip hash 600, recents file 600, recents dir 700) must still pass; the
   explicit `chmod` calls stay. Keep the contributor's first new assertion
   ("helper leaves the caller's umask alone", the in-process harness check);
   it passes because the functions no longer set umask. Invert the second: a
   `pass-cli` child reached through the real copy path must report `0077`, so
   the posture is pinned. Keep the `MOCK_UMASK_LOG` hook.
2. SECURITY.md: the contributor's quantification of the TOTP hash brute force
   and the reason the hash is kept for TOTP, as written. Verify the claim that
   the clip hash is removed on clear against `remove_clip_hash_if_matches`.

Acceptance. All offline suites, `budget-test.sh` and ShellCheck green.
`tools/envelope-matrix.sh` (dev-docs branch) before and after: zero moved
lines. Security suite mutation gate still rejects its seeded violation. Two
commits, contributor as author, messages in repo style, no trailers of any
kind. Push the branch; do not open a PR.

Fill the questions column of the implementation table before coding, re-emit
it at every stop point, and end the report with it plus the branch name and
the CI run ID once it exists.
