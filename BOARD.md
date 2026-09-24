# Board

Maintained by the conductor. One row per task. Status: done / in flight /
ready (brief exists, not dispatched) / blocked / held / idea. Priority: P0 ships
before anything else, P1 this release, P2 next, P3 when convenient.

Release plan: 1.5.1 = community fixes + large-vault fix. 1.6.0 = QML in CI +
field registry. Credit cards only after the registry.

| ID | Task | Status | Pri | Depends on | Blocks | Brief |
|---|---|---|---|---|---|---|
| G0 | Approve held CI runs on PRs 1, 3, 4, 5, 6 after intake | ready (Josh) | P0 | intake done | R1 R2 R3 | PR-PROCESS.md Gate 0 |
| R1 | Land PR 1 (ipcTarget) and PR 4 (SECURITY.md wording); reviewed, both correct | ready | P0 | none | 1.5.1 | briefs/pr1-pr4-review.md |
| R2 | Land PR 5 with two amendments (character set, exclusion on sanitised name); reviewed | ready | P0 | none | 1.5.1 | briefs/pr5-review.md |
| B1 | PR 6: one umask 077 in main() instead of four per-site calls; hash note as written | ready | P1 | none | 1.5.1 | briefs/pr6-partial.md |
| B2 | Issue 2: finish index after close, freshness window, loading text, ListView rows, perf threshold | done on origin/large-vault-index (f189472, 0d00b84); gates green locally 2026-09-24; awaiting PR for CI | P0 | none | 1.5.1 | briefs/issue2-large-vault.md |
| D1 | Disk index cache (PR 3): declined for now, in-memory first (B2); revisit only if B2 is not enough. Reviewer's nine findings on PR 3 are the requirements if it ever returns | decided 2026-09-24 | - | none | none | reviewer report, conductor |
| C1 | Reply to all five contributors and issue 2 | ready (Josh posts) | P0 | D1 | none | conductor drafts |
| C2 | .github/CONTRIBUTING.md and PR template | in flight | P1 | none | none | conductor |
| B3 | Tie the QML budget mirror to the helper constants (Service.qml:33-34 vs helper :24-26) or test that they agree | ready to brief | P1 | none | any budget change | none yet |
| B4 | Surface keybind parse errors and pass-cli version warning in the panel, not only console.warn | idea | P2 | none | none | none yet |
| B5 | Get the QML harnesses into CI (nested compositor in a container, or assertion suite from baselines) | idea | P1 | none | safe QML work at scale | none yet |
| B6 | Single field/type registry shared by helper and QML (six duplicated allowlists today) | idea | P2 | B5 preferred | credit cards, notes | none yet |
| B7 | Credit-card item type: index with --filter-type, copy number/cvv/expiry/name | idea | P3 | B6 | none | none yet |
| B8 | TOTP selection when an item has several TOTP fields (first one wins today, silently) | idea | P3 | B6 | none | none yet |
| B9 | Extend security-test residue contract to $XDG_STATE_HOME (today only XDG_RUNTIME_DIR is scanned) | ready to brief | P1 | none | any at-rest change | none yet |
| B10 | Offline test for SIGTERM mid-command (panel close does this routinely; scratch cleanup only reasoned about) | ready to brief | P2 | none | none | none yet |
| B11 | Product call: should logout delete recents.json? Today per-account IDs survive sign-out | held (Josh) | P2 | none | none | none |
| B12 | Panel snapshot baseline is theme-dependent (accent colour moved with Josh's theme in B2); pin a theme in the harness | ready to brief | P2 | none | none | none yet |
| H1 | Delete merged local branches with gone upstreams; remove the eight ~/projects/omarchy-protonpass-t* worktrees | ready (Josh) | P3 | none | none | none |
| H2 | Update Josh's install from 1.4.0 to current, shell restart | ready (Josh) | P1 | 1.5.1 tag | none | none |
| REL | 1.5.1: bump, tag, CI by run ID, SECURITY.md greps on fresh clone, marketplace [Verify] issue | blocked | P0 | R1 R2 B1 B2 | H2 | PR-PROCESS.md Gate 3 |

Not doing, on the record: disk index cache as proposed in PR 3 (pending D1);
raising INDEX_DEADLINE_SECONDS above 90; removing redundant umask calls.

Parallel lanes now: R1, R2, B1, B2 are four different sessions on four
disjoint file sets (B1 helper + tests; B2 Service.qml + Panel.qml; R1, R2
read-only). C2 is docs on `.github/` only.

Next three lanes after these: B3 (small, helper + Service + one test), B5
(investigation first: can quickshell run headless in CI?), B6 (design brief
before code).
