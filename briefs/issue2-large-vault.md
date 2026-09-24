# Build lane: issue 2, large vaults, in-memory fix (no disk cache)

Branch `large-vault-index` from `origin/main` in a scratch worktree. Read
issue 2 and PR 3 on josh2c/omarchy-protonpass for the diagnosis; the PR's disk
cache is not adopted (recorded decision: metadata never at rest, PLAN.md §1.3
and §3.7, SECURITY.md "the only things it writes to disk"). Adopt its two small
fixes and solve the rest in memory.

The mechanism, verified in source. `Service.qml` `onPanelOpened` calls
`refresh()` on every open; `onPanelClosed` terminates the running index
process; the index is kept in memory (`_hasIndex`) and the panel already shows
the old list while `refreshing`. With a 4,640-item vault a fetch takes 15 to 40
seconds, the user closes the panel before it finishes, the process is killed,
and the next open starts over. The index never completes.

Task.
1. Let an in-flight index finish after the panel closes instead of killing it.
   Keep the generation fencing exactly as it is (leave-alone list): a refresh
   requested while one runs still supersedes it; auth transitions still clear
   the model.
2. Do not refresh on every open. Refresh on open only when the in-memory index
   is older than a freshness window (propose a value and justify it; 5 minutes
   is the starting guess) or absent. Explicit refresh (button, `r`, `Ctrl+R`)
   always fetches. Doctor and recents behaviour on open are unchanged.
3. From PR 3, adopt: the header meta text shows "Loading Proton Pass logins..."
   while `state === "LOADING"` instead of stale doctor text; and the timeout
   naming so that `INDEX_TIMEOUT_SECONDS` and `INDEX_DEADLINE_SECONDS` do not
   mislead. The aggregate deadline is an availability bound introduced in
   1.5.0. If it must rise to fit a 4,640-item vault, say why, keep it as the
   single ceiling, and confirm `tests/budget-test.sh` and the CI seeded-mutation
   gate still reject a raised ceiling. Do not exceed 90 seconds.
4. Credit the issue and PR authors in the commit body for the diagnosis.
5. Second commit, after 1-3 are green: the row list. `Panel.qml` renders the
   Recent and All sections through two eager `Repeater`s over JS arrays
   (`Panel.qml:969-972`, `999-1003`), each delegate holding three `Text` nodes
   and a nested `Repeater` of three buttons. Reassigning the filtered array
   destroys and rebuilds every delegate, so at 4,640 items every keystroke
   rebuilds tens of thousands of objects inside the shell process, and the
   viewport is clipped to 300 px anyway. Replace with a `ListView` (sections
   for Recent and All, `cacheBuffer` sized to the viewport, delegates reused).
   Keyboard cursor, scroll-into-view, click-to-copy, accessible names, and the
   `Text.PlainText` pins must all survive; `tests/source-contract-test.sh`
   pins some of these by literal string and may need its pins moved, never
   weakened. Give `tests/row-perf-harness.qml` a pass/fail threshold at 5,000
   items instead of printing a number.

Acceptance. Both commits, sequentially, each green before the next. `tests/qml-service-scenarios.sh` in a nested compositor (never
the host session): every auth-transition scenario still resolves to its own
state; a close during LOADING followed by a reopen lands in READY without a
second fetch (add this scenario). Snapshot harness at both viewports for the
header text and the row list at 5,000 mock items. Key-matrix harness for the cursor keys. Live shell load with zero "Plugin widget failed" lines. Offline
suites, budget suite, ShellCheck green. Envelope matrix unchanged for the
helper unless task 3 changes a constant, in which case only those lines move.
No new files on disk, no new settings, no new environment variables. Commits
in repo style, no trailers. Push the branch; do not open a PR.

Fill the questions column of the implementation table before coding, re-emit
it at every stop point, and end the report with it plus the branch name and
the CI run ID.
