# Merge lane: PR 1 (ipcTarget) and PR 4 (SECURITY.md wording)

Both were read independently and check out: PR 1's `ipcTarget` is the one
line every other Omarchy panel sets and ours never did, the base Panel's
IpcHandler exposes only open/close/show/hide/toggle, and its contract pin is
right. PR 4's sentences match the code. Neither PR text carries attributions.

Task. Branch `community-1-4` from `origin/main` in a scratch worktree.
1. `git fetch origin pull/1/head:pr1-upstream pull/4/head:pr4-upstream`;
   cherry-pick each onto the branch, contributor as author, commit messages in
   repo style (rewrite if needed, no trailers).
2. PR 1 touches Panel.qml, so before it can ship: snapshot harness at both
   viewports (nested compositor only, never the host session), then a live
   shell load with zero "Plugin widget failed" journal lines, then
   `omarchy-shell josh2c.protonpass toggle` opens and closes the panel.
3. Add one README line under Keyboard use naming the IPC target with a sample
   Hyprland binding, so the feature is discoverable.
4. Offline suites and ShellCheck green. Push the branch; do not open a PR.

Report the branch name, the CI run ID, the harness results, and the
implementation table. Stop there.
