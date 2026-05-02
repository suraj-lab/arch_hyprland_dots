import QtQuick
import QtQuick.Layouts
import "../theme"

// Pure display component — toast data is managed by ShellRoot's Connections.
// Receives the shared ListModel (shellRoot.globalToastModel) as `toastModel`.

Item {
    id: root

    property var toastModel:  null   // shellRoot.globalToastModel
    property var dismissFunc: null   // function(id) — shell.qml's dismissNotif

    readonly property bool hasToasts: toastModel != null && toastModel.count > 0

    // ── Toast stack (top-right, grows downward) ───────────────────────────
    Column {
        anchors { right: parent.right; top: parent.top; margins: 16 }
        spacing: 8

        Repeater {
            model: root.toastModel

            Item {
                id: toastDelegate

                property int  savedId:      model.notifId
                property int  savedTimeout: model.toastTimeout
                property int  toastUrgency: model.urgency
                property bool dismissing:   false

                width: 360
                height: dismissing ? 0 : toastRect.height
                clip: true

                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // Slide-in from the right
                opacity: 0
                x: 30
                Component.onCompleted: { opacity = 1; x = 0 }
                Behavior on opacity { NumberAnimation { duration: Theme.animSlide } }
                Behavior on x      { NumberAnimation { duration: Theme.animSlide; easing.type: Easing.OutCubic } }

                // Auto-dismiss timer (timeout=0 → critical, stays until dismissed)
                Timer {
                    property int tid: toastDelegate.savedId
                    interval: toastDelegate.savedTimeout
                    running:  toastDelegate.savedTimeout > 0 && !toastDelegate.dismissing
                    onTriggered: toastDelegate.startDismiss()
                }

                // Dismiss animation delay — remove from model after slide-out finishes
                Timer {
                    id: dismissTimer
                    interval: 300
                    onTriggered: {
                        var sid = toastDelegate.savedId
                        root.removeToast(sid)
                        if (root.dismissFunc) root.dismissFunc(sid)
                    }
                }

                function startDismiss() {
                    if (dismissing) return
                    dismissing = true
                    opacity = 0
                    x = 60
                    dismissTimer.start()
                }

                readonly property color urgencyColor:
                    toastUrgency === 2 ? Theme.error :
                    toastUrgency === 0 ? Theme.textFaint : Theme.purple

                readonly property string iconChar: {
                    var n = (model.appName || "").toLowerCase()
                    if (n.indexOf("firefox")    >= 0 || n.indexOf("chromium") >= 0) return "\uf738"
                    if (n.indexOf("discord")    >= 0 || n.indexOf("webcord")  >= 0) return "\uf392"
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

                // ── Album art thumbnail (for MPRIS toasts) ────────────────
                property string artUrl: model.body && model.body.indexOf("art:") === 0
                                        ? model.body.substring(4) : ""

                Rectangle {
                    id: toastRect
                    width: parent.width
                    height: toastContent.implicitHeight + 20
                    radius: 10
                    color: Theme.popupBg
                    border.color: toastDelegate.urgencyColor
                    border.width: 1

                    // Left urgency strip
                    Rectangle {
                        width: 3; radius: 2
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 4 }
                        color: toastDelegate.urgencyColor
                    }

                    // Progress bar
                    Rectangle {
                        visible: toastDelegate.savedTimeout > 0
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.margins: 4
                        height: 2; radius: 1
                        color: Qt.rgba(toastDelegate.urgencyColor.r,
                                       toastDelegate.urgencyColor.g,
                                       toastDelegate.urgencyColor.b, 0.15)
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width; radius: parent.radius
                            color: toastDelegate.urgencyColor
                            transformOrigin: Item.Left
                            NumberAnimation on scale {
                                from: 1.0; to: 0.0
                                duration: toastDelegate.savedTimeout
                                running: toastDelegate.savedTimeout > 0
                            }
                        }
                    }

                    RowLayout {
                        id: toastContent
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.margins: 12; anchors.leftMargin: 16
                        spacing: 8

                        // Album art thumbnail (only for MPRIS/media toasts)
                        Rectangle {
                            visible: toastDelegate.artUrl !== ""
                            width: 40; height: 40; radius: 6
                            color: Theme.surface; clip: true
                            Layout.alignment: Qt.AlignTop
                            Image {
                                anchors.fill: parent
                                source: toastDelegate.artUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        // Icon (hidden when art is shown)
                        Text {
                            visible: toastDelegate.artUrl === ""
                            text: toastDelegate.iconChar
                            font.pixelSize: 15; font.family: Theme.fontFamily
                            color: toastDelegate.urgencyColor
                            Layout.alignment: Qt.AlignTop; topPadding: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Text {
                                text: model.appName
                                font.pixelSize: Theme.fontSm; font.bold: true
                                font.family: Theme.fontFamily; color: Theme.textDim
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            Text {
                                text: model.summary
                                font.pixelSize: Theme.fontNormal; font.bold: true
                                font.family: Theme.fontFamily; color: Theme.text
                                elide: Text.ElideRight; Layout.fillWidth: true
                                visible: text !== ""
                            }
                            Text {
                                text: toastDelegate.artUrl === "" ? model.body : ""
                                font.pixelSize: Theme.fontSm
                                font.family: Theme.fontFamily; color: Theme.textDim
                                elide: Text.ElideRight; Layout.fillWidth: true
                                maximumLineCount: 1; visible: text !== ""
                            }
                        }

                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: xHover.containsMouse ? Qt.rgba(1,1,1,0.15) : "transparent"
                            Layout.alignment: Qt.AlignTop
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent; text: "\uf00d"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: Theme.textDimmer
                            }
                            MouseArea {
                                id: xHover; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toastDelegate.startDismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    function removeToast(id) {
        if (root.toastModel == null) return
        for (var i = 0; i < root.toastModel.count; i++) {
            if (root.toastModel.get(i).notifId === id) {
                root.toastModel.remove(i)
                return
            }
        }
    }
}
