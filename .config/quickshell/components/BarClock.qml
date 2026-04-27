import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"

Item {
    id: root
    implicitWidth: clockText.implicitWidth
    implicitHeight: clockText.implicitHeight
    property bool popupOpen: false

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── Bar display ────────────────────────────────────────────────────────
    Text {
        id: clockText
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: hover.containsMouse ? Theme.accent : Theme.text
        font.pixelSize: Theme.fontXl
        font.bold: true
        font.family: Theme.fontFamily
        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popupOpen = !popupOpen
    }

    // ── Focus grab ─────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        id: calGrab
        windows: [calPopup]
        active: false
        onCleared: popupOpen = false
    }

    Timer {
        id: calGrabDelay
        interval: 50
        onTriggered: calGrab.active = popupOpen
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            // Reset to current month when opening
            viewMonth = clock.date.getMonth()
            viewYear = clock.date.getFullYear()
            calGrabDelay.restart()
        } else {
            calGrabDelay.stop()
            calGrab.active = false
        }
    }

    // ── Calendar state ─────────────────────────────────────────────────────
    property int viewMonth: clock.date.getMonth()
    property int viewYear: clock.date.getFullYear()

    property var monthNames: ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]

    function navMonth(dir) {
        var m = viewMonth + dir
        if (m > 11) { viewMonth = 0; viewYear++ }
        else if (m < 0) { viewMonth = 11; viewYear-- }
        else { viewMonth = m }
    }

    // Calendar helpers
    property int calOffset: {
        var d = new Date(viewYear, viewMonth, 1).getDay()
        return d === 0 ? 6 : d - 1  // Monday-start
    }
    property int calDays: new Date(viewYear, viewMonth + 1, 0).getDate()
    property bool isCurrentMonth: viewYear === clock.date.getFullYear() && viewMonth === clock.date.getMonth()
    property int today: clock.date.getDate()

    // ── Popup ──────────────────────────────────────────────────────────────
    PopupWindow {
        id: calPopup
        visible: popupOpen
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth: 280
        implicitHeight: calCol.implicitHeight + Theme.popupPadding * 2
        color: Theme.popupBg

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.border; border.width: 1
            radius: Theme.popupRadius

            ColumnLayout {
                id: calCol
                anchors { fill: parent; margins: Theme.popupPadding }
                spacing: 8

                // ── Month navigation ────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true

                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: prevMonH.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "\uf053"
                            color: prevMonH.containsMouse ? Theme.accent : Theme.textDim
                            font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }
                        MouseArea {
                            id: prevMonH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: navMonth(-1)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.monthNames[root.viewMonth] + " " + root.viewYear
                        color: Theme.text
                        font.pixelSize: Theme.fontBar; font.bold: true
                        font.family: Theme.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: nextMonH.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "\uf054"
                            color: nextMonH.containsMouse ? Theme.accent : Theme.textDim
                            font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }
                        MouseArea {
                            id: nextMonH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: navMonth(1)
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderLight }

                // ── Day-of-week header ──────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 0
                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            Layout.fillWidth: true; text: modelData
                            color: Theme.textFaint; font.pixelSize: Theme.fontSm
                            font.bold: true; font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // ── Calendar grid ───────────────────────────────────
                Grid {
                    id: calGrid
                    columns: 7; spacing: 2; Layout.fillWidth: true

                    Repeater {
                        model: 42
                        Rectangle {
                            property int day: index - root.calOffset + 1
                            property bool isToday: root.isCurrentMonth && day === root.today
                            property bool isValid: day >= 1 && day <= root.calDays
                            property bool isWeekend: index % 7 >= 5

                            width: (calGrid.width - 12) / 7; height: 24; radius: 6
                            color: isToday ? Theme.accent : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: parent.isValid ? parent.day : ""
                                color: {
                                    if (parent.isToday) return Theme.textDark
                                    if (!parent.isValid) return "transparent"
                                    if (parent.isWeekend) return Theme.textFaint
                                    return Theme.text
                                }
                                font.pixelSize: Theme.fontSm
                                font.bold: parent.isToday
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }
        }
    }
}
