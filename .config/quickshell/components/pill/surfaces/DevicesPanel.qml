import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Devices surface (SPEC 6.3): removable drives, one card each, with their volumes.
// Open (mounts first if needed) in thunar, Mount/Unmount, and Eject (unmount all, power off).
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    signal closeRequested()

    implicitWidth: Theme.surfaceWidth
    implicitHeight: column.implicitHeight + Theme.surfacePadding
    onActiveChanged: if (active) { Devices.error = ""; Devices.refresh() }

    function glyph(tran) { return tran === "usb" ? "\uf287" : tran === "mmc" ? "\uf7c2" : "\uf0a0" }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        Text {
            text: "Removable drives"
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true }
        }
        Text {
            visible: Devices.count === 0
            Layout.fillWidth: true
            Layout.topMargin: 4; Layout.bottomMargin: 4
            horizontalAlignment: Text.AlignHCenter
            text: "No removable drives"
            color: Theme.textFaint
            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
        }

        Repeater {
            model: Devices.drives
            Rectangle {
                id: card
                required property var modelData
                objectName: "drive:" + modelData.path
                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + 20
                radius: 12
                color: Theme.surface
                opacity: Devices.busy === modelData.path ? 0.6 : 1

                ColumnLayout {
                    id: cardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: root.glyph(card.modelData.tran); color: root.accent; font { family: Theme.fontFamily; pixelSize: 15 } }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.name + "  \u00b7  " + card.modelData.size
                            elide: Text.ElideRight
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                        }
                        SurfaceButton {   // unmount everything, then power off
                            objectName: "eject:" + card.modelData.path
                            Layout.fillWidth: false
                            Layout.preferredWidth: 76
                            Layout.preferredHeight: 28
                            accent: root.accent
                            label: Devices.busy === card.modelData.path ? "\u2026" : "\uf052 Eject"
                            enabled: Devices.busy === ""
                            onClicked: Devices.eject(card.modelData)
                        }
                    }

                    Repeater {
                        model: card.modelData.volumes
                        RowLayout {
                            id: vol
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: vol.modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: vol.modelData.fstype + " \u00b7 " + vol.modelData.size + " \u00b7 "
                                        + (Devices.busy === vol.modelData.path ? "working\u2026"
                                           : vol.modelData.mountpoint || "not mounted")
                                    elide: Text.ElideMiddle
                                    color: Theme.textFaint
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                }
                            }
                            SurfaceButton {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 28
                                accent: root.accent
                                primary: true
                                objectName: "open:" + vol.modelData.path
                                label: "Open"
                                enabled: Devices.busy === ""
                                onClicked: { Devices.open(vol.modelData); if (vol.modelData.mountpoint) root.closeRequested() }
                            }
                            SurfaceButton {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 84
                                Layout.preferredHeight: 28
                                accent: root.accent
                                label: vol.modelData.mountpoint ? "Unmount" : "Mount"
                                enabled: Devices.busy === ""
                                onClicked: vol.modelData.mountpoint ? Devices.unmount(vol.modelData) : Devices.mount(vol.modelData)
                            }
                        }
                    }
                }
            }
        }

        Text {
            objectName: "devicesError"
            Layout.fillWidth: true
            visible: Devices.error !== ""
            text: Devices.error
            wrapMode: Text.Wrap
            color: Theme.error
            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
        }
    }
}
