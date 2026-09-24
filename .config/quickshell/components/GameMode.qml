import QtQuick
import "../theme"

// Bar chip: shown while Desktop Game Mode is on (auto via gamemoded, or forced
// from the quick toggle). State comes from DesktopServices in shell.qml.
// Click to toggle (clicking while auto-on forces it off for this game session).
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
    Accessible.name: "Toggle Desktop Game Mode"
    Accessible.onPressAction: clicked()
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Text {
        id: label
        anchors.centerIn: parent
        opacity: root.activeFocus ? 0.65 : 1
        text: ""
        color: root.barAccent
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
