# Engineer brief: independent review of PR 14, then merge

You are the ENGINEER for this task: an independent reviewer with merge
rights for this lane only. Do the work directly in this session; do not
dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. The only public action allowed is the
one merge named below, and only if your review passes.

`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = d67ac33 (release 1.5.2). GitHub: josh2c/omarchy-protonpass.
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


## Mission

PR 14 (`sanitizer-mirror`, 83b2a53, run 36490813244) was written by an
engineer session after the PR 5 review found two unpinned claims in the
index sanitiser: the character class is two `def sanitize:` literals in two
jq programs, and the comment says stripping runs before capping. The PR
adds a byte-for-byte mirror assertion to `tests/source-contract-test.sh`, a
fourth CI seeded-mutation gate for it in `.github/workflows/ci.yml`, two
padded-title scenarios and vault-name class parity in `tests/helper-test.sh`
and `tests/mocks/pass-cli`. The author reports no runtime file touched and
the envelope matrix identical. Read `dev-docs:PR-PROCESS.md` Gates 1 and 2;
you own both. Read the code, not the description.

The CI mutation gates are on the leave-alone list, so the ci.yml change is
reviewed as a security change, not a test tweak. The author changed the
seed mid-lane, from narrowing the class to dropping vertical tab and form
feed from one copy, on the argument that the mirror must be the only check
that catches the seed. Decide whether that argument holds and whether the
gate fails closed when the seed does not apply.

The standard. Redo one mutation of your own per claim, not the author's:
does the mirror catch a drift you choose, and does the padding scenario
catch a cap-before-strip you introduce a different way? Could the mirror
pass by comparing the wrong two strings, or a comment against a literal? Is
the parser that extracts the two literals robust to the helper being
reformatted, or does it silently compare empty strings? Does anything
weaken an existing assertion? Full offline set, `budget-test.sh` and
ShellCheck on the head merged onto main; `tools/envelope-matrix.sh` before
and after. Asset line per PR-PROCESS Gate 2; this should be a "no new
surface" PR and you say so from the diff. Things we wondered; disagree with
them: is a fourth CI gate worth its wall time, or should the three existing
seeds and this one run as one job? Would a third sanitizer copy added
tomorrow be caught, or does the mirror only know about two?

## If it passes

`gh pr merge 14 --rebase --delete-branch`. Confirm the push-to-main run
green by ID, then `git -C ~/projects/omarchy-protonpass pull --ff-only` and
delete the local `sanitizer-mirror` branch. No live check is required if
you agree from the diff that no runtime file changed; say so explicitly.
This is 1.5.3 content; do not bump, tag or release.

## If it fails

Merge nothing. Post nothing. Report the finding with file:line and the
mutation that exposed it.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Final report: the verdict, your own mutations and
their results, the asset line, the merge commit and its run ID, and the
state of `~/projects/omarchy-protonpass`.
