import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../theme"

RowLayout {
    spacing: 6

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItem
            required property SystemTrayItem modelData
            property bool menuOpen: false
            implicitWidth: 20; implicitHeight: 20

            Image {
                anchors.fill: parent
                // Strip custom icon paths that quickshell can't resolve
                source: modelData.icon.indexOf("?path=") >= 0 ? "" : modelData.icon
                sourceSize.width: 20; sourceSize.height: 20
                scale: trayHover.containsMouse ? 1.2 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack } }
                opacity: trayHover.containsMouse ? 1.0 : 0.8
                Behavior on opacity { NumberAnimation { duration: Theme.animNormal } }
            }

            MouseArea {
                id: trayHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) modelData.activate()
                    else if (modelData.hasMenu) trayItem.menuOpen = !trayItem.menuOpen
                }
            }

            HyprlandFocusGrab {
                windows: [menuPopup]
                active: trayItem.menuOpen
                onCleared: trayItem.menuOpen = false
            }

            PopupWindow {
                id: menuPopup
                visible: trayItem.menuOpen && modelData.hasMenu
                anchor.item: trayItem
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom

                implicitWidth: Math.max(160, menuCol.implicitWidth + 16)
                implicitHeight: menuCol.implicitHeight + 12
                color: Theme.popupBg

                QsMenuOpener { id: opener; menu: modelData.menu }

                Rectangle {
                    anchors.fill: parent; color: "transparent"
                    border.color: Theme.border; border.width: 1; radius: 10; clip: true

                    ColumnLayout {
                        id: menuCol
                        anchors { fill: parent; margins: 6 }
                        spacing: 2

                        Repeater {
                            model: opener.children
                            Item {
                                id: entry
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: modelData.isSeparator ? 9 : 28

                                Rectangle {
                                    visible: entry.modelData.isSeparator
                                    anchors.centerIn: parent
                                    width: parent.width - 8; height: 1
                                    color: Theme.borderMuted
                                }
                                Rectangle {
                                    visible: !entry.modelData.isSeparator
                                    anchors.fill: parent; radius: 6
                                    color: entryHover.containsMouse && entry.modelData.enabled ? Theme.surfaceHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                        spacing: 8
                                        Text {
                                            text: entry.modelData.text
                                            color: entry.modelData.enabled ? Theme.text : Theme.textFaint
                                            font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: entry.modelData.hasChildren
                                            text: "\uf054"; color: Theme.textDimmer
                                            font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                                        }
                                    }
                                    MouseArea {
                                        id: entryHover; anchors.fill: parent; hoverEnabled: true
                                        enabled: !entry.modelData.isSeparator
                                        cursorShape: entry.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (entry.modelData.enabled && !entry.modelData.hasChildren) {
                                                entry.modelData.triggered()
                                                trayItem.menuOpen = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
