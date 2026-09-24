// Row-list cost harness, as a pass/fail gate.
//
// It fills the real panel with a synthetic 5,000-item vault -- the size the
// large-vault report is about -- types a query into it a character at a time,
// and asks two questions with fixed answers:
//
//   live delegates -- how many row objects the list has instantiated once it
//     has settled. A list that builds one object per item builds 5,000 of them
//     inside the shell process every other widget shares, to fill a viewport
//     300 px tall. A virtualised list builds the viewport plus its cache and
//     nothing else, so this number is bounded by the panel's own height and
//     does not move when the vault grows.
//   delegateSurvived -- whether the row objects outlive a subtitle clock tick.
//     If a row carried a precomputed subtitle, ticking the clock would build a
//     new array and destroy every row in the list; a delegate-side binding
//     leaves the same objects in place and only re-evaluates their text.
//
// Typing time is printed too, but it is a measurement, not the gate: wall clock
// inside a nested compositor wobbles, and a count does not.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
  id: harness

  readonly property int itemCount: 5000
  // A viewport of rows plus a screen of cache either side is on the order of
  // twenty. Two hundred is well clear of that and nowhere near per-item.
  readonly property int maxLiveDelegates: 200
  readonly property var queries: ["", "l", "lo", "log", "logi", "login", "login 4", "login 42", ""]

  property var panelRoot: null
  property var service: null
  property var content: null
  property int step: -1
  property var lastFirstRow: null
  property int rebuilds: 0
  property int worstDelegates: 0
  property bool failed: false

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

  function buildItems() {
    var out = []
    for (var i = 0; i < itemCount; i++) {
      out.push({
        itemId: "item_" + i,
        shareId: "share_a",
        vaultName: i % 3 === 0 ? "Work" : "Personal",
        title: "Login " + i,
        createTime: "2026-01-05T10:00:00"
      })
    }
    return out
  }

  // A row is any live object carrying both the item it renders and the cursor
  // index it answers to. That shape is what the panel promises the keyboard,
  // and it is the same whether the rows come from a Repeater or a ListView --
  // so this counts the same thing before and after the change.
  function collectRows(item, found) {
    if (!item) return found
    if (item.modelData !== undefined && item.cursorIndex !== undefined)
      found.push(item)
    var kids = item.children
    if (kids)
      for (var i = 0; i < kids.length; i++) collectRows(kids[i], found)
    return found
  }

  function liveRows() {
    return collectRows(content, [])
  }

  function firstRow() {
    var rows = liveRows()
    var best = null
    for (var i = 0; i < rows.length; i++)
      if (best === null || rows[i].cursorIndex < best.cursorIndex) best = rows[i]
    return best
  }

  function measure() {
    step++
    if (step >= queries.length) {
      churn()
      return
    }
    var svc = service
    var started = Date.now()
    svc.query = queries[step]
    // Force the filter to run before the clock is read; the list builds what it
    // needs on its own schedule, which is exactly what is being measured.
    var visible = svc.allRows.length
    var elapsed = Date.now() - started
    var rows = liveRows()
    if (rows.length > harness.worstDelegates) harness.worstDelegates = rows.length
    // Identity, not count: a rebuilt list has the same number of rows as a
    // reused one. Only the object tells you which happened.
    var current = firstRow()
    var reused = harness.lastFirstRow !== null && current === harness.lastFirstRow
    if (!reused) harness.rebuilds++
    harness.lastFirstRow = current
    console.log("PERF type query=" + JSON.stringify(queries[step])
      + " visible=" + visible
      + " liveDelegates=" + rows.length
      + " ms=" + elapsed
      + " rowReused=" + reused)
    stepTimer.restart()
  }

  function churn() {
    service.query = ""
    churnSettleTimer.restart()
  }

  property var tickBefore: null
  property int tickDelegates: 0
  property int tickMs: 0

  Timer {
    id: churnSettleTimer
    interval: 400
    repeat: false
    onTriggered: {
      var rows = harness.liveRows()
      if (rows.length > harness.worstDelegates) harness.worstDelegates = rows.length
      harness.tickBefore = harness.firstRow()
      harness.tickDelegates = rows.length
      var started = Date.now()
      harness.service.refreshSubtitleNow()
      harness.tickMs = Date.now() - started
      // A model-driven rebuild lands on a later event loop turn, so reading the
      // row back synchronously would report a survivor either way.
      tickCheckTimer.restart()
    }
  }

  Timer {
    id: tickCheckTimer
    interval: 250
    repeat: false
    onTriggered: {
      var after = harness.firstRow()
      var survived = harness.tickBefore !== null && harness.tickBefore === after
      console.log("PERF tick items=" + harness.itemCount
        + " liveDelegates=" + harness.tickDelegates
        + " ms=" + harness.tickMs
        + " delegateSurvived=" + survived)
      console.log("PERF summary items=" + harness.itemCount
        + " worstLiveDelegates=" + harness.worstDelegates
        + " limit=" + harness.maxLiveDelegates
        + " listRebuilds=" + harness.rebuilds
        + " ofSteps=" + harness.queries.length)
      if (harness.worstDelegates <= 0)
        console.log("PERF-FAIL no rows were found -- the list never rendered")
      else if (harness.worstDelegates > harness.maxLiveDelegates)
        console.log("PERF-FAIL " + harness.worstDelegates + " live row delegates at "
          + harness.itemCount + " items exceeds the limit of " + harness.maxLiveDelegates)
      else if (!survived)
        console.log("PERF-FAIL a subtitle clock tick destroyed and rebuilt the rows")
      else
        console.log("PERF-PASS " + harness.worstDelegates + " live row delegates at "
          + harness.itemCount + " items, rows survive a clock tick")
      console.log("HARNESS-DONE")
      Qt.quit()
    }
  }

  Timer {
    id: stepTimer
    interval: 250
    repeat: false
    onTriggered: harness.measure()
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
        // Recents on: without them every subtitle takes the "created <date>"
        // branch, which never reads the clock, and the very dependency this
        // harness exists to measure is not present.
        settings: ({showRecents: true, keybinds: "", excludeVaults: "",
                    clipboardClearSeconds: 45, pasteOnce: false})
      }
    }
  }

  Timer {
    id: startTimer
    interval: 1500
    repeat: false
    onTriggered: {
      harness.panelRoot.open()
      fillTimer.restart()
    }
  }

  Timer {
    id: fillTimer
    interval: 800
    repeat: false
    onTriggered: {
      var keyboardPanel = harness.findChild(plugin, function(c) {
        return c.focusTarget !== undefined && c.contentItem !== undefined
      })
      harness.service = harness.findChild(plugin, function(c) {
        return c.displayItems !== undefined && c.state !== undefined
      })
      harness.content = keyboardPanel && keyboardPanel.contentItem.length > 0
        ? keyboardPanel.contentItem[0] : null
      if (!harness.content || !harness.service || !plugin.opened) {
        console.log("PERF-SETUP-FAILED panel=" + (harness.content !== null)
          + " service=" + (harness.service !== null)
          + " opened=" + plugin.opened)
        console.log("HARNESS-DONE")
        Qt.quit()
        return
      }
      harness.service.state = "READY"
      harness.service.items = harness.buildItems()
      var now = Math.floor(Date.now() / 1000)
      var recents = []
      for (var r = 0; r < 8; r++)
        recents.push({shareId: "share_a", itemId: "item_" + r, ts: now - 3600 * (r + 1)})
      harness.service.recents = recents
      settleTimer.restart()
    }
  }

  // The list needs a few frames to build whatever it is going to build; giving
  // an eager list less time than it needs would flatter it.
  Timer {
    id: settleTimer
    interval: 3000
    repeat: false
    onTriggered: harness.measure()
  }

  Component.onCompleted: {
    panelRoot = plugin
    plugin.open()
    startTimer.start()
  }
}
