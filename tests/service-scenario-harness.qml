// Service state-machine harness: drives the real Service through the real
// helper against every mock scenario and prints the state it settles in.
//
// Each scenario gets a freshly constructed Service, so no case inherits
// another's state. The scenario is selected through a file the mock wrapper
// reads, because a process's environment is fixed once it starts.
//
// The final case is the invariant the audit names explicitly: an auth
// transition arriving while an index request is in flight must clear the model,
// and the in-flight response must not be able to repopulate it afterwards.
import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

ShellRoot {
  id: harness

  readonly property var scenarios: [
    "ready",
    "ready-multivault",
    "empty",
    "zero-logins",
    "zero-vaults",
    "locked",
    "logged-out",
    "expired",
    "offline",
    "malformed-vault-entry",
    "no-lock",
    "missing-cli"
  ]

  property int idx: -1
  property string settled: ""
  property int ticks: 0

  function svc() {
    return svcLoader.item
  }

  function observe() {
    var s = svc()
    if (!s) return "no-service"
    return "state=" + s.state
      + " items=" + s.items.length
      + " vaults=" + s.vaults.length
      + " warnings=" + s.warnings.length
      + " hasIndex=" + s.hasIndex
      + " refreshing=" + s.refreshing
      + " stale=" + s.staleWarning
      + " message=" + JSON.stringify(String(s.message))
  }

  Loader {
    id: svcLoader
    active: false
    sourceComponent: Component {
      Plugin.Service {
        settings: ({showRecents: true, excludeVaults: "", clipboardClearSeconds: 45, pasteOnce: false})
      }
    }
  }

  Process {
    id: scenarioWriter
    onExited: {
      svcLoader.active = false
      svcLoader.active = true
      harness.settled = ""
      harness.ticks = 0
      startTimer.restart()
    }
  }

  Timer {
    id: startTimer
    interval: 150
    repeat: false
    onTriggered: {
      harness.svc().onPanelOpened()
      settleTimer.restart()
    }
  }

  // Settle by observation, not by a fixed delay: the doctor call, the recents
  // load and the index each land at their own pace.
  Timer {
    id: settleTimer
    interval: 200
    repeat: false
    onTriggered: {
      var now = harness.observe()
      harness.ticks++
      if (now === harness.settled && harness.ticks > 3) {
        if (harness.idx >= harness.scenarios.length) {
          harness.runAuthCase()
          return
        }
        console.log("SCENARIO " + harness.scenarios[harness.idx] + " " + now)
        harness.next()
        return
      }
      harness.settled = now
      if (harness.ticks > 80) {
        console.log("SCENARIO "
          + (harness.idx < harness.scenarios.length ? harness.scenarios[harness.idx] : "auth-setup")
          + " UNSETTLED " + now)
        harness.next()
        return
      }
      settleTimer.restart()
    }
  }

  function next() {
    idx++
    var scenario = idx < scenarios.length ? scenarios[idx] : "ready"
    scenarioWriter.command = ["sh", "-c", "printf '%s' \"$1\" > \"$SCENARIO_FILE\"", "sh", scenario]
    scenarioWriter.running = true
  }

  function runAuthCase() {
    var s = svc()
    console.log("SCENARIO auth-before " + observe())
    // Start a refresh, then lock while that index request is still outstanding.
    s.refresh()
    s.lock()
    authTimer.restart()
  }

  Timer {
    id: authTimer
    interval: 3000
    repeat: false
    onTriggered: {
      console.log("SCENARIO auth-during-refresh " + harness.observe())
      harness.startLifecycle()
    }
  }

  // ---- index lifecycle cases ----------------------------------------------
  // These are pass/fail, not observations. They cover what the large-vault fix
  // promises: a fetch survives the panel closing, a reopen inside the freshness
  // window does not start a second one, and an explicit refresh -- here the one
  // a successful create issues -- fetches anyway.
  property string stage: ""
  property int stageTicks: 0
  property int indexCalls: 0
  property var afterCount: null

  function countIndexCalls(next) {
    afterCount = next
    logReader.command = ["sh", "-c", "grep -c '^index' \"$HELPER_LOG\" || true"]
    logReader.running = true
  }

  function lifecycleFail(label, detail) {
    console.log("LIFECYCLE-FAIL " + label + " " + detail + " " + observe())
    console.log("HARNESS-DONE")
    Qt.quit()
  }

  function startLifecycle() {
    stage = "loading-open"
    lifecycleWriter.command = ["sh", "-c",
      "printf '%s' \"$1\" > \"$SCENARIO_FILE\"; : > \"$HELPER_LOG\"", "sh", "slow-items"]
    lifecycleWriter.running = true
  }

  Process {
    id: logReader
    running: false
    command: []
    onExited: {
      harness.indexCalls = parseInt(String(logOutput.text).trim(), 10) || 0
      var next = harness.afterCount
      harness.afterCount = null
      if (next) next()
    }
    stdout: StdioCollector { id: logOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: lifecycleWriter
    running: false
    command: []
    onExited: {
      svcLoader.active = false
      svcLoader.active = true
      harness.stageTicks = 0
      lifecycleStart.restart()
    }
  }

  Timer {
    id: lifecycleStart
    interval: 200
    repeat: false
    onTriggered: {
      harness.svc().onPanelOpened()
      harness.stageTicks = 0
      lifecycleTimer.restart()
    }
  }

  Timer {
    id: lifecycleTimer
    interval: 200
    repeat: true
    running: false
    onTriggered: harness.lifecycleTick()
  }

  function lifecycleTick() {
    var s = svc()
    stageTicks++
    if (stageTicks > 150) {
      lifecycleTimer.running = false
      lifecycleFail(stage, "timed-out")
      return
    }

    if (stage === "loading-open") {
      // Wait for the fetch to actually be in flight before closing on it.
      if (s.state !== "LOADING") return
      s.onPanelClosed()
      stage = "closed-during-loading"
      stageTicks = 0
      return
    }

    if (stage === "closed-during-loading") {
      if (stageTicks < 3) return
      // Reopening must find the same fetch still running, not start another.
      s.onPanelOpened()
      stage = "reopened-during-loading"
      stageTicks = 0
      return
    }

    if (stage === "reopened-during-loading") {
      if (s.state !== "READY") return
      lifecycleTimer.running = false
      countIndexCalls(function() {
        if (harness.indexCalls !== 1 || !harness.svc().hasIndex) {
          harness.lifecycleFail("close-during-loading",
            "indexCalls=" + harness.indexCalls)
          return
        }
        console.log("SCENARIO close-during-loading indexCalls="
          + harness.indexCalls + " " + harness.observe())
        harness.stage = "fresh-close"
        harness.stageTicks = 0
        lifecycleTimer.running = true
      })
      return
    }

    if (stage === "fresh-close") {
      // A close and reopen with a fresh index in memory must not fetch again.
      s.onPanelClosed()
      s.onPanelOpened()
      stage = "fresh-reopened"
      stageTicks = 0
      return
    }

    if (stage === "fresh-reopened") {
      if (stageTicks < 6) return
      lifecycleTimer.running = false
      countIndexCalls(function() {
        if (harness.indexCalls !== 1) {
          harness.lifecycleFail("reopen-within-freshness-window",
            "indexCalls=" + harness.indexCalls)
          return
        }
        console.log("SCENARIO reopen-within-freshness-window indexCalls="
          + harness.indexCalls + " " + harness.observe())
        harness.startCreateCase()
      })
      return
    }

    if (stage === "create-ready") {
      if (s.state !== "READY" || !s.hasIndex) return
      if (!s.create("share_fixture_1", "Lifecycle Login", "username", "user@example.com")) {
        lifecycleTimer.running = false
        lifecycleFail("create-refetches", "create-refused")
        return
      }
      stage = "create-running"
      stageTicks = 0
      return
    }

    if (stage === "create-running") {
      if (s.createBusy) return
      if (stageTicks < 6) return
      lifecycleTimer.running = false
      countIndexCalls(function() {
        // The index was fresh, so only an explicit refresh can have fetched.
        if (harness.indexCalls !== 2) {
          harness.lifecycleFail("create-refetches",
            "indexCalls=" + harness.indexCalls)
          return
        }
        console.log("SCENARIO create-refetches indexCalls="
          + harness.indexCalls + " " + harness.observe())
        console.log("HARNESS-DONE")
        Qt.quit()
      })
      return
    }
  }

  function startCreateCase() {
    stage = "create-ready"
    lifecycleWriter.command = ["sh", "-c",
      "printf '%s' \"$1\" > \"$SCENARIO_FILE\"; : > \"$HELPER_LOG\"", "sh", "ready"]
    lifecycleWriter.running = true
  }

  Component.onCompleted: harness.next()
}
