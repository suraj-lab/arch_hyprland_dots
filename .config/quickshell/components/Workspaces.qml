import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../theme"

Row {
    id: root
    property color barAccent: "#00ffea"
    spacing: 3
    property string screenName: ""

    Repeater {
        model: [1, 2, 3, 4, 5]

        Item {
            required property int modelData

            // Full bar-height hit area, pill centered inside
            width: pill.width
            height: Theme.barHeight - Theme.barPadding * 2

            property var ws: {
                Hyprland.workspaces.count
                return Hyprland.workspaces.values.find(w =>
                    w.id === modelData &&
                    (root.screenName === "" || (w.monitor && w.monitor.name === root.screenName))
                ) ?? null
            }

            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter

                height: 10
                radius: 5

                width: ws && ws.focused  ? 32
                     : ws && ws.active   ? 22
                     : ws && ws.toplevels.count > 0 ? 16
                     : 10

                color: ws && ws.focused  ? root.barAccent
                     : ws && ws.active   ? Theme.wsActive
                     : ws && ws.toplevels.count > 0 ? Theme.wsOccupied
                     : "transparent"

                border.color: ws && ws.focused ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.45)
                            : ws && ws.toplevels.count > 0 ? Theme.borderLight
                            : Theme.borderMuted
                border.width: 1

                Behavior on width       { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                Behavior on color       { ColorAnimation  { duration: Theme.animMedium } }
                Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }
            }

            scale: hover.containsMouse ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

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
