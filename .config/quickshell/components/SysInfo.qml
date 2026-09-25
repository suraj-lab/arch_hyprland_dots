import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

RowLayout {
    spacing: Theme.barSpacing
    property bool expanded: false

    // Toggle icon
    Text {
        text: "\uf85a"
        color: Theme.pink
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
        scale: chipHover.containsMouse ? 1.15 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animNormal } }
        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: expanded = !expanded
        }
    }

    // Animated drawer
    Item {
        clip: true
        implicitHeight: drawer.implicitHeight
        implicitWidth: expanded ? drawer.implicitWidth : 0
        Behavior on implicitWidth {
            NumberAnimation { duration: Theme.animDrawer; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: drawer
            spacing: Theme.barSpacing
            opacity: expanded ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }

            Text { id: cpuText;  color: Theme.pink;    font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\ue266 " + (Sysmon.cpu < 0 ? "--" : Sysmon.cpu) + "%" }
            Text { id: memText;  color: Theme.warning; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\uf2db " + (Sysmon.mem < 0 ? "--" : Sysmon.mem) + "%" }
            Text { id: tempText; color: Theme.success; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\uf2c8 " + (Sysmon.temp < 0 ? "--" : Sysmon.temp) + "°C" }
        }
    }
}
