import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"

// System view for the unified panel.
// Brightness, quick toggles, network drill-in, power profiles, display info.

Item {
    id: root

    property color barAccent: "#00ffea"
    property bool viewActive: false
    property bool dndEnabled: false
    signal dndToggled()
    signal closeRequested()

    implicitHeight: panelCol.implicitHeight

    // ── System state ───────────────────────────────────────────────────────
    property real brightness: 0
    property bool wifiEnabled: false
    property bool bluetoothEnabled: false
    property string wifiSSID: ""

    // ── Network state ────────────────────────────────────────────────────
    property bool networkViewOpen: false
    property var networkList: []
    property var knownNetworks: []

    // ── Display info state ───────────────────────────────────────────────
    property var monitors: []

    // ── Refresh on view becoming active ──────────────────────────────────
    onViewActiveChanged: {
        if (viewActive) {
            refresh()
            refreshBrightness()
            monitorReadProc.running = true
        } else {
            networkViewOpen = false
        }
    }

    // ── System polling ─────────────────────────────────────────────────────
    function refresh() {
        wifiReadProc.running = true
        btReadProc.running = true
    }

    function refreshBrightness() {
        brightReadProc.running = true
    }

    Timer {
        interval: root.viewActive ? 2000 : 10000
        running: true; repeat: true
        onTriggered: refresh()
    }

    // Brightness (DDC/CI via ddcutil)
    Process {
        id: brightReadProc
        command: ["bash", "-c", "ddcutil getvcp 10 --bus 8 --brief 2>/dev/null | awk '{print $4, $5}'"]
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(/\s+/)
                if (parts.length >= 2) {
                    var current = parseInt(parts[0])
                    var max = parseInt(parts[1])
                    if (!isNaN(current) && !isNaN(max) && max > 0) root.brightness = current / max
                }
            }
        }
    }

    // Wifi
    Process {
        id: wifiReadProc
        command: ["bash", "-c", "echo $(nmcli radio wifi); nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2 | head -1"]
        stdout: SplitParser {
            property int lineNum: 0
            onRead: data => {
                if (lineNum === 0) root.wifiEnabled = (data.trim() === "enabled")
                else if (lineNum === 1) root.wifiSSID = data.trim()
                lineNum++
            }
        }
        onRunningChanged: { if (running) wifiReadProc.stdout.lineNum = 0 }
    }

    // Bluetooth
    Process {
        id: btReadProc
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | grep 'Powered:' | awk '{print $2}'"]
        stdout: SplitParser {
            onRead: data => { root.bluetoothEnabled = (data.trim() === "yes") }
        }
    }


    // Monitor info
    property var _monBuf: []
    Process {
        id: monitorReadProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: SplitParser {
            onRead: function(line) { root._monBuf.push(line) }
        }
        onRunningChanged: {
            if (!running) {
                var raw = root._monBuf.join(""); root._monBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var result = []
                    for (var i = 0; i < arr.length; i++) {
                        var m = arr[i]
                        result.push({
                            name: m.name || "",
                            desc: m.description || "",
                            width: m.width || 0,
                            height: m.height || 0,
                            refreshRate: Math.round(m.refreshRate || 0),
                            vrr: m.vrr || 0   // 0=off, 1=on, 2=fullscreen only
                        })
                    }
                    root.monitors = result
                } catch(e) { root.monitors = [] }
            }
        }
    }

    // ── Commands ────────────────────────────────────────────────────────────
    Process { id: brightCmdProc }
    Process { id: toggleCmdProc; onRunningChanged: { if (!running) refresh() } }

    // ── Network scanning ─────────────────────────────────────────────────
    property var _netBuf: []

    Process {
        id: netScanProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "auto"]
        stdout: SplitParser {
            onRead: function(line) { root._netBuf.push(line) }
        }
        onRunningChanged: {
            if (!running) {
                var raw = root._netBuf.slice()
                root._netBuf = []
                var seen = {}
                var result = []
                for (var i = 0; i < raw.length; i++) {
                    var parts = raw[i].split(":")
                    if (parts.length < 4) continue
                    var inUse = parts[0].trim() === "*"
                    var ssid = parts[1].trim()
                    if (!ssid) continue
                    var signal = parseInt(parts[2].trim()) || 0
                    var security = parts.slice(3).join(":").trim()
                    if (seen[ssid] !== undefined) {
                        if (signal > result[seen[ssid]].signal) result[seen[ssid]].signal = signal
                        if (inUse) result[seen[ssid]].inUse = true
                        continue
                    }
                    seen[ssid] = result.length
                    result.push({ inUse: inUse, ssid: ssid, signal: signal, security: security })
                }
                result.sort(function(a, b) {
                    if (a.inUse && !b.inUse) return -1
                    if (!a.inUse && b.inUse) return 1
                    return b.signal - a.signal
                })
                root.networkList = result
            }
        }
    }

    property var _knownBuf: []

    Process {
        id: knownNetProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "con", "show"]
        stdout: SplitParser {
            onRead: function(line) { root._knownBuf.push(line) }
        }
        onRunningChanged: {
            if (!running) {
                var names = []
                for (var i = 0; i < root._knownBuf.length; i++) {
                    var parts = root._knownBuf[i].split(":")
                    if (parts.length >= 2 && parts[1].trim().indexOf("wireless") >= 0)
                        names.push(parts[0].trim())
                }
                root._knownBuf = []
                root.knownNetworks = names
            }
        }
    }

    function isKnownNetwork(ssid) {
        for (var i = 0; i < knownNetworks.length; i++) {
            if (knownNetworks[i] === ssid) return true
        }
        return false
    }

    function scanNetworks() {
        knownNetProc.running = true
        netScanProc.running = true
    }

    Process {
        id: netConnectProc
        onRunningChanged: { if (!running) scanNetworks() }
    }

    function connectToNetwork(ssid, security) {
        var isOpen = !security || security === "" || security === "--"
        var isKnown = isKnownNetwork(ssid)
        if (isOpen || isKnown) {
            netConnectProc.command = ["nmcli", "dev", "wifi", "connect", ssid]
            netConnectProc.running = true
        } else {
            Hyprland.dispatch("exec [float;size 40% 30%;center] kitty -e nmcli dev wifi connect '" + ssid + "' --ask")
        }
    }

    function setBrightness(v) {
        var pct = Math.max(5, Math.min(100, Math.round(v * 100)))
        root.brightness = pct / 100
        brightCmdProc.command = ["bash", "-c",
            "ddcutil setvcp 10 " + pct + " --bus 8 --noverify & " +
            "ddcutil setvcp 10 " + pct + " --bus 10 --noverify & wait"]
        brightCmdProc.running = true
    }
    function toggleWifi() {
        toggleCmdProc.command = ["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"]
        toggleCmdProc.running = true
    }
    function toggleBluetooth() {
        toggleCmdProc.command = ["bash", "-c", "command -v bluetoothctl >/dev/null && bluetoothctl power " + (bluetoothEnabled ? "off" : "on")]
        toggleCmdProc.running = true
    }
    function toggleDND() {
        dndToggled()
    }

    // ── Visual ──────────────────────────────────────────────────────────────

    ColumnLayout {
        id: panelCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // ── Brightness ─────────────────────────────────────────
        MouseArea {
            Layout.fillWidth: true
            implicitHeight: brightCol.implicitHeight
            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 10
            onWheel: wheel => {
                var step = wheel.angleDelta.y / 120 * 0.05
                setBrightness(root.brightness + step)
            }

            ColumnLayout {
                id: brightCol
                anchors { left: parent.left; right: parent.right }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf185  Brightness"; color: Theme.warning; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily }
                    Item { Layout.fillWidth: true }
                    Text { text: Math.round(root.brightness * 100) + "%"; color: Theme.warning; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 8; radius: 4; color: Theme.trackBg
                    Rectangle {
                        width: parent.width * Math.min(1.0, root.brightness)
                        height: parent.height; radius: 4; color: Theme.warning
                        Behavior on width { NumberAnimation { duration: Theme.animNormal } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => { setBrightness(mouse.x / parent.width) }
                        onPositionChanged: mouse => { if (pressed) setBrightness(mouse.x / parent.width) }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 1; color: Theme.borderLight
            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 10
        }

        // ── Toggles / Network list ──────────────────────────────
        GridLayout {
            Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8
            Layout.leftMargin: 12; Layout.rightMargin: 12
            Layout.topMargin: 8; Layout.bottomMargin: 8
            visible: !root.networkViewOpen

            // Wifi
            Rectangle {
                id: wifiTile
                Layout.fillWidth: true; height: 52; radius: 12
                color: root.wifiEnabled ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.1) : Theme.surface
                border.color: root.wifiEnabled ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                SequentialAnimation {
                    id: wifiPress
                    NumberAnimation { target: wifiTile; property: "scale"; to: 0.93; duration: 80 }
                    NumberAnimation { target: wifiTile; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { wifiPress.start(); root.networkViewOpen = true; root.scanNetworks() }
                }
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "\uf1eb"; color: root.wifiEnabled ? root.barAccent : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                    Text { text: root.wifiEnabled ? (root.wifiSSID || "Wi-Fi") : "Wi-Fi"; color: root.wifiEnabled ? root.barAccent : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; elide: Text.ElideRight; Layout.maximumWidth: 120; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                }
            }

            // Bluetooth
            Rectangle {
                id: btTile
                Layout.fillWidth: true; height: 52; radius: 12
                color: root.bluetoothEnabled ? Qt.rgba(0.78,0.47,0.87,0.1) : Theme.surface
                border.color: root.bluetoothEnabled ? Qt.rgba(0.78,0.47,0.87,0.3) : Theme.borderMuted; border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                SequentialAnimation {
                    id: btPress
                    NumberAnimation { target: btTile; property: "scale"; to: 0.93; duration: 80 }
                    NumberAnimation { target: btTile; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { btPress.start(); toggleBluetooth() } }
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "\uf294"; color: root.bluetoothEnabled ? Theme.purple : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                    Text { text: "Bluetooth"; color: root.bluetoothEnabled ? Theme.purple : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                }
            }

            // DND
            Rectangle {
                id: dndTile
                Layout.fillWidth: true; height: 52; radius: 12
                color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.1) : Theme.surface
                border.color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.3) : Theme.borderMuted; border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                SequentialAnimation {
                    id: dndPress
                    NumberAnimation { target: dndTile; property: "scale"; to: 0.93; duration: 80 }
                    NumberAnimation { target: dndTile; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dndPress.start(); toggleDND() } }
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 3
                    Text { text: root.dndEnabled ? "\uf1f6" : "\uf0f3"; color: root.dndEnabled ? Theme.error : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                    Text { text: root.dndEnabled ? "DND On" : "DND Off"; color: root.dndEnabled ? Theme.error : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                }
            }

            // Mixer
            Rectangle {
                id: mixerTile
                Layout.fillWidth: true; height: 52; radius: 12
                color: mixerH.containsMouse ? Theme.surfaceHover : Theme.surface
                border.color: Theme.borderMuted; border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                SequentialAnimation {
                    id: mixerPress
                    NumberAnimation { target: mixerTile; property: "scale"; to: 0.93; duration: 80 }
                    NumberAnimation { target: mixerTile; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                }
                MouseArea {
                    id: mixerH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { mixerPress.start(); Hyprland.dispatch("exec [float;size 40% 90%;move 60% 5%] pavucontrol"); root.closeRequested() }
                }
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "\uf1de"; color: Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "Mixer"; color: Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }

        // ── Network list view ─────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8
            Layout.topMargin: 4; Layout.bottomMargin: 8
            spacing: 0
            visible: root.networkViewOpen

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4; Layout.rightMargin: 4
                spacing: 8

                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: backH.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "\uf053"; font.pixelSize: 10; font.family: Theme.fontFamily; color: backH.containsMouse ? root.barAccent : Theme.textDim; Behavior on color { ColorAnimation { duration: Theme.animFast } } }
                    MouseArea { id: backH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.networkViewOpen = false }
                }

                Text { text: "Networks"; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily; color: Theme.text }
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: scanH.containsMouse ? Theme.surfaceHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "\uf021"; font.pixelSize: 11; font.family: Theme.fontFamily; color: scanH.containsMouse ? root.barAccent : Theme.textDim; Behavior on color { ColorAnimation { duration: Theme.animFast } } }
                    MouseArea { id: scanH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.scanNetworks() }
                }

                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: wifiTogH.containsMouse ? (root.wifiEnabled ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.15) : Theme.surfaceHover) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "\uf1eb"; font.pixelSize: 12; font.family: Theme.fontFamily; color: root.wifiEnabled ? root.barAccent : Theme.textDimmer; Behavior on color { ColorAnimation { duration: Theme.animFast } } }
                    MouseArea { id: wifiTogH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggleWifi() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderLight; Layout.topMargin: 4; Layout.bottomMargin: 2 }

            Item {
                Layout.fillWidth: true; implicitHeight: 40
                visible: root.networkList.length === 0
                Text { anchors.centerIn: parent; text: root.wifiEnabled ? "Scanning..." : "Wi-Fi is off"; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint }
            }

            MouseArea {
                Layout.fillWidth: true
                implicitHeight: Math.min(netFlick.contentHeight, 220)
                visible: root.networkList.length > 0
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                    var step = 25
                    var newY = netFlick.contentY - (wheel.angleDelta.y > 0 ? step : -step)
                    netFlick.contentY = Math.max(0, Math.min(newY, netFlick.contentHeight - netFlick.height))
                }

                Flickable {
                    id: netFlick; anchors.fill: parent
                    contentHeight: netCol.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds; interactive: false

                    ColumnLayout {
                        id: netCol; width: parent.width; spacing: 2

                        Repeater {
                            model: root.networkList.length

                            Rectangle {
                                id: netItem
                                property var net: root.networkList[index] || ({})
                                property bool isConnected: net.inUse || false
                                property int sig: net.signal || 0

                                Layout.fillWidth: true; implicitHeight: 40; radius: 8
                                color: { if (isConnected) return Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.08); if (netItemH.containsMouse) return Qt.rgba(1,1,1,0.05); return "transparent" }
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                MouseArea {
                                    id: netItemH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (!netItem.isConnected) root.connectToNetwork(netItem.net.ssid, netItem.net.security) }
                                }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    spacing: 10
                                    Text { text: "\uf1eb"; font.pixelSize: 14; font.family: Theme.fontFamily; color: netItem.isConnected ? root.barAccent : netItem.sig >= 70 ? Theme.textDim : Theme.textDimmer }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: netItem.net.ssid || ""; font.pixelSize: 11; font.bold: true; font.family: Theme.fontFamily; color: netItem.isConnected ? root.barAccent : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Text {
                                            text: { var sec = netItem.net.security || ""; var p = []; if (sec && sec !== "--") p.push(sec); if (netItem.isConnected) p.push("Connected"); else if (root.isKnownNetwork(netItem.net.ssid || "")) p.push("Saved"); return p.join(" \u00b7 ") }
                                            font.pixelSize: 8; font.family: Theme.fontFamily; color: netItem.isConnected ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.5) : Theme.textFaint
                                        }
                                    }
                                    Item {
                                        visible: netItem.isConnected; implicitWidth: connBdg.implicitWidth + 12; implicitHeight: 16
                                        Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.15); border.color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3); border.width: 1
                                            Text { id: connBdg; anchors.centerIn: parent; text: "Connected"; font.pixelSize: 7; font.bold: true; font.family: Theme.fontFamily; color: root.barAccent }
                                        }
                                    }
                                    Row {
                                        visible: !netItem.isConnected; spacing: 1; Layout.alignment: Qt.AlignVCenter
                                        property color barColor: netItem.sig >= 70 ? Theme.success : netItem.sig >= 40 ? Theme.warning : Theme.error
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                property int barIdx: index
                                                property int threshold: [1, 25, 50, 75][barIdx]
                                                property bool active: netItem.sig >= threshold
                                                width: 3; height: [4, 7, 10, 14][barIdx]; radius: 1
                                                anchors.bottom: parent.bottom
                                                color: active ? parent.barColor : Qt.rgba(1,1,1,0.1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true; Layout.topMargin: 4
                text: "Click to connect"; font.pixelSize: 8; font.family: Theme.fontFamily
                color: Theme.textGhost; horizontalAlignment: Text.AlignHCenter
                visible: root.networkList.length > 0
            }
        }

        // ── Displays (visible when not in network drill-in) ─────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12; Layout.rightMargin: 12
            spacing: 6
            visible: !root.networkViewOpen && root.monitors.length > 0

            Rectangle {
                Layout.fillWidth: true; height: 1; color: Theme.borderLight
            }

            Text {
                text: "Displays"
                font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily
                color: Theme.textFaint; Layout.topMargin: 4
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 6

                Repeater {
                    model: root.monitors.length

                    Rectangle {
                        property var mon: root.monitors[index] || ({})
                        Layout.fillWidth: true; implicitHeight: monCol.implicitHeight + 16
                        radius: 8; color: Theme.surface
                        border.color: Qt.rgba(255,255,255,0.04); border.width: 1

                        ColumnLayout {
                            id: monCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 2
                            Text { text: mon.name || ""; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: Theme.text }
                            Text { text: (mon.width || 0) + "x" + (mon.height || 0) + " @ " + (mon.refreshRate || 0) + "Hz"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textFaint }
                            Rectangle {
                                width: vrrLabel.implicitWidth + 10; height: 14; radius: 3
                                color: mon.vrr > 0 ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.12) : Qt.rgba(255,255,255,0.04)
                                Text {
                                    id: vrrLabel; anchors.centerIn: parent
                                    text: mon.vrr === 2 ? "VRR FS" : mon.vrr === 1 ? "VRR ON" : "VRR OFF"
                                    font.pixelSize: 7; font.bold: true; font.family: Theme.fontFamily
                                    color: mon.vrr > 0 ? root.barAccent : Theme.textFaint
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
