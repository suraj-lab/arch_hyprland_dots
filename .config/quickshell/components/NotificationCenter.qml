import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"

// Bar bell button + slide-down notification history panel.
// All state is managed by ShellRoot; this component is purely display + signals.

Item {
    id: root
    scale: bellMouse.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    property color barAccent: "#00ffea"

    // Passed from shellRoot.globalNotifModel — a ListModel with roles:
    // notifId, appName, summary, body, urgency, notifTime
    property var  notifModel:          null
    property int  externalUnreadCount: 0
    onExternalUnreadCountChanged: if (externalUnreadCount > 0) badgeBounce.restart()
    property bool dndEnabled:          false
    property bool popupOpen:           false

    // Signals — shell.qml handles the actual state mutations
    signal panelOpened()
    signal dismissRequested(int notifId)
    signal clearAllRequested()
    signal dndToggled()

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
                popupOpen = !popupOpen
                if (popupOpen) root.panelOpened()
            }
        }
    }

    // ── Focus grab ───────────────────────────────────────────────────────────
    property bool _grabReady: false

    HyprlandFocusGrab {
        id: notifGrab
        windows: [notifPopup]
        active: popupOpen && root._grabReady
        onCleared: popupOpen = false
    }
    Timer {
        id: notifGrabDelay
        interval: 50
        onTriggered: root._grabReady = true
    }
    onPopupOpenChanged: {
        if (popupOpen) notifGrabDelay.restart()
        else { root._grabReady = false; notifGrabDelay.stop() }
    }

    // ── Popup panel ──────────────────────────────────────────────────────────
    PopupWindow {
        id: notifPopup
        visible: popupOpen
        anchor.item:    root
        anchor.edges:   Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth:  380
        implicitHeight: panelCol.implicitHeight
        color: Theme.popupBg

        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.color: Theme.border; border.width: 1
            radius: Theme.popupRadius; clip: true

            scale: popupOpen ? 1.0 : 0.95
            opacity: popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            ColumnLayout {
                id: panelCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 0

                // ── Header ───────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14; Layout.rightMargin: 14
                    Layout.topMargin: 12; Layout.bottomMargin: 8
                    spacing: 8

                    Text {
                        text: "\uf0f3"
                        font.pixelSize: Theme.fontLg; font.family: Theme.fontFamily
                        color: Theme.purple
                    }
                    Text {
                        text: "Notifications"
                        font.pixelSize: Theme.fontLg; font.bold: true
                        font.family: Theme.fontFamily; color: Theme.text
                    }

                    // Count pill
                    Rectangle {
                        visible: (root.notifModel ? root.notifModel.count : 0) > 0
                        width:  Math.max(18, cntText.implicitWidth + 8)
                        height: 16; radius: 8
                        color: Qt.rgba(198/255, 120/255, 221/255, 0.18)
                        Text {
                            id: cntText
                            anchors.centerIn: parent
                            text: root.notifModel ? root.notifModel.count.toString() : "0"
                            font.pixelSize: 9; font.bold: true
                            font.family: Theme.fontFamily; color: Theme.purple
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // DND toggle
                    Rectangle {
                        width: 28; height: 22; radius: 6
                        color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.12) : Theme.surface
                        border.color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.35) : Theme.borderMuted
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        Text {
                            anchors.centerIn: parent
                            text: root.dndEnabled ? "\uf1f6" : "\uf0f3"
                            font.pixelSize: 11; font.family: Theme.fontFamily
                            color: root.dndEnabled ? Theme.error : Theme.textDimmer
                            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dndToggled()
                        }
                    }

                    // Clear All
                    Rectangle {
                        visible: (root.notifModel ? root.notifModel.count : 0) > 0
                        height: 22
                        implicitWidth: clearLbl.implicitWidth + 14
                        radius: 6
                        color: clrHover.containsMouse
                               ? Qt.rgba(0.95,0.55,0.66,0.12) : "transparent"
                        border.color: clrHover.containsMouse
                                      ? Qt.rgba(0.95,0.55,0.66,0.35) : Theme.borderMuted
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            id: clearLbl
                            anchors.centerIn: parent
                            text: "Clear All"
                            font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                            color: clrHover.containsMouse ? Theme.error : Theme.textDim
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }
                        MouseArea {
                            id: clrHover; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearAllRequested()
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Theme.borderLight
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                }

                // ── List / empty state ────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    implicitHeight: hasItems ? notifScroll.height : emptyBox.implicitHeight

                    readonly property bool hasItems:
                        root.notifModel != null && root.notifModel.count > 0

                    // Empty state
                    Item {
                        id: emptyBox
                        visible: !parent.hasItems
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        implicitHeight: 90
                        Column {
                            anchors.centerIn: parent; spacing: 6
                            Text {
                                text: "\uf0f3"; color: Theme.textGhost
                                font.pixelSize: 28; font.family: Theme.fontFamily
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: "No notifications"
                                color: Theme.textFaint; font.pixelSize: Theme.fontSm
                                font.family: Theme.fontFamily
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Scrollable list (max 400px)
                    Flickable {
                        id: notifScroll
                        visible: parent.hasItems
                        anchors { left: parent.left; right: parent.right }
                        height: Math.min(notifColumn.implicitHeight, 400)
                        implicitHeight: height
                        contentHeight: notifColumn.implicitHeight
                        clip: true

                        Column {
                            id: notifColumn
                            anchors { left: parent.left; right: parent.right }
                            anchors.margins: 10
                            topPadding: 8; bottomPadding: 8
                            spacing: 6

                            // model is a ListModel — delegate accesses roles via model.roleName
                            Repeater {
                                model: root.notifModel

                                Item {
                                    id: notifRow   // named so children can reference without parent chains
                                    width: notifColumn.width
                                    implicitHeight: notifCard.height

                                    readonly property color uc:
                                        model.urgency === 2 ? Theme.error  :
                                        model.urgency === 0 ? Theme.textFaint : Theme.purple

                                    readonly property string appIcon: {
                                        var n = (model.appName || "").toLowerCase()
                                        if (n.indexOf("firefox")    >= 0 || n.indexOf("chromium") >= 0) return "\uf738"
                                        if (n.indexOf("discord")    >= 0) return "\uf392"
                                        if (n.indexOf("spotify")    >= 0) return "\uf1bc"
                                        if (n.indexOf("telegram")   >= 0) return "\uf2c6"
                                        if (n.indexOf("slack")      >= 0) return "\uf198"
                                        if (n.indexOf("network")    >= 0 || n.indexOf("nm-") >= 0) return "\uf1eb"
                                        if (n.indexOf("battery")    >= 0) return "\uf241"
                                        if (n.indexOf("volume")     >= 0 || n.indexOf("audio") >= 0) return "\ufa7d"
                                        if (n.indexOf("screenshot") >= 0) return "\uf030"
                                        if (n.indexOf("update")     >= 0 || n.indexOf("system") >= 0) return "\uf013"
                                        return "\uf0f3"
                                    }

                                    Rectangle {
                                        id: notifCard
                                        width: parent.width
                                        height: cardContent.implicitHeight + 18
                                        radius: 10
                                        color: cardHover.containsMouse ? Theme.surfaceHover : Theme.surface
                                        border.color: notifRow.uc; border.width: 1
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                        Rectangle {
                                            width: 3; radius: 2
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 4 }
                                            color: notifRow.uc; opacity: 0.85
                                        }

                                        MouseArea { id: cardHover; anchors.fill: parent; hoverEnabled: true }

                                        RowLayout {
                                            id: cardContent
                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                            anchors.margins: 12; anchors.leftMargin: 16
                                            spacing: 10

                                            Text {
                                                text: notifRow.appIcon
                                                font.pixelSize: 17; font.family: Theme.fontFamily
                                                color: notifRow.uc
                                                Layout.alignment: Qt.AlignTop; topPadding: 1
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        text: model.appName || ""
                                                        font.pixelSize: Theme.fontSm; font.bold: true
                                                        font.family: Theme.fontFamily; color: Theme.textDim
                                                        elide: Text.ElideRight; Layout.fillWidth: true
                                                    }
                                                    Text {
                                                        text: timeAgo(model.notifTime)
                                                        font.pixelSize: Theme.fontSm - 1
                                                        font.family: Theme.fontFamily
                                                        color: Theme.textFaint
                                                    }
                                                }

                                                Text {
                                                    text: model.summary || ""
                                                    font.pixelSize: Theme.fontNormal; font.bold: true
                                                    font.family: Theme.fontFamily; color: Theme.text
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                    visible: text !== ""
                                                }

                                                Text {
                                                    text: model.body || ""
                                                    font.pixelSize: Theme.fontSm
                                                    font.family: Theme.fontFamily; color: Theme.textDim
                                                    wrapMode: Text.WordWrap; maximumLineCount: 3
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                    visible: text !== ""
                                                }
                                            }

                                            // Dismiss ×
                                            Rectangle {
                                                width: 20; height: 20; radius: 10
                                                color: dimX.containsMouse ? Qt.rgba(1,1,1,0.15) : "transparent"
                                                Layout.alignment: Qt.AlignTop
                                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                                Text {
                                                    anchors.centerIn: parent; text: "\uf00d"
                                                    font.pixelSize: 9; font.family: Theme.fontFamily
                                                    color: Theme.textDimmer
                                                }
                                                MouseArea {
                                                    id: dimX; anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    // model.notifId is the role from ListModel
                                                    onClicked: root.dismissRequested(model.notifId)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true; implicitHeight: 8 }
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    function timeAgo(timestamp) {
        if (!timestamp) return ""
        var diff = Math.floor((Date.now() - timestamp) / 1000)
        if (diff < 5)     return "just now"
        if (diff < 60)    return diff + "s ago"
        if (diff < 3600)  return Math.floor(diff / 60) + "m ago"
        if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
        return Math.floor(diff / 86400) + "d ago"
    }
}
