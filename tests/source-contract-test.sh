#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")
PANEL_SOURCE=$(<"$ROOT/Panel.qml")

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
assert_contains 'property int _indexGeneration: 0' \
  "index generations are not tracked"
assert_contains 'if (responseGeneration !== root._indexGeneration)' \
  "stale index responses are not discarded"
assert_contains $'if (indexProcess.running) {\n            // Invalidate before SIGTERM so onExited cannot publish stale data.\n            _indexGeneration++;\n            indexProcess.running = false;' \
  "closing the panel does not invalidate and stop an index request"
assert_contains '// Copy and lock processes intentionally continue to completion.' \
  "panel close no longer documents the copy lifecycle boundary"
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
assert_contains 'Component.onCompleted: root.runDoctor(false)' \
  "doctor does not run at widget activation"
assert_contains 'indexProcess.command = [helperPath(), "index", "--exclude-vaults"' \
  "index arguments are not passed as an argv array"
assert_contains 'copyProcess.command = commandLine;' \
  "copy arguments are not passed as an argv array"
assert_contains 'lockProcess.command = [helperPath(), "lock"]' \
  "lock is not passed as an argv array"
assert_contains 'waitForEnd: true' \
  "process output collectors are not waiting for complete responses"
[[ $(grep -c '^    Process {' "$ROOT/Service.qml") -eq 4 ]] || \
  fail "Service.qml no longer has one process per helper command"
[[ $(grep -c 'waitForEnd: true' "$ROOT/Service.qml") -eq 8 ]] || \
  fail "every helper stdout/stderr collector must wait for completion"
[[ $(grep -c 'if (exitCode !== 0 || response === null)' "$ROOT/Service.qml") -eq 4 ]] || \
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
[[ $(grep -A1 -E 'text: loginRow\.modelData\.(title|vaultName)' "$ROOT/Panel.qml" | grep -c 'textFormat: Text.PlainText') -eq 2 ]] || \
  fail "every user-data render must use Text.PlainText"
for state in MISSING_DEPS LOGGED_OUT LOCKED UNREACHABLE ERROR READY LOADING; do
  [[ $PANEL_SOURCE == *"\"$state\""* ]] || fail "Panel.qml is missing the $state view"
done
assert_panel_contains 'text: "No login items found"' \
  "the empty index view is missing"
assert_panel_contains 'text: "No matches"' \
  "the empty search-result view is missing"
assert_panel_contains 'Showing cached list — refresh failed' \
  "the stale-index warning is missing"
assert_panel_contains 'interval: 3000' \
  "copy feedback is not a three-second replacing toast"
assert_panel_contains 'active: root.needsAttention' \
  "the bar icon does not map user-action states to urgent tint"
assert_panel_contains 'stdinEnabled: true' \
  "setup commands are not copied over stdin"
[[ $PANEL_SOURCE != *'--show-secrets'* ]] || fail "Panel.qml enables secret display"
[[ $PANEL_SOURCE != *'property string password'* ]] || fail "Panel.qml can retain a password"

printf 'service and panel source contract tests passed\n'
