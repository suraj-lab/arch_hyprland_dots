import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Updates surface (SPEC 6.4): counts per source with the first package names, when it last
// checked, "Check now", and "Update" (a floating terminal; nothing upgrades on its own).
Item {
    id: root
    property color accent: Theme.accent
    signal closeRequested()

    implicitWidth: Theme.surfaceWidth
    implicitHeight: column.implicitHeight + Theme.surfacePadding

    readonly property var sources: [
        { key: "pacman", title: "Official repositories", icon: "\uf303", data: Updates.pacman },
        { key: "aur", title: "AUR (paru)", icon: "\uf1b2", data: Updates.aur },
        { key: "flatpak", title: "Flatpak", icon: "\uf1b3", data: Updates.flatpak }
    ].filter(function(s) { return s.data.present })

    property real now: Date.now()
    Timer { interval: 30000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }
    function ago(ms) {
        if (!ms) return "not checked yet"
        var min = Math.round((root.now - ms) / 60000)
        return min < 1 ? "checked just now" : min < 60 ? "checked " + min + " min ago"
            : "checked " + Math.round(min / 60) + " h ago"
    }

    component Button: Rectangle {
        property string label
        property bool primary: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: 10
        opacity: enabled ? 1 : 0.4
        color: primary ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, mouse.containsMouse ? 0.25 : 0.15)
                       : mouse.containsMouse ? Theme.surfaceHover : Theme.surface
        border.width: 1
        border.color: primary ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4) : Theme.borderMuted
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.primary ? root.accent : Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
        }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: Updates.total > 0 ? Updates.total + (Updates.total === 1 ? " update" : " updates") : "Up to date"
                color: Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: Updates.checking ? "checking\u2026" : root.ago(Math.min(Updates.lastChecked, root.now))
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
        }

        Repeater {
            model: root.sources
            Rectangle {
                id: src
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: srcCol.implicitHeight + 20
                radius: 12
                color: Theme.surface
                ColumnLayout {
                    id: srcCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: src.modelData.icon; color: root.accent; font { family: Theme.fontFamily; pixelSize: 14 } }
                        Text {
                            Layout.fillWidth: true
                            text: src.modelData.title
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                        }
                        Text {
                            text: src.modelData.data.count < 0 ? "?" : src.modelData.data.count
                            color: src.modelData.data.count > 0 ? root.accent : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: !src.modelData.data.ok ? "Could not check (offline?)"
                            : src.modelData.data.items.slice(0, 6).join(", ")
                              + (src.modelData.data.items.length > 6 ? ", +" + (src.modelData.data.items.length - 6) + " more" : "")
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: src.modelData.data.ok ? Theme.textDim : Theme.warning
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Button {
                label: Updates.checking ? "Checking\u2026" : "Check now"
                enabled: !Updates.checking
                onClicked: Updates.check()
            }
            Button {
                objectName: "updateButton"
                label: "Update"
                primary: true
                enabled: Updates.total > 0
                onClicked: { Updates.update(); root.closeRequested() }
            }
        }
    }
}
