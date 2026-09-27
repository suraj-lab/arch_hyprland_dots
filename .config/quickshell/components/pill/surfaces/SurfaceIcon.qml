import QtQuick
import "../../../theme"

// Small icon button for the surfaces (rescan, show password): 28 px target, hover background.
// `spinning` turns the glyph (a refresh in progress); it finishes its turn when it stops.
Rectangle {
    id: icon
    property string glyph
    property color accent: Theme.accent
    property bool spinning: false
    signal clicked()
    implicitWidth: 28
    implicitHeight: 28
    radius: 8
    color: mouse.containsMouse ? Theme.surfaceHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Text {
        anchors.centerIn: parent
        text: icon.glyph
        color: mouse.containsMouse || icon.spinning ? icon.accent : Theme.textDim
        font { family: Theme.fontFamily; pixelSize: 14 }
        RotationAnimation on rotation {
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
            running: icon.spinning
            alwaysRunToEnd: true
        }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: icon.clicked() }
}
