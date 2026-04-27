import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../theme"

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

            Text { id: cpuText;  color: Theme.pink;    font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\ue266 --%"   }
            Text { id: memText;  color: Theme.warning; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\uf2db --%"   }
            Text { id: tempText; color: Theme.success; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; text: "\uf2c8 --°C" }
        }
    }

    onExpandedChanged: statsProc.running = expanded ? true : false

    Process {
        id: statsProc
        command: ["bash", "-c",
            "cpu=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}'); " +
            "mem=$(free | awk '/Mem/{printf \"%.0f\", $3/$2*100}'); " +
            "temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1); " +
            "echo \"${cpu:-0}|${mem:-0}|$((${temp:-0}/1000))\""
        ]
        stdout: SplitParser {
            onRead: data => {
                var p = data.split("|")
                if (p.length < 3) return
                cpuText.text  = "\ue266 " + p[0] + "%"
                memText.text  = "\uf2db " + p[1] + "%"
                tempText.text = "\uf2c8 " + p[2] + "°C"
            }
        }
    }

    Timer {
        interval: 3000
        running: expanded
        repeat: true
        onTriggered: { statsProc.running = false; statsProc.running = true }
    }
}
