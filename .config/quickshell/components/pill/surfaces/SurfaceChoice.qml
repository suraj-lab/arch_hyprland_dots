import QtQuick
import QtQuick.Layouts
import "../../../theme"

// Segmented choice for the surfaces: one option highlighted, a click picks another.
// options: [{ label, value }]; `value` is the current one (compared with ===).
Row {
    id: choice
    property var options: []
    property var value
    property color accent: Theme.accent
    signal chosen(var value)
    spacing: 4
    Repeater {
        model: choice.options
        Rectangle {
            id: opt
            required property var modelData
            readonly property bool on: choice.value === modelData.value
            objectName: "choice:" + modelData.label
            implicitWidth: label.implicitWidth + 20
            implicitHeight: 28
            radius: 8
            color: on ? Qt.rgba(choice.accent.r, choice.accent.g, choice.accent.b, 0.2)
                 : mouse.containsMouse ? Theme.surfaceHover : Theme.surface
            border.width: 1
            border.color: on ? Qt.rgba(choice.accent.r, choice.accent.g, choice.accent.b, 0.5) : Theme.borderMuted
            Text {
                id: label
                anchors.centerIn: parent
                text: opt.modelData.label
                color: opt.on ? choice.accent : Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm; bold: opt.on }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: choice.chosen(opt.modelData.value)
            }
        }
    }
}
