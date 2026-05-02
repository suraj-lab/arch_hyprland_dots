import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight - Theme.barPadding * 2
    scale: hover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    property bool popupOpen: false

    property real vol: 0
    property bool isMuted: false

    // ── Audio device picker state ────────────────────────────────────────
    property bool deviceViewOpen: false
    property bool appsViewOpen: false
    property string audioTab: "output"   // "output" | "input"
    property var sinkList: []
    property var sourceList: []
    property var appList: []
    property string defaultSinkName: ""
    property string defaultSourceName: ""
    property string defaultSinkDesc: ""

    // ── Media state ──────────────────────────────────────────────────────
    property var playerList: []
    property int activeIdx: 0
    property var activePlayer: {
        if (playerList.length === 0) return null
        var idx = Math.min(activeIdx, playerList.length - 1)
        return playerList[idx]
    }
    property real mediaPos: 0

    function playerColor(p) {
        if (!p) return root.barAccent
        var id = (p.identity || "").toLowerCase()
        if (id.indexOf("spotify") >= 0) return Theme.media
        if (id.indexOf("firefox") >= 0 || id.indexOf("chromium") >= 0 || id.indexOf("chrome") >= 0) return Theme.warning
        if (id.indexOf("vlc") >= 0) return Theme.purple
        return root.barAccent
    }

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

    Timer {
        interval: 1000
        running: popupOpen && root.activePlayer !== null
                 && root.activePlayer.playbackState === MprisPlaybackState.Playing
        repeat: true
        onTriggered: { if (root.activePlayer) root.mediaPos = root.activePlayer.position }
    }

    Connections {
        target: root.activePlayer
        enabled: root.activePlayer !== null
        function onPositionChanged() { root.mediaPos = root.activePlayer ? root.activePlayer.position : 0 }
        function onPlaybackStateChanged() { root.mediaPos = root.activePlayer ? root.activePlayer.position : 0 }
    }

    // ── Read volume via wpctl ──────────────────────────────────────────────
    function refreshVolume() { getVolumeProc.running = true }

    Process {
        id: getVolumeProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                var match = data.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (match) {
                    root.vol = parseFloat(match[1])
                    root.isMuted = !!match[2]
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: refreshVolume()
    }

    Component.onCompleted: {
        refreshVolume()
        refreshPlayers()
        defaultSinkProc.running = true
    }

    // ── Write volume/mute via wpctl ────────────────────────────────────────
    Process {
        id: cmdProc
        onRunningChanged: { if (!running) refreshVolume() }
    }

    function runCmd(args) {
        cmdProc.command = args
        cmdProc.running = true
    }

    function setVolume(v) {
        var clamped = Math.max(0, Math.min(1.5, v)).toFixed(2)
        runCmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", clamped])
    }

    function toggleMute() {
        runCmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    }

    // ── Audio device scanning ─────────────────────────────────────────────
    property var _sinkBuf: []
    property var _sourceBuf: []
    property var _appBuf: []
    property var _clientBuf: []
    property var clientMap: ({})

    Process {
        id: sinkScanProc
        command: ["bash", "-c", "pactl -f json list sinks 2>/dev/null"]
        stdout: SplitParser { onRead: function(line) { root._sinkBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._sinkBuf.join(""); root._sinkBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var result = []
                    for (var i = 0; i < arr.length; i++) {
                        var s = arr[i]
                        result.push({
                            name: s.name || "",
                            desc: s.description || s.name || "",
                            state: (s.state || "").toLowerCase(),
                            index: s.index || 0,
                            isDefault: (s.name || "") === root.defaultSinkName
                        })
                    }
                    root.sinkList = result
                    for (var j = 0; j < result.length; j++) {
                        if (result[j].isDefault) { root.defaultSinkDesc = result[j].desc; break }
                    }
                } catch(e) { root.sinkList = [] }
            }
        }
    }

    Process {
        id: sourceScanProc
        command: ["bash", "-c", "pactl -f json list sources 2>/dev/null"]
        stdout: SplitParser { onRead: function(line) { root._sourceBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._sourceBuf.join(""); root._sourceBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var result = []
                    for (var i = 0; i < arr.length; i++) {
                        var s = arr[i]
                        var name = s.name || ""
                        if (name.indexOf(".monitor") >= 0) continue
                        result.push({
                            name: name,
                            desc: s.description || name,
                            state: (s.state || "").toLowerCase(),
                            index: s.index || 0,
                            isDefault: name === root.defaultSourceName
                        })
                    }
                    root.sourceList = result
                } catch(e) { root.sourceList = [] }
            }
        }
    }

    Process {
        id: clientScanProc
        command: ["bash", "-c", "pactl -f json list clients 2>/dev/null"]
        stdout: SplitParser { onRead: function(line) { root._clientBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._clientBuf.join(""); root._clientBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var map = {}
                    for (var i = 0; i < arr.length; i++) {
                        var c = arr[i]
                        var props = c.properties || {}
                        var name = props["application.name"]
                                   || props["application.process.binary"]
                                   || ""
                        if (name) map[String(c.index)] = name
                    }
                    root.clientMap = map
                } catch(e) { root.clientMap = {} }
                appScanProc.running = true
            }
        }
    }

    Process {
        id: appScanProc
        command: ["bash", "-c", "pactl -f json list sink-inputs 2>/dev/null"]
        stdout: SplitParser { onRead: function(line) { root._appBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._appBuf.join(""); root._appBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var result = []
                    for (var i = 0; i < arr.length; i++) {
                        var si = arr[i]
                        var props = si.properties || {}
                        var appName = props["application.name"] || ""
                        if (!appName && si.client) {
                            appName = root.clientMap[String(si.client)] || ""
                        }
                        if (!appName) {
                            appName = props["application.process.binary"]
                                      || props["node.name"]
                                      || "Unknown"
                        }
                        var vol = 0
                        if (si.volume) {
                            var chans = Object.keys(si.volume)
                            var total = 0; var chanCount = 0
                            for (var c = 0; c < chans.length; c++) {
                                var cv = si.volume[chans[c]]
                                if (cv && typeof cv === "object" && cv.value_percent) {
                                    total += parseInt(cv.value_percent.replace("%", "")) || 0
                                    chanCount++
                                }
                            }
                            if (chanCount > 0) vol = Math.round(total / chanCount)
                        }
                        result.push({
                            index: si.index || 0,
                            appName: appName,
                            volume: vol,
                            muted: si.mute || false
                        })
                    }
                    root.appList = result
                } catch(e) { root.appList = [] }
            }
        }
    }

    Process {
        id: defaultSinkProc
        command: ["pactl", "get-default-sink"]
        stdout: SplitParser {
            onRead: function(line) { var t = line.trim(); if (t) root.defaultSinkName = t }
        }
        onRunningChanged: { if (!running) sinkScanProc.running = true }
    }

    Process {
        id: defaultSourceProc
        command: ["pactl", "get-default-source"]
        stdout: SplitParser {
            onRead: function(line) { var t = line.trim(); if (t) root.defaultSourceName = t }
        }
        onRunningChanged: { if (!running) sourceScanProc.running = true }
    }

    Process {
        id: audioSetProc
        onRunningChanged: { if (!running) scanAudio() }
    }

    Process { id: appVolProc }

    function scanAudio() {
        defaultSinkProc.running = true
        defaultSourceProc.running = true
        clientScanProc.running = true
    }

    function setDefaultSink(sinkName) {
        audioSetProc.command = ["pactl", "set-default-sink", sinkName]
        audioSetProc.running = true
    }

    function setDefaultSource(sourceName) {
        audioSetProc.command = ["pactl", "set-default-source", sourceName]
        audioSetProc.running = true
    }

    function setAppVolume(sinkInputIndex, pct) {
        appVolProc.command = ["bash", "-c", "pactl set-sink-input-volume " + sinkInputIndex + " " + pct + "%"]
        appVolProc.running = true
    }

    function updateAppVolumeUI(listIndex, newVol) {
        var list = []
        for (var i = 0; i < root.appList.length; i++) {
            if (i === listIndex) {
                var old = root.appList[i]
                list.push({ index: old.index, appName: old.appName, volume: newVol, muted: old.muted })
            } else {
                list.push(root.appList[i])
            }
        }
        root.appList = list
    }

    function appColor(name) {
        var n = name.toLowerCase()
        if (n.indexOf("spotify") >= 0) return Theme.media
        if (n.indexOf("firefox") >= 0 || n.indexOf("chromium") >= 0 || n.indexOf("chrome") >= 0) return Theme.warning
        if (n.indexOf("discord") >= 0) return "#7289da"
        if (n.indexOf("vlc") >= 0) return Theme.purple
        if (n.indexOf("steam") >= 0) return root.barAccent
        return root.barAccent
    }

    // ── Bar chip ───────────────────────────────────────────────────────────
    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            text: {
                if (root.isMuted) return "\uf6a9"
                var v = Math.round(root.vol * 100)
                return (v > 50 ? "\uf028" : "\uf027") + " " + v + "%"
            }
            color: hover.containsMouse ? Theme.success : root.barAccent
            font.pixelSize: Theme.fontIcon; font.bold: true; font.family: Theme.fontFamily
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) popupOpen = !popupOpen
            else toggleMute()
        }
        onWheel: wheel => {
            var step = wheel.angleDelta.y / 120 * 0.05
            setVolume(root.vol + step)
        }
    }

    // ── Popup focus grab ────────────────────────────────────────────────────
    property bool _grabReady: false

    HyprlandFocusGrab {
        id: volGrab
        windows: [volPopup]
        active: popupOpen && root._grabReady
        onCleared: popupOpen = false
    }

    Timer {
        id: volGrabDelay
        interval: 50
        onTriggered: root._grabReady = true
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            volGrabDelay.restart()
            scanAudio()
            refreshPlayers()
            if (root.activePlayer) root.mediaPos = root.activePlayer.position
        } else {
            root._grabReady = false
            volGrabDelay.stop()
            deviceViewOpen = false
            appsViewOpen = false
            audioTab = "output"
        }
    }

    // ── Popup ──────────────────────────────────────────────────────────────
    PopupWindow {
        id: volPopup
        visible: popupOpen
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom

        implicitWidth: 280
        implicitHeight: col.implicitHeight + 24
        color: Theme.popupBg

        // ── Album art blur background ─────────────────────────────────────
        Item {
            anchors.fill: parent
            z: 0

            property bool showBlur: root.activePlayer !== null
                                    && root.activePlayer.trackArtUrl
                                    && popupBlurArt.status === Image.Ready

            visible: opacity > 0
            opacity: showBlur ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }

            Image {
                id: popupBlurArt
                anchors.centerIn: parent
                width: parent.width * 1.4
                height: parent.height * 1.4
                source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }

            FastBlur {
                anchors.fill: parent
                source: popupBlurArt.status === Image.Ready ? popupBlurArt : null
                radius: 32
                visible: popupBlurArt.status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(15/255, 12/255, 20/255, 0.65)
            }
        }

        Rectangle {
            anchors.fill: parent; color: "transparent"
            border.color: Theme.border; border.width: 1; radius: Theme.popupRadius
            z: 1

            scale: popupOpen ? 1.0 : 0.95
            opacity: popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: Theme.popupPadding }
                spacing: 10

                // ── Media player (full when normal, compact when device view) ──

                // Full media player
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.playerList.length > 0 && !root.deviceViewOpen && !root.appsViewOpen

                    id: fullPlayer
                    property var p: root.activePlayer
                    property color pAccent: root.playerColor(root.activePlayer)

                    // Player tabs
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        visible: root.playerList.length > 1

                        Repeater {
                            model: root.playerList.length
                            Rectangle {
                                property var player: root.playerList[index]
                                property bool isActive: index === root.activeIdx
                                property color pColor: root.playerColor(player)
                                height: 20; radius: 6; implicitWidth: ftLabel.implicitWidth + 14
                                color: isActive ? Qt.rgba(pColor.r, pColor.g, pColor.b, 0.15) : "transparent"
                                border.color: isActive ? Qt.rgba(pColor.r, pColor.g, pColor.b, 0.3) : "transparent"; border.width: 1
                                Row {
                                    anchors.centerIn: parent; spacing: 4
                                    Rectangle { width: 5; height: 5; radius: 3; color: parent.parent.pColor; anchors.verticalCenter: parent.verticalCenter }
                                    Text { id: ftLabel; text: player ? (player.identity || "Media") : ""; color: parent.parent.isActive ? parent.parent.pColor : Theme.textDim; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeIdx = index; if (root.activePlayer) root.mediaPos = root.activePlayer.position } }
                            }
                        }
                    }

                    // Hero art
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 110
                        Layout.topMargin: root.playerList.length > 1 ? 4 : 0
                        color: Theme.surface; clip: true

                        Image {
                            id: heroArt; anchors.fill: parent
                            source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent; visible: heroArt.status !== Image.Ready
                            text: "\uf1bc"; color: fullPlayer.pAccent; font.pixelSize: 36; font.family: Theme.fontFamily; opacity: 0.3
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 40
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(15/255, 12/255, 20/255, 0.85) }
                            }
                        }
                    }

                    // Track info (crossfade on change)
                    Text {
                        id: trackTitleText
                        text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown") : ""
                        color: Theme.text; font.pixelSize: 12; font.bold: true; font.family: Theme.fontFamily
                        elide: Text.ElideRight; Layout.fillWidth: true; Layout.topMargin: 6
                        onTextChanged: function() { if (trackTitleText.text) trackTitleFade.restart() }
                        SequentialAnimation {
                            id: trackTitleFade
                            NumberAnimation { target: trackTitleText; property: "opacity"; to: 0; duration: 80 }
                            NumberAnimation { target: trackTitleText; property: "opacity"; to: 1; duration: 200 }
                        }
                    }
                    Text {
                        id: trackArtistText
                        text: { if (!root.activePlayer) return ""; var a = root.activePlayer.trackArtist || ""; var al = root.activePlayer.trackAlbum || ""; if (a && al) return a + " — " + al; return a || al || "" }
                        color: Theme.textDim; font.pixelSize: 9; font.family: Theme.fontFamily
                        elide: Text.ElideRight; Layout.fillWidth: true
                        onTextChanged: function() { if (trackArtistText.text) trackArtistFade.restart() }
                        SequentialAnimation {
                            id: trackArtistFade
                            NumberAnimation { target: trackArtistText; property: "opacity"; to: 0; duration: 80 }
                            NumberAnimation { target: trackArtistText; property: "opacity"; to: 1; duration: 200 }
                        }
                    }

                    // Progress
                    Rectangle {
                        Layout.fillWidth: true; height: 6; radius: 3
                        color: Theme.trackBg; Layout.topMargin: 6

                        Rectangle {
                            width: {
                                if (!root.activePlayer) return 0
                                var l = root.activePlayer.length
                                if (!l || l <= 0) return 0
                                return Math.min(1, root.mediaPos / l) * parent.width
                            }
                            height: parent.height; radius: 3; color: fullPlayer.pAccent
                            Behavior on width { NumberAnimation { duration: Theme.animNormal } }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (root.activePlayer && root.activePlayer.length > 0 && root.activePlayer.canSeek) {
                                    var s = (mouse.x / parent.width) * root.activePlayer.length
                                    root.activePlayer.position = s
                                    root.mediaPos = s
                                }
                            }
                            onPositionChanged: mouse => {
                                if (pressed && root.activePlayer && root.activePlayer.length > 0 && root.activePlayer.canSeek) {
                                    var s = Math.max(0, Math.min(root.activePlayer.length, (mouse.x / parent.width) * root.activePlayer.length))
                                    root.activePlayer.position = s
                                    root.mediaPos = s
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
                            color: Theme.textDimmer; font.pixelSize: 9; font.family: Theme.fontFamily
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: {
                                if (!root.activePlayer) return "0:00"
                                var s = Math.floor(root.activePlayer.length || 0)
                                if (isNaN(s) || s <= 0) return "\u221e"
                                return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
                            }
                            color: Theme.textDimmer; font.pixelSize: 9; font.family: Theme.fontFamily
                        }
                    }

                    // Controls
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2; Layout.bottomMargin: 4
                        spacing: 0

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: fpPrevH.containsMouse ? Theme.surfaceHover : "transparent"
                            Text {
                                anchors.centerIn: parent; text: "\uf048"
                                color: Theme.text; font.pixelSize: 12; font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: fpPrevH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous() }
                            }
                        }

                        Item { Layout.preferredWidth: 10 }

                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: fullPlayer.pAccent
                            scale: fpPlayH.containsMouse ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
                            Text {
                                anchors.centerIn: parent
                                text: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "\uf04c" : "\uf04b"
                                color: Theme.textDark; font.pixelSize: 12; font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: fpPlayH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying() }
                            }
                        }

                        Item { Layout.preferredWidth: 10 }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: fpNextH.containsMouse ? Theme.surfaceHover : "transparent"
                            Text {
                                anchors.centerIn: parent; text: "\uf051"
                                color: Theme.text; font.pixelSize: 12; font.family: Theme.fontFamily
                            }
                            MouseArea {
                                id: fpNextH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next() }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 1
                        color: Theme.borderLight; Layout.topMargin: 2
                    }
                }

                // Compact media player (when device view is open)
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    visible: root.playerList.length > 0 && (root.deviceViewOpen || root.appsViewOpen)

                    Rectangle {
                        width: 36; height: 36; radius: 6; color: Theme.surface; clip: true
                        Image {
                            anchors.fill: parent
                            source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop; asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent; visible: !root.activePlayer || !root.activePlayer.trackArtUrl
                            text: "\uf1bc"; color: root.playerColor(root.activePlayer); font.pixelSize: 16; font.family: Theme.fontFamily; opacity: 0.4
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { text: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textDim; elide: Text.ElideRight; Layout.fillWidth: true }
                    }

                    Row {
                        spacing: 4
                        Text {
                            text: "\uf048"; font.pixelSize: 10; font.family: Theme.fontFamily; color: Theme.textDim
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous() }
                            }
                        }
                        Text {
                            text: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing ? "\uf04c" : "\uf04b"
                            font.pixelSize: 10; font.family: Theme.fontFamily
                            color: root.playerColor(root.activePlayer)
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying() }
                            }
                        }
                        Text {
                            text: "\uf051"; font.pixelSize: 10; font.family: Theme.fontFamily; color: Theme.textDim
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next() }
                            }
                        }
                    }
                }

                // Divider after compact player
                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Theme.borderLight
                    visible: root.playerList.length > 0 && (root.deviceViewOpen || root.appsViewOpen)
                    Layout.topMargin: 4; Layout.bottomMargin: 2
                }

                // ── Volume slider (always visible) ────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf028  Volume"; color: Theme.text; font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Math.round(root.vol * 100) + "%"
                        color: root.isMuted ? Theme.error : root.barAccent
                        font.pixelSize: Theme.fontBar; font.bold: true; font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    onWheel: wheel => {
                        var step = wheel.angleDelta.y / 120 * 0.05
                        setVolume(root.vol + step)
                    }

                    Rectangle {
                        anchors.fill: parent; radius: 4; color: Theme.trackBg
                        Rectangle {
                            width: parent.width * Math.min(1.0, root.vol)
                            height: parent.height; radius: 4
                            color: root.isMuted ? Theme.mutedSlider : root.barAccent
                            Behavior on width  { NumberAnimation  { duration: Theme.animNormal } }
                            Behavior on color  { ColorAnimation   { duration: Theme.animMedium } }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => { setVolume(mouse.x / parent.width) }
                            onPositionChanged: mouse => { if (pressed) setVolume(mouse.x / parent.width) }
                        }
                    }
                }

                Text {
                    visible: root.vol > 1.0
                    text: "\u26a0  Above 100%"; color: Theme.warning
                    font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                }

                // ── Mute button (normal view) ─────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    visible: !root.deviceViewOpen && !root.appsViewOpen

                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 8
                        color: root.isMuted ? Theme.errorBg : Theme.surface
                        border.color: root.isMuted ? Theme.errorBorder : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animMedium } }
                        Text {
                            anchors.centerIn: parent
                            text: root.isMuted ? "\uf6a9  Unmute" : "\uf028  Mute"
                            color: root.isMuted ? Theme.error : Theme.text
                            font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: toggleMute()
                        }
                    }
                }

                // Devices + Apps buttons (side by side)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !root.deviceViewOpen && !root.appsViewOpen

                    // Devices button
                    Rectangle {
                        Layout.fillWidth: true; height: 26; radius: 8
                        color: devBtnH.containsMouse ? Theme.surfaceHover : Theme.surface
                        border.color: Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 6
                            Text { text: "\uf025"; font.pixelSize: 10; font.family: Theme.fontFamily; color: Theme.textDim }
                            Text { text: "Devices"; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textDim }
                            Item { Layout.fillWidth: true }
                            Text { text: "\uf054"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textGhost }
                        }

                        MouseArea {
                            id: devBtnH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.deviceViewOpen = true; root.scanAudio() }
                        }
                    }

                    // Apps button
                    Rectangle {
                        Layout.fillWidth: true; height: 26; radius: 8
                        color: appBtnH.containsMouse ? Theme.surfaceHover : Theme.surface
                        border.color: Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 6
                            Text { text: "\uf1de"; font.pixelSize: 10; font.family: Theme.fontFamily; color: Theme.textDim }
                            Text { text: "Apps"; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textDim }
                            Item { Layout.fillWidth: true }
                            Text { text: "\uf054"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textGhost }
                        }

                        MouseArea {
                            id: appBtnH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.appsViewOpen = true; clientScanProc.running = true }
                        }
                    }
                }

                // ── Audio device picker (drill-in view) ───────────
                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Theme.borderLight
                    visible: root.deviceViewOpen
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.deviceViewOpen

                    // Header
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8

                        Rectangle {
                            width: 24; height: 24; radius: 6
                            color: devBackH.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent; text: "\uf053"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: devBackH.containsMouse ? root.barAccent : Theme.textDim
                            }
                            MouseArea {
                                id: devBackH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.deviceViewOpen = false
                            }
                        }

                        Text {
                            text: "Audio Devices"
                            font.pixelSize: Theme.fontBar; font.bold: true
                            font.family: Theme.fontFamily; color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // Tabs
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6; spacing: 6

                        Repeater {
                            model: [
                                { key: "output", label: "Output" },
                                { key: "input", label: "Input" }
                            ]

                            Rectangle {
                                required property var modelData
                                property bool isActive: root.audioTab === modelData.key
                                height: 22; radius: 6
                                implicitWidth: atLabel.implicitWidth + 20
                                color: isActive ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.12) : Theme.surface
                                border.color: isActive ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                                Text {
                                    id: atLabel; anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily
                                    color: isActive ? root.barAccent : Theme.textDim
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.audioTab = modelData.key
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 1; color: Theme.borderLight
                        Layout.topMargin: 6; Layout.bottomMargin: 2
                    }

                    // ── Output tab ─────────────────────────────
                    Repeater {
                        model: root.audioTab === "output" ? root.sinkList.length : 0

                        Rectangle {
                            id: sinkItem
                            property var dev: root.sinkList[index] || ({})
                            property bool isDef: dev.isDefault || false

                            Layout.fillWidth: true; implicitHeight: 40; radius: 8
                            color: isDef ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.08)
                                   : sinkH.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            MouseArea {
                                id: sinkH; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (!sinkItem.isDef) root.setDefaultSink(sinkItem.dev.name) }
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                spacing: 8
                                Text { text: "\uf025"; font.pixelSize: 14; font.family: Theme.fontFamily; color: sinkItem.isDef ? root.barAccent : Theme.textDimmer }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    Text { text: sinkItem.dev.desc || ""; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: sinkItem.isDef ? root.barAccent : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text {
                                        text: { var s = sinkItem.dev.state || ""; return s.charAt(0).toUpperCase() + s.slice(1) }
                                        font.pixelSize: 8; font.family: Theme.fontFamily; color: sinkItem.isDef ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.5) : Theme.textFaint
                                    }
                                }
                                Item {
                                    visible: sinkItem.isDef; implicitWidth: skBdg.implicitWidth + 12; implicitHeight: 16
                                    Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.15); border.color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3); border.width: 1
                                        Text { id: skBdg; anchors.centerIn: parent; text: "Default"; font.pixelSize: 7; font.bold: true; font.family: Theme.fontFamily; color: root.barAccent }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; implicitHeight: 36
                        visible: root.audioTab === "output" && root.sinkList.length === 0
                        Text { anchors.centerIn: parent; text: "Scanning..."; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint }
                    }

                    // ── Input tab ──────────────────────────────
                    Repeater {
                        model: root.audioTab === "input" ? root.sourceList.length : 0

                        Rectangle {
                            id: srcItem
                            property var dev: root.sourceList[index] || ({})
                            property bool isDef: dev.isDefault || false

                            Layout.fillWidth: true; implicitHeight: 40; radius: 8
                            color: isDef ? Qt.rgba(0.78,0.47,0.87,0.08)
                                   : srcH.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            MouseArea {
                                id: srcH; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (!srcItem.isDef) root.setDefaultSource(srcItem.dev.name) }
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                spacing: 8
                                Text { text: "\uf130"; font.pixelSize: 14; font.family: Theme.fontFamily; color: srcItem.isDef ? Theme.purple : Theme.textDimmer }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    Text { text: srcItem.dev.desc || ""; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: srcItem.isDef ? Theme.purple : Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text {
                                        text: { var s = srcItem.dev.state || ""; return s.charAt(0).toUpperCase() + s.slice(1) }
                                        font.pixelSize: 8; font.family: Theme.fontFamily; color: srcItem.isDef ? Qt.rgba(0.78,0.47,0.87,0.5) : Theme.textFaint
                                    }
                                }
                                Item {
                                    visible: srcItem.isDef; implicitWidth: srBdg.implicitWidth + 12; implicitHeight: 16
                                    Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(0.78,0.47,0.87,0.15); border.color: Qt.rgba(0.78,0.47,0.87,0.3); border.width: 1
                                        Text { id: srBdg; anchors.centerIn: parent; text: "Default"; font.pixelSize: 7; font.bold: true; font.family: Theme.fontFamily; color: Theme.purple }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; implicitHeight: 36
                        visible: root.audioTab === "input" && root.sourceList.length === 0
                        Text { anchors.centerIn: parent; text: "No input devices"; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint }
                    }

                }

                // ── Apps view (separate drill-in) ─────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Theme.borderLight
                    visible: root.appsViewOpen
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    visible: root.appsViewOpen

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8

                        Rectangle {
                            width: 24; height: 24; radius: 6
                            color: appBackH.containsMouse ? Theme.surfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent; text: "\uf053"
                                font.pixelSize: 9; font.family: Theme.fontFamily
                                color: appBackH.containsMouse ? root.barAccent : Theme.textDim
                            }
                            MouseArea {
                                id: appBackH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appsViewOpen = false
                            }
                        }

                        Text {
                            text: "App Volume"
                            font.pixelSize: Theme.fontBar; font.bold: true
                            font.family: Theme.fontFamily; color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 1; color: Theme.borderLight
                        Layout.topMargin: 6; Layout.bottomMargin: 2
                    }

                    Repeater {
                        model: root.appList.length

                        Item {
                            id: appItem
                            property var app: root.appList[index] || ({})
                            property color ac: root.appColor(app.appName || "")
                            property int appVol: app.volume || 0

                            Layout.fillWidth: true
                            implicitHeight: 44

                            RowLayout {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 8

                                Rectangle {
                                    width: 26; height: 26; radius: 6
                                    color: Qt.rgba(appItem.ac.r, appItem.ac.g, appItem.ac.b, 0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            var n = (appItem.app.appName || "").toLowerCase()
                                            if (n.indexOf("spotify") >= 0) return "\uf1bc"
                                            if (n.indexOf("firefox") >= 0) return "\uf269"
                                            if (n.indexOf("discord") >= 0) return "\uf392"
                                            if (n.indexOf("chromium") >= 0 || n.indexOf("chrome") >= 0) return "\uf268"
                                            if (n.indexOf("vlc") >= 0) return "\uf04b"
                                            if (n.indexOf("steam") >= 0) return "\uf11b"
                                            return "\uf028"
                                        }
                                        font.pixelSize: 12; font.family: Theme.fontFamily; color: appItem.ac
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 3
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: appItem.app.appName || "Unknown"; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: Theme.text }
                                        Item { Layout.fillWidth: true }
                                        Text { text: appItem.appVol + "%"; font.pixelSize: 10; font.bold: true; font.family: Theme.fontFamily; color: appItem.ac }
                                    }

                                    MouseArea {
                                        Layout.fillWidth: true; implicitHeight: 8
                                        onWheel: function(wheel) {
                                            var step = wheel.angleDelta.y > 0 ? 5 : -5
                                            var nv = Math.max(0, Math.min(100, appItem.appVol + step))
                                            root.setAppVolume(appItem.app.index, nv)
                                            root.updateAppVolumeUI(index, nv)
                                        }

                                        Rectangle {
                                            anchors.fill: parent; radius: 4; color: Theme.trackBg
                                            Rectangle {
                                                width: parent.width * Math.min(1.0, appItem.appVol / 100)
                                                height: parent.height; radius: 4; color: appItem.ac
                                            }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: function(mouse) {
                                                    var pct = Math.max(0, Math.min(100, Math.round(mouse.x / parent.width * 100)))
                                                    root.setAppVolume(appItem.app.index, pct)
                                                    root.updateAppVolumeUI(index, pct)
                                                }
                                                onPositionChanged: function(mouse) {
                                                    if (pressed) {
                                                        var pct = Math.max(0, Math.min(100, Math.round(mouse.x / parent.width * 100)))
                                                        root.setAppVolume(appItem.app.index, pct)
                                                        root.updateAppVolumeUI(index, pct)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; implicitHeight: 44
                        visible: root.appList.length === 0
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 3
                            Text { text: "\uf028"; font.pixelSize: 18; font.family: Theme.fontFamily; color: Theme.textGhost; Layout.alignment: Qt.AlignHCenter }
                            Text { text: "No apps playing audio"; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
}
