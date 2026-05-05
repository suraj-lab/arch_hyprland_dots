import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"
import "views"

// Unified panel — single PopupWindow hosting Sound, Notifs, and System views.
// Replaces the separate PopupWindows from Volume, NotificationCenter, ControlCenter.

Item {
    id: root

    property color barAccent: "#00ffea"
    property bool panelOpen: false
    property string currentView: "sound"   // "sound" | "notifs" | "system"
    property var parentWindow: null        // barPanel PanelWindow, for focus grab

    // Passthrough
    property var  notifModel: null
    property bool dndEnabled: false
    property var  screenTimeTracker: null
    signal dismissRequested(int notifId)
    signal clearAllRequested()
    signal dndToggled()
    signal panelOpened()

    // Exposed for bar chips to read
    property real currentVolume: soundView.currentVolume
    property bool currentMuted: soundView.currentMuted

    function open(viewName) {
        currentView = viewName
        panelOpen = true
        root.panelOpened()
    }

    function close() {
        panelOpen = false
    }

    // ── Focus grab (binding pattern) ──────────────────────────────────────
    property bool _grabReady: false

    HyprlandFocusGrab {
        id: panelGrab
        windows: root.parentWindow ? [panelPopup, root.parentWindow] : [panelPopup]
        active: panelOpen && root._grabReady
        onCleared: panelOpen = false
    }

    Timer {
        id: grabDelay
        interval: 50
        onTriggered: root._grabReady = true
    }

    onPanelOpenChanged: {
        if (panelOpen) {
            grabDelay.restart()
        } else {
            root._grabReady = false
            grabDelay.stop()
        }
    }

    // ── Popup ──────────────────────────────────────────────────────────────
    PopupWindow {
        id: panelPopup
        visible: panelOpen
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth: 380
        implicitHeight: panelContent.implicitHeight
        color: Theme.popupBg

        Rectangle {
            id: panelContent
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.25)
            border.width: 1
            radius: 14
            clip: true

            implicitHeight: tabBar.implicitHeight + tabIndicator.height + viewsContainer.implicitHeight

            // Ease animation (OutCubic, NOT OutBack)
            scale: panelOpen ? 1.0 : 0.95
            opacity: panelOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 0

                // ── Tab bar ────────────────────────────────────────────────
                RowLayout {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.leftMargin: 8; Layout.rightMargin: 8
                    Layout.topMargin: 8
                    spacing: 2

                    Repeater {
                        model: [
                            { key: "sound",  icon: "\uf028",  label: "Sound" },
                            { key: "notifs", icon: "\uf0f3",  label: "Notifs" },
                            { key: "system", icon: "\uf013",  label: "System" }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index
                            property bool isActive: root.currentView === modelData.key

                            Layout.fillWidth: true
                            height: 36; radius: 8
                            color: isActive ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.06) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animMedium } }

                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentView = modelData.key
                            }

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 2
                                Text {
                                    text: modelData.icon
                                    font.pixelSize: 13; font.family: Theme.fontFamily
                                    color: isActive ? root.barAccent : Theme.textFaint
                                    Layout.alignment: Qt.AlignHCenter
                                    Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                }
                                Text {
                                    text: modelData.label
                                    font.pixelSize: 8; font.weight: Font.Bold
                                    font.family: Theme.fontFamily
                                    color: isActive ? root.barAccent : Theme.textFaint
                                    Layout.alignment: Qt.AlignHCenter
                                    Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                                }
                            }
                        }
                    }
                }

                // ── Tab indicator ──────────────────────────────────────────
                Item {
                    id: tabIndicator
                    Layout.fillWidth: true
                    Layout.leftMargin: 8; Layout.rightMargin: 8
                    implicitHeight: 2

                    Rectangle {
                        anchors { left: parent.left; right: parent.right }
                        height: 2; radius: 1
                        color: Theme.borderMuted
                    }

                    Rectangle {
                        width: parent.width / 3
                        height: 2; radius: 1
                        color: root.barAccent
                        x: {
                            if (root.currentView === "sound") return 0
                            if (root.currentView === "notifs") return parent.width / 3
                            return parent.width * 2 / 3
                        }
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: root.barAccent
                            opacity: 0.3
                            layer.enabled: true
                        }
                    }
                }

                // ── Views ──────────────────────────────────────────────────
                Item {
                    id: viewsContainer
                    Layout.fillWidth: true
                    implicitHeight: {
                        if (root.currentView === "sound") return soundView.implicitHeight
                        if (root.currentView === "notifs") return notifsView.implicitHeight
                        return systemView.implicitHeight
                    }

                    SoundView {
                        id: soundView
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        barAccent: root.barAccent
                        viewActive: root.currentView === "sound" && root.panelOpen
                        visible: root.currentView === "sound"
                    }

                    NotifsView {
                        id: notifsView
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        barAccent: root.barAccent
                        notifModel: root.notifModel
                        dndEnabled: root.dndEnabled
                        visible: root.currentView === "notifs"
                        onDismissRequested: function(id) { root.dismissRequested(id) }
                        onClearAllRequested: root.clearAllRequested()
                        onDndToggled: root.dndToggled()
                    }

                    SystemView {
                        id: systemView
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        barAccent: root.barAccent
                        viewActive: root.currentView === "system" && root.panelOpen
                        dndEnabled: root.dndEnabled
                        screenTimeTracker: root.screenTimeTracker
                        visible: root.currentView === "system"
                        onDndToggled: root.dndToggled()
                        onCloseRequested: root.close()
                    }
                }
            }
        }
    }
}
