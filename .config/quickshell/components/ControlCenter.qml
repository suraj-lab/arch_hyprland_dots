import QtQuick
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: iconText.implicitWidth
    implicitHeight: iconText.implicitHeight
    scale: iconHover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    signal chipClicked()

    // ── Bar icon ──────────────────────────────────────────────────────────
    Text {
        id: iconText
        text: "\uf013"
        color: iconHover.containsMouse ? root.barAccent : Theme.purple
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
    }

    MouseArea {
        id: iconHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chipClicked()
    }
}
