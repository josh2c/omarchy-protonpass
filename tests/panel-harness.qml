// Headless panel harness: instantiates the real Panel.qml against a stub bar
// inside a sandboxed copy of the Omarchy shell tree, drives it through every
// panel state, and dumps a structural snapshot of the visible item tree.
//
// The snapshot is the evidence for "pixel-equivalent": two runs that agree on
// every item's type, geometry, text, colour, font size and padding render the
// same pixels. Comparing structure rather than screenshots also survives theme
// and font differences between machines.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
  id: harness

  // Fixed metadata so row geometry is reproducible. `ts` is anchored to the
  // run's own clock at a whole number of hours so the relative-time subtitle
  // lands in the same bucket every time.
  readonly property var sampleItems: [
    {itemId: "item_a", shareId: "share_a", vaultName: "Personal",
     title: "Alpha Login", createTime: "2026-01-05T10:00:00"},
    {itemId: "item_b", shareId: "share_a", vaultName: "Personal",
     title: "Beta Login", createTime: "2026-02-11T10:00:00"},
    {itemId: "item_c", shareId: "share_b", vaultName: "Work",
     title: "Gamma Login", createTime: "2026-03-19T10:00:00"}
  ]

  function sampleRecents() {
    return [{shareId: "share_b", itemId: "item_c",
             ts: Math.floor(Date.now() / 1000) - 7200}]
  }

  function reset() {
    var svc = harness.service
    svc.items = []
    svc.recents = []
    svc.query = ""
    svc.message = ""
    // showToast("") is the reset path both before and after the toast refactor.
    harness.panelRoot.showToast("")
    harness.panelRoot.copyPendingKey = ""
  }

  readonly property var scenarios: [
    {label: "INIT", setup: function(svc) { svc.state = "INIT" }},
    {label: "LOADING", setup: function(svc) { svc.state = "LOADING" }},
    {label: "MISSING_DEPS", setup: function(svc) {
      svc.state = "MISSING_DEPS"; svc.message = "Proton Pass CLI not found" }},
    // Two logged-out scenarios, not one: the panel tells the first run apart
    // from an expired session by the classifier message, so both messages have
    // to be the ones the helper actually emits (omarchy-protonpass,
    // classify_failure) or the snapshot proves nothing about the split.
    {label: "LOGGED_OUT_FIRST_RUN", setup: function(svc) {
      svc.state = "LOGGED_OUT"; svc.message = "Not signed in to Proton Pass" }},
    {label: "LOGGED_OUT_EXPIRED", setup: function(svc) {
      svc.state = "LOGGED_OUT"; svc.message = "Session expired — sign in again" }},
    {label: "LOCKED", setup: function(svc) {
      svc.state = "LOCKED"; svc.message = "Session locked — unlock to continue" }},
    {label: "UNREACHABLE", setup: function(svc) {
      svc.state = "UNREACHABLE"; svc.message = "Could not reach Proton — check your connection" }},
    {label: "ERROR", setup: function(svc) {
      svc.state = "ERROR"; svc.message = "Something went wrong" }},
    {label: "READY_EMPTY", setup: function(svc) { svc.state = "READY" }},
    {label: "READY_ITEMS", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems },
     ready: function(svc) { return svc.allRows.length === harness.sampleItems.length
       && !svc.displayingRecents }},
    {label: "READY_RECENTS", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems
      svc.recents = harness.sampleRecents() },
     ready: function(svc) { return svc.displayingRecents && svc.recentRows.length > 0 }},
    {label: "READY_NO_MATCHES", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems; svc.query = "zzz" },
     ready: function(svc) { return svc.filteredItems.length === 0 }},
    // Busy state is as perishable as a toast: if the panel blinks closed and
    // the harness reopens it, onOpenedChanged clears both, and the capture then
    // settles on a panel that is merely idle. Re-assert it each tick.
    {label: "READY_COPY_PENDING", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems
      harness.panelRoot.copyPendingKey = "password@item_b"
      harness.panelRoot.showPendingToast("Copying…") },
     sustain: function() {
       harness.panelRoot.copyPendingKey = "password@item_b"
       harness.panelRoot.showPendingToast("Copying…")
     },
     ready: function() { return String(harness.panelRoot.copyPendingKey) !== "" }},
    // Toasts dismiss themselves after three seconds, which is shorter than a
    // slow settle. Re-assert them each tick so the capture cannot race the
    // dismissal timer.
    {label: "READY_TOAST", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems
      harness.panelRoot.showToast("Copied password") },
     sustain: function() { harness.panelRoot.showToast("Copied password") }},
    {label: "READY_CREATED_TOAST", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems
      harness.panelRoot.showCreatedToast("share_a", "item_a") },
     sustain: function() { harness.panelRoot.showCreatedToast("share_a", "item_a") }},
    {label: "READY_WARNING", setup: function(svc) {
      svc.state = "READY"; svc.items = harness.sampleItems
      svc.warnings = ["one vault failed"]; svc.message = "Some vaults could not be read" }}
  ]
  property int stateIndex: -1
  property int attempt: 0
  property var settledLines: null
  property int stableCount: 0
  property var panelRoot: null
  property var keyboardPanel: null
  property var service: null

  // The plugin's KeyboardPanel is a window, not an Item child, so it has to be
  // found among the root's data children.
  function findChild(obj, probe) {
    var kids = obj.data
    if (!kids) return null
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      if (child && probe(child)) return child
    }
    return null
  }

  function findKeyboardPanel(obj) {
    return findChild(obj, function(child) {
      return child.focusTarget !== undefined && child.contentItem !== undefined
    })
  }

  // The Service lives inside Panel.qml as a private id; the harness finds it
  // by shape rather than making Panel.qml grow a test-only alias.
  function findService(obj) {
    return findChild(obj, function(child) {
      return child.displayItems !== undefined && child.state !== undefined
    })
  }

  function fixed(value) {
    return Math.round(Number(value) * 100) / 100
  }

  property var snapshotRoot: null

  // Absolute position inside the panel content, so the comparison does not
  // care how many layout wrappers a subtree is nested in.
  function absolute(item) {
    var point = item.mapToItem(snapshotRoot, 0, 0)
    return fixed(point.x) + "," + fixed(point.y)
  }

  // A paint line records only what a user can see: text, glyphs, and the
  // surfaces behind them, each at its absolute position and size.
  function paints(item) {
    var name = String(item).split("(")[0].split("_QML")[0]
    if (item.text !== undefined && String(item.text) !== "") return true
    if (item.iconText !== undefined && String(item.iconText) !== "") return true
    if (name.indexOf("BorderSurface") !== -1 || name.indexOf("Rectangle") !== -1) return true
    return false
  }

  function paintLine(item) {
    var name = String(item).split("(")[0].split("_QML")[0]
    var out = name + " at=" + absolute(item)
      + " size=" + fixed(item.width) + "x" + fixed(item.height)
    if (item.text !== undefined && String(item.text) !== "")
      out += " text=" + JSON.stringify(String(item.text))
    if (item.iconText !== undefined && String(item.iconText) !== "")
      out += " icon=" + JSON.stringify(String(item.iconText))
    if (item.color !== undefined && item.font !== undefined)
      out += " color=" + String(item.color) + " px=" + fixed(item.font.pixelSize)
        + " bold=" + String(item.font.bold)
    if (item.color !== undefined && item.font === undefined)
      out += " fill=" + String(item.color)
    if (item.horizontalAlignment !== undefined)
      out += " align=" + String(item.horizontalAlignment)
    if (item.wrapMode !== undefined)
      out += " wrap=" + String(item.wrapMode)
    try {
      var accessibleName = item.Accessible.name
      if (accessibleName !== undefined && String(accessibleName) !== "")
        out += " a11y=" + JSON.stringify(String(accessibleName))
    } catch (e) {}
    return out
  }

  function collectPaints(item, lines) {
    if (!item || item.visible === false) return
    if (item !== snapshotRoot && paints(item)) lines.push(paintLine(item))
    var kids = item.children
    if (!kids) return
    for (var i = 0; i < kids.length; i++) collectPaints(kids[i], lines)
  }

  function describe(item) {
    var name = String(item)
    name = name.split("(")[0].split("_QML")[0]
    var out = name + " x=" + fixed(item.x) + " y=" + fixed(item.y)
      + " w=" + fixed(item.width) + " h=" + fixed(item.height)
    if (item.text !== undefined && String(item.text) !== "")
      out += " text=" + JSON.stringify(String(item.text))
    if (item.iconText !== undefined && String(item.iconText) !== "")
      out += " icon=" + JSON.stringify(String(item.iconText))
    if (item.color !== undefined && item.font !== undefined)
      out += " color=" + String(item.color) + " px=" + fixed(item.font.pixelSize)
        + " bold=" + String(item.font.bold)
    if (item.topPadding !== undefined && Number(item.topPadding) !== 0)
      out += " padT=" + fixed(item.topPadding)
    if (item.bottomPadding !== undefined && Number(item.bottomPadding) !== 0)
      out += " padB=" + fixed(item.bottomPadding)
    if (item.leftPadding !== undefined && Number(item.leftPadding) !== 0)
      out += " padL=" + fixed(item.leftPadding)
    if (item.horizontalAlignment !== undefined)
      out += " align=" + String(item.horizontalAlignment)
    if (item.wrapMode !== undefined)
      out += " wrap=" + String(item.wrapMode)
    try {
      var accessibleName = item.Accessible.name
      if (accessibleName !== undefined && String(accessibleName) !== "")
        out += " a11y=" + JSON.stringify(String(accessibleName))
    } catch (e) {}
    return out
  }

  function dump(item, depth, lines) {
    if (!item || item.visible === false) return
    if (depth > 0) lines.push(new Array(depth + 1).join("  ") + describe(item))
    var kids = item.children
    if (!kids) return
    for (var i = 0; i < kids.length; i++)
      dump(kids[i], depth + 1, lines)
  }

  // The panel is a real layer-shell surface and primes keyboard focus, so any
  // stray keystroke during the run would land in the search field and make the
  // snapshot non-reproducible. Blank every text input before capturing.
  function sanitize(item) {
    if (!item) return
    if (item.placeholderText !== undefined && String(item.text) !== "") item.text = ""
    var kids = item.children
    if (!kids) return
    for (var i = 0; i < kids.length; i++) sanitize(kids[i])
  }

  // Some position reads come back internally impossible: two differently sized
  // children of a Row sharing an x, or every child of a Column sharing a y.
  // That is not a render -- it is mapToItem resolved against a parent chain
  // that is still mid-polish, and it happens at certain surface sizes. Treat it
  // as not settled and read again.
  //
  // This is not hypothetical tidiness. A dump carrying exactly that signature
  // was mistaken for a layout regression in shipped code, and the fix attempts
  // that followed were chasing an artifact.
  function geometrySane(item) {
    if (!item || item.visible === false) return true
    var kids = item.children
    if (!kids) return true
    var name = String(item).split("(")[0]
    var isRow = name.indexOf("QQuickRow") === 0
    var isColumn = name.indexOf("QQuickColumn") === 0
    if (isRow || isColumn) {
      var seen = ({})
      for (var i = 0; i < kids.length; i++) {
        var kid = kids[i]
        if (!kid || kid.visible === false) continue
        // Non-visual children (Repeaters, Components) sit at the origin with no
        // size and are not laid out; they cannot collide with anything.
        if (kid.width === 0 && kid.height === 0) continue
        var slot = String(isRow ? kid.x : kid.y)
        if (seen[slot] === true) return false
        seen[slot] = true
      }
    }
    for (var j = 0; j < kids.length; j++)
      if (!geometrySane(kids[j])) return false
    return true
  }

  function captureLines() {
    var content = keyboardPanel && keyboardPanel.contentItem.length > 0
      ? keyboardPanel.contentItem[0] : null
    if (!content || !content.visible) return null
    if (!geometrySane(content)) {
      console.log("DIAG geometry-inconsistent " + scenarios[stateIndex].label)
      return null
    }
    sanitize(content)
    // Park keyboard focus on the key catcher so the search field's focus fill
    // is the same in every capture instead of following whatever the compositor
    // last handed the surface.
    content.forceActiveFocus()
    snapshotRoot = content
    var lines = []
    collectPaints(content, lines)
    return lines.length === 0 ? null : lines
  }

  function sameLines(a, b) {
    if (a === null || b === null || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++)
      if (a[i] !== b[i]) return false
    return true
  }

  function emitLines(label, lines) {
    console.log("SNAPSHOT-BEGIN " + label)
    for (var i = 0; i < lines.length; i++) console.log("| " + lines[i])
    console.log("SNAPSHOT-END " + label)
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
        settings: ({showRecents: true, keybinds: "", excludeVaults: "", clipboardClearSeconds: 45, pasteOnce: false})
      }
    }
  }

  Timer {
    id: stepTimer
    interval: 120
    repeat: false
    onTriggered: harness.tick()
  }

  function applyScenario() {
    if (!panelRoot.opened) panelRoot.open()
    reset()
    scenarios[stateIndex].setup(harness.service)
    settledLines = null
    stableCount = 0
    attempt = 0
    stepTimer.restart()
  }

  // Two things make a single delayed read unreliable: the panel is a real
  // layer-shell surface on a live session and can be dismissed out from under
  // the harness, and injecting items re-lays out the list over several frames.
  // So capture repeatedly and only accept a tree that reads identically twice
  // in a row -- a settled layout -- rather than trusting a fixed delay.
  function scenarioReady() {
    var check = scenarios[stateIndex].ready
    return check === undefined || check(harness.service)
  }

  // A scenario whose precondition has stopped holding is not just unsettled --
  // something undid it. Re-apply the setup rather than waiting for a state that
  // will never come back on its own.
  function reapply() {
    var sustain = scenarios[stateIndex].sustain
    if (sustain !== undefined) sustain()
    else scenarios[stateIndex].setup(harness.service)
  }

  function tick() {
    var sustain = scenarios[stateIndex].sustain
    if (sustain !== undefined) sustain()
    var lines = captureLines()
    attempt++
    if (lines === null) {
      if (!panelRoot.opened) panelRoot.open()
      settledLines = null
      stableCount = 0
    } else if (!scenarioReady()) {
      reapply()
      // A stable tree is not necessarily the right tree: without this, a
      // scenario can be captured before its own precondition holds and the
      // result looks settled because nothing is changing yet.
      settledLines = null
      stableCount = 0
    } else if (sameLines(settledLines, lines)) {
      stableCount++
      // Two matching reads are not enough: a list mid-relayout holds still for
      // longer than one interval, and a scenario was captured with the previous
      // scenario's rows stacked at the same y. Require several matches and a
      // minimum settling time before believing the tree.
      if (stableCount >= 6 && attempt >= 14) {
        emitLines(scenarios[stateIndex].label, lines)
        advance()
        return
      }
    } else {
      settledLines = lines
      stableCount = 0
    }

    if (attempt >= 60) {
      console.log("SNAPSHOT " + scenarios[stateIndex].label + " EMPTY")
      advance()
      return
    }
    stepTimer.restart()
  }

  function advance() {
    stateIndex++
    if (stateIndex >= scenarios.length) {
      console.log("HARNESS-DONE")
      Qt.quit()
      return
    }
    applyScenario()
  }

  Component.onCompleted: {
    panelRoot = plugin
    keyboardPanel = findKeyboardPanel(plugin)
    service = findService(plugin)
    console.log("HARNESS-WIRED kbPanel=" + (keyboardPanel !== null) + " service=" + (service !== null))
    plugin.open()
    startTimer.start()
  }

  // The first open() often does not stick: the layer-shell surface is still
  // being set up and the panel comes back closed. Open, let it settle, open
  // again, and re-assert on every step.
  Timer {
    id: startTimer
    interval: 1200
    repeat: false
    onTriggered: {
      harness.panelRoot.open()
      settleTimer.start()
    }
  }

  Timer {
    id: settleTimer
    interval: 800
    repeat: false
    onTriggered: {
      harness.stateIndex = -1
      harness.advance()
    }
  }
}
