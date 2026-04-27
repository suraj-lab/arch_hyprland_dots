import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

Item {
    id: root
    property bool menuOpen: false
    function toggle() { root.menuOpen = !root.menuOpen }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: root.menuOpen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.65)
                opacity: root.menuOpen ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

                // Click outside to close
                MouseArea { anchors.fill: parent; onClicked: root.menuOpen = false }

                // Centered card
                Rectangle {
                    anchors.centerIn: parent
                    width: 560; height: 200
                    radius: 20
                    color: Theme.popupBg
                    border.color: Theme.border; border.width: 1
                    scale: root.menuOpen ? 1.0 : 0.88
                    Behavior on scale { NumberAnimation { duration: Theme.animSlide; easing.type: Easing.OutBack } }

                    MouseArea { anchors.fill: parent }  // block click-through

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 18

                        Text {
                            text: "Session"
                            color: Theme.text; font.pixelSize: Theme.fontXl
                            font.bold: true; font.family: Theme.fontFamily
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            spacing: 12; Layout.alignment: Qt.AlignHCenter

                            // ── Lock ──────────────────────────────────────
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: lkH.containsMouse ? Qt.rgba(0,1,0.92,0.15) : Theme.surface
                                border.color: lkH.containsMouse ? Qt.rgba(0,1,0.92,0.4) : Theme.borderMuted; border.width: 1
                                scale: lkH.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf023"; color: lkH.containsMouse ? Theme.accent : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                    Text { text: "Lock";   color: lkH.containsMouse ? Theme.accent : Theme.textDim;    font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                }
                                HoverHandler { id: lkH }
                                TapHandler { onTapped: { lkProc.running = true; root.menuOpen = false } }
                                Process { id: lkProc; command: ["loginctl", "lock-session"] }
                            }

                            // ── Logout ────────────────────────────────────
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: loH.containsMouse ? Qt.rgba(1,0.62,0.27,0.15) : Theme.surface
                                border.color: loH.containsMouse ? Qt.rgba(1,0.62,0.27,0.4) : Theme.borderMuted; border.width: 1
                                scale: loH.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf2f5"; color: loH.containsMouse ? Theme.warning : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                    Text { text: "Logout"; color: loH.containsMouse ? Theme.warning : Theme.textDim;    font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                }
                                HoverHandler { id: loH }
                                TapHandler { onTapped: { loProc.running = true; root.menuOpen = false } }
                                Process { id: loProc; command: ["hyprctl", "dispatch", "exit"] }
                            }

                            // ── Suspend ───────────────────────────────────
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: suH.containsMouse ? Qt.rgba(0.78,0.47,0.87,0.15) : Theme.surface
                                border.color: suH.containsMouse ? Qt.rgba(0.78,0.47,0.87,0.4) : Theme.borderMuted; border.width: 1
                                scale: suH.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf186"; color: suH.containsMouse ? Theme.purple : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                    Text { text: "Suspend"; color: suH.containsMouse ? Theme.purple : Theme.textDim;   font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                }
                                HoverHandler { id: suH }
                                TapHandler { onTapped: { suProc.running = true; root.menuOpen = false } }
                                Process { id: suProc; command: ["systemctl", "suspend"] }
                            }

                            // ── Reboot ────────────────────────────────────
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: rbH.containsMouse ? Qt.rgba(0.04,0.86,0.62,0.15) : Theme.surface
                                border.color: rbH.containsMouse ? Qt.rgba(0.04,0.86,0.62,0.4) : Theme.borderMuted; border.width: 1
                                scale: rbH.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf021"; color: rbH.containsMouse ? Theme.media : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                    Text { text: "Reboot"; color: rbH.containsMouse ? Theme.media : Theme.textDim;   font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                }
                                HoverHandler { id: rbH }
                                TapHandler { onTapped: { rbProc.running = true; root.menuOpen = false } }
                                Process { id: rbProc; command: ["systemctl", "reboot"] }
                            }

                            // ── Shutdown ──────────────────────────────────
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: sdH.containsMouse ? Qt.rgba(0.95,0.55,0.66,0.15) : Theme.surface
                                border.color: sdH.containsMouse ? Qt.rgba(0.95,0.55,0.66,0.4) : Theme.borderMuted; border.width: 1
                                scale: sdH.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf011"; color: sdH.containsMouse ? Theme.error : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                    Text { text: "Shutdown"; color: sdH.containsMouse ? Theme.error : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                                }
                                HoverHandler { id: sdH }
                                TapHandler { onTapped: { sdProc.running = true; root.menuOpen = false } }
                                Process { id: sdProc; command: ["systemctl", "poweroff"] }
                            }
                        }
                    }
                }

                Keys.onEscapePressed: root.menuOpen = false
                focus: root.menuOpen
            }
        }
    }
}
