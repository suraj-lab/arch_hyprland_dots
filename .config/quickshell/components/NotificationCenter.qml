import QtQuick
import QtQuick.Layouts
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    scale: bellMouse.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    signal chipClicked()
    signal panelOpened()

    property int  externalUnreadCount: 0
    property bool dndEnabled: false

    onExternalUnreadCountChanged: if (externalUnreadCount > 0) badgeBounce.restart()

    implicitWidth:  bellChip.implicitWidth + 8
    implicitHeight: bellChip.implicitHeight

    // ── Bell chip ────────────────────────────────────────────────────────────
    Item {
        id: bellChip
        anchors.centerIn: parent
        implicitWidth:  bellRow.implicitWidth
        implicitHeight: Theme.barHeight - Theme.barPadding * 2

        Row {
            id: bellRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: "\uf0f3"
                font.pixelSize: Theme.fontIcon
                font.family:    Theme.fontFamily
                color: bellMouse.containsMouse      ? root.barAccent
                     : root.externalUnreadCount > 0 ? Theme.purple
                     :                                Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
            }

            Rectangle {
                id: badge
                visible: root.externalUnreadCount > 0
                scale: 1.0
                width:   Math.max(16, badgeText.implicitWidth + 6)
                height:  14; radius: 7
                color:   Theme.error
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation {
                    id: badgeBounce
                    NumberAnimation { target: badge; property: "scale"; to: 1.4; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: badge; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                }

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.externalUnreadCount > 99 ? "99+" : root.externalUnreadCount.toString()
                    font.pixelSize: 9; font.bold: true
                    font.family:    Theme.fontFamily
                    color: "white"
                }
            }
        }

        MouseArea {
            id: bellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: {
                root.chipClicked()
                root.panelOpened()
            }
        }
    }
}
