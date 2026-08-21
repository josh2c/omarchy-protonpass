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
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool cursorActive: false
  property int cursorIndex: 0
  property string toastText: ""
  property string setupClipboardText: ""
  property int statusTick: 0
  property bool logoutArmed: false
  property bool createFormOpen: false
  property string createVaultShareId: ""
  property string createIdentifierField: "username"
  property string createdShareId: ""
  property string createdItemId: ""
  readonly property bool createControlsEnabled: !svc.copyBusy && !svc.createBusy
  readonly property bool createFormValid: svc.validCreateInput(
    createVaultShareId, createTitle.text, createIdentifierField, createIdentifier.text)

  readonly property var keybindConfiguration: Keybinds.parse(
    String(svc.setting("keybinds", "")),
    function(entry) { console.warn("omarchy-protonpass: invalid keybind entry: " + entry) })
  readonly property var effectiveKeybinds: keybindConfiguration.bindings

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
      if (!row || !panelFlick) return
      var point = row.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      var top = point.y
      var bottom = top + row.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin)
        panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function copySelected(field) {
    if (!selectedItem || svc.copyBusy) return
    svc.copy(selectedItem.shareId, selectedItem.itemId, field)
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

  function handleChord(event) {
    var action = effectiveKeybinds[chordForEvent(event)]
    if (action === undefined)
      return false
    triggerAction(action)
    event.accepted = true
    return true
  }

  function syncedAgeText() {
    statusTick
    if (svc.lastSuccessfulIndexAt <= 0) return "syncing"
    var minutes = Math.max(0, Math.floor((Date.now() - svc.lastSuccessfulIndexAt) / 60000))
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

  function showToast(message) {
    createdShareId = ""
    createdItemId = ""
    toastText = String(message || "")
    if (toastText !== "") toastTimer.restart()
  }

  function showCreatedToast(shareId, itemId) {
    createdShareId = String(shareId || "")
    createdItemId = String(itemId || "")
    toastText = "Login created"
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
    svc.create(createVaultShareId, createTitle.text, createIdentifierField, createIdentifier.text)
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
      svc.onPanelOpened()
      Qt.callLater(function() { search.forceActiveFocus() })
    } else {
      disarmLogout()
      closeCreateForm()
      toastTimer.stop()
      toastText = ""
      createdShareId = ""
      createdItemId = ""
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
    onTriggered: {
      root.toastText = ""
      root.createdShareId = ""
      root.createdItemId = ""
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened && svc.state === "READY"
    onTriggered: root.statusTick++
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus || createTitle.activeFocus || createIdentifier.activeFocus

      // The stock catcher also reserves h/l/x/space. The v1 contract does
      // not: in list mode every printable key except the explicit actions
      // below must refocus search and insert that character.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (keyCatcher.blocked) return
        if (root.handleChord(event)) return
        if (event.key === Qt.Key_Escape) {
          root.layeredEscape(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          search.forceActiveFocus(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Down || event.text === "j") {
          root.moveCursor(1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Up || event.text === "k") {
          root.moveCursor(-1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.copySelected("password"); event.accepted = true; return
        }
        if (event.text === "u") {
          root.copySelected("username"); event.accepted = true; return
        }
        if (event.text === "p") {
          root.copySelected("password"); event.accepted = true; return
        }
        if (event.text === "t") {
          root.copySelected("totp"); event.accepted = true; return
        }
        if (event.text === "L") {
          svc.lock(); event.accepted = true; return
        }
        if (event.text === "r") {
          svc.refresh(); event.accepted = true; return
        }
        if (event.text === "/") {
          root.refocusSearch(""); event.accepted = true; return
        }
        if (event.text && event.text.length === 1) {
          root.refocusSearch(event.text); event.accepted = true
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
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

          PanelHero {
            width: parent.width
            title: "Proton Pass"
            meta: svc.state === "READY"
              ? root.headerStatusText()
              : (svc.message !== "" ? svc.message : "Checking pass-cli…")
            detail: svc.state === "READY" && search.text !== ""
              ? svc.filteredItems.length + (svc.filteredItems.length === 1 ? " match" : " matches")
              : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
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

          BorderSurface {
            visible: root.toastText !== ""
            width: parent.width
            implicitHeight: toastContent.implicitHeight + Style.space(18)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.20), 1)
            radius: Style.cornerRadius
            Accessible.role: Accessible.AlertMessage
            Accessible.name: root.toastText

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
                text: root.toastText
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: copyCreatedPassword.visible ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Button {
                id: copyCreatedPassword
                visible: root.createdShareId !== "" && root.createdItemId !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Copy password"
                enabled: root.createControlsEnabled
                focusable: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                Accessible.role: Accessible.Button
                Accessible.name: "Copy password for created login"
                onClicked: svc.copy(root.createdShareId, root.createdItemId, "password")
              }
            }
          }

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
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (root.handleChord(event)) return
              if (event.key === Qt.Key_Escape) {
                root.layeredEscape(); event.accepted = true; return
              }
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.copySelected("password"); event.accepted = true; return
              }
              if (event.key === Qt.Key_Up) {
                root.moveCursor(-1); event.accepted = true; return
              }
              if (event.key === Qt.Key_Down) {
                root.moveCursor(1)
                keyCatcher.forceActiveFocus()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                if (!root.cursorActive) root.moveCursor(1)
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
            }
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

          Column {
            visible: svc.state === "READY"
            width: parent.width
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

            Text {
              visible: svc.displayingRecents
              width: parent.width
              topPadding: Style.space(8)
              leftPadding: Style.space(10)
              text: "Recent"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              id: recentRepeater
              model: svc.recentRows
              delegate: loginRowDelegate
            }

            Text {
              visible: svc.query === "" && svc.items.length > 0
              width: parent.width
              topPadding: svc.displayingRecents ? Style.space(8) : 0
              leftPadding: Style.space(10)
              text: "All"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              id: itemRepeater
              model: svc.allRows
              delegate: loginRowDelegate
            }

            Component {
              id: loginRowDelegate

              CursorSurface {
                id: loginRow
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: rowContent.implicitHeight + Style.space(14)
                hasCursor: root.cursorActive && root.cursorIndex === modelData.cursorIndex
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.modelData.cursorIndex
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.modelData.cursorIndex
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
                      text: loginRow.modelData.subtitle
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

                    PanelActionButton {
                      iconText: ""
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
                      Accessible.role: Accessible.Button
                      Accessible.name: "Copy username"
                      onClicked: svc.copy(loginRow.modelData.shareId, loginRow.modelData.itemId, "username")
                    }
                    PanelActionButton {
                      iconText: ""
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
                      Accessible.role: Accessible.Button
                      Accessible.name: "Copy password"
                      onClicked: svc.copy(loginRow.modelData.shareId, loginRow.modelData.itemId, "password")
                    }
                    PanelActionButton {
                      iconText: ""
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
                      Accessible.role: Accessible.Button
                      Accessible.name: "Copy TOTP code"
                      onClicked: svc.copy(loginRow.modelData.shareId, loginRow.modelData.itemId, "totp")
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: svc.state === "INIT" || svc.state === "LOADING"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              topPadding: Style.space(32)
              bottomPadding: Style.space(32)
              text: svc.state === "LOADING" ? "Loading Proton Pass logins…" : "Checking Proton Pass CLI…"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            visible: svc.state === "MISSING_DEPS"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: "Proton Pass CLI not found or wl-clipboard is unavailable"
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: svc.message
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Proton Pass CLI access requires Pass Plus or Pass Professional. Pass Essentials is not eligible."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: installerText.implicitHeight + Style.space(18)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Text {
                id: installerText
                anchors.left: parent.left
                anchors.right: installerCopy.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(9)
                text: "curl -fsSL https://proton.me/download/pass-cli/install.sh | bash"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
              PanelActionButton {
                id: installerCopy
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(8)
                iconText: ""
                tooltipText: "Copy official installer command"
                Accessible.role: Accessible.Button
                Accessible.name: "Copy official installer command"
                onClicked: root.copySetupCommand(installerText.text)
              }
            }

            BorderSurface {
              width: parent.width
              implicitHeight: archText.implicitHeight + Style.space(18)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Text {
                id: archText
                anchors.left: parent.left
                anchors.right: archCopy.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(9)
                text: "yay -S proton-pass-cli-bin"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              PanelActionButton {
                id: archCopy
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(8)
                iconText: ""
                tooltipText: "Copy Arch AUR command"
                Accessible.role: Accessible.Button
                Accessible.name: "Copy Arch AUR command"
                onClicked: root.copySetupCommand(archText.text)
              }
            }

            Text {
              width: parent.width
              text: "Arch note: the AUR package named pass-cli is unrelated. Use proton-pass-cli-bin."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: clipboardText.implicitHeight + Style.space(18)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              Text {
                id: clipboardText
                anchors.left: parent.left
                anchors.right: clipboardCopy.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(9)
                text: "sudo pacman -S wl-clipboard"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              PanelActionButton {
                id: clipboardCopy
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(8)
                iconText: ""
                tooltipText: "Copy wl-clipboard install command"
                Accessible.role: Accessible.Button
                Accessible.name: "Copy wl-clipboard install command"
                onClicked: root.copySetupCommand(clipboardText.text)
              }
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Recheck"
              onClicked: svc.recheck()
            }
          }

          Column {
            visible: svc.state === "LOGGED_OUT"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: svc.message
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Sign-in requires a plan with CLI access (Pass Plus or Pass Professional) — an eligibility error appears in the sign-in terminal otherwise."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)
              Button {
                text: "Sign in"
                onClicked: root.launchTerminal(["omarchy", "launch", "terminal", "pass-cli", "login"])
              }
              Button { text: "Retry"; onClicked: svc.retry() }
            }
          }

          Column {
            visible: svc.state === "LOCKED"
            width: parent.width
            spacing: Style.space(10)
            Text {
              width: parent.width
              text: svc.message
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)
              Button {
                text: "Unlock"
                onClicked: root.launchTerminal(["omarchy", "launch", "terminal", "pass-cli", "session", "unlock"])
              }
              Button { text: "Retry"; onClicked: svc.retry() }
            }
          }

          Column {
            visible: svc.state === "UNREACHABLE" || svc.state === "ERROR"
            width: parent.width
            spacing: Style.space(10)
            Text {
              width: parent.width
              text: svc.message
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Retry"
              onClicked: svc.retry()
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

          Row {
            visible: svc.state === "READY"
            width: parent.width
            spacing: Style.space(8)

            Column {
              width: parent.width - footerActions.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                visible: svc.staleWarning || svc.refreshing
                width: parent.width
                text: svc.staleWarning ? "Showing cached list — refresh failed" : "Refreshing…"
                textFormat: Text.PlainText
                color: svc.staleWarning ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Row {
              id: footerActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                visible: svc.refreshing
                text: "↻"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                  running: svc.refreshing
                }
              }
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                Accessible.role: Accessible.Button
                Accessible.name: "Refresh Proton Pass"
                enabled: !svc.refreshing
                onClicked: svc.refresh()
              }
              PanelActionButton {
                iconText: ""
                tooltipText: root.createFormOpen ? "Close create form" : "Create login"
                Accessible.role: Accessible.Button
                Accessible.name: tooltipText
                enabled: root.createControlsEnabled && svc.vaults.length > 0
                focusable: true
                onClicked: {
                  if (root.createFormOpen) {
                    root.closeCreateForm()
                    search.forceActiveFocus()
                  } else {
                    root.openCreateForm()
                  }
                }
              }
              PanelActionButton {
                iconText: "󰌾"
                tooltipText: "Lock Proton Pass"
                Accessible.role: Accessible.Button
                Accessible.name: "Lock Proton Pass"
                onClicked: svc.lock()
              }
              Button {
                property real reservedWidth: 0
                onImplicitWidthChanged: reservedWidth = Math.max(reservedWidth, implicitWidth)
                width: Math.max(reservedWidth, implicitWidth)
                text: svc.logoutBusy ? "Logging out…" : (root.logoutArmed ? "Confirm log out" : "Log out")
                enabled: !svc.logoutBusy
                foreground: root.logoutArmed ? root.urgent : root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.controlPaddingY
                Accessible.role: Accessible.Button
                Accessible.name: text
                onClicked: root.requestLogout()
              }
            }
          }
        }
      }
    }
  }
}
