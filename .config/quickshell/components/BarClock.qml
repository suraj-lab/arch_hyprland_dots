import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"
import "../services"

Item {
    id: root
    implicitWidth: clockText.implicitWidth
    implicitHeight: clockText.implicitHeight
    scale: hover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    property bool popupOpen: false
    property color barAccent: "#00ffea"
    property var parentWindow: null   // bar PanelWindow: clicking the clock must toggle, not clear+reopen

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Day name from date string "YYYY-MM-DD"
    function dayName(dateStr) {
        var d = new Date(dateStr + "T12:00:00")
        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[d.getDay()]
    }

    // ── Bar display ────────────────────────────────────────────────────────
    Text {
        id: clockText
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: hover.containsMouse ? root.barAccent : Theme.text
        font.pixelSize: Theme.fontXl
        font.bold: true
        font.family: Theme.fontFamily
        Behavior on color { ColorAnimation { duration: Theme.animMedium } }

        onTextChanged: clockFade.restart()
        SequentialAnimation {
            id: clockFade
            NumberAnimation { target: clockText; property: "opacity"; to: 0.0; duration: 80 }
            NumberAnimation { target: clockText; property: "opacity"; to: 1.0; duration: 150 }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popupOpen = !popupOpen
    }

    // ── Focus grab ─────────────────────────────────────────────────────────
    property bool _grabReady: false

    HyprlandFocusGrab {
        id: calGrab
        windows: root.parentWindow ? [calPopup, root.parentWindow] : [calPopup]
        active: popupOpen && root._grabReady
        onCleared: popupOpen = false
    }

    Timer {
        id: calGrabDelay
        interval: 50
        onTriggered: root._grabReady = true
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            viewMonth = clock.date.getMonth()
            viewYear = clock.date.getFullYear()
            calGrabDelay.restart()
            Weather.refreshIfStale()
        } else {
            root._grabReady = false
            calGrabDelay.stop()
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

        implicitWidth: 290
        implicitHeight: calCol.implicitHeight + Theme.popupPadding * 2
        color: Theme.popupBg

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.border; border.width: 1
            radius: Theme.popupRadius

            scale: popupOpen ? 1.0 : 0.95
            opacity: popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

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
                            color: prevMonH.containsMouse ? root.barAccent : Theme.textDim
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
                            color: nextMonH.containsMouse ? root.barAccent : Theme.textDim
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
                            color: isToday ? root.barAccent : "transparent"

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

                // ── Weather section ────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Theme.borderLight
                    Layout.topMargin: 6
                }

                // Error state
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: Weather.error && !Weather.loaded
                    Layout.topMargin: 4

                    Text {
                        anchors.centerIn: parent
                        text: "Weather unavailable"
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSm
                        font.family: Theme.fontFamily
                    }
                }

                // Loading state
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    visible: !Weather.loaded && !Weather.error
                    Layout.topMargin: 4

                    Text {
                        anchors.centerIn: parent
                        text: "\uf110  Loading..."
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSm
                        font.family: Theme.fontFamily
                    }
                }

                // Current weather
                Item {
                    Layout.fillWidth: true
                    implicitHeight: currentRow.implicitHeight
                    visible: Weather.loaded
                    Layout.topMargin: 4
                    Layout.leftMargin: 4; Layout.rightMargin: 4

                    RowLayout {
                        id: currentRow
                        anchors { left: parent.left; right: parent.right }
                        spacing: 10

                        // Weather icon
                        Text {
                            text: Weather.icon(Weather.code)
                            font.pixelSize: 28
                            font.family: Theme.fontFamily
                            color: {
                                var c = parseInt(Weather.code)
                                if (c === 113) return Theme.warning    // sunny = warm
                                if (c === 116) return root.barAccent     // partly cloudy
                                if (c === 200 || c >= 386) return Theme.purple  // thunder
                                if (c >= 176 && c <= 314) return Theme.network // rain = blue-ish
                                if ((c >= 317 && c <= 350) || c === 179 || c === 227 || c === 230) return "#cdd6f4" // snow = white
                                return Theme.textDim
                            }
                        }

                        // Temp + description
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true

                            Text {
                                text: Weather.temp + "\u00b0C"
                                font.pixelSize: 22; font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.text
                            }
                            Text {
                                text: Weather.desc
                                font.pixelSize: 9
                                font.family: Theme.fontFamily
                                color: Theme.textFaint
                            }
                        }

                        // Details column
                        ColumnLayout {
                            spacing: 1
                            Layout.alignment: Qt.AlignRight

                            Text {
                                text: "Feels " + Weather.feels + "\u00b0"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: Theme.textDimmer
                                Layout.alignment: Qt.AlignRight
                            }
                            Text {
                                text: "Humid " + Weather.humidity + "%"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: Theme.textDimmer
                                Layout.alignment: Qt.AlignRight
                            }
                            Text {
                                text: "Wind " + Weather.wind + "km/h"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: Theme.textDimmer
                                Layout.alignment: Qt.AlignRight
                            }
                        }
                    }
                }

                // 3-day forecast
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                    Layout.topMargin: 4
                    spacing: 4
                    visible: Weather.loaded && Weather.forecastDays.length > 0

                    Repeater {
                        model: Weather.forecastDays.length

                        Rectangle {
                            property var day: Weather.forecastDays[index] || ({})

                            Layout.fillWidth: true
                            implicitHeight: fcCol.implicitHeight + 12
                            radius: 8
                            color: Theme.surface
                            border.color: fcHover.containsMouse
                                          ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.06)
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                            MouseArea {
                                id: fcHover
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            ColumnLayout {
                                id: fcCol
                                anchors {
                                    horizontalCenter: parent.horizontalCenter
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 2

                                Text {
                                    text: day.date ? root.dayName(day.date) : ""
                                    font.pixelSize: 8; font.bold: true
                                    font.family: Theme.fontFamily
                                    color: Theme.textFaint
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: day.code ? Weather.icon(day.code) : ""
                                    font.pixelSize: 16
                                    font.family: Theme.fontFamily
                                    color: Theme.textDim
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: (day.high || "") + "\u00b0"
                                    font.pixelSize: 10; font.bold: true
                                    font.family: Theme.fontFamily
                                    color: Theme.text
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: (day.low || "") + "\u00b0"
                                    font.pixelSize: 9
                                    font.family: Theme.fontFamily
                                    color: Theme.textFaint
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }

                // Location line
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4; Layout.rightMargin: 4
                    Layout.topMargin: 2; Layout.bottomMargin: 2
                    visible: Weather.loaded

                    Text {
                        text: "London, GB"
                        font.pixelSize: 8; font.family: Theme.fontFamily
                        color: Theme.textGhost
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "wttr.in"
                        font.pixelSize: 8; font.family: Theme.fontFamily
                        color: Theme.textGhost
                    }
                }
            }
        }
    }
}
