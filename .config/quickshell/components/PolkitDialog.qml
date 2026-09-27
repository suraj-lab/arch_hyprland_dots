import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"
import "pill/surfaces"

// Polkit password prompt (SPEC 6.1): a dimmed full-screen overlay on the focused monitor with
// a centred card. Its own window, so it works whether or not the pill is visible. `flow` is
// the PolkitAgent's AuthFlow (shell.qml owns the agent); null when nothing is asking.
// Exclusive keyboard focus while open, so the password cannot land in another window.
Scope {
    id: root
    property var flow: null
    property color accent: Theme.accent
    property alias window: win
    readonly property bool open: !!flow && !flow.isCompleted

    // The monitor is chosen once per request, so the prompt never jumps while typing.
    property string screenName: ""
    onOpenChanged: if (open) screenName = Hypr.focusedMonitor ? Hypr.focusedMonitor.name : ""

    // The password leaves the field as soon as it is submitted or the request ends.
    function submit() {
        if (!flow || !flow.isResponseRequired) return
        var value = field.text
        field.text = ""
        flow.submit(value)
    }
    function cancel() { field.text = ""; if (flow) flow.cancelAuthenticationRequest() }
    // The field is disabled while polkit checks (which drops its focus); when polkit asks
    // again (wrong password, other identity) the focus goes straight back to it.
    Connections {
        target: root.flow
        function onIsResponseRequiredChanged() { if (root.flow.isResponseRequired) field.forceActiveFocus() }
    }
    function userName(identity) {
        return identity ? (identity.displayName || identity.string || String(identity.id)) : ""
    }

    PanelWindow {
        id: win
        objectName: "polkitWindow"
        visible: root.open
        screen: Quickshell.screens.find(function(s) { return s.name === root.screenName }) || Quickshell.screens[0]
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: Qt.rgba(0, 0, 0, 0.45)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-polkit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            field.text = ""
            if (visible) Qt.callLater(function() { field.forceActiveFocus() })
        }

        Rectangle {
            id: card
            objectName: "polkitCard"
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 40)
            height: body.implicitHeight + 40
            radius: 20
            color: Theme.frameBg
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12

                RowLayout {
                    spacing: 12
                    Rectangle {
                        implicitWidth: 40; implicitHeight: 40; radius: 12
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: "\uf023"   // lock
                            color: root.accent
                            font { family: Theme.fontFamily; pixelSize: 18 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Authentication required"
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.flow ? root.flow.actionId : ""
                            elide: Text.ElideMiddle
                            color: Theme.textFaint
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                        }
                    }
                }

                Text {
                    objectName: "polkitMessage"
                    Layout.fillWidth: true
                    text: root.flow ? root.flow.message : ""
                    wrapMode: Text.Wrap
                    color: Theme.textDim
                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                }

                // Who authenticates: one line, or a choice when polkit offers several.
                Text {
                    visible: !!root.flow && root.flow.identities.length === 1
                    text: "As " + root.userName(root.flow ? root.flow.selectedIdentity : null)
                    color: Theme.textDim
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: !!root.flow && root.flow.identities.length > 1
                    spacing: 6
                    Repeater {
                        model: root.flow ? root.flow.identities : []
                        Rectangle {
                            id: who
                            required property var modelData
                            readonly property bool chosen: root.flow && root.flow.selectedIdentity === modelData
                            objectName: "identity:" + root.userName(modelData)
                            implicitWidth: whoText.implicitWidth + 20
                            implicitHeight: 28
                            radius: 8
                            color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                                 : whoMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                            border.width: 1
                            border.color: chosen ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5) : Theme.borderMuted
                            Text {
                                id: whoText
                                anchors.centerIn: parent
                                text: (who.modelData.isGroup ? "\uf0c0 " : "\uf007 ") + root.userName(who.modelData)
                                color: who.chosen ? root.accent : Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                            }
                            MouseArea {
                                id: whoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Switching restarts the conversation for that identity.
                                onClicked: { field.text = ""; root.flow.selectedIdentity = who.modelData; field.forceActiveFocus() }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 10
                    color: Theme.surface
                    border.width: 1
                    border.color: field.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : Theme.borderMuted
                    opacity: root.flow && root.flow.isResponseRequired ? 1 : 0.5
                    TextInput {
                        id: field
                        objectName: "polkitField"
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        enabled: !!root.flow && root.flow.isResponseRequired
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        color: Theme.text
                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                        clip: true
                        onAccepted: root.submit()
                        Keys.onEscapePressed: root.cancel()
                        Text {
                            visible: !parent.text
                            anchors.verticalCenter: parent.verticalCenter
                            // polkit/PAM prompts end in ": " ("Password: ").
                            text: !root.flow ? "" : root.flow.isResponseRequired
                                ? (root.flow.inputPrompt.replace(/:\s*$/, "") || "Password") : "Checking\u2026"
                            color: Theme.textFaint
                            font: parent.font
                        }
                    }
                }

                Text {
                    objectName: "polkitError"
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: !root.flow ? ""
                        : root.flow.supplementaryMessage !== "" ? root.flow.supplementaryMessage
                        : root.flow.failed ? "Authentication failed, try again." : ""
                    wrapMode: Text.Wrap
                    color: !root.flow || root.flow.supplementaryIsError || root.flow.supplementaryMessage === "" ? Theme.error : Theme.textDim
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    SurfaceButton { accent: root.accent; label: "Cancel"; onClicked: root.cancel() }
                    SurfaceButton {
                        accent: root.accent
                        primary: true
                        label: "Authenticate"
                        enabled: !!root.flow && root.flow.isResponseRequired
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
