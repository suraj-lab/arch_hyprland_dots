import QtQuick
import Quickshell.Io
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // Only visible when gamemoded is active
    property bool active: false
    visible: active

    Text {
        id: label
        text: "\uf11b"
        color: root.barAccent
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
    }

    Process {
        id: proc
        command: ["bash", "-c", "gamemoded -s 2>/dev/null | grep -c 'Daemon is active' || echo 0"]
        running: true
        stdout: SplitParser {
            onRead: data => { root.active = parseInt(data.trim()) > 0 }
        }
    }

    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: { proc.running = false; proc.running = true }
    }
}
