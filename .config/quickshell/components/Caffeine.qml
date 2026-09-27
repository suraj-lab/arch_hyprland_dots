import QtQuick
import "../theme"

// Bar chip for Caffeine. Classic shows it only while Caffeine is on (`active`); the pill bar
// always shows it and dims it while off (`on`). Click toggles.
Item {
    id: root
    property color barAccent: "#00ffea"
    property bool active: false
    property bool on: true
    signal clicked()

    implicitWidth: Math.max(24, label.implicitWidth)
    implicitHeight: 24
    visible: active
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: on ? "Turn off Caffeine" : "Turn on Caffeine"
    Accessible.onPressAction: clicked()
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Text {
        id: label
        anchors.centerIn: parent
        opacity: root.activeFocus ? 0.65 : 1
        text: ""   // nf-fa-coffee
        color: root.on ? Theme.warning : Theme.textDimmer
        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
