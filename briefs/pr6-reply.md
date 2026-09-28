Thanks. One problem before I can merge: I deleted the `umask 077` line from `main()` and every suite still passed, budget-test included. Nothing pins the change.

Cause is `tests/helper-test.sh:14`, where the suite sets `umask 077` for itself. Both legs of the new child assertion inherit that mask. The sourced-helper leg never runs `main()`, and the `"$HELPER"` subprocess inherits the test shell's mask. So the assertion checks the harness, not the helper. The existing captured-stderr mode check has the same issue: set the harness mask to 022 and it fails on main and on this branch alike. With a real caller umask of 022, `open_stderr_capture` produces 644 here, 600 on main. That file has no chmod after it, so it's the case the `main()` mask exists for.

Fix I'd suggest: run one copy-path call from a subshell with a loose mask, `( umask 022; "$HELPER" copy ... )`, and have the mock expect `0077` for it. That can only pass if `main()` set the mask. Keep the "caller's umask alone" assertion. Please confirm it goes red with the `main()` line removed.

Rest is fine as is: chmods kept, per-site calls gone, SECURITY.md paragraph unchanged. Still merges cleanly, no rebase needed.
