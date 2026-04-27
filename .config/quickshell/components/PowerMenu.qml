import QtQuick
import "../theme"

// Emits clicked() — shell.qml connects it to sessionOpen toggle.
Item {
    id: root
    implicitWidth: 32
    implicitHeight: 32

    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: hover.containsMouse ? Theme.wsActive : "transparent"
        border.color: hover.containsMouse ? Theme.border : "transparent"
        border.width: 1
        Behavior on color        { ColorAnimation { duration: Theme.animMedium } }
        Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }
        scale: hover.containsMouse ? 1.1 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: "\uf011"
            color: hover.containsMouse ? Theme.pink : Theme.purple
            font.pixelSize: Theme.fontIcon
            font.family: Theme.fontFamily
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
