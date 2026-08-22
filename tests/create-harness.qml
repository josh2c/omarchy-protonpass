import Quickshell
import Quickshell.Io
import QtQuick
import "." as Local

ShellRoot {
  Local.Service {
    id: svc
    settings: ({})
    panelOpen: true
    onToastRequested: function(m) { console.log("TOAST:" + m) }
    onStateChanged: {
      console.log("STATE:" + state);
      if (state === "READY" && !createBusy) {
        var ok = svc.create("share_fixture_1", "Harness Login", "username", "harnessuser");
        console.log("CREATE-STARTED:" + ok);
      }
    }
    onCreateBusyChanged: if (!createBusy) { console.log("CREATE-DONE"); doneTimer.start(); }
    Component.onCompleted: refresh()
  }
  Timer { id: doneTimer; interval: 300; onTriggered: Qt.quit() }
  Timer { interval: 10000; running: true; onTriggered: { console.log("HANG-TIMEOUT"); Qt.quit(); } }
}
