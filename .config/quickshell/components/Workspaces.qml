import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../theme"

RowLayout {
    spacing: 4
    property string screenName: ""

    Repeater {
        model: [1, 2, 3, 4, 5]

        Rectangle {
            required property int modelData

            property var ws: {
                Hyprland.workspaces.count
                return Hyprland.workspaces.values.find(w =>
                    w.id === modelData &&
                    (screenName === "" || (w.monitor && w.monitor.name === screenName))
                ) ?? null
            }

            width: Theme.wsSize; height: Theme.wsSize
            radius: Theme.wsRadius

            color: ws && ws.focused  ? Theme.accent
                 : ws && ws.active   ? Theme.wsActive
                 : ws && ws.toplevels.count > 0 ? Theme.wsOccupied
                 : "transparent"

            border.color: ws && ws.focused ? Theme.accentGlow : Theme.border
            border.width: 1

            Behavior on color       { ColorAnimation  { duration: Theme.animMedium } }
            Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }

            scale: ws && ws.focused ? 1.1 : (hover.containsMouse ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            Text {
                anchors.centerIn: parent
                text: parent.modelData
                color: parent.ws && parent.ws.focused ? Theme.textDark : Theme.text
                font.pixelSize: Theme.fontBar
                font.bold: true
                font.family: Theme.fontFamily
                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (parent.ws) parent.ws.activate()
                    else Hyprland.dispatch("workspace " + parent.modelData)
                }
            }
        }
    }
}
