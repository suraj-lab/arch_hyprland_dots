import QtQuick
import Quickshell
import "../../.config/quickshell/services"

// Loaded only by check-desktop-phase3.py in a scratch HOME, without a compositor.
ShellRoot {
    id: root
    property bool dndEnabled: true
    Binding { target: Desktop; property: "dndEnabled"; value: root.dndEnabled }
    Connections {
        target: Desktop
        function onDndRequested(enabled) { root.dndEnabled = enabled }
    }
    function report() {
        console.log("CONFIG " + JSON.stringify(Config.idle))
    }
    // Use the real singleton/bindings with harmless helper commands supplied by the runner.
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!Desktop._gameChecked) return
            console.log("DESKTOP " + JSON.stringify({
                lockSec: Desktop.lockTimeout, dpmsSec: Desktop.dpmsTimeout,
                suspendSec: Desktop.suspendTimeout, dnd: root.dndEnabled,
                backendDnd: Desktop.dndEnabled, gameMode: Desktop.gameMode
            }))
        }
    }
    Component.onCompleted: report()
    Connections {
        target: Config
        function onIdleChanged() { report() }
    }
}
