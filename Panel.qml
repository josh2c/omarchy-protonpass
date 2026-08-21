import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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

  readonly property var selectedItem: {
    var rows = svc.filteredItems
    if (!rows || rows.length === 0) return null
    return rows[Math.max(0, Math.min(cursorIndex, rows.length - 1))]
  }
  readonly property bool needsAttention: ["MISSING_DEPS", "LOGGED_OUT", "LOCKED"].indexOf(svc.state) !== -1

  function ensureCursor() {
    var count = svc.filteredItems.length
    if (count === 0) {
      cursorActive = false
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(cursorIndex, count - 1))
  }

  function moveCursor(delta) {
    var count = svc.filteredItems.length
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
      var row = itemRepeater.itemAt(root.cursorIndex)
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

  function refocusSearch(text) {
    search.forceActiveFocus()
    if (text !== "") search.insert(search.cursorPosition, text)
  }

  function layeredEscape() {
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
    toastText = String(message || "")
    if (toastText !== "") toastTimer.restart()
  }

  function copySetupCommand(commandText) {
    if (setupCopyProcess.running) return
    setupClipboardText = commandText
    setupCopyProcess.command = ["wl-copy"]
    setupCopyProcess.running = true
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
      toastTimer.stop()
      toastText = ""
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
    function onFilteredItemsChanged() { root.ensureCursor() }
    function onStateChanged() {
      if (root.opened && svc.state === "READY")
        Qt.callLater(function() { search.forceActiveFocus() })
    }
  }

  Timer {
    id: toastTimer
    interval: 3000
    repeat: false
    onTriggered: root.toastText = ""
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
      blocked: search.activeFocus

      // The stock catcher also reserves h/l/x/space. The v1 contract does
      // not: in list mode every printable key except the explicit actions
      // below must refocus search and insert that character.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (keyCatcher.blocked) return
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
              ? svc.items.length + (svc.items.length === 1 ? " login" : " logins")
              : (svc.message !== "" ? svc.message : "Checking pass-cli…")
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
            implicitHeight: toastLabel.implicitHeight + Style.space(18)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.20), 1)
            radius: Style.cornerRadius

            Text {
              id: toastLabel
              anchors.centerIn: parent
              width: parent.width - Style.space(20)
              text: root.toastText
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          TextField {
            id: search
            visible: svc.state === "READY"
            width: parent.width
            placeholderText: "Search logins and vaults…"
            foreground: root.foreground
            onTextChanged: {
              svc.query = text
              root.cursorActive = false
              root.cursorIndex = 0
            }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
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

            Repeater {
              id: itemRepeater
              model: svc.filteredItems

              delegate: CursorSurface {
                id: loginRow
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: rowContent.implicitHeight + Style.space(14)
                hasCursor: root.cursorActive && root.cursorIndex === index
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.index
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.cursorIndex = loginRow.index
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
                  }

                  Row {
                    id: copyActions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    PanelActionButton {
                      iconText: "u"
                      tooltipText: "Copy username"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
                      onClicked: svc.copy(loginRow.modelData.shareId, loginRow.modelData.itemId, "username")
                    }
                    PanelActionButton {
                      iconText: "p"
                      tooltipText: "Copy password"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
                      onClicked: svc.copy(loginRow.modelData.shareId, loginRow.modelData.itemId, "password")
                    }
                    PanelActionButton {
                      iconText: "t"
                      tooltipText: "Copy TOTP"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: !svc.copyBusy
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

          Row {
            visible: svc.state === "READY"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width - footerActions.width - parent.spacing
              text: svc.staleWarning ? "Showing cached list — refresh failed"
                : (svc.refreshing ? "Refreshing…" : "j/k move · u/p/t copy · L lock · r refresh")
              textFormat: Text.PlainText
              color: svc.staleWarning ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
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
                enabled: !svc.refreshing
                onClicked: svc.refresh()
              }
              PanelActionButton {
                iconText: "󰌾"
                tooltipText: "Lock Proton Pass"
                onClicked: svc.lock()
              }
            }
          }
        }
      }
    }
  }
}
