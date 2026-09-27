import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Network surface (SPEC 6.2): Wi-Fi power, the scanned list, and a card for the selected
// network: password inline, connect, disconnect, forget; plus hidden networks. The list is
// rebuilt on every signal change while scanning, so the password field lives in the card
// below it, never in a row.
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    signal closeRequested()

    implicitWidth: Theme.surfaceWidth
    implicitHeight: column.implicitHeight + Theme.surfacePadding

    property string selected: ""
    property bool hiddenOpen: false
    readonly property var sel: Net.networks.find(function(n) { return n.ssid === root.selected }) || null
    readonly property bool needsPsk: !!sel && !sel.known && !sel.inUse && sel.security !== "" && !sel.enterprise

    onActiveChanged: if (active) { selected = ""; hiddenOpen = false; rescan() }
    // NetworkManager keeps scanning while the surface is open, so the icon spins for a few
    // seconds after each requested scan (about how long NetworkManager takes) instead.
    property bool refreshing: false
    function rescan() { Net.scan(); refreshing = true; refreshDone.restart() }
    Timer { id: refreshDone; interval: 3000; onTriggered: root.refreshing = false }
    onSelectedChanged: { psk.text = ""; if (needsPsk) Qt.callLater(function() { psk.input.forceActiveFocus() }) }
    Timer { interval: 20000; running: root.active; repeat: true; onTriggered: Net.scan() }

    function status(n) {
        var p = []
        if (n.security) p.push(n.security)
        p.push(n.busy ? "Connecting\u2026" : n.inUse ? "Connected" : n.known ? "Saved" : "")
        return p.filter(function(x) { return x }).join(" \u00b7 ")
    }
    function submit() {
        if (!sel) return
        if (sel.known) Net.connectKnown(sel.ssid)
        else if (sel.security === "") Net.connect(sel.ssid)
        else if (Net.validPsk(psk.text)) { Net.connectPsk(sel.ssid, psk.text); psk.text = "" }
    }
    function submitHidden() {
        if (hiddenSsid.text === "" || (hiddenPsk.text !== "" && !Net.validPsk(hiddenPsk.text))) return
        Net.connectHidden(hiddenSsid.text, hiddenPsk.text)
        hiddenPsk.text = ""
    }

    // Single-line input with a placeholder; Enter submits, Escape closes the surface.
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        property string placeholder
        property bool secret: false
        signal accepted()
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: input.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : Theme.borderMuted
        TextInput {
            id: input
            anchors { left: parent.left; right: eye.left; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 4 }
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
            clip: true
            echoMode: field.secret && !eye.shown ? TextInput.Password : TextInput.Normal
            onAccepted: field.accepted()
            Keys.onEscapePressed: root.closeRequested()
            Text {
                visible: !parent.text
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                color: Theme.textFaint
                font: parent.font
            }
        }
        SurfaceIcon {
            id: eye
            property bool shown: false
            visible: field.secret
            width: field.secret ? implicitWidth : 0
            anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
            glyph: shown ? "\uf070" : "\uf06e"
            accent: root.accent
            onClicked: eye.shown = !eye.shown
        }
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                spacing: 0
                Text { text: "Wi-Fi"; color: Theme.text; font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true } }
                Text {
                    text: !Net.wifiEnabled ? "Off" : Net.ssid ? "Connected to " + Net.ssid : "Not connected"
                    color: Theme.textFaint
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
            }
            Item { Layout.fillWidth: true }
            SurfaceIcon {   // rescan
                visible: Net.wifiEnabled
                objectName: "wifiRescan"
                glyph: "\uf021"
                accent: root.accent
                spinning: root.refreshing
                onClicked: root.rescan()
            }
            SurfaceSwitch {
                objectName: "wifiSwitch"
                on: Net.wifiEnabled
                accent: root.accent
                onToggled: Net.toggleWifi()
            }
        }

        Text {
            visible: Net.networks.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 6; Layout.bottomMargin: 6
            horizontalAlignment: Text.AlignHCenter
            text: Net.wifiEnabled ? "Scanning\u2026" : "Wi-Fi is off"
            color: Theme.textFaint
            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
        }

        Flickable {
            id: listFlick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 6 * 46)
            visible: Net.networks.length > 0
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: list
                width: listFlick.width
                spacing: 2
                Repeater {
                    model: Net.networks
                    Rectangle {
                        id: row
                        required property var modelData
                        objectName: "network:" + modelData.ssid
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 10
                        color: root.selected === modelData.ssid ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                             : rowMouse.containsMouse ? Theme.surfaceHover : "transparent"
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = root.selected === row.modelData.ssid ? "" : row.modelData.ssid
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            Text {   // nf-md-wifi_strength_1..4
                                text: String.fromCodePoint(0xF091F + 3 * Math.min(3, Math.floor(row.modelData.signal / 25)))
                                color: row.modelData.inUse ? root.accent : Theme.textDim
                                font { family: Theme.fontFamily; pixelSize: 16 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.ssid
                                    elide: Text.ElideRight
                                    color: row.modelData.inUse ? root.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: row.modelData.inUse }
                                }
                                Text {
                                    visible: text !== ""
                                    text: root.status(row.modelData)
                                    color: Theme.textFaint
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                }
                            }
                            Text {
                                visible: row.modelData.security !== ""
                                text: "\uf023"
                                color: Theme.textFaint
                                font { family: Theme.fontFamily; pixelSize: 11 }
                            }
                        }
                    }
                }
            }
        }

        // The selected network.
        Rectangle {
            objectName: "networkCard"
            visible: !!root.sel
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight + 20
            radius: 12
            color: Theme.surface
            ColumnLayout {
                id: card
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    visible: !!root.sel && root.sel.enterprise && !root.sel.known
                    text: "Enterprise (802.1X) networks need a certificate or login: set them up with nmtui."
                    wrapMode: Text.Wrap
                    color: Theme.textDim
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
                Field {
                    id: psk
                    objectName: "pskField"
                    visible: root.needsPsk
                    secret: true
                    placeholder: "Password"
                    onAccepted: root.submit()
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!root.sel && Net.error.ssid === root.sel.ssid
                    text: Net.error.text
                    wrapMode: Text.Wrap
                    color: Theme.error
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SurfaceButton {
                        accent: root.accent
                        primary: true
                        visible: !!root.sel && !root.sel.inUse && !(root.sel.enterprise && !root.sel.known)
                        label: root.sel && root.sel.busy ? "Connecting\u2026" : "Connect"
                        enabled: !!root.sel && !root.sel.busy && (!root.needsPsk || Net.validPsk(psk.text))
                        onClicked: root.submit()
                    }
                    SurfaceButton {
                        accent: root.accent
                        visible: !!root.sel && root.sel.inUse
                        label: "Disconnect"
                        onClicked: Net.disconnect(root.sel.ssid)
                    }
                    SurfaceButton {
                        accent: root.accent
                        visible: !!root.sel && root.sel.known
                        label: "Forget"
                        onClicked: Net.forget(root.sel.ssid)
                    }
                }
            }
        }

        // Hidden networks (not in the scan) go by name through nmcli.
        Rectangle {
            visible: Net.wifiEnabled
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 8
            color: hiddenMouse.containsMouse ? Theme.surfaceHover : "transparent"
            Text {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: (root.hiddenOpen ? "\uf078  " : "\uf054  ") + "Hidden network"
                color: hiddenMouse.containsMouse ? root.accent : Theme.textDim
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
            MouseArea { id: hiddenMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.hiddenOpen = !root.hiddenOpen }
        }
        ColumnLayout {
            visible: root.hiddenOpen && Net.wifiEnabled
            Layout.fillWidth: true
            spacing: 8
            Field { id: hiddenSsid; placeholder: "Network name (SSID)"; onAccepted: hiddenPsk.input.forceActiveFocus() }
            Field { id: hiddenPsk; secret: true; placeholder: "Password (empty for an open network)"; onAccepted: root.submitHidden() }
            Text {
                Layout.fillWidth: true
                visible: Net.error.ssid === "(hidden)"
                text: Net.error.text
                wrapMode: Text.Wrap
                color: Theme.error
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
            SurfaceButton {
                accent: root.accent
                primary: true
                label: Net.hiddenBusy ? "Connecting\u2026" : "Connect"
                enabled: !Net.hiddenBusy && hiddenSsid.text !== "" && (hiddenPsk.text === "" || Net.validPsk(hiddenPsk.text))
                onClicked: root.submitHidden()
            }
        }
    }
}
