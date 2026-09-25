# Engineer brief: release 1.5.2

Do not start this lane before 2026-10-09 unless the coordinator says both
PRs 5 and 6 have merged earlier.

You are the ENGINEER for this task. Do the work directly in this session; do
not dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. Only the public actions named below are
allowed.

## The project

`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = 2ae1b35 (release 1.5.1 plus two merged test PRs). GitHub: josh2c/omarchy-protonpass.
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

## Task

1. Contributor PRs. Check PRs 5 and 6 on GitHub.
   - If a PR was amended and its CI is green: review the amendment against
     the request-changes comment on that PR (the coordinator's two points for
     PR 5; the single-umask posture for PR 6), run the offline suites and the
     budget suite on its head merged onto main, mutation-check each new
     assertion once, then `gh pr review <n> --approve` and
     `gh pr merge <n> --squash`. Confirm the contributor stays the author.
   - If a PR has no amendment: branch `pr<n>-landed` from `origin/main`,
     `git fetch origin pull/<n>/head`, cherry-pick the contributor's commits
     keeping them as author, then add one commit of your own that applies
     the requested amendments (for PR 5: the extra code points U+061C,
     U+2060-2064, U+2028/2029, U+00AD, U+E0000-E007F, and excludeVaults
     matching on the sanitised name, each with a scenario; for PR 6: one
     `umask 077` at the top of main(), the four per-site calls removed,
     every chmod kept, the child assertion inverted to expect 0077). Push,
     open a PR whose body credits the contributor and links their PR, wait
     for CI by run ID, merge with rebase, then comment on the contributor's
     PR with the merged commit and close it. Tone: thank them, say exactly
     what was added on top and why.
2. SECURITY.md recipe 3: its prose says "the copy at the bottom passes
   copy_args" but the value copy is followed by three wl-copy guard and
   clear lines. Reword so the sentence points at the right line and the
   recipe's output still matches the text. Verify the recipe by running it.
3. CI concurrency: `.github/workflows/ci.yml` uses one concurrency group
   with cancel-in-progress for every ref, so two merges to main in quick
   succession cancel the first merge commit's only run. Scope cancellation
   so pull-request runs still cancel their predecessors but pushes to main
   never cancel each other (for example a group keyed on the ref for PRs and
   on the commit SHA for main). Prove it: push two commits to a scratch
   branch's PR and see the first cancelled; the main behaviour is proven at
   release time when the bump and the merge both run.
4. `dev-docs:T12-ACCEPTANCE.md`: add one line under keyboard chords saying
   that synthesized input (wtype) does not reach the panel on the host seat
   and the nested key-matrix harness is the instrument for chord acceptance.
   Commit on the dev-docs branch and push it (fast-forward only).
5. Release: same steps as `briefs/release-1.5.1.md` (bump to 1.5.2,
   SECURITY.md recipes on a fresh clone, full harness set in the nested
   compositor, live load, release commit with a plain-prose body naming
   every change and contributor, PR, CI by run ID, rebase merge, annotated
   unsigned tag, marketplace `[Verify]` issue at the tagged commit, update
   Josh's install with `omarchy plugin update josh2c.protonpass --yes` after
   fast-forwarding the local clone, shell restart, confirm 1.5.2 in the bar).
   Delete the release branch on origin after the merge.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Stop at the first failure and report it with the exact
output; do not improvise on the public repository. The final report lists
every deletion made, every run ID with its conclusion, the leak checks, and
the state of the local clone and the live install.
