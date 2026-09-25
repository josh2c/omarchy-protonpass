# Engineer brief: repository and machine hygiene

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

Six cleanups, in this order. Look before every deletion; list what you are
about to remove and why it is safe, then remove it.

1. Remote: delete the stale branch `release-1.5.1` on origin (its commit is
   on main as 094346a; confirm with `git branch -r --contains`). Remote heads
   must end as `main` and `dev-docs` only.
2. Local clone `~/projects/omarchy-protonpass`: delete every local branch
   whose upstream is gone (`git branch -vv | grep ': gone\]'`) after
   confirming each is merged into main by content (`git diff main <branch>
   --stat` on the files that matter, or `git cherry`), or is an old-history
   duplicate of a commit that is on main under a new SHA (compare the commit
   message and diff). Also `polish-setup-card`, `h1`-`h3`, `rd-reverify`,
   `f3-create-stdin`, `ra-busy-feedback`, `rb-test-prune`, `t*` branches.
   Anything you cannot prove merged: leave it and list it.
3. Worktrees: the eight directories `~/projects/omarchy-protonpass-t*` are
   worktrees from the first build (t8 to t22, August). Confirm each has a
   clean tree and no unpushed content that is absent from main, then
   `git worktree remove` each and delete its branch. `git worktree prune`.
4. Live install `~/.config/omarchy/plugins/josh2c.protonpass`: it is on
   `main` at 094346a. Delete the leftover branch `t1-repo-scaffold` inside
   that clone (`git -C <install> branch -D t1-repo-scaffold`). Do not change
   its checkout and do not restart the shell; nothing here needs it.
5. Stale sandboxes: 14 directories `/tmp/omarchy-protonpass-tests.*` are
   left from test runs. They hold mock data only. Confirm none is in use
   (`lsof +D` or an mtime in the last ten minutes), then remove them.
6. Find out why `cleanup_test_sandbox` in `tests/lib.sh` does not always
   fire, and fix it on a branch `sandbox-cleanup` from `origin/main`. Likely
   candidates: a suite that exits before the trap is set, a `timeout` kill
   that skips EXIT, a suite that sources lib.sh in a subshell, or a
   background job holding the directory. Prove the cause by reproducing the
   leak, fix it, prove the fix. Keep the change inside `tests/`; the helper
   and the security suite's assertions are not touched (leave-alone list).
   Offline suites, budget suite and ShellCheck green. Push, open a PR, wait
   for CI by run ID, report; do not merge.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Stop at the first failure and report it with the exact
output; do not improvise on the public repository. The final report lists
every deletion made, every run ID with its conclusion, the leak checks, and
the state of the local clone and the live install.
