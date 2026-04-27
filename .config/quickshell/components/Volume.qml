import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../theme"

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight - Theme.barPadding * 2
    property bool popupOpen: false

    property real vol: 0
    property bool isMuted: false

    // ── Read volume via wpctl ──────────────────────────────────────────────
    function refreshVolume() { getVolumeProc.running = true }

    Process {
        id: getVolumeProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                // Output: "Volume: 0.50" or "Volume: 0.50 [MUTED]"
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

    // ── Write volume/mute via wpctl ────────────────────────────────────────
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

    // ── Bar chip ───────────────────────────────────────────────────────────
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
            color: hover.containsMouse ? Theme.success : Theme.accent
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
            if (mouse.button === Qt.LeftButton) popupOpen = !popupOpen
            else toggleMute()
        }
        onWheel: wheel => {
            var step = wheel.angleDelta.y / 120 * 0.05  // 5% per wheel notch
            setVolume(root.vol + step)
        }
    }

    // ── Popup focus grab ────────────────────────────────────────────────────
    HyprlandFocusGrab {
        id: volGrab
        windows: [volPopup]
        active: false
        onCleared: popupOpen = false
    }

    Timer {
        id: volGrabDelay
        interval: 50
        onTriggered: volGrab.active = popupOpen
    }

    onPopupOpenChanged: {
        if (popupOpen) volGrabDelay.restart()
        else { volGrabDelay.stop(); volGrab.active = false }
    }

    // ── Popup ──────────────────────────────────────────────────────────────
    PopupWindow {
        id: volPopup
        visible: popupOpen
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth: 220
        implicitHeight: col.implicitHeight + 24
        color: Theme.popupBg

        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.color: Theme.border; border.width: 1; radius: Theme.popupRadius

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: Theme.popupPadding }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf028  Volume"; color: Theme.text; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Math.round(root.vol * 100) + "%"
                        color: root.isMuted ? Theme.error : Theme.accent
                        font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 8; radius: 4; color: Theme.trackBg
                    Rectangle {
                        width: parent.width * Math.min(1.0, root.vol)
                        height: parent.height; radius: 4
                        color: root.isMuted ? Theme.mutedSlider : Theme.accent
                        Behavior on width  { NumberAnimation  { duration: Theme.animNormal } }
                        Behavior on color  { ColorAnimation   { duration: Theme.animMedium } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            setVolume(mouse.x / parent.width)
                        }
                        onPositionChanged: mouse => {
                            if (pressed) setVolume(mouse.x / parent.width)
                        }
                    }
                }

                Text {
                    visible: root.vol > 1.0
                    text: "\u26a0  Above 100%"; color: Theme.warning
                    font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 8
                        color: root.isMuted ? Theme.errorBg : Theme.surface
                        border.color: root.isMuted ? Theme.errorBorder : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        Text {
                            anchors.centerIn: parent
                            text: root.isMuted ? "\uf6a9  Unmute" : "\uf028  Mute"
                            color: root.isMuted ? Theme.error : Theme.text
                            font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: toggleMute()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 8
                        color: mixH.containsMouse ? Theme.surfaceHover : Theme.surface
                        border.color: Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text { anchors.centerIn: parent; text: "\uf1de  Mixer"; color: Theme.purple; font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily }
                        MouseArea {
                            id: mixH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Hyprland.dispatch("exec [float;size 40% 90%;move 60% 5%] pavucontrol")
                                popupOpen = false
                            }
                        }
                    }
                }
            }
        }
    }
}
