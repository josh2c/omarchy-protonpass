# Engineer brief: independent review of PRs 12, 5 and 6, then merge

You are the ENGINEER for this task: an independent reviewer with merge
rights for this lane only. Do the work directly in this session; do not
dispatch. You are working on Josh's own machine, which is also his live
desktop, and you act on the public repository josh2c/omarchy-protonpass with
Josh's GitHub account through `gh`. The only public actions allowed are the
approvals, merges and contributor comments named below, and only if your
review passes.

`omarchy-protonpass` is a Proton Pass bar-widget plugin for Omarchy Quattro
(Hyprland + quickshell). Repo: `~/projects/omarchy-protonpass`, `main` =
`origin/main` = 2ae1b35 (release 1.5.1 plus the merged residue-scan and budget-mirror test PRs). GitHub: josh2c/omarchy-protonpass.
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

Three pull requests are ready for a fresh pair of eyes. Read
`dev-docs:PR-PROCESS.md`; you own Gates 1 and 2 for all three and Gate 3 for
the merges. Read the code, not the descriptions. Two of the three come from
an outside contributor, Nathan Day (dadofsambonzuki), who amended them after
a request-changes review. The plugin copies passwords; every merge here is a
trust decision, and you are the last reader before it lands.

Order matters. PR 12 and PR 6 both touch `tests/lib.sh`; PR 5 and PR 6 both
touch the helper, `tests/helper-test.sh` and `tests/mocks/pass-cli`; and both
contributor branches fork from 1.5.0 (e529a3e), not from current main.
GitHub reports all three mergeable today, but that is against main as it is
now, and each merge changes it. Review all three first, merge in the order
12, 5, 6, and after every merge re-check that the next one still applies
cleanly and still passes on the merged tree, not on its own branch. If a
contributor PR stops applying cleanly, do not rebase it yourself: their
branch is their vehicle. Stop and report so the coordinator can ask them.

- PR 12 (`sandbox-cleanup`, cc218b5, run 36096141760, our own): tests-only.
  `tests/helper-test.sh` sources the helper, and the helper's own
  `trap ... EXIT` was displacing the suite's sandbox cleanup, leaking
  `/tmp/omarchy-protonpass-tests.*`. The fix re-arms the cleanup in
  `tests/lib.sh`.
- PR 5 (`security/sanitize-index-display-text`, head e11ab4a, run
  36334199355): the helper strips C0/C1 controls, ESC, DEL and a named set
  of invisible and direction-changing code points from item titles and vault
  names in the index, before the 256-character cap, with `(untitled login)`
  and `(unnamed vault)` fallbacks. The amendment widened the class to
  U+00AD, U+061C, U+2028/9, U+2060-2064 and the tag block, and moved the
  `excludeVaults` comparison into the sanitised space. The review comment on
  the PR is the contract the amendment must meet. The contributor reports
  budget-test wall time unchanged within noise.
- PR 6 (`fix/leaked-umask-and-hash-at-rest-note`, head 68f49bd, run
  36333078219): one `umask 077` at the top of `main()` replaces four per-site
  calls; every chmod kept; the "caller's umask alone" assertion kept; the
  pass-cli child assertion inverted to require 0077. Plus a SECURITY.md
  paragraph quantifying the offline guess against the at-rest TOTP hash.
  The review comment on the PR is the contract.

The standard, for each PR. Does the change do what the review asked, and
nothing the review did not ask? Does every new test pin what it claims: redo
one mutation of your own choosing per PR, not one the author reported, and
show it goes red. Does anything weaken or remove an existing assertion?
Could a new assertion pass on a wrong input? Run the full offline set and
`budget-test.sh` on each PR's head merged onto the then-current main, and
`tools/envelope-matrix.sh` before and after: every moved line is a behaviour
change the PR must name. ShellCheck: the contributor has no shellcheck
locally, so CI is the only run so far; run it here. Gate 0 item 3: scan the
contributor's commit messages and both PR bodies for tool attributions and
session links. Then the asset line per PR: secret values, Proton session,
clipboard, availability of the shell process, integrity of the helper path,
data at rest. PR 5 handles untrusted text from shared vaults; say how type,
size, cardinality and rate stay bounded after it, not just before.

Things we wondered; disagree with them. PR 5: a title or vault name that is
not a string (null, a number, an object) used to pass through the slice as
whatever jq made of it; now it goes through `gsub`, which errors on
non-strings, and a jq error inside the index loop is an availability
question for the whole index, not one item. Is that reachable through the
hostile mock, and what happens if it is? Does jq slice `[0:$limit]` by code
point, so the cap stays 256 characters and not 256 bytes? Does the vault
`name` that reaches `vaultName` on each item come from the sanitised
`$vaults` array or from the raw listing? The sanitizer class now lives in
two jq programs in one file; the budget-mirror lane just spent a PR pinning
two copies of one number, and this is two copies of one character class.
Is a source-contract assertion warranted, or is a comment enough? The
contributor reports `budget-test.sh` fails `item truncation was silent`
under machine load on the unmodified tree; if you can reproduce it, that is
a finding to report, not fix. PR 6: `helper-test.sh` sources the helper and
calls functions directly, so nothing inside the suite passes through
`main()` and its mask any more; does any existing assertion silently depend
on the per-site umask that was removed? Is there any file creation at the
top level of the script, before `main()` runs? Does the inverted child
assertion actually reach a pass-cli child through the copy path, or does
the mock short-circuit before one is spawned? PR 12: after the fix, does
the helper's own scratch-file cleanup still run when the helper is
sourced, or did we trade one leak for another?

## If a PR passes

- PR 12: `gh pr merge 12 --rebase --delete-branch`.
- PR 5 and PR 6: `gh pr review <n> --approve` with a body that says what you
  checked, then `gh pr merge <n> --squash`. Write the squash message in repo
  style: imperative title, plain prose body saying what changed and why; no
  trailers. Confirm the contributor stays the author on the merged commit
  (`git log -1 --format='%an %ae'` on origin/main after each merge).
- After each merge: confirm the push-to-main run green by run ID, then
  `git -C ~/projects/omarchy-protonpass pull --ff-only` before you test the
  next PR against it.
- After the last merge: PR 5 and PR 6 both change the shipped helper. Do the
  nested-compositor snapshot harness at both viewports and one live load
  with the merged main in Josh's install, zero "widget failed" journal
  lines, and restore the install to `main` afterwards (it will already be
  main; confirm it fast-forwarded and the bar shows the widget).

## If a PR fails

Merge nothing further. Post nothing on that PR. Report the finding with
file:line and the mutation or input that exposed it, so the coordinator can
write the contributor reply. A PR that passed earlier in the order stays
merged; say which did.

## Reporting

Emit the implementation table (feature / part name · % complete · LOE ·
% certainty · questions to nail down human-AI intent before implementation)
with the questions column filled before you start, at every stop point, and
in the final report. Final report: per PR the verdict, your own mutation and
its result, the envelope matrix result, the asset-by-asset line, the merged
commit, its author and its run ID, the leak checks after every harness run,
and the state of `~/projects/omarchy-protonpass` and the live install.
