# Board

Maintained by the conductor. One row per task. Status: done / in flight /
ready (brief exists, not dispatched) / blocked / held / idea. Priority: P0 ships
before anything else, P1 this release, P2 next, P3 when convenient.

Release plan: 1.5.1 = large-vault fix + PRs 1 and 4 (cut now). 1.5.2 = PRs 5
and 6 once the contributors amend, plus budget-mirror and residue-scan. 1.6.0 =
QML in CI + field registry. Credit cards only after the registry.

| ID | Task | Status | Pri | Depends on | Blocks | Brief |
|---|---|---|---|---|---|---|
| G0 | Approve held CI runs on PRs 1, 3, 4, 5, 6 after intake | done 2026-09-25, all green | P0 | - | - | - |
| R1 | PRs 1 and 4 live-checked on merged main and squash-merged | done 2026-09-25 | P0 | G0 | 1.5.1 | briefs/pr1-pr4-review.md (live-check part only) |
| R2 | PR 5: request changes (character set, exclusion on sanitised name); contributor amends; re-review; merge | waiting on contributor after Josh posts | P0 | G0 | 1.5.1 | replies.md; briefs/pr5-review.md is the fallback if the contributor goes quiet |
| B1 | PR 6: request changes (one umask 077 in main(), inverted child assertion); contributor amends; merge | waiting on contributor after Josh posts | P1 | G0 | 1.5.1 | replies.md; briefs/pr6-partial.md is the fallback |
| OPS | Merge PR 7, approve fork CI, post reviews on 5 and 6, comment and close 3, live-check and merge 1 and 4, push docs branches | done 2026-09-25: PR 7 rebased (5634ed4, 4d7f305), PR 1 squashed b3a6f8e, PR 4 squashed 490a809, PR 8 docs 45431fb, PR 3 closed with explanation, reviews on 5 and 6 posted | P0 | none | REL | briefs/release-ops-1.md |
| B2 | Issue 2: finish index after close, freshness window, loading text, ListView rows, perf threshold | done on origin/large-vault-index (f189472, 0d00b84); gates green locally 2026-09-24; PR 7 open, CI run 36081896834 success 2026-09-25; awaiting rebase-and-merge | P0 | none | 1.5.1 | briefs/issue2-large-vault.md |
| D1 | Disk index cache (PR 3): declined for now, in-memory first (B2); revisit only if B2 is not enough. Reviewer's nine findings on PR 3 are the requirements if it ever returns | decided 2026-09-24 | - | none | none | reviewer report, conductor |
| C1 | Post review comments on PRs 5 and 6, comment on PR 3, approve 1 and 4 | done 2026-09-25 | P0 | none | R1 R2 B1 | scratchpad board/replies.md |
| C2 | .github/CONTRIBUTING.md and PR template | done, PR 8 merged 45431fb | P1 | none | none | conductor |
| B3 | Budget mirror parity test, third CI gate, RECENTS_LIMIT pair | done on branch: PR 11 (03c626c), run 36089010218 green; shape (a) declined, 1.6.0 item | P1 | none | any budget change | none yet |
| B4 | Surface keybind parse errors and pass-cli version warning in the panel, not only console.warn | idea | P2 | none | none | none yet |
| B5 | Get the QML harnesses into CI (nested compositor in a container, or assertion suite from baselines) | idea | P1 | none | safe QML work at scale | none yet |
| B6 | Single field/type registry shared by helper and QML (six duplicated allowlists today) | idea | P2 | B5 preferred | credit cards, notes | none yet |
| B7 | Credit-card item type | deferred 2026-09-25: not until a user asks and B6 is done | P3 | B6 | none | none |
| B8 | TOTP selection when an item has several TOTP fields (first one wins today, silently) | idea | P3 | B6 | none | none yet |
| B9 | Extend security-test residue contract to $XDG_STATE_HOME | done on branch: PR 10 (532aa9b), run 36088531451 green |
| RV1 | Independent review (Gates 1-2) of PRs 10 and 11, then merge | done 2026-09-25: both pass, merged 47ebec4 (run 36090346954) and 2ae1b35 (run 36090368865) | P1 | none | 1.5.2 | briefs/review-merge-10-11.md |
| B14 | Shape (a): helper emits its limits in the envelope, service validates against them under a fixed ceiling; touches _validatedResponse | idea | P3 | B6 | none | none yet | P1 | none | any at-rest change | none yet |
| B10 | Offline test for SIGTERM mid-command (panel close does this routinely; scratch cleanup only reasoned about) | ready to brief | P2 | none | none | none yet |
| B11 | Product call: should logout delete recents.json? Today per-account IDs survive sign-out | held (Josh) | P2 | none | none | none |
| B12 | Panel snapshot baseline is theme-dependent (accent colour moved with Josh's theme in B2); pin a theme in the harness | ready to brief | P2 | none | none | none yet |
| REL2 | Release 1.5.2 on 2026-10-09: PRs 5 and 6 (merged or landed by fallback), recipe-3 wording, CI concurrency guard, T12 note, release steps | brief ready, dated | P1 | date or PRs 5+6 merged | none | briefs/release-1.5.2.md |
| D2 | SECURITY.md recipe 3 prose says "the copy at the bottom passes copy_args" but three wl-copy guard lines follow the value copy; pre-existing imprecision, fix wording in 1.5.2 | ready to brief (docs) | P2 | none | none | none yet |
| B13 | Live keyboard-driven acceptance: wtype cannot reach the panel on the host seat; the key-matrix harness in the nested compositor is the instrument; record in T12-ACCEPTANCE | ready to brief (docs) | P3 | none | none | none yet |
| B15 | CI concurrency guard for main | folded into REL2 | P2 | none | none | none yet |
| B16 | Test sandbox cleanup does not always fire | folded into H1 | P2 | none | none | none yet |
| B17 | Residue term list: add a per-source coverage guard so emptying one fixture cannot silently drop its terms | idea | P3 | none | none | none yet |
| H1 | Hygiene: stale remote branch, dead local branches, eight t* worktrees, install's old branch, stale sandboxes, sandbox-cleanup fix (PR) | ready | P2 | none | none | briefs/hygiene.md |
| H2 | Josh's install updated to 1.5.1 on main (was t1-repo-scaffold at 1.4.0; that branch still exists in the install, delete it) | done 2026-09-25 | P1 | - | - | - |
| REL | 1.5.1: bump, tag, CI by run ID, SECURITY.md greps on fresh clone, marketplace [Verify] issue, Josh's install | done 2026-09-25: 094346a, tag 1.5.1, runs 36086210843 + 36086666487 green, marketplace issue omacom/omarchy-plugin-marketplace#8602 open | P0 | - | - | briefs/release-1.5.1.md |

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
