import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Keybinds.js" as Keybinds

Panel {
  id: root
  moduleName: "josh2c.protonpass"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // Fine print sits a step below dim: present for the user who goes looking,
  // never competing with the sentence that tells them what to do.
  readonly property color muted: Qt.darker(foreground, 1.9)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool cursorActive: false
  property int cursorIndex: 0
  // The whole toast lifecycle in one object, reset only through clearToast():
  // text is the message, pending marks a "Copying…"/"Creating…" message the
  // result is expected to replace, and the created* pair names the login a
  // "Login created" toast offers a password copy for.
  property var toast: root.emptyToast()
  // Key of the control whose copy is in flight ("<field>@<itemId>"), so the
  // clicked icon can show its own busy state while copyBusy stays global. Kept
  // out of the toast object: it is busy state, cleared on its own when a copy
  // ends without a result toast.
  property string copyPendingKey: ""
  property string setupClipboardText: ""
  property bool logoutArmed: false
  property bool createFormOpen: false
  property string createVaultShareId: ""
  property string createIdentifierField: "username"
  readonly property bool createControlsEnabled: !svc.copyBusy && !svc.createBusy
  readonly property bool createFormValid: svc.validCreateInput(
    createVaultShareId, createTitle.text, createIdentifierField, createIdentifier.text)

  readonly property var keybindConfiguration: Keybinds.parse(
    String(svc.setting("keybinds", "")),
    function(entry) { console.warn("omarchy-protonpass: invalid keybind entry: " + entry) })
  readonly property var effectiveKeybinds: keybindConfiguration.bindings

  // Row-level copy actions. Both accessible names are part of the busy-feedback
  // contract: every icon names its idle state and its in-flight state.
  readonly property var copyActionSpecs: [
    {icon: "", field: "username", name: "Copy username", busyName: "Copying username…"},
    {icon: "", field: "password", name: "Copy password", busyName: "Copying password…"},
    {icon: "", field: "totp", name: "Copy TOTP code", busyName: "Copying TOTP code…"}
  ]

  // Header actions. Labels and enablement are resolved per frame by the
  // functions below rather than stored here, so the model stays constant and
  // the buttons are never rebuilt mid-interaction.
  // One icon family at one weight: all four header actions are Material Design
  // strokes now. fa-plus sat a family apart from its neighbours, and the solid
  // md-lock carried more filled area than anything beside it, so both read as
  // louder than the row they belong to.
  readonly property var headerActionSpecs: [
    {icon: "󰑐", action: "refresh", tooltip: "Refresh", name: "Refresh Proton Pass"},
    {icon: "󰐕", action: "create", focusable: true},
    {icon: "󰍁", action: "lock", tooltip: "Lock Proton Pass", name: "Lock Proton Pass"}
  ]

  function headerActionLabel(spec) {
    if (spec.action === "create")
      return createFormOpen ? "Close create form" : "Create login"
    return spec.name
  }

  function headerActionEnabled(spec) {
    if (spec.action === "refresh") return !svc.refreshing
    if (spec.action === "create") return createControlsEnabled && svc.vaults.length > 0
    return true
  }

  function runHeaderAction(spec) {
    if (spec.action === "refresh") { svc.refresh(); return }
    if (spec.action === "lock") { svc.lock(); return }
    if (createFormOpen) {
      closeCreateForm()
      search.forceActiveFocus()
    } else {
      openCreateForm()
    }
  }

  // The helper classifies a logged-out session two ways -- an expired or
  // revoked session, and a plain "never signed in" -- but the response
  // envelope carries only state + message (contracts frozen, PLAN 2.5), so the
  // only place that distinction survives is the message the expired branch
  // emits. tests/source-contract-test.sh pins the two strings together so a
  // reworded classifier cannot silently re-tone the first-run view.
  readonly property bool sessionExpired: svc.state === "LOGGED_OUT"
    && String(svc.message).indexOf("Session expired") === 0

  // Every non-READY panel state as data. Blocks render in order through the one
  // Column below: a line of text in one of two tones, a copyable install
  // command, or a row of buttons. A new state is a row here, not a new Column.
  //
  // The tone field is a property of the row, not of a block: "setup" is the
  // expected shape of a plugin nobody has finished setting up -- nothing is
  // wrong, so nothing is red -- and "fault" is something that broke and keeps
  // the alarm colour. A block's lead line takes the row's tone; a dim line is
  // always the quieter explanatory voice. A row may carry a when predicate,
  // letting two rows offer different views of one state; first match wins, so
  // the narrower row is listed first.
  readonly property var stateViews: [
    {states: ["INIT", "LOADING"], tone: "setup", spacing: Style.space(8), blocks: [
      {dim: svc.state === "LOADING" ? "Loading Proton Pass logins…" : "Checking Proton Pass CLI…",
       size: Style.font.body, wrap: Text.NoWrap,
       topPad: Style.space(32), bottomPad: Style.space(32)}
    ]},
    // The install commands keep the panel open, so Check again is reachable
    // here in a way it is not on the sign-in card.
    {states: ["MISSING_DEPS"], tone: "setup", setup: true, spacing: Style.space(8), blocks: [
      {lead: "Set up Proton Pass", bold: true},
      {dim: svc.message},
      {fine: "Requires Pass Plus or Pass Professional."},
      {command: "yay -S proton-pass-cli-bin", name: "Copy Arch AUR command"},
      {dim: "Arch note: the AUR package named pass-cli is unrelated. Use proton-pass-cli-bin.",
       size: Style.font.caption, align: Text.AlignLeft},
      {dim: "Other distributions: see protonpass.github.io/pass-cli for official packages.",
       size: Style.font.caption, align: Text.AlignLeft},
      {command: "sudo pacman -S wl-clipboard", name: "Copy wl-clipboard install command"},
      {buttons: [{text: "Check again", action: "recheck"}]}
    ], footer: [
      {dim: "Secrets are only ever copied to the clipboard, never shown or stored.",
       size: Style.font.caption}
    ]},
    // One action, not two: launchTerminal() closes the panel on click, and
    // reopening re-checks through Service.onPanelOpened(), so a Check again
    // control on this card could never be reached after a sign-in.
    {states: ["LOGGED_OUT"], when: function() { return !root.sessionExpired },
     tone: "setup", setup: true, spacing: Style.space(8), blocks: [
      {lead: "Ready to connect", bold: true},
      {dim: "Sign in opens Proton's own CLI in a terminal. Your password and 2FA go straight to Proton, never to this plugin."},
      {fine: "Requires Pass Plus or Pass Professional."},
      {buttons: [
        {text: "Sign in", icon: "󰍂",
         argv: ["omarchy", "launch", "terminal", "pass-cli", "login"]}
      ]}
    ]},
    {states: ["LOGGED_OUT"], tone: "fault", spacing: Style.space(10), blocks: [
      {lead: svc.message},
      {dim: "Sign-in requires a plan with CLI access (Pass Plus or Pass Professional) — an eligibility error appears in the sign-in terminal otherwise."},
      {buttons: [
        {text: "Sign in", argv: ["omarchy", "launch", "terminal", "pass-cli", "login"]},
        {text: "Retry", action: "retry"}
      ]}
    ]},
    {states: ["LOCKED"], tone: "fault", spacing: Style.space(10), blocks: [
      {lead: svc.message, wrap: Text.NoWrap},
      {buttons: [
        {text: "Unlock", argv: ["omarchy", "launch", "terminal", "pass-cli", "session", "unlock"]},
        {text: "Retry", action: "retry"}
      ]}
    ]},
    {states: ["UNREACHABLE", "ERROR"], tone: "fault", spacing: Style.space(10), blocks: [
      {lead: svc.message},
      {buttons: [{text: "Retry", action: "retry"}]}
    ]}
  ]

  readonly property var activeStateView: {
    for (var i = 0; i < stateViews.length; i++) {
      var view = stateViews[i]
      if (view.states.indexOf(svc.state) === -1) continue
      if (view.when !== undefined && !view.when()) continue
      return view
    }
    return null
  }

  function runStateAction(button) {
    if (button.argv !== undefined) { launchTerminal(button.argv); return }
    if (button.action === "recheck") { svc.recheck(); return }
    svc.retry()
  }

  readonly property var selectedItem: {
    var rows = svc.displayItems
    if (!rows || rows.length === 0) return null
    return rows[Math.max(0, Math.min(cursorIndex, rows.length - 1))]
  }
  readonly property bool needsAttention: ["MISSING_DEPS", "LOGGED_OUT", "LOCKED"].indexOf(svc.state) !== -1

  function ensureCursor() {
    var count = svc.displayItems.length
    if (count === 0) {
      cursorActive = false
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(cursorIndex, count - 1))
  }

  function moveCursor(delta) {
    var count = svc.displayItems.length
    if (count === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = delta < 0 ? count - 1 : 0
    } else {
      cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + delta))
    }
    scrollCursorIntoView()
  }

  function scrollCursorIntoView() {
    Qt.callLater(function() {
      var recentCount = svc.recentRows.length
      var row = root.cursorIndex < recentCount
        ? recentRepeater.itemAt(root.cursorIndex)
        : itemRepeater.itemAt(root.cursorIndex - recentCount)
      if (!row || !itemListFlick) return
      var point = row.mapToItem(itemListFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      var top = point.y
      var bottom = top + row.height
      var maxY = Math.max(0, itemListFlick.contentHeight - itemListFlick.height)
      if (top < itemListFlick.contentY + margin)
        itemListFlick.contentY = Math.max(0, top - margin)
      else if (bottom > itemListFlick.contentY + itemListFlick.height - margin)
        itemListFlick.contentY = Math.min(maxY, bottom + margin - itemListFlick.height)
    })
  }

  function copySelected(field) {
    if (!selectedItem || svc.copyBusy) return
    requestCopy(selectedItem.shareId, selectedItem.itemId, field)
  }

  // Single entry point for every copy trigger (row icon, keyboard action and
  // the created-login toast button) so no site can forget the feedback.
  function requestCopy(shareId, itemId, field) {
    if (!svc.copy(shareId, itemId, field)) return false
    copyPendingKey = String(field) + "@" + String(itemId)
    showPendingToast("Copying…")
    return true
  }

  function copyPendingFor(itemId, field) {
    return copyPendingKey === String(field) + "@" + String(itemId)
  }

  function chordForEvent(event) {
    var allowedModifiers = Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier
    if ((event.modifiers & ~allowedModifiers) !== 0)
      return ""

    var keyName = ""
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      keyName = "enter"
    else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F9)
      keyName = "f" + String(event.key - Qt.Key_F1 + 1)
    else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
      keyName = String.fromCharCode("a".charCodeAt(0) + event.key - Qt.Key_A)
    if (keyName === "")
      return ""

    var parts = []
    if (event.modifiers & Qt.ControlModifier) parts.push("ctrl")
    if (event.modifiers & Qt.ShiftModifier) parts.push("shift")
    if (event.modifiers & Qt.AltModifier) parts.push("alt")
    parts.push(keyName)
    return parts.join("+")
  }

  function triggerAction(action) {
    switch (action) {
    case "copy-username": root.copySelected("username"); break
    case "copy-password": root.copySelected("password"); break
    case "copy-totp": root.copySelected("totp"); break
    case "cursor-down": root.moveCursor(1); break
    case "cursor-up": root.moveCursor(-1); break
    case "refresh": svc.refresh(); break
    case "lock": svc.lock(); break
    case "clear-clipboard":
      if (typeof svc.clearClipboard === "function") svc.clearClipboard()
      break
    case "logout":
      if (typeof root.requestLogout === "function") root.requestLogout()
      break
    }
  }

  // A chord that still produces a printable character -- a letter with at most
  // Shift -- must not fire an action while the search field has focus, or it
  // would swallow the keystroke instead of typing it.
  function isTypingChord(chord) {
    return /^(shift\+)?[a-z]$/.test(chord)
  }

  // The panel's only key handler. fromSearch is the sole difference between
  // the two focus contexts: it gates the printable chords and the fall-through
  // that sends an unclaimed character to the search field, and it decides which
  // way Tab and the down arrow hand focus over.
  function handleKey(event, fromSearch) {
    var chord = chordForEvent(event)
    var action = effectiveKeybinds[chord]
    if (action !== undefined && !(fromSearch && isTypingChord(chord))) {
      triggerAction(action)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      layeredEscape()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      if (fromSearch) {
        if (!cursorActive) moveCursor(1)
        keyCatcher.forceActiveFocus()
      } else {
        search.forceActiveFocus()
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down) {
      moveCursor(1)
      // Arrowing down out of the search field hands the list the keyboard;
      // arrowing up deliberately does not.
      if (fromSearch) keyCatcher.forceActiveFocus()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) {
      moveCursor(-1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      copySelected("password")
      event.accepted = true
      return
    }

    // Anything left over belongs to the search field. When it already has
    // focus, leave it alone and let it type.
    if (fromSearch)
      return
    if (event.text === "/") {
      refocusSearch("")
      event.accepted = true
      return
    }
    if (event.text && event.text.length === 1) {
      refocusSearch(event.text)
      event.accepted = true
    }
  }

  function syncedAgeText() {
    if (svc.lastSuccessfulIndexAt <= 0) return "syncing"
    var minutes = Math.max(0, Math.floor((svc.subtitleNow - svc.lastSuccessfulIndexAt) / 60000))
    return "synced " + minutes + "m ago"
  }

  function headerStatusText() {
    var count = svc.items.length
    return count + (count === 1 ? " login" : " logins") + " · " + syncedAgeText()
  }

  function refocusSearch(text) {
    search.forceActiveFocus()
    if (text !== "") search.insert(search.cursorPosition, text)
  }

  function layeredEscape() {
    if (createFormOpen) {
      closeCreateForm()
      search.forceActiveFocus()
    } else
    if (search.text !== "") {
      search.clear()
      search.forceActiveFocus()
    } else {
      close()
    }
  }

  function launchTerminal(args) {
    Quickshell.execDetached(args)
    close()
  }

  function emptyToast() {
    return {text: "", pending: false, createdShareId: "", createdItemId: ""}
  }

  function clearToast() {
    toastTimer.stop()
    toast = emptyToast()
  }

  function showToast(message) {
    clearToast()
    copyPendingKey = ""
    toast = {text: String(message || ""), pending: false, createdShareId: "", createdItemId: ""}
    if (toast.text !== "") toastTimer.restart()
  }

  // Shown in the same frame as the click. Deliberately not auto-dismissed here:
  // the result toast replaces it, and the busy-cleared handler arms the timer
  // for the paths that change state instead of emitting a result toast.
  function showPendingToast(message) {
    toastTimer.stop()
    // The created-login pair survives: copying the new password from the
    // "Login created" toast swaps its text without dismissing the button.
    toast = {text: String(message || ""), pending: true,
             createdShareId: toast.createdShareId, createdItemId: toast.createdItemId}
  }

  function showCreatedToast(shareId, itemId) {
    copyPendingKey = ""
    toast = {text: "Login created", pending: false,
             createdShareId: String(shareId || ""), createdItemId: String(itemId || "")}
    toastTimer.restart()
  }

  function openCreateForm() {
    if (svc.vaults.length === 0 || !createControlsEnabled) return
    createVaultShareId = svc.vaults[0].shareId
    createIdentifierField = "username"
    createTitle.clear()
    createIdentifier.clear()
    createFormOpen = true
    Qt.callLater(function() { createTitle.forceActiveFocus() })
  }

  function closeCreateForm() {
    createFormOpen = false
    createTitle.clear()
    createIdentifier.clear()
    createVaultShareId = ""
  }

  function submitCreate() {
    if (!createFormValid || !createControlsEnabled) return
    if (svc.create(createVaultShareId, createTitle.text, createIdentifierField, createIdentifier.text))
      showPendingToast("Creating…")
  }

  function copySetupCommand(commandText) {
    if (setupCopyProcess.running) return
    setupClipboardText = commandText
    setupCopyProcess.command = ["wl-copy"]
    setupCopyProcess.running = true
  }

  function disarmLogout() {
    logoutArmed = false
    logoutArmTimer.stop()
  }

  function requestLogout() {
    if (svc.logoutBusy) return
    if (!logoutArmed) {
      logoutArmed = true
      logoutArmTimer.restart()
      return
    }
    disarmLogout()
    svc.logout()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      search.clear()
      panelFlick.contentY = 0
      itemListFlick.contentY = 0
      svc.onPanelOpened()
      Qt.callLater(function() { search.forceActiveFocus() })
    } else {
      disarmLogout()
      closeCreateForm()
      clearToast()
      copyPendingKey = ""
      svc.onPanelClosed()
    }
  }

  onCursorIndexChanged: scrollCursorIntoView()

  Service {
    id: svc
    settings: root.settings
  }

  Connections {
    target: svc
    function onToastRequested(message) { root.showToast(message) }
    function onLoginCreated(shareId, itemId) {
      root.closeCreateForm()
      root.showCreatedToast(shareId, itemId)
      Qt.callLater(function() { search.forceActiveFocus() })
    }
    function onCopyBusyChanged() {
      if (svc.copyBusy) return
      root.copyPendingKey = ""
      // Auth transitions and cli-missing end a copy without a result toast;
      // give the pending text a normal dismissal rather than leaving it up.
      if (root.toast.pending) toastTimer.restart()
    }
    function onCreateBusyChanged() {
      if (!svc.createBusy && root.toast.pending) toastTimer.restart()
    }
    function onFilteredItemsChanged() { root.ensureCursor() }
    function onDisplayItemsChanged() { root.ensureCursor() }
    function onStateChanged() {
      root.disarmLogout()
      if (root.opened && svc.state === "READY")
        Qt.callLater(function() { search.forceActiveFocus() })
    }
  }

  Timer {
    id: toastTimer
    interval: 3000
    repeat: false
    onTriggered: root.clearToast()
  }

  Timer {
    id: logoutArmTimer
    interval: 4000
    repeat: false
    onTriggered: root.logoutArmed = false
  }

  Process {
    id: setupCopyProcess
    stdinEnabled: true
    onStarted: {
      write(root.setupClipboardText)
      root.setupClipboardText = ""
    }
    onExited: function(exitCode) {
      root.showToast(exitCode === 0 ? "Install command copied" : "Could not copy install command")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    active: root.needsAttention
    tooltipText: "Proton Pass"
    Accessible.role: Accessible.Button
    Accessible.name: "Proton Pass"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: search
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(
      panelHeader.implicitHeight + Style.space(12) + content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus || createTitle.activeFocus || createIdentifier.activeFocus

      // The stock catcher also reserves h/l/x/space. The v1 contract does
      // not: in list mode every printable key except the explicit actions
      // must refocus search and insert that character.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (keyCatcher.blocked) return
        root.handleKey(event, false)
      }

      PanelHero {
        id: panelHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "Proton Pass"
        meta: svc.state === "READY"
          ? root.headerStatusText()
            + (svc.staleWarning ? " · cached — refresh failed" : (svc.refreshing ? " · refreshing" : ""))
          : (svc.message !== "" ? svc.message : "Checking pass-cli…")
        detail: svc.state === "READY" && search.text !== ""
          ? svc.filteredItems.length + (svc.filteredItems.length === 1 ? " match" : " matches")
          : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        trailingControl: Component {
          Row {
            id: headerActions
            visible: svc.state === "READY"
            spacing: Style.space(6)

            Repeater {
              model: root.headerActionSpecs

              delegate: PanelActionButton {
                required property var modelData
                readonly property string label: root.headerActionLabel(modelData)
                iconText: modelData.icon
                tooltipText: modelData.tooltip !== undefined ? modelData.tooltip : label
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name !== undefined ? modelData.name : label
                enabled: root.headerActionEnabled(modelData)
                focusable: modelData.focusable === true
                onClicked: root.runHeaderAction(modelData)
              }
            }
            // At rest this is an icon like the three actions beside it, so it
            // stops holding the width of words it is not showing. Arming it
            // spells the words out in the alarm colour: the row reflows at
            // exactly the moment a destructive action is armed, which is the
            // one moment that deserves the user's eye. The label is never
            // dropped from the tooltip or the accessible name, so the icon is
            // not the only thing naming it.
            Button {
              readonly property string label: svc.logoutBusy ? "Logging out…"
                : (root.logoutArmed ? "Confirm log out" : "Log out")
              // Its three neighbours are PanelActionButtons pinned to a square
              // slot. Sizing this one from content instead put it off that grid
              // -- wider and taller than the row it sits in -- so it borrows the
              // same slot expression and only leaves it when the words appear.
              readonly property real slot: Math.max(Style.space(22),
                iconSize + Style.spacing.sm * 2)
              readonly property bool expanded: svc.logoutBusy || root.logoutArmed
              iconText: "󰍃"
              text: expanded ? label : ""
              tooltipText: label
              enabled: !svc.logoutBusy
              foreground: root.logoutArmed ? root.urgent : root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              width: expanded ? implicitWidth : slot
              height: slot
              horizontalPadding: expanded ? Style.spacing.controlPaddingX : 0
              verticalPadding: 0
              Accessible.role: Accessible.Button
              Accessible.name: label
              onClicked: root.requestLogout()
            }
          }
        }
        iconComponent: Component {
          Text {
            text: "󰌆"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Flickable {
        id: panelFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: panelHeader.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          TextField {
            id: search
            visible: svc.state === "READY"
            width: parent.width
            placeholderText: "Search logins and vaults…"
            Accessible.name: "Search Proton Pass logins"
            foreground: root.foreground
            onTextChanged: {
              svc.query = text
              root.cursorActive = false
              root.cursorIndex = 0
              itemListFlick.contentY = 0
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handleKey(event, true) }
          }

          BorderSurface {
            visible: svc.state === "READY" && root.createFormOpen
            width: parent.width
            implicitHeight: createForm.implicitHeight + Style.space(20)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), 1)
            radius: Style.cornerRadius

            Column {
              id: createForm
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Create login"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              TextField {
                id: createTitle
                width: parent.width
                enabled: root.createControlsEnabled
                placeholderText: "Title"
                Accessible.name: "Login title"
                foreground: root.foreground
                Keys.onEscapePressed: {
                  root.closeCreateForm()
                  search.forceActiveFocus()
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  text: "Username"
                  enabled: root.createControlsEnabled
                  focusable: true
                  foreground: root.createIdentifierField === "username" ? root.foreground : root.dim
                  Accessible.role: Accessible.Button
                  Accessible.name: "Use username identifier"
                  onClicked: root.createIdentifierField = "username"
                }
                Button {
                  text: "Email"
                  enabled: root.createControlsEnabled
                  focusable: true
                  foreground: root.createIdentifierField === "email" ? root.foreground : root.dim
                  Accessible.role: Accessible.Button
                  Accessible.name: "Use email identifier"
                  onClicked: root.createIdentifierField = "email"
                }
              }

              TextField {
                id: createIdentifier
                width: parent.width
                enabled: root.createControlsEnabled
                placeholderText: root.createIdentifierField === "email" ? "Email (optional)" : "Username (optional)"
                Accessible.name: root.createIdentifierField === "email" ? "Login email" : "Login username"
                foreground: root.foreground
                Keys.onEscapePressed: {
                  root.closeCreateForm()
                  search.forceActiveFocus()
                }
                Keys.onReturnPressed: root.submitCreate()
                Keys.onEnterPressed: root.submitCreate()
              }

              Text {
                width: parent.width
                text: "Vault"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: svc.vaults

                  CursorSurface {
                    id: createVaultOption
                    required property var modelData
                    width: parent.width
                    implicitHeight: createVaultName.implicitHeight + Style.space(12)
                    activeFocusOnTab: true
                    current: root.createVaultShareId === modelData.shareId
                    hasCursor: activeFocus
                    foreground: root.foreground
                    Accessible.role: Accessible.Button
                    Accessible.name: "Use vault " + modelData.name
                    Keys.onReturnPressed: if (root.createControlsEnabled)
                      root.createVaultShareId = modelData.shareId
                    Keys.onEnterPressed: if (root.createControlsEnabled)
                      root.createVaultShareId = modelData.shareId
                    Keys.onSpacePressed: if (root.createControlsEnabled)
                      root.createVaultShareId = modelData.shareId
                    Accessible.onPressAction: if (root.createControlsEnabled)
                      root.createVaultShareId = modelData.shareId

                    Text {
                      id: createVaultName
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(9)
                      anchors.rightMargin: Style.space(9)
                      text: createVaultOption.modelData.name
                      textFormat: Text.PlainText
                      color: root.createVaultShareId === createVaultOption.modelData.shareId
                        ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: root.createControlsEnabled
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.createVaultShareId = createVaultOption.modelData.shareId
                    }
                  }
                }
              }

              Row {
                anchors.right: parent.right
                spacing: Style.space(6)

                Button {
                  text: "Cancel"
                  enabled: root.createControlsEnabled
                  focusable: true
                  onClicked: {
                    root.closeCreateForm()
                    search.forceActiveFocus()
                  }
                }
                Button {
                  text: svc.createBusy ? "Creating…" : "Create login"
                  enabled: root.createControlsEnabled && root.createFormValid
                  focusable: true
                  Accessible.role: Accessible.Button
                  Accessible.name: text
                  onClicked: root.submitCreate()
                }
              }
            }
          }

          BorderSurface {
            visible: svc.state === "READY" && svc.warnings.length > 0
            width: parent.width
            implicitHeight: warningText.implicitHeight + Style.space(18)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.08)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.25), 1)
            radius: Style.cornerRadius

            Text {
              id: warningText
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              text: svc.message
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          Flickable {
            id: itemListFlick
            visible: svc.state === "READY"
            width: parent.width
            implicitHeight: Math.min(itemListContent.implicitHeight, Style.space(300))
            height: implicitHeight
            contentWidth: width
            contentHeight: itemListContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: itemListContent
              width: itemListFlick.width
              spacing: Style.space(4)

            Text {
              visible: svc.items.length === 0
              width: parent.width
              topPadding: Style.space(28)
              bottomPadding: Style.space(28)
              text: "No login items found" + (String(svc.setting("excludeVaults", "")).trim() !== ""
                ? "\nSome vaults are excluded in plugin settings." : "")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Text {
              visible: svc.items.length > 0 && svc.filteredItems.length === 0
              width: parent.width
              topPadding: Style.space(28)
              bottomPadding: Style.space(28)
              text: "No matches"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSectionHeader {
              visible: svc.displayingRecents
              width: parent.width
              topPadding: Style.space(8)
              leftPadding: Style.space(10)
              text: "Recent"
              textFormat: Text.PlainText
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Each list lives in its own Column so a row can read the offset
            // its section starts at -- a Repeater reparents delegates to its
            // own parent, which makes that Column the row's parent.
            Column {
              id: recentSection
              property int rowOffset: 0
              visible: svc.recentRows.length > 0
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                id: recentRepeater
                model: svc.recentRows
                delegate: loginRowDelegate
              }
            }

            PanelSectionHeader {
              id: allSectionHeader
              visible: svc.query === "" && svc.items.length > 0
              width: parent.width
              // PanelSectionHeader reserves a sliver above the glyph so a header
              // sitting at the top of this clipping list is not beheaded. Keep at
              // least that much when the gap under "Recent" does not apply.
              topPadding: svc.displayingRecents
                ? Style.space(8) : Math.ceil(allSectionHeader.fontSize * 0.15)
              leftPadding: Style.space(10)
              text: "All"
              textFormat: Text.PlainText
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: allSection
              property int rowOffset: svc.recentRows.length
              visible: svc.allRows.length > 0
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                id: itemRepeater
                model: svc.allRows
                delegate: loginRowDelegate
              }
            }

              Component {
                id: loginRowDelegate

                CursorSurface {
                id: loginRow
                required property var modelData
                required property int index
                // Derived here rather than baked into the model, so filtering
                // does not have to rebuild every row to renumber it.
                readonly property int cursorIndex: loginRow.parent.rowOffset + loginRow.index
                width: parent.width
                implicitHeight: rowContent.implicitHeight + Style.space(14)
                hasCursor: root.cursorActive && root.cursorIndex === loginRow.cursorIndex
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.cursorIndex
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.cursorIndex
                    keyCatcher.forceActiveFocus()
                  }
                }

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Column {
                    width: Math.max(1, parent.width - copyActions.width - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: loginRow.modelData.title
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: loginRow.modelData.vaultName
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: svc.subtitleFor(loginRow.modelData)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Row {
                    id: copyActions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Repeater {
                      model: root.copyActionSpecs

                      delegate: PanelActionButton {
                        required property var modelData
                        readonly property bool pending: root.copyPendingFor(
                          loginRow.modelData.itemId, modelData.field)
                        iconText: pending ? "󰔟" : modelData.icon
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: !svc.copyBusy
                        Accessible.role: Accessible.Button
                        Accessible.name: pending ? modelData.busyName : modelData.name
                        onClicked: root.requestCopy(
                          loginRow.modelData.shareId, loginRow.modelData.itemId, modelData.field)
                      }
                    }
                  }
                }
                }
              }
            }
          }

          Column {
            id: stateView
            readonly property var view: root.activeStateView
            // A setup state lays out flush against the panel: no surface of its
            // own, because the panel is already a bordered surface and a second
            // frame inside it reads as a box in a box. What separates it from a
            // fault view is alignment, rhythm, a real bordered action, and a
            // ruled-off trust footer.
            readonly property bool setupLayout: view !== null && view.setup === true
            visible: view !== null
            width: parent.width
            spacing: view ? view.spacing : 0

            Repeater {
              model: stateView.view ? stateView.view.blocks : []

              delegate: Loader {
                id: blockLoader
                required property var modelData
                // No explicit height: the Loader adopts the block's implicitHeight
                // and resizes the block to match. Binding height to
                // item.implicitHeight instead makes the two chase each other.
                width: parent.width
                sourceComponent: modelData.command !== undefined
                  ? commandBlock
                  : (modelData.buttons !== undefined ? buttonsBlock : textBlock)
                onLoaded: item.spec = blockLoader.modelData
              }
            }

            // The trust footer speaks for the plugin as a whole, not for the
            // step being offered. It carried a PanelSeparator above it until
            // that rule was found to stop the enclosing Column positioning at
            // all -- every child stacked at y=0, which the snapshot harness
            // rejected as impossible geometry and which would have shipped as a
            // collapsed dependency card. The footer stands apart on size and
            // colour instead.
            Repeater {
              model: stateView.view && stateView.view.footer !== undefined
                ? stateView.view.footer : []

              delegate: Loader {
                id: footerLoader
                required property var modelData
                width: parent.width
                sourceComponent: textBlock
                onLoaded: item.spec = footerLoader.modelData
              }
            }

            Component {
              id: textBlock

              // Two voices: the lead names the situation, dim explains it. Only
              // the lead carries the row's tone -- alarm colour on a fault,
              // plain foreground on a setup state, because "not set up yet" is
              // not a fault and must not be dressed as one. The shape they
              // share -- centred, wrapped, body or small-body -- is the
              // default, so a block only spells out where it differs.
              Text {
                property var spec: ({})
                readonly property bool leadTone: spec.lead !== undefined
                readonly property bool fineTone: spec.fine !== undefined
                readonly property bool faultTone: stateView.view
                  && stateView.view.tone === "fault"
                text: leadTone ? spec.lead
                  : (fineTone ? spec.fine : (spec.dim !== undefined ? spec.dim : ""))
                textFormat: Text.PlainText
                color: leadTone ? (faultTone ? root.urgent : root.foreground)
                  : (fineTone ? root.muted : root.dim)
                font.family: root.fontFamily
                font.pixelSize: spec.size !== undefined ? spec.size
                  : (leadTone ? Style.font.body
                    : (fineTone ? Style.font.caption : Style.font.bodySmall))
                font.bold: spec.bold === true
                horizontalAlignment: spec.align !== undefined ? spec.align
                  : (stateView.setupLayout ? Text.AlignLeft : Text.AlignHCenter)
                wrapMode: spec.wrap !== undefined ? spec.wrap : Text.WordWrap
                topPadding: spec.topPad !== undefined ? spec.topPad : 0
                bottomPadding: spec.bottomPad !== undefined ? spec.bottomPad : 0
              }
            }

            Component {
              id: commandBlock

              BorderSurface {
                property var spec: ({})
                implicitHeight: commandText.implicitHeight + Style.space(18)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                Text {
                  id: commandText
                  anchors.left: parent.left
                  anchors.right: commandCopy.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(9)
                  text: spec.command !== undefined ? spec.command : ""
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: spec.wrap !== undefined ? spec.wrap : Text.NoWrap
                }

                PanelActionButton {
                  id: commandCopy
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.rightMargin: Style.space(8)
                  iconText: ""
                  tooltipText: spec.name
                  Accessible.role: Accessible.Button
                  Accessible.name: spec.name
                  onClicked: root.copySetupCommand(commandText.text)
                }
              }
            }

            Component {
              id: buttonsBlock

              Item {
                property var spec: ({})
                implicitHeight: stateButtons.implicitHeight

                // A setup action anchors left, under the text it follows; a
                // fault view keeps its centred button row.
                Row {
                  id: stateButtons
                  anchors.left: stateView.setupLayout ? parent.left : undefined
                  anchors.horizontalCenter: stateView.setupLayout
                    ? undefined : parent.horizontalCenter
                  spacing: Style.space(8)

                  Repeater {
                    model: spec.buttons !== undefined ? spec.buttons : []

                    delegate: Button {
                      required property var modelData
                      text: modelData.text
                      iconText: modelData.icon !== undefined ? modelData.icon : ""
                      // Outlined at rest so it reads as a control rather than
                      // as another line of text.
                      bordered: stateView.setupLayout
                      onClicked: root.runStateAction(modelData)
                    }
                  }
                }
              }
            }
          }

          BorderSurface {
            visible: root.toast.text !== ""
            width: parent.width
            implicitHeight: toastContent.implicitHeight + Style.space(18)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.20), 1)
            radius: Style.cornerRadius
            Accessible.role: Accessible.AlertMessage
            Accessible.name: root.toast.text

            Row {
              id: toastContent
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              spacing: Style.space(8)

              Text {
                id: toastLabel
                width: Math.max(1, parent.width - (copyCreatedPassword.visible
                  ? copyCreatedPassword.width + parent.spacing : 0))
                anchors.verticalCenter: parent.verticalCenter
                text: root.toast.text
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: copyCreatedPassword.visible ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Button {
                id: copyCreatedPassword
                visible: root.toast.createdShareId !== "" && root.toast.createdItemId !== ""
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool pending: root.copyPendingFor(root.toast.createdItemId, "password")
                text: pending ? "Copying…" : "Copy password"
                enabled: root.createControlsEnabled
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                Accessible.role: Accessible.Button
                Accessible.name: copyCreatedPassword.pending
                  ? "Copying password for created login…"
                  : "Copy password for created login"
                onClicked: root.requestCopy(root.toast.createdShareId, root.toast.createdItemId, "password")
              }
            }
          }

          BorderSurface {
            visible: svc.state === "READY" && svc.clipboardCountdownActive
            width: parent.width
            implicitHeight: countdownText.implicitHeight + Style.space(14)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), 1)
            radius: Style.cornerRadius
            Accessible.role: Accessible.Button
            Accessible.name: countdownText.text

            Text {
              id: countdownText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(7)
              text: "Clears in " + svc.clipboardSecondsRemaining + "s · click to clear now"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(7)
              anchors.rightMargin: Style.space(7)
              anchors.bottomMargin: Style.space(4)
              height: 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
              radius: 1

              Rectangle {
                width: parent.width * (svc.clipboardClearSeconds > 0
                  ? svc.clipboardSecondsRemaining / svc.clipboardClearSeconds : 0)
                height: parent.height
                color: root.foreground
                radius: 1
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !svc.clearClipboardBusy
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: svc.clearClipboard()
            }
          }

        }
      }
    }
  }
}
