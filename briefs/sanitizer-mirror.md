# Build lane: pin the sanitizer class and the strip-before-cap claim

You are the ENGINEER for this task. Do the work directly in this session; do
not dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. The only public action allowed is opening
one pull request.


`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = 0ed757e (release 1.5.1 plus PRs 10, 11, 12 and 5). GitHub: josh2c/omarchy-protonpass.
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

PR 5 (merged as 0ed757e, author Nathan Day) strips control and format
characters from item titles and vault names in `index_command`. The
independent reviewer found two claims the tests do not hold:

1. The character class is written twice, as two `def sanitize:` literals in
   two jq programs in the helper. They are byte-identical today and nothing
   pins them together: narrowing only the vault-name copy (dropping
   U+2060-2064 and the tag block) leaves the whole offline suite green,
   because the property assertion covers `.title` only and the vault-name
   scenarios pin ESC and U+202E alone.
2. The helper comment says stripping before capping means control padding
   cannot spend the display budget. Swapping the cap ahead of the strip
   leaves the suite green.

Branch `sanitizer-mirror` from `origin/main` in a scratch worktree.

For 1, add an `assert_mirrors`-style check to `tests/source-contract-test.sh`
that the two `def sanitize:` literals are byte-for-byte equal, following the
budget-mirror precedent (PR 11). Do not restructure the helper to share the
class through a shell variable: that changes the shipped runtime for a test
concern, and the duplication is one contract stated twice, which is the
shape we chose for the budget numbers. If a fourth CI seeded-mutation gate is
the right way to prove the new check fails closed, add it the way PR 11 did;
if you think it is not warranted, say why in the report.

For 2, add a `helper-test.sh` scenario in the pass-cli mock: a title whose
visible text is followed by more than 256 stripped characters must index as
its visible text, not as `(untitled login)` or a truncated string. Extend
the vault-name scenarios so the classes the property assertion covers for
titles are also represented for vault names.

Acceptance. Each new assertion red under the mutation that motivated it
(narrow one copy of the class; swap cap and strip) and green on the
unmodified tree. All offline suites, `budget-test.sh` and ShellCheck green.
Envelope matrix before and after identical: this lane changes no runtime
behaviour, and if you find you need to, stop and report. Commit in repo
style, push, open a PR whose body says what is pinned and why, and report
the CI run ID. Do not merge.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Final report: the two mutations and their results, the
PR number and run ID, and the state of `~/projects/omarchy-protonpass`.
