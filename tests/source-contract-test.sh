#!/usr/bin/env bash
set -euo pipefail

# Behavioral and security contracts for the QML layer, which CI cannot
# instantiate. Presentation, wording, layout, and file-shape details are
# deliberately not pinned here: they are owned by the release walkthrough.
# Secret-hygiene invariants over every runtime source file are owned by
# tests/security-test.sh.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")
PANEL_SOURCE=$(<"$ROOT/Panel.qml")
HELPER_SOURCE=$(<"$ROOT/omarchy-protonpass")

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
assert_panel_contains() {
  [[ $PANEL_SOURCE == *"$1"* ]] || fail "$2"
}

# --- Helper path resolution ---------------------------------------------
assert_contains 'Quickshell.env("OMARCHY_PROTONPASS_HELPER")' \
  "the test helper override is missing"
assert_contains 'Qt.resolvedUrl("omarchy-protonpass").toString().replace(/^file:\/\//, "")' \
  "the installed helper is not resolved relative to Service.qml"

# --- Response trust boundary --------------------------------------------
assert_contains 'schemaVersion !== 1' \
  "schemaVersion 1 is not enforced"
assert_contains 'data.command !== expectedCommand' \
  "helper responses are not bound to their requested command"
assert_contains 'typeof data.message !== "string"' \
  "the common message field is not type checked"
assert_contains 'typeof vault.shareId !== "string"' \
  "index vault share IDs are not validated"
assert_contains 'typeof vault.name !== "string"' \
  "index vault names are not validated"
assert_contains '"clear-now": ["cleared", "not-owner", "error"]' \
  "clear-now response states are not validated"
assert_contains 'waitForEnd: true' \
  "process output collectors are not waiting for complete responses"

# --- Generation fencing over cached metadata ----------------------------
assert_contains 'property int _indexGeneration: 0' \
  "index generations are not tracked"
assert_contains 'if (responseGeneration !== root._indexGeneration)' \
  "stale index responses are not discarded"
assert_contains $'_indexGeneration++;\n            indexProcess.running = false;' \
  "closing the panel does not invalidate before stopping an index request"
[[ $(grep -c '_indexGeneration++' "$ROOT/Service.qml") -ge 2 ]] || \
  fail "panel close and auth transitions must both invalidate in-flight index metadata"
assert_contains $'if (response.state === "logged-out-ok") {\n                root._clearIndex();\n                root.state = "LOGGED_OUT";' \
  "successful logout does not drop the model and enter LOGGED_OUT"

# --- argv-array discipline ----------------------------------------------
assert_contains 'indexProcess.command = [helperPath(), "index", "--exclude-vaults"' \
  "index arguments are not passed as an argv array"
assert_contains 'copyProcess.command = commandLine;' \
  "copy arguments are not passed as an argv array"
assert_contains 'lockProcess.command = [helperPath(), "lock"]' \
  "lock is not passed as an argv array"
assert_contains 'clearClipboardProcess.command = [helperPath(), "clear-now"]' \
  "clear-now is not passed as a fixed argv array"
assert_contains 'logoutProcess.command = [helperPath(), "logout"]' \
  "logout is not passed as a fixed argv array"
assert_contains 'recentsProcess.command = [helperPath(), "recents", operation]' \
  "recents operations are not passed as a fixed argv array"
assert_contains 'createProcess.command = [helperPath(), "create", "--share-id", share]' \
  "create is not passed as a metadata-free fixed argv array"
assert_not_contains 'createProcess.command = [helperPath(), "create", "--share-id", share, title' \
  "create metadata can enter argv"
assert_panel_contains '["omarchy", "launch", "terminal", "pass-cli", "login"]' \
  "login is not launched through a fixed terminal argv array"
assert_panel_contains '["omarchy", "launch", "terminal", "pass-cli", "session", "unlock"]' \
  "unlock is not launched through a fixed terminal argv array"

# --- Create metadata travels over stdin, never argv, and is not retained -
assert_contains 'write(root._createInput);' \
  "create input is not sent over stdin"
assert_contains 'root._createInput = "";' \
  "create input is not cleared after use"
assert_contains 'function validCreateInput(shareId, title, identifierField, identifier)' \
  "QML create validation does not mirror the helper wall"

# --- Copy guards --------------------------------------------------------
assert_contains $'if (copyBusy\n                || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(share)' \
  "copy is not guarded by the panel-wide busy flag and id validation"
assert_not_contains 'copyProcess.running = false' \
  "copy processes can be killed before completion"

# --- Nothing unreviewed reaches the log ---------------------------------
assert_not_contains 'console.warn(String(raw' \
  "a raw helper response can reach logs"
assert_not_contains 'console.log(' \
  "Service.qml writes unreviewed data to logs"

# --- User data is never interpreted as markup ---------------------------
# Row title, vault name and subtitle all render helper-supplied text. The
# subtitle is computed in the delegate rather than carried on the row, so it is
# matched by its binding rather than by a model property.
[[ $(grep -A1 -E 'text: (loginRow\.modelData\.(title|vaultName)|svc\.subtitleFor\(loginRow\.modelData\))' "$ROOT/Panel.qml" \
  | grep -c 'textFormat: Text.PlainText') -eq 3 ]] || \
  fail "every user-data render must use Text.PlainText"
assert_panel_contains $'text: createVaultOption.modelData.name\n                      textFormat: Text.PlainText' \
  "create-form vault names are not forced to plain text"

# --- Destructive actions keep their confirmation seam -------------------
assert_panel_contains 'if (typeof root.requestLogout === "function") root.requestLogout()' \
  "the logout chord bypasses the two-step confirmation seam"
[[ $PANEL_SOURCE != *'case "logout": svc.logout()'* ]] || \
  fail "a keybinding can invoke destructive logout without confirmation"
assert_panel_contains 'if (typeof svc.clearClipboard === "function") svc.clearClipboard()' \
  "the clear-clipboard chord is not routed to the helper-backed service seam"

# --- Remappable keybinds remain configurable ----------------------------
jq -e '
  .barWidget.defaults.keybinds == "" and
  ([.barWidget.schema[] | select(.key == "keybinds" and .type == "string" and .defaultValue == "")] | length) == 1
' "$ROOT/manifest.json" >/dev/null || fail "the keybinds setting schema is missing"

# --- Busy feedback fires before the helper responds ---------------------
# Copies take 1.4-1.8 s of Proton round trip; the panel must state that it
# is working in the same frame as the click, not after the response.
assert_panel_contains $'  function requestCopy(shareId, itemId, field) {\n    if (!svc.copy(shareId, itemId, field)) return false\n    copyPendingKey = String(field) + "@" + String(itemId)\n    showPendingToast("Copying\u2026")' \
  "copy triggers do not show busy feedback before the helper responds"
# The three copy icons render from one Repeater, so the contract is that the
# spec table names both states and the delegate binds the pair -- the same
# guarantee the three unrolled bindings used to give.
assert_panel_contains 'Accessible.name: pending ? modelData.busyName : modelData.name' \
  "the copy icon delegate does not name both its idle and busy state"
for action in "username" "password" "TOTP code"; do
  assert_panel_contains \
    "name: \"Copy $action\", busyName: \"Copying $action…\"" \
    "the Copy $action icon button lacks an accessible name for both states"
done


# --- The logged-out kind survives the envelope --------------------------
# Not a wording test: the helper classifies "expired session" and "never
# signed in" separately, the envelope carries only state + message, and the
# panel re-derives the split from the expired message so a first run is not
# shown in the alarm tone. The two strings are one contract -- reword the
# classifier without the panel and the first-run view silently turns red.
[[ $HELPER_SOURCE == *'CLASSIFIED_KIND=session-expired'* ]] || \
  fail "the helper no longer classifies an expired session separately"
[[ $HELPER_SOURCE == *'CLASSIFIED_MESSAGE="Session expired'* ]] || \
  fail "the expired-session message the panel keys off has been reworded"
assert_panel_contains 'String(svc.message).indexOf("Session expired") === 0' \
  "the panel no longer tells an expired session apart from a first run"

printf 'service and panel source contract tests passed\n'
