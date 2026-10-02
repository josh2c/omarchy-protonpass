# Engineer brief: independent review of PR 6, then merge

You are the ENGINEER for this task: an independent reviewer with merge
rights for this lane only. Do the work directly in this session; do not
dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. The only public actions allowed are the
one approval and one merge named below, and only if your review passes.
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = cac36e6 (release 1.5.2 plus PR 14). GitHub: josh2c/omarchy-protonpass.
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

## Mission

PR 6 (`fix/leaked-umask-and-hash-at-rest-note`, head 0bb071f, run
36539781607 green) is from an outside contributor, Nathan Day
(dadofsambonzuki). It has been through two request-changes rounds and this
is the third read. Read `dev-docs:PR-PROCESS.md`; you own Gates 1 and 2 and
the Gate 3 merge. Read the code, not the description, and read the two
review comments on the PR and the contributor's replies: they are the
contract.

What the PR does, per the diff: one `umask 077` at the top of `main()` in
the helper replaces four per-site calls; every chmod kept; a SECURITY.md
paragraph quantifies the offline guess against the at-rest TOTP hash
(6-digit code, 10^6 candidates, measured well under a second). Tests: the
"caller's umask alone" assertion stays; a new assertion starts a real
copy-path call from a subshell holding 0022 with its own runtime directory,
and the mock records the inherited mask plus the mode of the helper's
stderr scratch file, expecting `0077 600`. `tests/lib.sh` and
`tests/mocks/pass-cli` carry the plumbing.

Why it was held last time: the first version of that assertion read the
harness's own `umask 077` from `tests/helper-test.sh:14`, so deleting the
`main()` line left every suite green. The contributor reports that is now
red: `expected '0077 600', got '0022 644'`. The contributor also corrected
one claim in our second review: on main the captured-stderr mode check
passed at harness mask 022 because `open_stderr_capture` set its own mask;
only on this branch did it depend on the harness. Take that as given unless
the code says otherwise.

The standard. The same as every contributor PR: redo the mutation yourself,
delete the `main()` umask line and show which assertion goes red; then
choose one mutation of your own that the contributor did not report. Does
the new assertion actually reach a pass-cli child through the copy path,
or does the mock short-circuit? Does the scratch-file mode column read the
helper's file and not one the harness created? Run `helper-test.sh` under
caller umasks 0022, 0002 and 0027 as the contributor did. Full offline set,
`budget-test.sh` and ShellCheck on the head merged onto current main (the
branch forks from 1.5.0; `git merge` it onto a scratch copy of main and test
that tree). `tools/envelope-matrix.sh` before and after: the matrix now
includes the control scenarios if lane B21 has landed, otherwise it is the
old 121 lines; either way every moved line is a behaviour change the PR must
name. Gate 0 item 3: scan all four commit messages and the PR body for tool
attributions and session links. Asset line per Gate 2; this PR acts on data
at rest and on the pass-cli child's files, say in which direction. Things we
wondered; disagree with them: with the per-site masks gone, is there any
helper function that creates a file and is reachable without going through
`main()` in production, not just in the sourced test leg? Does the stricter
mask change anything the pass-cli child does that a user would notice, for
example a session directory pass-cli expects to share?

## If it passes

`gh pr review 6 --approve` with a body that says what you checked, then
`gh pr merge 6 --squash`. Squash message in repo style: imperative title,
plain prose body saying what changed and why, crediting nothing and nobody
in trailers. Confirm the contributor stays the author on origin/main. Push
to main run green by ID. `git -C ~/projects/omarchy-protonpass pull
--ff-only`. This PR changes the shipped helper: do the nested-compositor
snapshot harness at both viewports and one live load in Josh's install
(fast-forward it to the merged main, restart the shell, zero "widget
failed" lines, widget in the bar), and leave the install on main. This is
1.5.3 content; do not bump, tag or release.

## If it fails

Merge nothing. Post nothing. Report the finding with file:line and the
mutation or input that exposed it, so the coordinator can write the
contributor reply.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Final report: the verdict, both mutations and their
results, the umask sweep, the envelope matrix result, the asset line, the
merged commit with its author and run ID, the leak checks after every
harness run, and the state of `~/projects/omarchy-protonpass` and the live
install.
