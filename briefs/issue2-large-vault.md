# Engineer brief: issue 2, large vaults, in-memory fix (branch `large-vault-index`)

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
  `git -C ~/projects/omarchy-protonpass worktree add /tmp/lv-wt -b large-vault-index origin/main`.
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
  `git -C ~/.config/omarchy/plugins/josh2c.protonpass fetch /tmp/lv-wt large-vault-index && git -C ~/.config/omarchy/plugins/josh2c.protonpass checkout FETCH_HEAD`,
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

## The problem (issue 2, PR 3 on GitHub; read both)

A user with a 4,640-item vault sees 15 to 40 s of loading on every panel
open. PR 3 proposes a disk cache; it is declined (metadata at rest breaks the
promise in SECURITY.md and PLAN.md §3.7). Two of its small fixes are adopted
below. The mechanism, verified in source:

- `Service.qml` `onPanelOpened` (around :410-435) calls `refresh()` on every
  open; `onPanelClosed` (around :438-441) terminates the running index
  process. The index is kept in memory (`_hasIndex`) and the panel already
  shows the old list while `refreshing`. So a 30 s fetch that the user closes
  the panel on is killed and restarted next open; it never completes.
- `Panel.qml` renders the Recent and All sections through two eager
  `Repeater`s over JS arrays (around :969-972 and :999-1003); each delegate
  holds three `Text` nodes and a nested `Repeater` of three buttons.
  Reassigning the filtered array destroys and rebuilds every delegate, so at
  4,640 items each keystroke rebuilds tens of thousands of objects inside the
  shared shell process, while the viewport is clipped to 300 px.

## Task, two commits, sequentially, each green before the next

Commit 1, Service.qml plus the header text in Panel.qml:
1. Let an in-flight index finish after the panel closes instead of killing
   it. Keep the generation fencing exactly as it is: a refresh requested while
   one runs still supersedes it; auth transitions still clear the model.
2. Do not refresh on every open. Refresh on open only when the in-memory
   index is absent or older than a freshness window. Propose the value and
   justify it in the commit body; 5 minutes is the starting guess. Explicit
   refresh (button, `r`, `Ctrl+R`) always fetches. Doctor and recents
   behaviour on open are unchanged.
3. From PR 3: the header meta text shows "Loading Proton Pass logins..."
   while `state === "LOADING"` instead of stale doctor text.
4. From PR 3: `INDEX_TIMEOUT_SECONDS` (per vault) and `INDEX_DEADLINE_SECONDS`
   (aggregate) mislead; the deadline silently clamps the per-vault timeout.
   Rename or comment so the ceiling is obvious. The aggregate deadline is an
   availability bound from 1.5.0. If it must rise to fit a 4,640-item vault,
   say why, keep it as the single ceiling, do not exceed 90 s, and confirm
   `tests/budget-test.sh` and the CI seeded-mutation gate still reject a
   raised ceiling. Note `Service.qml:33-34` mirror the helper's item and vault
   limits by hand; if you touch a limit, keep both sides equal.
5. Credit the issue and PR authors (eddownes) in the commit body for the
   diagnosis.

Commit 2, Panel.qml rows:
6. Replace the two `Repeater`s with a `ListView` (sections for Recent and
   All, `cacheBuffer` sized to the viewport, delegates reused). Keyboard
   cursor, scroll-into-view, click-to-copy, accessible names, and the
   `Text.PlainText` pins must all survive. `tests/source-contract-test.sh`
   pins some of these by literal string; move pins, never weaken them.
7. Give `tests/row-perf-harness.qml` and `qml-row-perf.sh` a pass/fail
   threshold at 5,000 items instead of printing a number; the harness must
   fail on `origin/main` and pass on your branch. Say what it measures.

## Acceptance

- Offline suites, `budget-test.sh`, and ShellCheck (`shellcheck
  omarchy-protonpass tests/*.sh tests/mocks/*`) green.
- `tests/qml-service-scenarios.sh` in the nested compositor: every
  auth-transition scenario (`locked`, `logged-out`, `expired`, `offline`)
  resolves to its own state; add a scenario where the panel closes during
  LOADING and reopens, landing in READY with no second fetch.
- `tests/qml-panel-snapshot.sh` at both viewports for the header text and the
  row list at 5,000 mock items; `tests/qml-key-matrix.sh` for cursor keys.
- Envelope matrix unchanged for the helper unless task 4 changes a constant,
  in which case only those lines move.
- Live shell load on the branch as described above, zero "widget failed"
  lines, panel opens, types, copies against the mock, and the desktop is
  restored to `main` afterwards.
- No new files on disk, no new settings, no new environment variables.
- Push the branch to origin; do not open a PR. Report the CI run ID and read
  its conclusion with `gh run view <id>`, never by watching the kickoff.

## Reporting

Before writing code, emit the implementation table (columns: feature / part
name · % complete · LOE · % certainty · questions to nail down human-AI intent
before implementation) with the questions column filled, and stop for answers
if any question changes the design. Re-emit the table at every progress or
stop point. If a verification result flips between runs, stop on the second
flip and report what you know versus what you claimed; do not write a third
variation. The final report ends with: the table, the branch name, the CI run
ID and conclusion, the harness results, the leak checks, and confirmation the
live install is back on `main`.
