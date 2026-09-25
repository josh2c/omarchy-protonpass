# Engineer brief: independent review of PRs 10 and 11, then merge

You are the ENGINEER for this task: an independent reviewer with merge
rights for this lane only. Do the work directly in this session; do not
dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. The only public actions allowed are the
two merges named below, and only if your review passes.

## The project

`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = release 1.5.1 (094346a). GitHub: josh2c/omarchy-protonpass.
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

Two pull requests were written by engineer sessions in this project, each
with a green CI run and a self-reported mutation test. Neither has had a
fresh pair of eyes. Read `dev-docs:PR-PROCESS.md` Gates 1 and 2; you own
both, for both PRs. Read the code, not the descriptions.

- PR 10 (`residue-scan`, 532aa9b, run 36088531451): extends
  `tests/security-test.sh` so no file under the sandbox's `XDG_STATE_HOME`
  may hold the marker secret, an item title, a vault name, or a username
  after the copy, create, index and recents paths run; terms derived from
  fixtures; asserts at least one file was read; second pass after recents
  clear. The author added an index run to the suite, arguing the contract is
  vacuous without it.
- PR 11 (`budget-mirror`, 03c626c, run 36089010218): a source-contract
  check that the helper's `INDEX_MAX_ITEMS_TOTAL` / `INDEX_MAX_VAULTS` /
  `RECENTS_LIMIT` equal the service's `maxIndexItems` / `maxIndexVaults` /
  the inline recents bound; a third CI seeded-mutation gate for it; a comment
  in Service.qml. No limit changed. The author declined the alternative of
  emitting limits in the envelope, which would have touched
  `_validatedResponse`.

The standard. For each PR: does the test actually pin what it claims? Redo
one mutation of your own choosing per PR, not the one the author reported,
and show it goes red. Does anything weaken or remove an existing assertion?
Could the new assertions pass on an empty or wrong input (a scan that finds
no files, a parser that reads a comment instead of the constant, a regex
that matches the wrong line)? Does the new CI gate fail closed if the seed
does not apply? What surface does each PR add, per asset: secret values,
Proton session, clipboard, shell availability, helper integrity, data at
rest. Both PRs are test-only or comment-only in the shipped tree; confirm
that from the diff, not the description. Things we wondered; disagree with
them: is a term list derived from fixtures actually stronger than a
hand-kept one, or does it just move the trust? Does the fixture-derived
username list include the email fallback value?

## If both pass

`gh pr merge 10 --rebase --delete-branch`, then
`gh pr merge 11 --rebase --delete-branch` (PR 11 touches ci.yml and
Service.qml; if it no longer applies cleanly after 10, stop and report, do
not rebase it yourself). Confirm the push-to-main run for each is green by
ID. `git -C ~/projects/omarchy-protonpass pull --ff-only`. No live check is
required: nothing in the shipped runtime changes behaviour; say so
explicitly if you agree after reading the diffs, and if you disagree, do the
nested-compositor snapshot and a live load before merging.

## If either fails

Merge nothing. Post nothing. Report the finding with file:line and the
mutation that exposed it.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
before you start and at every stop point. Final report: per PR the verdict,
your own mutation and its result, the asset-by-asset line, the merge commit
and its run ID, the leak checks, and the state of `~/projects/omarchy-protonpass`.
