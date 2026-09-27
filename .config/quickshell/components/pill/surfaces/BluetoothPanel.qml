import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../services"

// Bluetooth surface (SPEC 6.2): power, scan, and a card for the selected device: pair (then
// trust and connect), connect, disconnect, forget. Battery shows when the device reports it.
Item {
    id: root
    property color accent: Theme.purple
    property bool active: false
    signal closeRequested()

    implicitWidth: Theme.surfaceWidth
    implicitHeight: column.implicitHeight + Theme.surfacePadding

    property string selected: ""
    readonly property var sel: Bt.devices.find(function(d) { return d.address === root.selected }) || null

    onActiveChanged: if (active) { selected = ""; Bt.scan() }
    Timer { interval: 25000; running: root.active && Bt.enabled; repeat: true; onTriggered: Bt.scan() }
    Connections { target: Bt; function onEnabledChanged() { if (root.active && Bt.enabled) Bt.scan() } }

    // BlueZ icon names (freedesktop device icons) to Nerd Font glyphs.
    function glyph(icon) {
        return icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0 ? "\uf025"
            : icon.indexOf("audio") >= 0 ? "\uf028"
            : icon === "input-mouse" ? "\uf8cc"
            : icon === "input-keyboard" ? "\uf11c"
            : icon === "input-gaming" ? "\uf11b"
            : icon === "phone" ? "\uf10b"
            : icon === "computer" ? "\uf109"
            : "\uf294"
    }
    function status(d) {
        var p = [d.pairing ? "Pairing\u2026" : d.busy ? (d.connected ? "Disconnecting\u2026" : "Connecting\u2026")
                 : d.connected ? "Connected" : d.paired ? "Paired" : ""]
        if (d.battery >= 0) p.push(d.battery + "%")
        return p.filter(function(x) { return x }).join(" \u00b7 ")
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
                Text { text: "Bluetooth"; color: Theme.text; font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true } }
                Text {
                    text: !Bt.adapter ? "No adapter" : !Bt.enabled ? "Off" : Bt.scanning ? "Searching for devices\u2026" : "On"
                    color: Theme.textFaint
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
            }
            Item { Layout.fillWidth: true }
            SurfaceIcon {   // rescan
                visible: Bt.enabled
                glyph: "\uf021"
                accent: root.accent
                spinning: Bt.scanning   // the real 30 s discovery
                onClicked: Bt.scan()
            }
            SurfaceSwitch {
                objectName: "btSwitch"
                visible: !!Bt.adapter
                on: Bt.enabled
                accent: root.accent
                onToggled: Bt.toggle()
            }
        }

        Text {
            visible: Bt.devices.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 6; Layout.bottomMargin: 6
            horizontalAlignment: Text.AlignHCenter
            text: !Bt.enabled ? "Bluetooth is off" : Bt.scanning ? "Searching\u2026" : "No devices found"
            color: Theme.textFaint
            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 6 * 46)
            visible: Bt.devices.length > 0
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: list
                width: parent.width
                spacing: 2
                Repeater {
                    model: Bt.devices
                    Rectangle {
                        id: row
                        required property var modelData
                        objectName: "device:" + modelData.address
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 10
                        color: root.selected === modelData.address ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                             : rowMouse.containsMouse ? Theme.surfaceHover : "transparent"
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = root.selected === row.modelData.address ? "" : row.modelData.address
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 10
                            Text {
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: root.glyph(row.modelData.icon)
                                color: row.modelData.connected ? root.accent : Theme.textDim
                                font { family: Theme.fontFamily; pixelSize: 15 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                    color: row.modelData.connected ? root.accent : Theme.text
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: row.modelData.connected }
                                }
                                Text {
                                    visible: text !== ""
                                    text: root.status(row.modelData)
                                    color: Theme.textFaint
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            objectName: "deviceCard"
            visible: !!root.sel
            Layout.fillWidth: true
            spacing: 8
            SurfaceButton {
                accent: root.accent
                primary: true
                visible: !!root.sel && !root.sel.connected
                enabled: !!root.sel && !root.sel.busy
                label: root.sel && root.sel.paired ? "Connect" : "Pair and connect"
                onClicked: Bt.connect(root.sel.address)
            }
            SurfaceButton {
                accent: root.accent
                visible: !!root.sel && root.sel.connected
                enabled: !!root.sel && !root.sel.busy
                label: "Disconnect"
                onClicked: Bt.disconnect(root.sel.address)
            }
            SurfaceButton {
                accent: root.accent
                visible: !!root.sel && root.sel.paired
                label: "Forget"
                onClicked: { Bt.forget(root.sel.address); root.selected = "" }
            }
        }
    }
}
