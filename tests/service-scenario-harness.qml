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
      console.log("HARNESS-DONE")
      Qt.quit()
    }
  }

  Component.onCompleted: harness.next()
}
