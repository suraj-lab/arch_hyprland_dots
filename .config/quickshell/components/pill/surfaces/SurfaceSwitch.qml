import QtQuick
import "../../../theme"

// On/off switch for the surfaces (Wi-Fi, Bluetooth power); a ring on hover.
Rectangle {
    id: sw
    property bool on: false
    property color accent: Theme.accent
    signal toggled()
    implicitWidth: 38
    implicitHeight: 22
    radius: 11
    color: on ? Qt.rgba(accent.r, accent.g, accent.b, 0.35) : Theme.surfaceHover
    border.width: 1
    border.color: mouse.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.7) : "transparent"
    Rectangle {
        width: 16; height: 16; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: sw.on ? parent.width - width - 3 : 3
        color: sw.on ? sw.accent : Theme.textDim
        Behavior on x { NumberAnimation { duration: Theme.animFast } }
    }
    MouseArea { id: mouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
}
