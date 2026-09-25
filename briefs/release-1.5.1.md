# Engineer brief: release 1.5.1

You are the ENGINEER for this task. Do the work directly in this session; do
not dispatch, do not ask the coordinator to run anything. You are working on
Josh's own machine, which is also his live desktop, so the environment rules
below are not optional.

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

## Task

Cut release 1.5.1 from `origin/main` once the coordinator confirms which of
the community PRs are in (PR 7 and PRs 1 and 4 at minimum; 5 and 6 if merged
by then). Branch `release-1.5.1` in a scratch worktree.

1. Bump `manifest.json` version to 1.5.1. Nothing else in the tree changes
   for the bump; `tests/manifest-test.sh` checks shape, not a pinned value.
2. Re-run every grep recipe in SECURITY.md exactly as written, from the
   plugin directory, and confirm each returns what the document says. If a
   recipe drifted, fix the document, not the code, and say so.
3. Fresh-clone check: `git clone <repo> /tmp/rel-clone`, list the tree, and
   confirm it contains only the runtime files, tests, README, SECURITY.md,
   LICENSE, preview.png, manifest.json, and `.github/`. No dev docs.
4. Acceptance on mocks, nested compositor only: snapshot harness at both
   viewports, key matrix, service scenarios, create harness, row-perf gate.
   Live shell load of the release ref as described above with zero "widget
   failed" lines; one open, one search, one copy against the mock helper;
   restore the install to its previous checkout afterwards.
5. Commit "Release 1.5.1" with a body that lists what changed since 1.5.0 in
   plain prose, one paragraph per merged PR, contributors named. Push,
   open a PR, wait for CI by run ID, merge with rebase.
6. Tag: `git tag -a 1.5.1 -m "<same body>"` on the merged main commit (no
   signing key exists; never `-s`), `git push origin 1.5.1`. Confirm the
   push-to-main CI run is green by ID.
7. Marketplace: open a `[Verify]` issue on omacom/omarchy-plugin-marketplace
   for plugin `josh2c.protonpass` at the tagged commit, using the same form
   as issue 2528 there (verification action: verify and publish a newer
   upstream commit; target commit: full SHA; acknowledgment box ticked).
   Report the issue URL; do not chase it.
8. Update Josh's install: `omarchy plugin update josh2c.protonpass --yes`,
   then the shell restart recipe above, then confirm the bar shows the
   widget, the manifest in the install says 1.5.1, and no "widget failed"
   lines. This is the one step that changes Josh's desktop permanently; do
   it last and say clearly that it was done.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. If a verification result flips between runs, stop on
the second flip and report what you know versus what you claimed. The final
report lists the branch, every run ID with its conclusion, and the leak
checks.
