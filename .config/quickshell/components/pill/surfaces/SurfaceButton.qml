import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Text button used by the small surfaces (updates, network, bluetooth).
Rectangle {
    id: button
    property string label
    property bool primary: false
    property color accent: Theme.accent
    signal clicked()
    Layout.fillWidth: true
    Layout.preferredHeight: 34
    radius: 10
    opacity: enabled ? 1 : 0.4
    color: primary ? Qt.rgba(accent.r, accent.g, accent.b, mouse.containsMouse ? 0.25 : 0.15)
                   : mouse.containsMouse ? Theme.surfaceHover : Theme.surface
    border.width: 1
    border.color: primary ? Qt.rgba(accent.r, accent.g, accent.b, 0.4) : Theme.borderMuted
    Text {
        anchors.centerIn: parent
        text: button.label
        color: button.primary ? button.accent : Theme.text
        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
}
