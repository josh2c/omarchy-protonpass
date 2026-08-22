// Keyboard matrix harness: presses every binding, in both focus contexts, as
// real key events delivered by the compositor, and prints what the panel did.
//
// Runs inside a throwaway nested Hyprland (see tests/qml-key-matrix.sh) so the
// synthetic keystrokes cannot escape into the developer's own session.
//
// The output is one line per (chord x context) case naming the observable
// effect -- focus, search text, cursor, which field a copy was requested for,
// service busy flags, logout arming, panel open state. Diff two runs to prove a
// key-handling refactor changed nothing.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
  id: harness

  // Alt+letter is deliberately absent: whether Qt reports a character for it is
  // decided by the keymap and varies between runs on unmodified code too, so a
  // row for it would be noise rather than signal.
  //
  // Each case is a modifier set plus a key, or a literal piece of text where
  // the character itself is what matters (an uppercase letter needs whatever
  // shifting the keymap actually requires).
  readonly property var cases: [
    {chord: "u", text: "u"},
    {chord: "p", text: "p"},
    {chord: "t", text: "t"},
    {chord: "r", text: "r"},
    {chord: "j", text: "j"},
    {chord: "k", text: "k"},
    {chord: "l", text: "l"},
    {chord: "a", text: "a"},
    {chord: "slash", text: "/"},
    // Shift+letter needs both properties a real keyboard produces: the Shift
    // modifier *and* the uppercase character. Pressing the modifier around a
    // keysym gives the modifier but a lowercase character; typing the text
    // alone gives the character but no modifier. Do both.
    {chord: "shift+l", mods: ["shift"], text: "L"},
    {chord: "ctrl+u", mods: ["ctrl"], key: "u"},
    {chord: "ctrl+p", mods: ["ctrl"], key: "p"},
    {chord: "ctrl+t", mods: ["ctrl"], key: "t"},
    {chord: "ctrl+r", mods: ["ctrl"], key: "r"},
    {chord: "ctrl+l", mods: ["ctrl"], key: "l"},
    {chord: "ctrl+shift+x", mods: ["ctrl", "shift"], key: "x"},
    {chord: "enter", mods: [], key: "Return"},
    {chord: "shift+enter", mods: ["shift"], key: "Return"},
    {chord: "ctrl+enter", mods: ["ctrl"], key: "Return"},
    {chord: "escape", mods: [], key: "Escape"},
    {chord: "tab", mods: [], key: "Tab"},
    {chord: "backtab", mods: ["shift"], key: "Tab"},
    {chord: "up", mods: [], key: "Up"},
    {chord: "down", mods: [], key: "Down"}
  ]

  // wtype applies modifiers and keys as fast as it can, which the compositor
  // and Qt do not always observe in order -- Shift+Return arriving as a bare
  // Return, for instance. -s pauses between operations so each press is seen
  // before the next one.
  function wtypeArgs(item) {
    var mods = item.mods !== undefined ? item.mods : []
    var args = ["-s", "40"]
    for (var i = 0; i < mods.length; i++) args = args.concat(["-M", mods[i]])
    args = args.concat(item.text !== undefined
      ? ["-s", "60", item.text, "-s", "60"]
      : ["-s", "60", "-k", item.key, "-s", "60"])
    for (var j = mods.length - 1; j >= 0; j--) args = args.concat(["-m", mods[j]])
    return args
  }

  readonly property var contexts: ["list", "search"]

  readonly property var sampleItems: [
    {itemId: "item_a", shareId: "share_a", vaultName: "Personal",
     title: "Alpha Login", createTime: "2026-01-05T10:00:00"},
    {itemId: "item_b", shareId: "share_a", vaultName: "Personal",
     title: "Beta Login", createTime: "2026-02-11T10:00:00"}
  ]

  property var panelRoot: null
  property var keyboardPanel: null
  property var service: null
  property var keyCatcher: null
  property var searchField: null
  property int caseIndex: -1
  property int focusTries: 0
  property int inputRetries: 0
  property int contextIndex: 0
  property bool ready: false

  function findChild(obj, probe) {
    var kids = obj.data
    if (!kids) return null
    for (var i = 0; i < kids.length; i++)
      if (kids[i] && probe(kids[i])) return kids[i]
    return null
  }

  function findDescendant(item, probe) {
    if (!item) return null
    if (probe(item)) return item
    var kids = item.children
    if (!kids) return null
    for (var i = 0; i < kids.length; i++) {
      var hit = findDescendant(kids[i], probe)
      if (hit) return hit
    }
    return null
  }

  function wire() {
    panelRoot = plugin
    keyboardPanel = findChild(plugin, function(c) {
      return c.focusTarget !== undefined && c.contentItem !== undefined
    })
    service = findChild(plugin, function(c) {
      return c.displayItems !== undefined && c.state !== undefined
    })
    keyCatcher = keyboardPanel && keyboardPanel.contentItem.length > 0
      ? keyboardPanel.contentItem[0] : null
    searchField = findDescendant(keyCatcher, function(i) {
      return i.placeholderText !== undefined
    })
    return keyCatcher !== null && searchField !== null && service !== null
  }

  function wantedFocus() {
    return contexts[contextIndex] === "search" ? "search" : "catcher"
  }

  function droppedModifier() {
    var text = String(searchField.text)
    for (var i = 0; i < text.length; i++)
      if (text.charCodeAt(i) < 32) return true
    return false
  }

  function focusName() {
    if (searchField && searchField.activeFocus) return "search"
    if (keyCatcher && keyCatcher.activeFocus) return "catcher"
    return "other"
  }

  function observe() {
    var svc = service
    return "focus=" + focusName()
      + " search=" + JSON.stringify(String(searchField.text))
      + " cursor=" + (panelRoot.cursorActive ? "on" : "off") + ":" + panelRoot.cursorIndex
      + " copy=" + JSON.stringify(String(panelRoot.copyPendingKey))
      + " refreshing=" + svc.refreshing
      + " clearing=" + svc.clearClipboardBusy
      + " logoutArmed=" + panelRoot.logoutArmed
      + " createOpen=" + panelRoot.createFormOpen
      + " opened=" + panelRoot.opened
      + " toastPending=" + (String(panelRoot.copyPendingKey) !== "")
  }

  function resetState() {
    var svc = service
    svc.copyBusy = false
    svc.refreshing = false
    svc.clearClipboardBusy = false
    svc.logoutBusy = false
    svc.createBusy = false
    svc.state = "READY"
    svc.items = sampleItems
    svc.query = ""
    panelRoot.showToast("")
    panelRoot.copyPendingKey = ""
    panelRoot.logoutArmed = false
    if (panelRoot.createFormOpen) panelRoot.closeCreateForm()
    if (!panelRoot.opened) panelRoot.open()
    searchField.text = ""
    panelRoot.cursorActive = false
    panelRoot.cursorIndex = 0
    if (contexts[contextIndex] === "search") searchField.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  // Which helper command a key triggered is the one observable that names every
  // action uniformly -- copy names its field, refresh is an index, lock/logout/
  // clear-now speak for themselves -- so the stub helper logs its argv and the
  // harness drains that log around each keypress.
  // A stub helper from an earlier case is still sleeping, and the Service
  // guards each command against its own process already running -- so without
  // reaping them, "lock" fires once for the whole run and every later lock,
  // logout or clear-now case silently observes nothing.
  //
  // Only PIDs the stub helper recorded for itself are killed. Matching on a
  // command-line pattern instead would be a loaded gun: any unrelated process
  // whose arguments happen to mention the helper -- an editor, a grep, the
  // shell that launched this run -- would be killed too.
  Process {
    id: reaper
    command: ["sh", "-c",
      "while read -r pid; do kill \"$pid\" 2>/dev/null; done < \"$MATRIX_PIDS\" 2>/dev/null; : > \"$MATRIX_PIDS\"; exit 0"]
    onExited: {
      harness.resetState()
      setupTimer.restart()
    }
  }

  Process {
    id: logClearer
    command: ["sh", "-c", ": > \"$MATRIX_LOG\""]
    onExited: {
      typer.command = ["wtype"].concat(harness.wtypeArgs(harness.cases[harness.caseIndex]))
      typer.running = true
    }
  }

  Process {
    id: typer
    onExited: settleTimer.restart()
  }

  Process {
    id: logReader
    command: ["sh", "-c", "cat \"$MATRIX_LOG\" 2>/dev/null; : > \"$MATRIX_LOG\""]
    stdout: StdioCollector {
      id: logCollector
      waitForEnd: true
    }
    onExited: {
      // A control character in the search field means the compositor delivered
      // the key without its modifier -- Ctrl+U arriving as 0x15 rather than as
      // a Ctrl chord. That is an input-delivery failure, not panel behaviour,
      // and recording it would put a plausible-looking wrong row in the matrix.
      if (harness.droppedModifier()) {
        harness.inputRetries++
        if (harness.inputRetries < 4) {
          harness.applyScenario()
          return
        }
        console.log("CASE " + harness.cases[harness.caseIndex].chord
          + " ctx=" + harness.contexts[harness.contextIndex] + " INPUT-UNRELIABLE")
        harness.next()
        return
      }
      harness.inputRetries = 0
      var helper = String(logCollector.text).replace(/\n+$/, "").replace(/\n/g, " | ")
      console.log("CASE " + harness.cases[harness.caseIndex].chord
        + " ctx=" + harness.contexts[harness.contextIndex]
        + " helper=" + JSON.stringify(helper) + " " + harness.observe())
      harness.next()
    }
  }

  // Long enough that a helper process the keypress started has actually written
  // its argv before the log is drained; a shorter wait races the spawn and the
  // same case reports a helper command only sometimes.
  Timer {
    id: settleTimer
    interval: 550
    repeat: false
    onTriggered: logReader.running = true
  }

  // Long enough for the fallout of a reaped helper -- and of the index request
  // that reopening the panel starts -- to land before the log is truncated.
  Timer {
    id: setupTimer
    interval: 320
    repeat: false
    onTriggered: {
      var want = harness.wantedFocus()
      if (want === "search") searchField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
      confirmTimer.restart()
    }
  }

  // The panel grabs focus through Qt.callLater in several places, so a focus
  // assertion can be undone one event loop later -- after the check but before
  // the keypress. Confirm it a second time, a beat later, and only then type;
  // typing into the wrong context is the one failure that silently produces a
  // plausible-looking wrong answer.
  Timer {
    id: confirmTimer
    interval: 140
    repeat: false
    onTriggered: {
      if (focusName() !== harness.wantedFocus()) {
        harness.focusTries++
        if (harness.focusTries < 15) {
          setupTimer.restart()
          return
        }
        console.log("CASE " + harness.cases[harness.caseIndex].chord
          + " ctx=" + harness.contexts[harness.contextIndex] + " FOCUS-LOST")
        harness.next()
        return
      }
      harness.focusTries = 0
      logClearer.running = true
    }
  }

  function next() {
    contextIndex++
    if (contextIndex >= contexts.length) {
      contextIndex = 0
      caseIndex++
    }
    if (caseIndex >= cases.length) {
      console.log("MATRIX-DONE")
      Qt.quit()
      return
    }
    focusTries = 0
    reaper.running = true
  }

  QtObject {
    id: barStub
    readonly property string position: "top"
    readonly property real barSize: 40
    readonly property color foreground: "#e6e6e6"
    readonly property color barForeground: "#e6e6e6"
    readonly property color urgent: "#ff5555"
    readonly property string fontFamily: "monospace"
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(key) { activePopout = key }
    function releasePopout(key) { if (activePopout === key) activePopout = null }
    function targetBelongsToWindow(target, window) { return false }
    function switchPanelFrom(panel, direction) { return false }
  }

  PanelWindow {
    id: barWindow
    anchors { top: true; left: true; right: true }
    implicitHeight: 40
    color: "#101010"
    WlrLayershell.layer: WlrLayer.Top

    Item {
      id: anchor
      x: barWindow.width - 60
      width: 30
      height: 30
      anchors.verticalCenter: parent.verticalCenter

      Plugin.Panel {
        id: plugin
        anchors.fill: parent
        bar: barStub
        moduleName: "josh2c.protonpass"
        manageIpc: false
        settings: ({showRecents: true, keybinds: String(Quickshell.env("MATRIX_KEYBINDS") || ""),
                    excludeVaults: "", clipboardClearSeconds: 45, pasteOnce: false})
      }
    }
  }

  Timer {
    id: openTimer
    interval: 1400
    repeat: false
    onTriggered: {
      plugin.open()
      startTimer.start()
    }
  }

  Timer {
    id: startTimer
    interval: 900
    repeat: false
    onTriggered: {
      if (!harness.wire() || !panelRoot.opened) {
        console.log("MATRIX-SETUP-FAILED")
        Qt.quit()
        return
      }
      harness.caseIndex = 0
      harness.contextIndex = 0
      reaper.running = true
    }
  }

  Component.onCompleted: {
    wire()
    plugin.open()
    openTimer.start()
  }
}
