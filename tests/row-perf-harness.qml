// Row-model cost harness: fills the panel with a synthetic 500-item vault and
// measures what typing actually costs, and whether the clock tick throws the
// list away.
//
// Two numbers matter:
//   type   -- wall time to apply a query and re-lay out the list.
//   churn  -- whether the delegate objects survive a subtitle clock tick. If
//             the rows carry a precomputed subtitle, ticking the clock builds a
//             new array and every delegate in the list is destroyed and rebuilt;
//             if the subtitle is a delegate binding, the same objects stay put
//             and only the text re-evaluates.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
  id: harness

  readonly property int itemCount: 500
  readonly property var queries: ["", "l", "lo", "log", "logi", "login", "login 4", "login 42", ""]

  property var panelRoot: null
  property var keyboardPanel: null
  property var service: null
  property var content: null
  property var listColumn: null
  property int step: -1
  property var lastFirstRow: null
  property int rebuilds: 0

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

  // The deepest Column holding the rows, found by shape so the harness does not
  // depend on internal ids.
  function findListColumn() {
    var best = null
    function walk(item, depth) {
      if (!item) return
      if (String(item).indexOf("QQuickColumn") === 0 && item.children.length > 20)
        best = item
      var kids = item.children
      for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1)
    }
    walk(content, 0)
    return best
  }

  function firstRow() {
    var column = findListColumn()
    if (!column) return null
    for (var i = 0; i < column.children.length; i++) {
      var child = column.children[i]
      if (child && child.modelData !== undefined) return child
    }
    return null
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
    // Force the whole chain to settle before reading the clock: the row count
    // makes the filter run, and the delegate count makes the Repeater actually
    // build them. content.implicitHeight is useless here -- the key catcher
    // fills its parent and never reports a content-driven height.
    var visible = svc.allRows.length
    var column = findListColumn()
    var delegates = column ? column.children.length : -1
    var height = column ? column.implicitHeight : 0
    var elapsed = Date.now() - started
    // Identity, not count: a rebuilt list has the same number of delegates as
    // a reused one. Only the object tells you which happened.
    var current = firstRow()
    var reused = harness.lastFirstRow !== null && current === harness.lastFirstRow
    if (!reused) harness.rebuilds++
    harness.lastFirstRow = current
    console.log("PERF type query=" + JSON.stringify(queries[step])
      + " visible=" + visible
      + " delegates=" + delegates
      + " ms=" + elapsed
      + " rowReused=" + reused
      + " height=" + Math.round(height))
    stepTimer.restart()
  }

  function churn() {
    service.query = ""
    var before = firstRow()
    var beforeCount = service.allRows.length
    var column = findListColumn()
    var started = Date.now()
    service.refreshSubtitleNow()
    var delegates = column ? column.children.length : -1
    var height = column ? column.implicitHeight : 0
    var elapsed = Date.now() - started
    // A Repeater rebuild triggered by a model change lands on a later event
    // loop turn, so reading the delegate back synchronously would report a
    // survivor either way. Look again once the frame has gone through.
    harness.tickBefore = before
    harness.tickRows = beforeCount
    harness.tickDelegates = delegates
    harness.tickMs = elapsed
    tickCheckTimer.restart()
  }

  property var tickBefore: null
  property int tickRows: 0
  property int tickDelegates: 0
  property int tickMs: 0

  Timer {
    id: tickCheckTimer
    interval: 250
    repeat: false
    onTriggered: {
      var after = harness.firstRow()
      console.log("PERF tick rows=" + harness.tickRows
        + " delegates=" + harness.tickDelegates
        + " ms=" + harness.tickMs
        + " delegateSurvived=" + (harness.tickBefore !== null && harness.tickBefore === after))
      console.log("PERF summary listRebuilds=" + harness.rebuilds
        + " ofSteps=" + harness.queries.length)
      console.log("HARNESS-DONE")
      Qt.quit()
    }
  }

  Timer {
    id: stepTimer
    interval: 90
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
      harness.panelRoot = plugin
      harness.keyboardPanel = harness.findChild(plugin, function(c) {
        return c.focusTarget !== undefined && c.contentItem !== undefined
      })
      harness.service = harness.findChild(plugin, function(c) {
        return c.displayItems !== undefined && c.state !== undefined
      })
      harness.content = harness.keyboardPanel && harness.keyboardPanel.contentItem.length > 0
        ? harness.keyboardPanel.contentItem[0] : null
      if (!harness.content || !harness.service || !plugin.opened) {
        console.log("PERF-SETUP-FAILED")
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

  Timer {
    id: settleTimer
    interval: 700
    repeat: false
    onTriggered: harness.measure()
  }

  Component.onCompleted: {
    plugin.open()
    openTimer.start()
  }
}
