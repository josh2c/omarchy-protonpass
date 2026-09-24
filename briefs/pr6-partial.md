# Build lane: PR 6, adopt with a different umask posture

You are the ENGINEER for this task. Do the work directly in this session; do
not dispatch, do not ask the coordinator to run anything. Push the branch and
report. You are working on Josh's own machine, which is also his live desktop,
so the environment rules below are not optional.

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
  `git -C ~/projects/omarchy-protonpass worktree add /tmp/<lane>-wt -b <branch> origin/main`.
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
  `git -C ~/.config/omarchy/plugins/josh2c.protonpass fetch /tmp/<lane>-wt <branch> && git -C ~/.config/omarchy/plugins/josh2c.protonpass checkout FETCH_HEAD`,
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
