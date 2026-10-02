# Board

Maintained by the conductor. One row per task. Status: done / in flight /
ready (brief exists, not dispatched) / blocked / held / idea. Priority: P0 ships
before anything else, P1 this release, P2 next, P3 when convenient.

Release plan: 1.5.1 shipped 2026-09-24. 1.5.2 shipped 2026-09-28 (d67ac33:
PRs 5, 10, 11, 12, recipe-3 wording, CI concurrency guard). 1.5.3 = PR 14
(merged cac36e6) + PR 6 once amended + B21/B22; B10 and B12 wait until PR 6
lands because they touch the same test files. PR 6 amended 2026-09-29 and in
review; cut 1.5.3 once RV4 and B21 both land. 1.6.0 =
QML in CI + field registry. Credit cards only after the registry.

| ID | Task | Status | Pri | Depends on | Blocks | Brief |
|---|---|---|---|---|---|---|
| G0 | Approve held CI runs on PRs 1, 3, 4, 5, 6 after intake | done 2026-09-25, all green | P0 | - | - | - |
| R1 | PRs 1 and 4 live-checked on merged main and squash-merged | done 2026-09-25 | P0 | G0 | 1.5.1 | briefs/pr1-pr4-review.md (live-check part only) |
| R2 | PR 5: request changes (character set, exclusion on sanitised name); contributor amends; re-review; merge | done 2026-09-28, squash-merged 0ed757e, contributor as author | P0 | G0 | 1.5.2 | briefs/review-merge-5-6-12.md |
| B1 | PR 6: request changes (one umask 077 in main(), inverted child assertion); contributor amends; merge | amended 2026-09-29 (0bb071f: child from a 0022 subshell, mock records mask + scratch-file mode, expects 0077 600), run 36539781607 green; review lane RV4 ready |  P1 | G0 | 1.5.2 or 1.5.3 | briefs/pr6-reply.md; briefs/pr6-partial.md is the fallback after two quiet weeks |
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
| RV2 | Independent review (Gates 1-3) of PRs 12, 5 and 6 in that order, then merge | done 2026-09-28: PR 12 merged b9f5052 (run 36486225814), PR 5 merged 0ed757e author Nathan Day (run 36487031957), envelope matrix identical, snapshots identical, live load clean; PR 6 held at Gate 1 | P0 | none | REL2 | briefs/review-merge-5-6-12.md |
| B18 | budget-test.sh is load sensitive: under load the aggregate deadline lands before the per-vault cap and `item truncation was silent` fails on an unmodified tree (contributor report on PR 5, 175s runs) | closed 2026-09-28: not reproduced here at 108s idle, 139s and 257s under load, passed all three; reopen only if it shows on our machine or in CI | P2 | none | none | none yet |
| B19 | Sanitizer character class is two jq copies in one file; byte-for-byte assert_mirrors in source-contract-test.sh, plus a scenario pinning strip-before-cap and vault-name class coverage | done 2026-09-28, merged cac36e6 via RV3 | P2 | none | 1.5.3 | briefs/sanitizer-mirror.md |
| RV1 | Independent review (Gates 1-2) of PRs 10 and 11, then merge | done 2026-09-25: both pass, merged 47ebec4 (run 36090346954) and 2ae1b35 (run 36090368865) | P1 | none | 1.5.2 | briefs/review-merge-10-11.md |
| B14 | Shape (a): helper emits its limits in the envelope, service validates against them under a fixed ceiling; touches _validatedResponse | idea | P3 | B6 | none | none yet | P1 | none | any at-rest change | none yet |
| B10 | Offline test for SIGTERM mid-command (panel close does this routinely; scratch cleanup only reasoned about) | ready to brief | P2 | none | none | none yet |
| B11 | Product call: should logout delete recents.json? Today per-account IDs survive sign-out | held (Josh) | P2 | none | none | none |
| B12 | Panel snapshot baseline is theme-dependent (accent colour moved with Josh's theme in B2); pin a theme in the harness | ready to brief | P2 | none | none | none yet |
| REL2 | Release 1.5.2 | done 2026-09-28: d67ac33, tag 1.5.2, PR 15 run 36491189783, main run 36492012650, marketplace omacom/omarchy-plugin-marketplace#9196 (baseline flags the install-command strings as package-manager/privilege, maintainer review pending), install on main 1.5.2; PR 13 proved PR-side cancellation (36489962035 cancelled); main-side cancellation correct by construction, unobserved | P1 | - | - | briefs/release-1.5.2.md |
| RV4 | Independent review (Gates 1-3) of PR 6 third round, then squash merge with contributor as author, live load after | ready 2026-10-01; runs in parallel with B21 (disjoint files) | P1 | none | 1.5.3 | briefs/review-merge-6.md |
| RV3 | Independent review (Gates 1-2) of PR 14, then rebase merge; ci.yml gate change reviewed as security | done 2026-09-28: pass, merged cac36e6, run 36495529759 green; two own mutations red; extractor end-of-line hole found, CI seed 4 is the only catcher for the wrapped shape | P2 | none | 1.5.3 | briefs/review-merge-14.md |
| M1 | Marketplace: 8602 closed as superseded 2026-09-28; 9196 waits on maintainer manual review of the copy-install-command strings, 2528 took one day | waiting on maintainer | P2 | none | listing | scratchpad close-8602.md |
| B21 | Sanitizer mirror extractor reads to end of line; wrapping both jq copies identically blinds it; read the whole definition | ready 2026-09-28 | P2 | none | none | briefs/mirror-extractor.md |
| B22 | Envelope matrix covers no control-* scenario, so its identity says nothing about the sanitizer; add them | ready 2026-09-28, same lane as B21 | P2 | none | none | briefs/mirror-extractor.md |
| B23 | All four CI seeded gates use continue-on-error, so an unrelated step failure reads as "seed caught"; assert on the suite's own output, not the step outcome | idea | P3 | none | none | none yet |
| B20 | Live search/copy is not scriptable on the host seat (IPC exposes open/close/show/hide/toggle only); nested key-matrix + service-scenario harnesses are the instrument; recorded in T12-ACCEPTANCE 350fa0d | done, on record | P3 | - | - | - |
| D2 | SECURITY.md recipe 3 prose says "the copy at the bottom passes copy_args" but three wl-copy guard lines follow the value copy; pre-existing imprecision, fix wording in 1.5.2 | done in REL2 04b49f7 | P2 | none | none | none yet |
| B13 | Live keyboard-driven acceptance: wtype cannot reach the panel on the host seat; the key-matrix harness in the nested compositor is the instrument; record in T12-ACCEPTANCE | done in REL2 step 4, dev-docs 350fa0d | P3 | none | none | none yet |
| B15 | CI concurrency guard for main | done in REL2 f11e9a1 | P2 | none | none | none yet |
| B16 | Test sandbox cleanup does not always fire | folded into H1 | P2 | none | none | none yet |
| B17 | Residue term list: add a per-source coverage guard so emptying one fixture cannot silently drop its terms | idea | P3 | none | none | none yet |
| H1 | Hygiene | done 2026-09-25: 38 local branches, 8 worktrees, remote release branch, install branch, 14 sandboxes removed; HANDOFF.md preserved on dev-docs 44e4106; sandbox-cleanup fix on PR 12 (cc218b5, run 36096141760 green), review+merge folded into REL2 step 0 | P2 | none | none | briefs/hygiene.md |
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
