# Board

Maintained by the conductor. One row per task. Status: done / in flight /
ready (brief exists, not dispatched) / blocked / held / idea. Priority: P0 ships
before anything else, P1 this release, P2 next, P3 when convenient.

Release plan: 1.5.1 = community fixes + large-vault fix. 1.6.0 = QML in CI +
field registry. Credit cards only after the registry.

| ID | Task | Status | Pri | Depends on | Blocks | Brief |
|---|---|---|---|---|---|---|
| G0 | Approve held CI runs on PRs 1, 3, 4, 5, 6 after intake | ready (Josh) | P0 | intake done | R1 R2 R3 | PR-PROCESS.md Gate 0 |
| R1 | PR 1 live check on pull/1/head (nested compositor + live load + toggle), then Josh approves and squash-merges PRs 1 and 4 in the UI | ready | P0 | G0 | 1.5.1 | briefs/pr1-pr4-review.md (live-check part only) |
| R2 | PR 5: request changes (character set, exclusion on sanitised name); contributor amends; re-review; merge | waiting on contributor after Josh posts | P0 | G0 | 1.5.1 | replies.md; briefs/pr5-review.md is the fallback if the contributor goes quiet |
| B1 | PR 6: request changes (one umask 077 in main(), inverted child assertion); contributor amends; merge | waiting on contributor after Josh posts | P1 | G0 | 1.5.1 | replies.md; briefs/pr6-partial.md is the fallback |
| OPS | Merge PR 7, approve fork CI, post reviews on 5 and 6, comment and close 3, live-check and merge 1 and 4, push docs branches | in flight 2026-09-25 | P0 | none | REL | briefs/release-ops-1.md |
| B2 | Issue 2: finish index after close, freshness window, loading text, ListView rows, perf threshold | done on origin/large-vault-index (f189472, 0d00b84); gates green locally 2026-09-24; PR 7 open, CI run 36081896834 success 2026-09-25; awaiting rebase-and-merge | P0 | none | 1.5.1 | briefs/issue2-large-vault.md |
| D1 | Disk index cache (PR 3): declined for now, in-memory first (B2); revisit only if B2 is not enough. Reviewer's nine findings on PR 3 are the requirements if it ever returns | decided 2026-09-24 | - | none | none | reviewer report, conductor |
| C1 | Post review comments on PRs 5 and 6, comment on PR 3, approve 1 and 4 | ready (Josh posts) | P0 | none | R1 R2 B1 | scratchpad board/replies.md |
| C2 | .github/CONTRIBUTING.md and PR template | in flight | P1 | none | none | conductor |
| B3 | Tie the QML budget mirror to the helper constants (Service.qml:33-34 vs helper :24-26) or test that they agree | ready, briefs/budget-mirror.md | P1 | none | any budget change | none yet |
| B4 | Surface keybind parse errors and pass-cli version warning in the panel, not only console.warn | idea | P2 | none | none | none yet |
| B5 | Get the QML harnesses into CI (nested compositor in a container, or assertion suite from baselines) | idea | P1 | none | safe QML work at scale | none yet |
| B6 | Single field/type registry shared by helper and QML (six duplicated allowlists today) | idea | P2 | B5 preferred | credit cards, notes | none yet |
| B7 | Credit-card item type: index with --filter-type, copy number/cvv/expiry/name | idea | P3 | B6 | none | none yet |
| B8 | TOTP selection when an item has several TOTP fields (first one wins today, silently) | idea | P3 | B6 | none | none yet |
| B9 | Extend security-test residue contract to $XDG_STATE_HOME (today only XDG_RUNTIME_DIR is scanned) | ready, briefs/residue-scan.md | P1 | none | any at-rest change | none yet |
| B10 | Offline test for SIGTERM mid-command (panel close does this routinely; scratch cleanup only reasoned about) | ready to brief | P2 | none | none | none yet |
| B11 | Product call: should logout delete recents.json? Today per-account IDs survive sign-out | held (Josh) | P2 | none | none | none |
| B12 | Panel snapshot baseline is theme-dependent (accent colour moved with Josh's theme in B2); pin a theme in the harness | ready to brief | P2 | none | none | none yet |
| H1 | Delete merged local branches with gone upstreams; remove the eight ~/projects/omarchy-protonpass-t* worktrees | ready (Josh) | P3 | none | none | none |
| H2 | Update Josh's install from 1.4.0 to current, shell restart | ready (Josh) | P1 | 1.5.1 tag | none | none |
| REL | 1.5.1: bump, tag, CI by run ID, SECURITY.md greps on fresh clone, marketplace [Verify] issue, Josh's install | brief ready, blocked on ops lane | P0 | ops lane (PR 7, 1, 4 merged) | none | briefs/release-1.5.1.md |

Not doing, on the record: disk index cache as proposed in PR 3 (pending D1);
raising INDEX_DEADLINE_SECONDS above 90; removing redundant umask calls.

Community PRs stay the contributors' vehicle: review comments ask for the
change, the contributor pushes to their branch, CI runs on approval, merge in
the UI with them as author. Our own branches (briefs/pr5, pr6) are the
fallback only if a contributor goes quiet for two weeks; then cherry-pick with
authorship kept, credit in the body, and close their PR with a link.

Next three lanes after these: B3 (small, helper + Service + one test), B5
(investigation first: can quickshell run headless in CI?), B6 (design brief
before code).
