import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import "../theme"

Item {
    id: root
    implicitWidth: iconText.implicitWidth
    implicitHeight: iconText.implicitHeight
    property bool popupOpen: false
    property bool dndEnabled: false   // passed from shellRoot.dndEnabled
    signal dndToggled()               // shell.qml flips shellRoot.dndEnabled on this signal

    // ── System state ───────────────────────────────────────────────────────
    property real volume: 0
    property bool volMuted: false
    property real brightness: 0
    property bool wifiEnabled: false
    property bool bluetoothEnabled: false
    property string wifiSSID: ""

    // ── Media state ────────────────────────────────────────────────────────
    property var playerList: []
    property int activeIdx: 0

    // Get the currently selected player (null-safe)
    property var activePlayer: {
        if (playerList.length === 0) return null
        var idx = Math.min(activeIdx, playerList.length - 1)
        return playerList[idx]
    }

    // Live position for progress bar
    property real mediaPos: 0

    // Accent color per player identity
    function playerColor(p) {
        if (!p) return Theme.accent
        var id = (p.identity || "").toLowerCase()
        if (id.indexOf("spotify") >= 0) return Theme.media
        if (id.indexOf("firefox") >= 0 || id.indexOf("chromium") >= 0 || id.indexOf("chrome") >= 0) return Theme.warning
        if (id.indexOf("vlc") >= 0) return Theme.purple
        return Theme.accent
    }

    // Update player list from MPRIS
    function refreshPlayers() {
        var list = Mpris.players.values
        var result = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].canTogglePlaying || list[i].trackTitle) result.push(list[i])
        }
        playerList = result
        if (activeIdx >= result.length) activeIdx = Math.max(0, result.length - 1)
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { refreshPlayers() }
    }

    Component.onCompleted: refreshPlayers()

    // Position polling (only when popup open and playing)
    Timer {
        interval: 1000
        running: popupOpen && root.activePlayer !== null
                 && root.activePlayer.playbackState === MprisPlaybackState.Playing
        repeat: true
        onTriggered: {
            if (root.activePlayer) root.mediaPos = root.activePlayer.position
        }
    }

    // React to playback state changes
    Connections {
        target: root.activePlayer
        enabled: root.activePlayer !== null
        function onPositionChanged() { root.mediaPos = root.activePlayer ? root.activePlayer.position : 0 }
        function onPlaybackStateChanged() { root.mediaPos = root.activePlayer ? root.activePlayer.position : 0 }
    }

    // ── System polling ─────────────────────────────────────────────────────
    function refresh() {
        volReadProc.running = true
        wifiReadProc.running = true
        btReadProc.running = true
    }

    function refreshBrightness() {
        brightReadProc.running = true
    }

    Timer {
        interval: popupOpen ? 2000 : 10000
        running: true; repeat: true
        onTriggered: refresh()
    }

    // Volume
    Process {
        id: volReadProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                var match = data.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (match) {
                    var v = parseFloat(match[1])
                    root.volume = isNaN(v) ? 0 : v
                    root.volMuted = !!match[2]
                }
            }
        }
    }

    // Brightness (DDC/CI via ddcutil — reads from first detected display)
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

    // ── Commands ────────────────────────────────────────────────────────────
    Process { id: volCmdProc; onRunningChanged: { if (!running) volReadProc.running = true } }
    Process { id: brightCmdProc }
    Process { id: toggleCmdProc; onRunningChanged: { if (!running) refresh() } }

    function setVolume(v) {
        volCmdProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.max(0, Math.min(1.5, v)).toFixed(2)]
        volCmdProc.running = true
    }
    function toggleVolMute() {
        volCmdProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        volCmdProc.running = true
    }
    function setBrightness(v) {
        var pct = Math.max(5, Math.min(100, Math.round(v * 100)))
        root.brightness = pct / 100  // Optimistic update for responsive slider
        // DDC/CI: set both monitors (bus 8 = ViewSonic, bus 10 = Dell)
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
        dndToggled()   // shell.qml handles the actual flip via onDndToggled
    }

    // ── Bar icon ───────────────────────────────────────────────────────────
    Text {
        id: iconText
        text: "\uf013"
        color: iconHover.containsMouse ? Theme.accent : Theme.purple
        font.pixelSize: Theme.fontIcon
        font.family: Theme.fontFamily
        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
    }

    MouseArea {
        id: iconHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popupOpen = !popupOpen
    }

    // ── Focus grab ─────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        id: ccGrab
        windows: [ccPopup]
        active: false
        onCleared: popupOpen = false
    }
    Timer { id: ccGrabDelay; interval: 50; onTriggered: ccGrab.active = popupOpen }
    onPopupOpenChanged: {
        if (popupOpen) {
            refresh()
            refreshBrightness()
            refreshPlayers()
            if (root.activePlayer) root.mediaPos = root.activePlayer.position
            ccGrabDelay.restart()
        } else {
            ccGrabDelay.stop()
            ccGrab.active = false
        }
    }

    // ── Popup ──────────────────────────────────────────────────────────────
    PopupWindow {
        id: ccPopup
        visible: popupOpen
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth: 340
        implicitHeight: panelCol.implicitHeight
        color: Theme.popupBg

        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.color: Theme.border; border.width: 1; radius: Theme.popupRadius
            clip: true

            ColumnLayout {
                id: panelCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 0

                // ══════════════════════════════════════════════════════════
                // ── NOW PLAYING ───────────────────────────────────────────
                // ══════════════════════════════════════════════════════════

                // Player tabs (only shown when players exist)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 10
                    spacing: 6
                    visible: root.playerList.length > 0

                    Repeater {
                        model: root.playerList.length
                        Rectangle {
                            property var player: root.playerList[index]
                            property bool isActive: index === root.activeIdx
                            property color pColor: root.playerColor(player)

                            height: 22; radius: 8
                            implicitWidth: tabRow.implicitWidth + 16
                            color: isActive ? Qt.rgba(pColor.r, pColor.g, pColor.b, 0.15) : "transparent"
                            border.color: isActive ? Qt.rgba(pColor.r, pColor.g, pColor.b, 0.3) : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Row {
                                id: tabRow
                                anchors.centerIn: parent; spacing: 4
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    color: parent.parent.pColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: player ? (player.identity || "Media") : "Media"
                                    color: parent.parent.isActive ? parent.parent.pColor : Theme.textDim
                                    font.pixelSize: Theme.fontSm; font.bold: true
                                    font.family: Theme.fontFamily
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.activeIdx = index
                                    if (root.activePlayer) root.mediaPos = root.activePlayer.position
                                }
                            }
                        }
                    }
                }

                // Active player card
                Item {
                    Layout.fillWidth: true
                    implicitHeight: playerCol.implicitHeight
                    visible: root.playerList.length > 0

                    id: playerCard
                    property var p: root.activePlayer
                    property color accent: root.playerColor(root.activePlayer)

                    ColumnLayout {
                        id: playerCol
                        anchors { left: parent.left; right: parent.right }
                        spacing: 0

                        // Hero art
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 130
                            color: Theme.surface

                            Image {
                                id: heroArt
                                anchors.fill: parent
                                source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: heroArt.status !== Image.Ready
                                text: "\uf1bc"
                                color: playerCard.accent
                                font.pixelSize: 40; font.family: Theme.fontFamily
                                opacity: 0.3
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 50
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(15/255, 12/255, 20/255, 0.85) }
                                }
                            }
                        }

                        // Track info
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 8
                            spacing: 1

                            Text {
                                text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown") : ""
                                color: Theme.text; font.pixelSize: Theme.fontBar; font.bold: true
                                font.family: Theme.fontFamily; elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: {
                                    if (!root.activePlayer) return ""
                                    var artist = root.activePlayer.trackArtist || ""
                                    var album = root.activePlayer.trackAlbum || ""
                                    if (artist && album) return artist + " — " + album
                                    return artist || album || ""
                                }
                                color: Theme.textDim; font.pixelSize: Theme.fontSm
                                font.family: Theme.fontFamily; elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Progress bar
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 8
                            spacing: 3

                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.trackBg

                                Rectangle {
                                    width: {
                                        if (!root.activePlayer) return 0
                                        var len = root.activePlayer.length
                                        if (!len || len <= 0) return 0
                                        return Math.min(1, root.mediaPos / len) * parent.width
                                    }
                                    height: parent.height; radius: 4
                                    color: playerCard.accent
                                    Behavior on width { NumberAnimation { duration: Theme.animNormal } }
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (root.activePlayer && root.activePlayer.length > 0 && root.activePlayer.canSeek) {
                                            var seekTo = (mouse.x / parent.width) * root.activePlayer.length
                                            root.activePlayer.position = seekTo
                                            root.mediaPos = seekTo
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed && root.activePlayer && root.activePlayer.length > 0 && root.activePlayer.canSeek) {
                                            var seekTo = Math.max(0, Math.min(root.activePlayer.length, (mouse.x / parent.width) * root.activePlayer.length))
                                            root.activePlayer.position = seekTo
                                            root.mediaPos = seekTo
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: {
                                        var s = Math.floor(root.mediaPos)
                                        if (isNaN(s) || s < 0) s = 0
                                        return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
                                    }
                                    color: Theme.textDimmer; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: {
                                        if (!root.activePlayer) return "0:00"
                                        var s = Math.floor(root.activePlayer.length || 0)
                                        if (isNaN(s) || s <= 0) return "∞"
                                        return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
                                    }
                                    color: Theme.textDimmer; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                                }
                            }
                        }

                        // Controls
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12; Layout.rightMargin: 12
                            Layout.topMargin: 4; Layout.bottomMargin: 8
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 0

                            Item { Layout.fillWidth: true }

                            // Prev
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: npPrevH.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    anchors.centerIn: parent; text: "\uf048"
                                    color: Theme.text; font.pixelSize: Theme.fontBar; font.family: Theme.fontFamily
                                }
                                MouseArea {
                                    id: npPrevH; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous() }
                                }
                            }

                            Item { Layout.preferredWidth: 12 }

                            // Play/Pause
                            Rectangle {
                                width: 36; height: 36; radius: 18
                                color: playerCard.accent
                                scale: npPlayH.containsMouse ? 1.08 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
                                Text {
                                    anchors.centerIn: parent
                                    text: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "\uf04c" : "\uf04b"
                                    color: Theme.textDark
                                    font.pixelSize: Theme.fontBar; font.family: Theme.fontFamily
                                }
                                MouseArea {
                                    id: npPlayH; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (root.activePlayer && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying() }
                                }
                            }

                            Item { Layout.preferredWidth: 12 }

                            // Next
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: npNextH.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    anchors.centerIn: parent; text: "\uf051"
                                    color: Theme.text; font.pixelSize: Theme.fontBar; font.family: Theme.fontFamily
                                }
                                MouseArea {
                                    id: npNextH; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next() }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // Not Playing state
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    visible: root.playerList.length === 0

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "\uf1bc"; color: Theme.textGhost
                            font.pixelSize: 24; font.family: Theme.fontFamily
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "Not Playing"; color: Theme.textFaint
                            font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                // ══════════════════════════════════════════════════════════
                // ── SYSTEM CONTROLS ───────────────────────────────────────
                // ══════════════════════════════════════════════════════════

                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Theme.borderLight
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                }

                // Volume — MouseArea wraps entire section for scroll
                MouseArea {
                    Layout.fillWidth: true
                    implicitHeight: volCol.implicitHeight
                    Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 10
                    onWheel: wheel => {
                        var step = wheel.angleDelta.y / 120 * 0.05
                        setVolume(root.volume + step)
                    }

                    ColumnLayout {
                        id: volCol
                        anchors { left: parent.left; right: parent.right }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: root.volMuted ? "\uf6a9" : "\uf028"
                                color: root.volMuted ? Theme.error : Theme.accent
                                font.pixelSize: 16; font.family: Theme.fontFamily
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: toggleVolMute()
                                }
                            }
                            Text { text: "  Volume"; color: Theme.text; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.volMuted ? "Muted" : Math.round(root.volume * 100) + "%"
                                color: root.volMuted ? Theme.error : Theme.accent
                                font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 8; radius: 4; color: Theme.trackBg
                            Rectangle {
                                width: parent.width * Math.min(1.0, root.volMuted ? 0 : root.volume)
                                height: parent.height; radius: 4
                                color: root.volMuted ? Theme.error : Theme.accent
                                Behavior on width { NumberAnimation { duration: Theme.animNormal } }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => { setVolume(mouse.x / parent.width) }
                                onPositionChanged: mouse => { if (pressed) setVolume(mouse.x / parent.width) }
                            }
                        }
                    }
                }

                // Brightness — MouseArea wraps entire section for scroll
                MouseArea {
                    Layout.fillWidth: true
                    implicitHeight: brightCol.implicitHeight
                    Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 6
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

                // Toggles
                GridLayout {
                    Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    Layout.topMargin: 8; Layout.bottomMargin: 12

                    // Wifi
                    Rectangle {
                        Layout.fillWidth: true; height: 52; radius: 12
                        color: root.wifiEnabled ? Qt.rgba(0,1,0.92,0.1) : Theme.surface
                        border.color: root.wifiEnabled ? Qt.rgba(0,1,0.92,0.3) : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggleWifi() }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 3
                            Text { text: "\uf1eb"; color: root.wifiEnabled ? Theme.accent : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                            Text { text: root.wifiEnabled ? (root.wifiSSID || "Wi-Fi") : "Wi-Fi"; color: root.wifiEnabled ? Theme.accent : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; elide: Text.ElideRight; Layout.maximumWidth: 120; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                        }
                    }

                    // Bluetooth
                    Rectangle {
                        Layout.fillWidth: true; height: 52; radius: 12
                        color: root.bluetoothEnabled ? Qt.rgba(0.78,0.47,0.87,0.1) : Theme.surface
                        border.color: root.bluetoothEnabled ? Qt.rgba(0.78,0.47,0.87,0.3) : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggleBluetooth() }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 3
                            Text { text: "\uf294"; color: root.bluetoothEnabled ? Theme.purple : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                            Text { text: "Bluetooth"; color: root.bluetoothEnabled ? Theme.purple : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                        }
                    }

                    // DND
                    Rectangle {
                        Layout.fillWidth: true; height: 52; radius: 12
                        color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.1) : Theme.surface
                        border.color: root.dndEnabled ? Qt.rgba(0.95,0.55,0.66,0.3) : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggleDND() }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 3
                            Text { text: root.dndEnabled ? "\uf1f6" : "\uf0f3"; color: root.dndEnabled ? Theme.error : Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                            Text { text: root.dndEnabled ? "DND On" : "DND Off"; color: root.dndEnabled ? Theme.error : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: Theme.animMedium } } }
                        }
                    }

                    // Mixer
                    Rectangle {
                        Layout.fillWidth: true; height: 52; radius: 12
                        color: mixerH.containsMouse ? Theme.surfaceHover : Theme.surface
                        border.color: Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        MouseArea {
                            id: mixerH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { Hyprland.dispatch("exec [float;size 40% 90%;move 60% 5%] pavucontrol"); popupOpen = false }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 3
                            Text { text: "\uf1de"; color: Theme.textDimmer; font.pixelSize: 16; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter }
                            Text { text: "Mixer"; color: Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
}
