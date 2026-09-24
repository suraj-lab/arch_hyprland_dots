import QtQuick
import "../theme"

// Bar chip: shown while Caffeine is keeping the screens awake. Click to turn off.
Item {
    id: root
    property color barAccent: "#00ffea"
    property bool active: false
    signal clicked()

    implicitWidth: Math.max(24, label.implicitWidth)
    implicitHeight: 24
    visible: active
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Turn off Caffeine"
    Accessible.onPressAction: clicked()
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Text {
        id: label
        anchors.centerIn: parent
        opacity: root.activeFocus ? 0.65 : 1
        text: ""   // nf-fa-coffee
        color: Theme.warning
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
