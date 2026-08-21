#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")
PANEL_SOURCE=$(<"$ROOT/Panel.qml")
README_SOURCE=$(<"$ROOT/README.md")
ACCEPTANCE_SOURCE=$(<"$ROOT/T12-ACCEPTANCE.md")
CI_SOURCE=$(<"$ROOT/.github/workflows/ci.yml")

command -v node >/dev/null || {
  printf 'FAIL: node is required for keybind parser assertions\n' >&2
  exit 1
}
node "$ROOT/tests/keybinds-test.js" "$ROOT/Keybinds.js"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() {
  [[ $SERVICE_SOURCE == *"$1"* ]] || fail "$2"
}
assert_not_contains() {
  [[ $SERVICE_SOURCE != *"$1"* ]] || fail "$2"
}

assert_contains 'Quickshell.env("OMARCHY_PROTONPASS_HELPER")' \
  "the test helper override is missing"
assert_contains 'Qt.resolvedUrl("omarchy-protonpass").toString().replace(/^file:\/\//, "")' \
  "the installed helper is not resolved relative to Service.qml"
assert_contains 'schemaVersion !== 1' \
  "schemaVersion 1 is not enforced"
assert_contains 'data.command !== expectedCommand' \
  "helper responses are not bound to their requested command"
assert_contains 'typeof data.message !== "string"' \
  "the common message field is not type checked"
assert_contains 'itemId: response.items[i].itemId' \
  "the retained model does not include itemId"
assert_contains 'shareId: response.items[i].shareId' \
  "the retained model does not include shareId"
assert_contains 'vaultName: response.items[i].vaultName' \
  "the retained model does not include vaultName"
assert_contains 'title: response.items[i].title' \
  "the retained model does not include title"
assert_contains 'createTime: response.items[i].createTime' \
  "the retained model does not include createTime"
assert_contains 'property var vaults: []' \
  "the Service does not retain the frozen vault picker model"
assert_contains 'root.vaults = cleanVaults;' \
  "successful indexes do not retain validated vaults"
assert_contains 'typeof vault.shareId !== "string"' \
  "index vault share IDs are not validated"
assert_contains 'typeof vault.name !== "string"' \
  "index vault names are not validated"
assert_contains 'property int _indexGeneration: 0' \
  "index generations are not tracked"
assert_contains 'if (responseGeneration !== root._indexGeneration)' \
  "stale index responses are not discarded"
assert_contains $'if (indexProcess.running) {\n            // Invalidate before SIGTERM so onExited cannot publish stale data.\n            _indexGeneration++;\n            indexProcess.running = false;' \
  "closing the panel does not invalidate and stop an index request"
assert_contains '// Copy, create, clear-now, lock, recents, and logout processes intentionally continue to completion.' \
  "panel close no longer documents the non-cancelled helper lifecycle boundary"
assert_contains $'// An auth transition is authoritative. Invalidate any older index so\n        // it cannot repopulate metadata after logout, lock, or session expiry.\n        _indexGeneration++;' \
  "auth transitions do not invalidate in-flight index metadata"
assert_contains $'if (copyBusy\n                || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(share)' \
  "copy is not guarded by the panel-wide busy flag and id validation"
assert_contains $'if (root.panelOpen)\n                root.toastRequested(root._copyToast(response));' \
  "late copy responses do not suppress their toast"
assert_contains $'if (root._authTransition(response.state, response.message))\n                return;' \
  "late copy responses do not preserve auth-state transitions"
assert_contains $'root.message = response.message;\n            } else if (root._authTransition(response.state, response.message)) {\n            } else if (response.state === "cli-missing") {' \
  "lock responses do not clear cached metadata on logout"
assert_contains 'root.items = cleanItems;' \
  "successful index refreshes do not atomically swap the model"
assert_contains 'root.staleWarning = true;' \
  "failed background refreshes do not mark the cached model stale"
assert_contains 'root.runDoctor(false);' \
  "doctor does not run at widget activation"
assert_contains 'indexProcess.command = [helperPath(), "index", "--exclude-vaults"' \
  "index arguments are not passed as an argv array"
assert_contains 'copyProcess.command = commandLine;' \
  "copy arguments are not passed as an argv array"
assert_contains 'lockProcess.command = [helperPath(), "lock"]' \
  "lock is not passed as an argv array"
assert_contains 'clearClipboardProcess.command = [helperPath(), "clear-now"]' \
  "clear-now is not passed as a fixed argv array"
assert_contains '"clear-now": ["cleared", "not-owner", "error"]' \
  "clear-now response states are not validated"
assert_contains 'root._startClipboardCountdown(response.clearSeconds);' \
  "successful copy responses do not start the client-side countdown"
assert_contains 'root._hideClipboardCountdown();' \
  "clear-now responses do not hide the countdown"
assert_contains 'root.lastSuccessfulIndexAt = Date.now();' \
  "the last successful index time is not recorded client-side"
assert_contains 'logoutProcess.command = [helperPath(), "logout"]' \
  "logout is not passed as a fixed argv array"
assert_contains 'createProcess.command = [helperPath(), "create", "--share-id", share]' \
  "create is not passed as a metadata-free fixed argv array"
assert_contains 'body[identifierField] = identifier;' \
  "create does not build its non-secret stdin template"
assert_contains 'write(root._createInput);' \
  "create input is not sent over stdin"
assert_contains 'root._createInput = "";' \
  "create input is not cleared after use"
assert_contains 'function validCreateInput(shareId, title, identifierField, identifier)' \
  "QML create validation does not mirror the helper wall"
assert_not_contains 'createProcess.command = [helperPath(), "create", "--share-id", share, title' \
  "create metadata can enter argv"
assert_contains 'waitForEnd: true' \
  "process output collectors are not waiting for complete responses"
[[ $(grep -c '^    Process {' "$ROOT/Service.qml") -eq 8 ]] || \
  fail "Service.qml no longer has one process per helper command"
[[ $(grep -c 'waitForEnd: true' "$ROOT/Service.qml") -eq 16 ]] || \
  fail "every helper stdout/stderr collector must wait for completion"
[[ $(grep -c 'if (exitCode !== 0 || response === null)' "$ROOT/Service.qml") -eq 7 ]] || \
  fail "exit-code discipline is not enforced for every helper command"
assert_not_contains 'copyProcess.running = false' \
  "copy processes can be killed before completion"
assert_contains 'No session lock configured — run pass-cli session create-lock' \
  "the no-lock recovery toast is missing"
[[ $SERVICE_SOURCE != *$'\x60'* ]] || \
  fail "Service.qml contains a backtick banned by the security suite"
assert_not_contains 'console.warn(String(raw' \
  "a raw helper response can reach logs"
assert_not_contains 'console.log(' \
  "Service.qml writes unreviewed data to logs"

assert_panel_contains() {
  [[ $PANEL_SOURCE == *"$1"* ]] || fail "$2"
}
assert_panel_not_contains() {
  [[ $PANEL_SOURCE != *"$1"* ]] || fail "$2"
}

assert_panel_contains 'focusTarget: search' \
  "the panel does not open into search focus"
assert_panel_contains 'blocked: search.activeFocus' \
  "PanelKeyCatcher is not suspended while search owns text input"
assert_panel_contains 'if (event.key === Qt.Key_Down)' \
  "search does not intercept Down for list handoff"
assert_panel_contains 'keyCatcher.forceActiveFocus()' \
  "search cannot hand keyboard focus to list mode"
assert_panel_contains 'root.copySelected("password")' \
  "Enter does not copy the selected password"
assert_panel_contains 'root.refocusSearch(event.text)' \
  "printable list keys do not refocus search"
assert_panel_contains 'root.refocusSearch("")' \
  "slash does not refocus search without insertion"
assert_panel_contains 'readonly property var effectiveKeybinds: keybindConfiguration.bindings' \
  "the effective keybind table is not exposed to the panel"
assert_panel_contains 'if (root.handleChord(event)) return' \
  "modifier chords are not intercepted before normal key handling"
[[ $(grep -c 'if (root.handleChord(event)) return' "$ROOT/Panel.qml") -eq 2 ]] || \
  fail "both search and list focus must handle effective chords"
assert_panel_contains 'if (typeof root.requestLogout === "function") root.requestLogout()' \
  "the logout chord bypasses the two-step confirmation seam"
assert_panel_contains 'if (typeof svc.clearClipboard === "function") svc.clearClipboard()' \
  "the clear-clipboard chord is not routed to the helper-backed service seam"
[[ $PANEL_SOURCE != *'case "logout": svc.logout()'* ]] || \
  fail "a keybinding can invoke destructive logout without confirmation"
assert_panel_contains 'if (search.text !== "")' \
  "Escape does not clear search before closing"
assert_panel_contains '["omarchy", "launch", "terminal", "pass-cli", "login"]' \
  "login is not launched through a fixed terminal argv array"
assert_panel_contains '["omarchy", "launch", "terminal", "pass-cli", "session", "unlock"]' \
  "unlock is not launched through a fixed terminal argv array"
assert_panel_contains 'text: loginRow.modelData.title' \
  "login titles are not rendered"
assert_panel_contains 'text: loginRow.modelData.vaultName' \
  "vault names are not rendered"
[[ $(grep -A1 -E 'text: loginRow\.modelData\.(title|vaultName|subtitle)' "$ROOT/Panel.qml" | grep -c 'textFormat: Text.PlainText') -eq 3 ]] || \
  fail "every user-data render must use Text.PlainText"
assert_contains 'recentTs: recent.ts' \
  "recent timestamps are not joined to index metadata in memory"
assert_contains 'qsTr("used %L1 minutes ago").arg(amount)' \
  "relative used times are not translatable with locale-formatted numbers"
assert_contains 'created.toLocaleDateString(Qt.locale(), Locale.ShortFormat)' \
  "created dates are not formatted with the active locale"
assert_contains 'onItemsChanged: refreshSubtitleNow()' \
  "subtitle time is not refreshed when the index model changes"
assert_contains 'onRecentsChanged: refreshSubtitleNow()' \
  "subtitle time is not refreshed when recents change"
assert_contains $'panelOpen = true;\n        refreshSubtitleNow();' \
  "subtitle time is not refreshed when the panel opens"
[[ $(grep -c 'interval: 1000' "$ROOT/Service.qml") -eq 1 ]] || \
  fail "subtitle support added a per-second timer"
assert_panel_contains 'text: loginRow.modelData.subtitle' \
  "row subtitles are not rendered"
for state in MISSING_DEPS LOGGED_OUT LOCKED UNREACHABLE ERROR READY LOADING; do
  [[ $PANEL_SOURCE == *"\"$state\""* ]] || fail "Panel.qml is missing the $state view"
done
assert_panel_contains 'text: "No login items found"' \
  "the empty index view is missing"
assert_panel_contains 'text: "No matches"' \
  "the empty search-result view is missing"
assert_panel_contains 'cached — refresh failed' \
  "the stale-index warning is missing"
assert_panel_contains '" · " + syncedAgeText()' \
  "the header does not show the client-side sync age"
assert_panel_contains 'svc.filteredItems.length + (svc.filteredItems.length === 1 ? " match" : " matches")' \
  "filtering does not show a match-count badge"
assert_panel_contains 'text: "Clears in " + svc.clipboardSecondsRemaining + "s · click to clear now"' \
  "the text-first clipboard countdown is missing"
assert_panel_contains 'onClicked: svc.clearClipboard()' \
  "the countdown cannot clear the clipboard immediately"
for action in username password 'TOTP code'; do
  assert_panel_contains "Accessible.name: \"Copy $action\"" \
    "the Copy $action icon button lacks an accessible name"
done
assert_panel_not_contains 'function shortcutLabel(' \
  "the removed shortcut-label UI helper is still present"
assert_panel_not_contains 'tooltipText: "Copy username' \
  "the username action still exposes shortcut hover chrome"
assert_panel_not_contains 'tooltipText: "Copy password' \
  "the password action still exposes shortcut hover chrome"
assert_panel_not_contains 'tooltipText: "Copy TOTP code' \
  "the TOTP action still exposes shortcut hover chrome"
assert_panel_not_contains 'u/p/t in list' \
  "the footer key legend is still present"
assert_panel_contains 'iconText: ""' \
  "the username action does not use the Nerd Font person icon"
assert_panel_contains 'iconText: ""' \
  "the password action does not use the Nerd Font key icon"
assert_panel_contains 'iconText: ""' \
  "the TOTP action does not use the Nerd Font clock icon"
[[ $PANEL_SOURCE != *'iconText: "u"'* && $PANEL_SOURCE != *'iconText: "p"'* && $PANEL_SOURCE != *'iconText: "t"'* ]] || \
  fail "a row action still renders as a letter button"
assert_panel_contains 'interval: 3000' \
  "copy feedback is not a three-second replacing toast"
assert_panel_contains 'active: root.needsAttention' \
  "the bar icon does not map user-action states to urgent tint"
assert_panel_contains 'stdinEnabled: true' \
  "setup commands are not copied over stdin"
assert_panel_contains 'model: svc.vaults' \
  "the create form picker is not built from the validated vault model"
assert_panel_contains 'text: createVaultOption.modelData.name' \
  "the create form does not render vault names"
assert_panel_contains $'text: createVaultOption.modelData.name\n                      textFormat: Text.PlainText' \
  "create-form vault names are not forced to plain text"
assert_panel_contains 'activeFocusOnTab: true' \
  "vault choices are not keyboard focusable"
assert_panel_contains 'current: root.createVaultShareId === modelData.shareId' \
  "the selected creation vault is not visibly identified"
assert_panel_contains 'Keys.onReturnPressed: if (root.createControlsEnabled)' \
  "vault choices cannot be selected from the keyboard"
assert_panel_contains 'svc.validCreateInput(' \
  "the create form does not share the Service validation wall"
assert_panel_contains 'svc.create(createVaultShareId, createTitle.text, createIdentifierField, createIdentifier.text)' \
  "the create form does not submit only its non-secret fields"
assert_panel_contains 'enabled: root.createControlsEnabled && root.createFormValid' \
  "invalid or busy create forms are not disabled"
assert_panel_contains 'visible: root.createdShareId !== "" && root.createdItemId !== ""' \
  "successful creation does not expose a copy-password affordance"
assert_panel_contains 'svc.copy(root.createdShareId, root.createdItemId, "password")' \
  "the created-login affordance does not use the opaque copy seam"
assert_panel_not_contains 'Use my own password' \
  "the removed custom-password flow is exposed in the panel"
assert_panel_not_contains 'custom password' \
  "the removed custom-password flow is exposed in the panel"
jq -e '
  .barWidget.defaults.keybinds == "" and
  ([.barWidget.schema[] | select(.key == "keybinds" and .type == "string" and .defaultValue == "")] | length) == 1
' "$ROOT/manifest.json" >/dev/null || fail "the keybinds setting schema is missing"
assert_contains 'recentsProcess.command = [helperPath(), "recents", operation]' \
  "recents operations are not passed as a fixed argv array"
assert_contains 'readonly property bool showRecents: boolSetting("showRecents", true)' \
  "showRecents does not default to true"
assert_contains 'for (var i = 0; i < recentMetadata.length && joined.length < 8; i++)' \
  "recent items are not capped at eight"
assert_contains 'source[j].shareId === recent.shareId && source[j].itemId === recent.itemId' \
  "recent ids are not joined against the in-memory index"
assert_contains 'runRecents("clear")' \
  "disabling recents does not request helper-owned store deletion"
assert_panel_contains 'text: "Recent"' \
  "the Recent section is missing"
assert_panel_contains 'text: "All"' \
  "the empty-query All section is missing"
assert_panel_contains 'model: svc.recentRows' \
  "the Recent section is not rendered from joined index rows"
assert_panel_contains 'model: svc.allRows' \
  "the All section is missing its index rows"
assert_panel_contains $'function requestLogout() {\n    if (svc.logoutBusy) return\n    if (!logoutArmed)' \
  "logout does not require an idle first click to arm"
assert_panel_contains $'disarmLogout()\n    svc.logout()' \
  "logout confirmation does not disarm before invoking the helper"
assert_panel_contains $'id: logoutArmTimer\n    interval: 4000\n    repeat: false' \
  "logout confirmation does not disarm after exactly four seconds"
assert_panel_contains $'function onStateChanged() {\n      root.disarmLogout()' \
  "logout confirmation is not disarmed on every service state change"
assert_panel_contains 'root.logoutArmed ? "Confirm log out" : "Log out"' \
  "logout confirmation is not exposed as text"
assert_contains $'if (response.state === "logged-out-ok") {\n                root._clearIndex();\n                root.state = "LOGGED_OUT";' \
  "successful logout does not drop the model and enter LOGGED_OUT"
[[ $(grep -c 'Accessible.role: Accessible.Button' "$ROOT/Panel.qml") -ge 7 ]] || \
  fail "icon-only actions do not expose button roles"
assert_panel_contains 'Accessible.name: "Search Proton Pass logins"' \
  "the search field has no stable accessible name"
assert_panel_contains 'Accessible.name: "Lock Proton Pass"' \
  "the lock icon has no accessible name"
assert_panel_contains 'Accessible.role: Accessible.AlertMessage' \
  "copy feedback is not exposed as an accessible alert"
assert_panel_contains 'Accessible.name: text' \
  "the logout action does not announce its armed label"
assert_panel_contains 'svc.staleWarning ? " · cached — refresh failed" : (svc.refreshing ? " · refreshing" : "")' \
  "refresh activity is not conveyed in the header status text"
assert_panel_contains 'trailingControl: Component {' \
  "session actions are not attached to the fixed header"
assert_panel_contains 'id: headerActions' \
  "the header action row is missing"
assert_panel_contains $'anchors.top: panelHeader.bottom\n        anchors.topMargin: Style.space(12)' \
  "the scrolling body is not anchored below the fixed header"
assert_panel_contains 'id: itemListFlick' \
  "the login list has no independent scroll viewport"
assert_panel_contains 'implicitHeight: Math.min(itemListContent.implicitHeight, Style.space(300))' \
  "the login list height is not capped"
assert_panel_contains 'contentHeight: itemListContent.implicitHeight' \
  "the capped login list cannot scroll its full content"
assert_panel_contains 'var maxY = Math.max(0, itemListFlick.contentHeight - itemListFlick.height)' \
  "keyboard selection does not scroll the internal login viewport"
assert_panel_not_contains 'id: footerActions' \
  "session controls remain in the footer"
header_actions_match=$(grep -n 'id: headerActions' "$ROOT/Panel.qml")
item_list_match=$(grep -n 'id: itemListFlick' "$ROOT/Panel.qml")
toast_match=$(grep -n 'id: toastContent' "$ROOT/Panel.qml")
countdown_match=$(grep -n 'id: countdownText' "$ROOT/Panel.qml")
header_actions_line=${header_actions_match%%:*}
item_list_line=${item_list_match%%:*}
toast_line=${toast_match%%:*}
countdown_line=${countdown_match%%:*}
[[ $header_actions_line -lt $item_list_line
    && $item_list_line -lt $toast_line
    && $toast_line -lt $countdown_line ]] || \
  fail "header controls and footer feedback are not in their fixed regions"
[[ $PANEL_SOURCE != *'--show-secrets'* ]] || fail "Panel.qml enables secret display"
[[ $PANEL_SOURCE != *'property string password'* ]] || fail "Panel.qml can retain a password"

for required_readme_text in \
  '## Create a login' \
  'long login lists scroll independently' \
  'use an official Proton Pass app' \
  'sole shortcut reference' \
  '`Ctrl+U`' \
  '`Ctrl+P`' \
  '`Ctrl+T`' \
  '`Ctrl+R`' \
  '`Ctrl+L`' \
  '`Ctrl+Shift+X`' \
  'ctrl+shift+c:copy-password,ctrl+o:logout' \
  'contains opaque item/share IDs and timestamps only' \
  'turning it off deletes the local recents store immediately'; do
  [[ $README_SOURCE == *"$required_readme_text"* ]] || \
    fail "README is missing required release documentation: $required_readme_text"
done
[[ $README_SOURCE == *'[combined 1.2.0 acceptance checklist](T12-ACCEPTANCE.md)'* ]] || \
  fail "README does not link the combined release gate"

for required_acceptance_text in \
  'single combined v1.0 + v1.1 + v1.2 release gate' \
  'With search focused and text already entered' \
  'at least 3× one viewport of login rows' \
  'recents.json` is deleted immediately' \
  'used X ago' \
  'no hover tooltips, shortcut labels, or footer shortcut legend' \
  'With Orca running' \
  'empty vault with no logins' \
  'Choose **Copy password** in the success message' \
  'git tag -s 1.2.0'; do
  [[ $ACCEPTANCE_SOURCE == *"$required_acceptance_text"* ]] || \
    fail "combined acceptance checklist is missing: $required_acceptance_text"
done

ci_step_count=$(grep -c '^      - name:' "$ROOT/.github/workflows/ci.yml")
ci_step_timeout_count=$(grep -c '^        timeout-minutes: 2$' "$ROOT/.github/workflows/ci.yml")
[[ $ci_step_count -eq 10 && $ci_step_timeout_count -eq $ci_step_count ]] || \
  fail "every CI step must have the two-minute timeout"
[[ $CI_SOURCE == *'timeout-minutes: 10'* ]] || fail "the CI job timeout is missing"

printf 'service and panel source contract tests passed\n'
