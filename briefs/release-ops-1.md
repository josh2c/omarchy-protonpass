# Engineer brief: merge PR 7, triage the community PRs, publish the docs branches

You are the ENGINEER for this task. Do the work directly in this session; do
not dispatch, do not ask the coordinator to run anything. You are working on
Josh's own machine, which is also his live desktop, and you are acting on the
public repository josh2c/omarchy-protonpass with Josh's GitHub account through
`gh`. Every public action below is pre-approved by the maintainer as written;
do nothing public that is not listed.

## The project

`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = release 1.5.0 (e529a3e). GitHub: josh2c/omarchy-protonpass.
Runtime is four files: `omarchy-protonpass` (bash helper, the only component
that touches secrets, wraps the official `pass-cli`), `Service.qml` (state
machine, one Process per helper command), `Panel.qml` (UI and the single key
handler), `Keybinds.js`. Tests in `tests/`: offline bash suites
(`manifest-test.sh`, `helper-test.sh`, `security-test.sh`,
`source-contract-test.sh`, `budget-test.sh` which takes about 90 s) and QML
harnesses (`qml-*.sh`) that need a nested compositor. Mocks under
`tests/mocks/` (`pass-cli`, `hostile-pass-cli`, `wl-copy`, `wl-paste`);
`MOCK_SCENARIO` selects behaviour. Read `SECURITY.md` and `README.md` first;
they are the promises this change must keep.

Decision record and tools live on the orphan branch `dev-docs`:
`git show dev-docs:PLAN.md` (§1.3 defers a disk index, §3.7 says metadata is
never at rest), `git show dev-docs:PR-PROCESS.md`, and `tools/` (check out
with `git worktree add <dir> dev-docs`): `envelope-matrix.sh` diffs every
helper command × scenario before and after a change; `stress.sh` hunts hangs.

## Binding rules

- Secrets never enter QML, argv, the environment, files, or logs. Item
  metadata stays in memory only. No new files on disk, no new settings, no
  new environment variables.
- Leave-alone list: `_validatedResponse`, the index generation fencing,
  `unset` discipline, `printf x` capture, the `/dev/fd` template path, TOCTOU
  double reads, rejection sampling, mode and symlink checks, the dynamic
  security suite, and the CI seeded-mutation gates. If your change needs to
  touch one, stop and say so in the report instead of changing it.
- Redundant hygiene in the helper is mechanism, not clutter. Do not "clean up".
- Commit messages: imperative title, plain prose body saying what changed and
  why. No tool attributions, no `Co-Authored-By`, no session links, anywhere.
  Check with `git log origin/main..HEAD --format=%B | grep -iE 'claude|co-authored|session'`
  before pushing; it must print nothing. Commit as
  `git -c user.name="Josh Garcia" -c user.email="garciajosh313@gmail.com"`.
- No version pins in tests (shape checks only).

## Machine and environment

- Work in a scratch worktree, never in `~/projects/omarchy-protonpass` itself:
  `git -C ~/projects/omarchy-protonpass worktree add /tmp/<lane>-wt <ref>`.
  Remove it (`git worktree remove`) when done.
- Josh's live install is `~/.config/omarchy/plugins/josh2c.protonpass`, a
  clone whose origin is the local repo. Do not modify it. Hot reload serves
  stale QML; a live check needs `omarchy plugin update josh2c.protonpass --yes`
  followed by a full shell restart, and only do a live check if the brief's
  acceptance requires it (it does, once, at the end). The shipped
  `omarchy-restart-shell` can report success with no shell running. Use:
  `while timeout 5 quickshell kill -p /usr/share/omarchy/shell --any-display >/dev/null 2>&1; do :; done; sleep 1; hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'`
  then check `journalctl --user -n 200 | grep -i 'widget failed'` is empty.
  Because the live install's origin is the local repo, the live check needs
  the branch merged into a local throwaway ref the install can pull; simplest
  is to point the install's checkout at your branch with
  `git -C ~/.config/omarchy/plugins/josh2c.protonpass fetch /tmp/<lane>-wt <ref> && git -C ~/.config/omarchy/plugins/josh2c.protonpass checkout FETCH_HEAD`,
  restart the shell, verify, then `checkout main` and restart again so Josh's
  desktop is left as you found it. Say in the report that you restored it.
- The QML harnesses are layer-shell surfaces that grab exclusive keyboard
  focus. Never run them on the host Wayland session: they steal Josh's
  keyboard while he types. `tests/lib-nested-display.sh` starts a nested
  Hyprland and detects its display through the lock file the compositor holds
  open; it refuses if the detected display equals `$WAYLAND_DISPLAY`. Use the
  `tests/qml-*.sh` wrappers, which go through it. After every harness run
  check for leaks: `pgrep -a Hyprland` (only the host one), `pgrep -af
  silent-helper` (nothing), `ls /run/user/1000 | grep wayland-` (only the host
  socket). Kill anything left.
- `pass-cli` 2.3.2 is installed at `~/.local/bin/pass-cli`. You do not need a
  Proton account; every suite runs on mocks. Do not run `pass-cli login`.
- `mise` shims can shadow `/usr/bin`; if a tool behaves oddly, prefix
  `PATH=/usr/bin:$PATH`.
- Baselines under `tests/baselines/` are comparison tools, not CI members;
  when your change intentionally alters the snapshot, regenerate and commit
  the baseline and say what moved.

## Task, in this order

1. Merge PR 7 (branch `large-vault-index`, CI run 36081896834 success).
   `gh pr merge 7 --rebase --delete-branch`. Confirm `origin/main` now ends
   with the two commits "Keep the index in memory across panel opens" and
   "Render the login rows through a virtualised list". Then
   `git -C ~/projects/omarchy-protonpass pull --ff-only`.

2. Approve the held workflow runs on the five fork PRs so they get CI:
   for each of PRs 1, 3, 4, 5, 6, find the pending run
   (`gh run list --workflow CI --event pull_request --limit 20`) and approve it:
   `gh api -X POST repos/josh2c/omarchy-protonpass/actions/runs/<run_id>/approve`.
   If a run is already completed, skip it. Wait for every run and record the
   run ID and conclusion by `gh run view <id>`, never by watching the kickoff.
   Runs on PR 3 and PR 5 may need a rebase now that main moved; do not rebase
   contributor branches, just record the result.

3. Post the reviews and comments below, verbatim, from a temp file each
   (`--body-file`), so nothing is mangled by shell quoting:
   - PR 5: `gh pr review 5 --request-changes --body-file <file>`
   - PR 6: `gh pr review 6 --request-changes --body-file <file>`
   - PR 3: `gh pr comment 3 --body-file <file>`, then `gh pr close 3`.
     The issue is closed by PR 7's "Fixes #2"; confirm issue 2 is closed and
     if not, `gh issue close 2 --comment "Fixed by #7."`.

4. PR 1 live check, then merge PRs 1 and 4.
   PR 1 adds one line to Panel.qml. Its CI must be green (step 2). Then:
   `git -C ~/projects/omarchy-protonpass fetch origin pull/1/head:pr1-check`
   into a scratch worktree; run `tests/qml-panel-snapshot.sh` in the nested
   compositor (rules above) and confirm the only diff against the baseline
   is none or the expected nothing; then point the live install at that ref
   as described above, restart the shell, confirm zero "widget failed"
   journal lines, run `omarchy-shell josh2c.protonpass toggle` twice and see
   the panel open and close, then restore the install to its previous
   checkout (record what it was first: `git -C ~/.config/omarchy/plugins/josh2c.protonpass log -1 --format=%h`)
   and restart the shell again. If PR 1 does not apply cleanly on the new
   main, stop and report; do not rebase the contributor's branch.
   On success: `gh pr review 1 --approve --body-file <file>` with the PR 1
   text below, `gh pr merge 1 --squash`; then `gh pr review 4 --approve
   --body-file <file>` and `gh pr merge 4 --squash`. GitHub keeps the
   contributor as author on a squash merge; confirm with
   `git log -2 --format='%an %s' origin/main` after each.

5. Publish the two docs branches. Both exist locally in
   `~/projects/omarchy-protonpass`, commits already written, no trailers.
   - `git push origin dev-docs` (fast-forward of the orphan docs branch; if
     it is not a fast-forward, stop and report, never force).
   - `git push -u origin pr-process-docs`, then
     `gh pr create --head pr-process-docs --title "Tell contributors how changes are reviewed" --body "Adds .github/CONTRIBUTING.md and a pull request template describing the review gates, the commit hygiene rule, and which harnesses contributors can and cannot run. Docs only."`
     Wait for its CI run, record the ID and conclusion, and if green
     `gh pr merge <n> --rebase --delete-branch`.

6. Leave the machine clean: remove every scratch worktree you created,
   run the leak checks, and confirm the live install is back on the checkout
   you recorded in step 4.

## Texts to post (verbatim; each goes in its own temp file)


## PR 1 (CJKaufman), approve and squash-merge in the GitHub UI after our live check
Thanks, this is a real gap: a keyboard-first panel with no way to summon it from a compositor keybind. Verified against the shell's base Panel: the IpcHandler exposes only open, close, show, hide and toggle, so nothing new can trigger a copy. Loaded live with the toggle working. Merging into 1.5.1.

## PR 4 (dadofsambonzuki), approve and squash-merge in the UI
Agreed on both points, and the helper override was the larger omission for a document that asks readers to verify everything. Each sentence checks against the code. Merging into 1.5.1.

## PR 5 (dadofsambonzuki), "Request changes" review
This is the kind of finding we should have made ourselves: 1.5.0 bounded the length of shared-vault text and not its content. The implementation and the three scenarios check out. Two changes before merge:

1. The character class misses a few invisible or direction-changing code points: U+061C (Arabic letter mark, Bidi_Control), U+2060 to U+2064 (word joiner and invisible operators), U+2028 and U+2029, U+00AD (soft hyphen), and the tag block U+E0000 to U+E007F. Please add them and extend the control-characters scenario so each class is represented under the property assertion.
2. The excludeVaults comparison still uses the raw vault name, so a vault whose real name carries a hidden character displays clean but cannot be excluded by typing what the user sees. Please match on the sanitised name, with a scenario.

If you can, note the budget-test wall time before and after; the stripping runs over up to 10,000 items inside the aggregate deadline. Once these land I will merge with you as author.

## PR 6 (dadofsambonzuki), "Request changes" review
The umask leak is real and the two red-first assertions are exactly the evidence we like. The SECURITY.md commit is accurate and lands as written. One change to the first commit: in this helper redundant hygiene is deliberate, so the two sites that drop umask because mktemp and chmod already give 0600 should keep a restrictive mask. A process-wide user-only default is also a benefit for the pass-cli child, not a bug. So rather than four scoped calls, please make it one deliberate `umask 077` at the top of main() with a comment, remove the four per-site calls, keep every chmod, keep the "caller's umask alone" assertion, and invert the child assertion so a pass-cli child reached through the copy path must report 0077. That pins the posture instead of forbidding it. Happy to merge with you as author once that is in.

## PR 3 and issue 2 (eddownes), comment on the PR, then close it after our PR merges
Thank you for the diagnosis. It is confirmed and it is the top item for the next release. Two of your fixes land as they are: the loading header text and the timeout constant that misleads. The disk cache does not, and I want to be straight about why. The plugin's stated model is that item metadata lives only in memory, and SECURITY.md and the marketplace listing both promise that the only things written to disk are recent-item IDs and a hash. A cache of titles and vault names, including from shared vaults, changes that promise, and changing it is a design decision I am not going to make inside a PR. What we found reading the code alongside your report: the service already keeps the index in memory and shows the old list while refreshing, but every panel open triggers a refresh and every close kills the fetch in flight. With a 30-second fetch that is why it never completes. #7 lets the fetch finish after close, refreshes only when the index is older than five minutes, and replaces the eager row rendering with a recycled list view, which at 4,640 items was also costing on every keystroke. You are credited in both commits. If in-memory turns out not to be enough for your vault, a disk cache comes back as a deliberate, documented change. One more thing: commits and PR text here cannot carry tool attributions or session links; if you send further changes, please leave those out.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
before you start and at every stop point. If any step fails, stop there,
leave everything after it undone, and report what happened with the exact
command output; do not improvise a workaround on the public repository. The
final report lists: every run ID with its conclusion, every merge with the
resulting main commit and author, every comment and review posted with its
URL, the PR 1 harness and live results, the leak checks, and the live
install's checkout before and after.
