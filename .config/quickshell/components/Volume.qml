import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight - Theme.barPadding * 2
    scale: hover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    signal chipClicked()

    property real vol: 0
    property bool isMuted: false

    // ── Read volume via wpctl ─────────────────────────────────────────────
    function refreshVolume() { getVolumeProc.running = true }

    Process {
        id: getVolumeProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                var match = data.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (match) {
                    root.vol = parseFloat(match[1])
                    root.isMuted = !!match[2]
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: refreshVolume()
    }

    Component.onCompleted: refreshVolume()

    // ── Write volume/mute via wpctl ───────────────────────────────────────
    Process {
        id: cmdProc
        onRunningChanged: { if (!running) refreshVolume() }
    }

    function runCmd(args) {
        cmdProc.command = args
        cmdProc.running = true
    }

    function setVolume(v) {
        var clamped = Math.max(0, Math.min(1.5, v)).toFixed(2)
        runCmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", clamped])
    }

    function toggleMute() {
        runCmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    }

    // ── Bar chip ──────────────────────────────────────────────────────────
    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            text: {
                if (root.isMuted) return "\uf6a9"
                var v = Math.round(root.vol * 100)
                return (v > 50 ? "\uf028" : "\uf027") + " " + v + "%"
            }
            color: hover.containsMouse ? Theme.success : root.barAccent
            font.pixelSize: Theme.fontIcon; font.bold: true; font.family: Theme.fontFamily
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) root.chipClicked()
            else toggleMute()
        }
        onWheel: wheel => {
            var step = wheel.angleDelta.y / 120 * 0.05
            setVolume(root.vol + step)
        }
    }
}
