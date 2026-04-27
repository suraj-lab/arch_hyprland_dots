import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../theme"

Item {
    id: root
    anchors.fill: parent

    // ── State ──────────────────────────────────────────────────────────────
    property real volume: 0
    property real prevVolume: -1
    property bool muted: false
    property bool prevMuted: false
    property bool osdVisible: false

    // ── Show/hide logic ────────────────────────────────────────────────────
    function showOSD() {
        osdVisible = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: Theme.osdHideDelay
        onTriggered: osdVisible = false
    }

    // ── Volume polling (wpctl) ─────────────────────────────────────────────
    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                var match = data.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (!match) return
                var newVol = parseFloat(match[1])
                var newMuted = !!match[2]

                root.volume = newVol
                root.muted = newMuted

                // Detect changes (skip initial read)
                if (root.prevVolume >= 0) {
                    if (Math.abs(newVol - root.prevVolume) > 0.005 || newMuted !== root.prevMuted)
                        root.showOSD()
                }
                root.prevVolume = newVol
                root.prevMuted = newMuted
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: volProc.running = true
    }

    Component.onCompleted: volProc.running = true

    // ── Visual ─────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: osdVisible ? Theme.osdBottomMargin : Theme.osdBottomMargin - 20
        width: Theme.osdWidth
        height: Theme.osdHeight
        radius: Theme.osdRadius
        color: Theme.popupBg
        border.color: Theme.border
        border.width: 1
        opacity: osdVisible ? 1.0 : 0.0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 18
                rightMargin: 18
            }
            spacing: 14

            // Icon
            Text {
                text: {
                    if (root.muted) return "\uf6a9"
                    if (root.volume > 0.5) return "\uf028"
                    if (root.volume > 0) return "\uf027"
                    return "\uf026"
                }
                color: root.muted ? Theme.error : Theme.accent
                font.pixelSize: 18
                font.family: Theme.fontFamily
            }

            // Progress bar
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Theme.trackBg

                Rectangle {
                    width: parent.width * Math.min(1.0, root.muted ? 0 : root.volume)
                    height: parent.height
                    radius: 3
                    color: root.muted ? Theme.error : Theme.accent
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // Percentage
            Text {
                text: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
                color: root.muted ? Theme.error : Theme.accent
                font.pixelSize: Theme.fontBar
                font.bold: true
                font.family: Theme.fontFamily
                Layout.minimumWidth: 48
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
