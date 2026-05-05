import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    property string screenName: ""

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // ── Workspace pill row ───────────────────────────────────────────────
    Row {
        id: row
        spacing: 3

        Repeater {
            model: [1, 2, 3, 4, 5]

            Item {
                id: pillContainer
                required property int modelData

                height: Theme.barHeight - Theme.barPadding * 2
                width: pill.width
                clip: false

                property var ws: {
                    Hyprland.workspaces.count
                    return Hyprland.workspaces.values.find(function(w) {
                        return w.id === modelData &&
                            (root.screenName === "" ||
                             (w.monitor && w.monitor.name === root.screenName))
                    }) ?? null
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

                    border.color: ws && ws.focused
                        ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.45)
                        : ws && ws.toplevels.count > 0 ? Theme.borderLight
                        : Theme.borderMuted
                    border.width: 1

                    Behavior on width        { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    Behavior on color        { ColorAnimation  { duration: Theme.animMedium } }
                    Behavior on border.color { ColorAnimation  { duration: Theme.animMedium } }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function() {
                            if (pillContainer.ws) pillContainer.ws.activate()
                            else Hyprland.dispatch("workspace " + pillContainer.modelData)
                        }
                    }
                }
            }
        }
    }
}
