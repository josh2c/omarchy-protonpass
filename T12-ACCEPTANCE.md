# Combined Manual Acceptance Checklist — omarchy-protonpass 1.2.0

Run on this machine with the real eligible Proton account. This is the single combined v1.0 + v1.1 + v1.2 release gate. Every box must be checked before signing the `1.2.0` tag. If any step diverges from PLAN.md, stop and record it — do not work around it.

## Install & setup
- [ ] Fresh install: `omarchy plugin add https://github.com/josh2c/omarchy-protonpass --enable` (remove any dev copy first)
- [ ] With pass-cli absent from PATH: panel shows the setup view with copyable install commands and the eligibility note
- [ ] Install pass-cli via the official script; Recheck (or reopen panel) leaves setup state

## Auth lifecycle
- [ ] Logged out: panel shows "Not signed in" with the eligibility hint; Sign in opens a terminal running `pass-cli login` (web flow)
- [ ] Complete login incl. 2FA in the browser; reopening the panel loads the index
- [ ] `pass-cli session create-lock` in a terminal, then panel `L`: session locks, model clears, LOCKED view with Unlock
- [ ] Unlock via panel terminal button; reopening recovers READY
- [ ] Lock without a configured lock (after `session remove-lock`): toast explains `session create-lock`

## Index & search
- [ ] Items from ≥2 vaults appear; duplicate titles disambiguated by vault name
- [ ] With at least 3× one viewport of login rows, refresh/new/lock/logout remain visible and clickable in the header without scrolling; only the item list scrolls
- [ ] Search filters as you type; zero matches shows "No matches"
- [ ] Excluded vaults setting (type with a space after the comma) hides those vaults
- [ ] Unicode/emoji titles render correctly, plain text only

## Copy actions (verify each against the real item)
- [ ] `u` on an item with username → username copied
- [ ] `u` on an email-only item → email copied, toast names the fallback
- [ ] `p` / Enter → password copied
- [ ] `t` on a TOTP item → current code copied and accepted by the target site
- [ ] `t` on a no-TOTP item → "No TOTP on this item" toast, nothing copied
- [ ] Copied values NEVER appear anywhere in the panel

## Keyboard chords and remapping
- [ ] With search focused and text already entered, `Ctrl+U`, `Ctrl+P`, and `Ctrl+T` still copy the highlighted item's username/email, password, and TOTP
- [ ] With search focused, `Ctrl+R` refreshes, `Ctrl+L` locks, and `Ctrl+Shift+X` clears a plugin-owned clipboard value
- [ ] `Enter` copies password and `Shift+Enter` copies username/email in both search and list focus
- [ ] Set `keybinds` to `ctrl+shift+c:copy-password,ctrl+o:logout`; both remaps fire and unmodified defaults remain active
- [ ] The remapped logout chord arms confirmation only; a second invocation within 4 s confirms it
- [ ] Restore the `keybinds` setting to empty; the documented default chord table works again

## Clipboard countdown and clear-now
- [ ] After a copy, the panel shows the textual countdown and progress indicator
- [ ] Clicking the countdown clears the current plugin-owned value immediately and hides the countdown
- [ ] `Ctrl+Shift+X` clears the current plugin-owned value immediately and never clears newer clipboard content

## Clipboard safety
- [ ] Copied value absent from Omarchy clipboard history (Super+V or equivalent)
- [ ] After 45 s, clipboard is cleared (paste into a scratch buffer)
- [ ] Copy secret, then immediately copy other text; after 45 s the other text SURVIVES
- [ ] Paste-once setting on: first paste works; note any app breakage; setting off restores normal behavior
- [ ] Clear-seconds 0: no auto-clear, toast omits the countdown

## Failure states
- [ ] Network down (toggle Wi-Fi/ethernet): panel shows unreachable; stale list marked if present; Retry recovers after reconnect
- [ ] Revoke the CLI session from Proton account settings: next refresh shows "Session expired — sign in again"

## Recents, subtitles, and row chrome
- [ ] With an empty query, recently copied items appear in most-recent-first order above All and are capped at eight
- [ ] `~/.local/state/omarchy-protonpass/recents.json` is mode `0600` and every record contains exactly `shareId`, `itemId`, and integer `ts`
- [ ] Recents contains no titles, vault names, usernames, copied field names, or secret values
- [ ] Turn **Show recent items** off: the Recent section disappears and `recents.json` is deleted immediately
- [ ] Turn **Show recent items** on and copy an item: the store and Recent section return
- [ ] A recently copied row shows `used X ago`; an item absent from recents shows a locale-formatted `created <date>` subtitle
- [ ] Row person/key/clock actions have no hover tooltips, shortcut labels, or footer shortcut legend; clicking each still copies the intended field
- [ ] The README chord table is the only visible shortcut reference, and all documented chords still fire

## Logout and accessibility
- [ ] First **Log out** click changes the button to **Confirm log out** without logging out; it disarms after 4 s
- [ ] Arm logout, cause another Service state change, and confirm the action disarms
- [ ] Confirm logout with the second click; the model clears, LOGGED_OUT appears, and sign-in restores READY
- [ ] With Orca running, the row icon buttons announce **Copy username**, **Copy password**, and **Copy TOTP code**
- [ ] Orca announces the search field, lock/create controls, clipboard countdown, creation/copy feedback, and armed logout text meaningfully

## Generated login creation
- [ ] An empty vault with no logins is present and selectable in the create-form vault picker
- [ ] On an account with zero login items, all non-excluded vaults remain selectable creation targets
- [ ] Submit is disabled for an empty title, over-500-character title/identifier, or while copy/create is busy
- [ ] Create a login with a title, username or email, and selected vault; no password field or custom-password flow appears
- [ ] Creation succeeds, the new login appears after refresh, and its vault/title metadata is correct in the official Proton app
- [ ] Choose **Copy password** in the success message; the generated password copies and works for the new login
- [ ] The generated password never appears in the panel, process arguments, logs, notifications, or clipboard history
- [ ] Confirm the README directs custom-password creation to the official Proton Pass apps

## Plugin lifecycle
- [ ] `omarchy plugin update` shows diff flow (no-op update is fine)
- [ ] Disable → icon disappears; re-enable → returns in right section
- [ ] Hot reload: touch an installed QML file; shell reloads plugin without restart
- [ ] `omarchy-restart-shell`: plugin returns, index refetches on first open
- [ ] `omarchy plugin remove josh2c.protonpass` → clean removal; reinstall for release

## Sign-off
- [ ] All boxes checked, divergences: none / listed below
- [ ] Date + pass-cli version recorded
- [ ] `omarchy plugin validate .` and all four test suites pass on the exact release commit
- [ ] GitHub Actions passes on the exact release commit with every test step timeout enforced

## Release — only after every box above is checked
- [ ] Confirm the release commit is on `main` and the worktree is clean
- [ ] Create the signed tag: `git tag -s 1.2.0 -m "omarchy-protonpass 1.2.0"`
- [ ] Verify the signature: `git tag -v 1.2.0`
- [ ] Push the release commit and tag: `git push origin main 1.2.0`

Divergences found:
-
