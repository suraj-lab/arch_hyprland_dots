import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"

Item {
    id: root

    property color barAccent: "#00ffea"
    property string screenName: ""

    Behavior on barAccent { ColorAnimation { duration: 500 } }

    signal closeRequested()

    // ── Data layer ──────────────────────────────────────────
    property var _monitorsBuf: []
    property var monitorData: ({})
    property var allMonitors: ({})
    property bool monitorReady: false

    readonly property real monitorAspect: {
        var w = monitorData.width
        var h = monitorData.height
        return (w > 0 && h > 0) ? (w / h) : (16 / 9)
    }

    // Reactive binding — re-evaluates whenever Hyprland.toplevels.values changes.
    // Hyprland.refreshToplevels() is called in Connections below to trigger updates.
    property var allClients: {
        var result = []
        var tvs = Hyprland.toplevels.values
        for (var i = 0; i < tvs.length; i++) {
            var t = tvs[i]
            var info = (t.lastIpcObject != null) ? t.lastIpcObject : {}
            result.push({
                wayland:   t.wayland,
                address:   info.address,
                at:        info.at,
                size:      info.size,
                workspace: info.workspace,
                monitor:   info.monitor,
                title:     info.title,
                "class":   info["class"]
            })
        }
        return result
    }

    Component.onCompleted: {
        monitorsProc.running = true
        Hyprland.refreshToplevels()
        forceActiveFocus()
    }

    // Monitors still use Process — Hyprland.monitors reactive API is unverified
    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: SplitParser {
            onRead: function(line) { root._monitorsBuf.push(line) }
        }
        onRunningChanged: {
            if (!running) {
                var raw = root._monitorsBuf.join("")
                root._monitorsBuf = []
                try {
                    var arr = JSON.parse(raw)
                    var map = {}
                    for (var i = 0; i < arr.length; i++) {
                        map[arr[i].name] = arr[i]
                        if (arr[i].name === root.screenName) {
                            root.monitorData = arr[i]
                            root.monitorReady = true
                        }
                    }
                    root.allMonitors = map
                } catch(e) {}
            }
        }
    }

    // Refresh toplevels when windows open/close/move so allClients stays live
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            var n = ev.name
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "windowtitle") {
                Hyprland.refreshToplevels()
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────
    function clientsForWorkspace(wsId) {
        return root.allClients.filter(function(c) {
            return c.workspace != null && c.workspace.id === wsId
        })
    }

    function monitorByID(id) {
        for (var name in root.allMonitors) {
            if (root.allMonitors[name].id === id) return root.allMonitors[name]
        }
        return null
    }

    function monitorForWorkspace(wsId) {
        for (var i = 0; i < root.allClients.length; i++) {
            var c = root.allClients[i]
            if (c.workspace != null && c.workspace.id === wsId) {
                var m = monitorByID(c.monitor)
                if (m != null) return m
            }
        }
        return root.monitorData
    }

    // ── Backdrop (click to close) ───────────────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(15/255, 12/255, 20/255, 0.45)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 250 } }
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // ── Content card ────────────────────────────────────────
    Rectangle {
        id: contentCard
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, 1300)
        height: Math.min(parent.height * 0.75, 700)
        radius: 10
        color: Theme.popupBg
        border.color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.35)
        border.width: 1

        scale: 0.95
        opacity: 0
        Component.onCompleted: {
            scale = 1.0
            opacity = 1.0
        }
        Behavior on scale   { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea { anchors.fill: parent }

        // Header
        RowLayout {
            id: header
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 24
            }
            height: 32
            spacing: 8

            Rectangle {
                width: 4; height: 16; radius: 2
                color: root.barAccent
            }
            Text {
                text: "Overview"
                font.pixelSize: 16
                font.bold: true
                font.family: Theme.fontFamily
                color: root.barAccent
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "ESC to close"
                font.pixelSize: 10
                font.family: Theme.fontFamily
                color: Theme.textDim
            }
        }

        // Header divider
        Rectangle {
            id: headerDivider
            anchors {
                top: header.bottom
                topMargin: 16
                left: parent.left
                right: parent.right
                leftMargin: 24
                rightMargin: 24
            }
            height: 1
            color: Qt.rgba(255/255, 255/255, 255/255, 0.08)
        }

        // Workspace grid
        GridLayout {
            id: wsGrid
            anchors {
                top: headerDivider.bottom
                topMargin: 16
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 24
            }
            columns: Math.max(1, Math.min(3, Math.floor(contentCard.width / 280)))
            rowSpacing: 16
            columnSpacing: 16

            Repeater {
                model: [1, 2, 3, 4, 5]

                Rectangle {
                    id: wsCard
                    required property var modelData

                    property int wsId: modelData
                    property var wsClients: root.clientsForWorkspace(wsId)
                    property var wsMonitor: root.monitorReady ? root.monitorForWorkspace(wsId) : root.monitorData
                    property bool isActive: {
                        var fm = Hyprland.focusedMonitor
                        if (fm == null || fm.activeWorkspace == null) return false
                        return fm.activeWorkspace.id === wsId
                    }

                    Layout.fillWidth: true
                    Layout.minimumWidth: 280
                    Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                    Layout.preferredHeight: 48 + Math.max(80, (width - 24) / Math.max(1, root.monitorAspect))
                    radius: 8
                    color: isActive
                        ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.10)
                        : Qt.rgba(35/255, 28/255, 45/255, 0.55)
                    border.color: isActive
                        ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.6)
                        : (wsHover.containsMouse
                            ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.35)
                            : Theme.border)
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    transform: Translate {
                        y: wsHover.containsMouse ? -2 : 0
                        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: wsHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Hyprland.dispatch("workspace " + wsCard.wsId)
                            root.closeRequested()
                        }
                    }

                    // Workspace label row
                    RowLayout {
                        id: wsHeader
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            margins: 12
                        }
                        height: 20
                        spacing: 6

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: wsCard.isActive ? root.barAccent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: wsCard.wsId
                                font.pixelSize: 10
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: wsCard.isActive ? Theme.textDark : Theme.text
                            }
                        }
                        Text {
                            text: "Workspace " + wsCard.wsId
                            font.pixelSize: 11
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: wsCard.wsClients.length + ""
                            font.pixelSize: 9
                            font.family: Theme.fontFamily
                            color: Theme.textDim
                        }
                    }

                    // Windows container (recessed inset)
                    Rectangle {
                        id: windowsArea
                        anchors {
                            top: wsHeader.bottom
                            topMargin: 4
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: 12
                        }
                        radius: 6
                        color: Qt.rgba(8/255, 6/255, 14/255, 0.6)
                        border.color: Qt.rgba(255/255, 255/255, 255/255, 0.05)
                        border.width: 1
                        clip: true

                        readonly property real monW: (wsCard.wsMonitor != null && wsCard.wsMonitor.width)  ? wsCard.wsMonitor.width  : 1920
                        readonly property real monH: (wsCard.wsMonitor != null && wsCard.wsMonitor.height) ? wsCard.wsMonitor.height : 1080
                        readonly property real sx: width / Math.max(monW, 1)
                        readonly property real sy: height / Math.max(monH, 1)
                        readonly property real s: Math.min(sx, sy)

                        Text {
                            anchors.centerIn: parent
                            text: "Empty"
                            font.pixelSize: 10
                            font.family: Theme.fontFamily
                            color: Theme.textFaint
                            visible: wsCard.wsClients.length === 0
                        }

                        Repeater {
                            model: wsCard.wsClients

                            Rectangle {
                                id: winRect
                                required property var modelData
                                required property int index

                                readonly property real winX: {
                                    var pos = modelData.at
                                    var baseX = (wsCard.wsMonitor != null && wsCard.wsMonitor.x !== undefined) ? wsCard.wsMonitor.x : 0
                                    return (pos != null && pos.length > 0) ? Math.max(0, pos[0] - baseX) : 0
                                }
                                readonly property real winY: {
                                    var pos = modelData.at
                                    var baseY = (wsCard.wsMonitor != null && wsCard.wsMonitor.y !== undefined) ? wsCard.wsMonitor.y : 0
                                    return (pos != null && pos.length > 1) ? Math.max(0, pos[1] - baseY) : 0
                                }
                                readonly property real winW: {
                                    var sz = modelData.size
                                    return (sz != null && sz.length > 0) ? sz[0] : 200
                                }
                                readonly property real winH: {
                                    var sz = modelData.size
                                    return (sz != null && sz.length > 1) ? sz[1] : 150
                                }

                                x: winX * windowsArea.s
                                y: winY * windowsArea.s
                                width:  Math.max(24, winW * windowsArea.s)
                                height: Math.max(20, winH * windowsArea.s)
                                radius: 4
                                clip: true

                                readonly property color winCol: {
                                    var cls = (modelData["class"] || "").toLowerCase()
                                    if (cls.indexOf("firefox")  >= 0 || cls.indexOf("chromium") >= 0) return Theme.warning
                                    if (cls.indexOf("code")     >= 0 || cls.indexOf("codium")   >= 0) return root.barAccent
                                    if (cls.indexOf("discord")  >= 0 || cls.indexOf("webcord")  >= 0) return "#7289da"
                                    if (cls.indexOf("spotify")  >= 0) return Theme.media
                                    if (cls.indexOf("kitty")    >= 0 || cls.indexOf("alacritty") >= 0) return Theme.purple
                                    return Theme.textDim
                                }

                                // Coloured border + faint fill — stays visible as fallback
                                // when ScreencopyView has no content (minimised, X11, etc.)
                                color: Qt.rgba(winCol.r, winCol.g, winCol.b, 0.08)
                                border.color: Qt.rgba(winCol.r, winCol.g, winCol.b, 0.4)
                                border.width: 1

                                // Live thumbnail — active only when wayland handle exists
                                Loader {
                                    id: thumbLoader
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    active: winRect.modelData.wayland != null
                                    sourceComponent: Component {
                                        ScreencopyView {
                                            anchors.fill: parent
                                            captureSource: winRect.modelData.wayland
                                            live: false
                                            paintCursor: false
                                            // Only show when content is available —
                                            // coloured rectangle shows through when not
                                            visible: hasContent
                                        }
                                    }
                                }

                                z: winHover.containsMouse ? 10 : index
                                scale: winHover.containsMouse ? 1.03 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                MouseArea {
                                    id: winHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var addr = winRect.modelData.address
                                        if (addr != null) {
                                            Hyprland.dispatch("focuswindow address:" + addr)
                                        }
                                        root.closeRequested()
                                    }
                                }

                                // Title tooltip on hover
                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        var t = winRect.modelData.title || winRect.modelData["class"] || ""
                                        return t.length > 20 ? t.substring(0, 20) + "…" : t
                                    }
                                    font.pixelSize: 9
                                    font.family: Theme.fontFamily
                                    color: Qt.rgba(winRect.winCol.r, winRect.winCol.g, winRect.winCol.b, 0.8)
                                    visible: winHover.containsMouse && parent.width > 30
                                    width: parent.width - 4
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Keyboard handling ────────────────────────────────────
    focus: true
    Keys.onEscapePressed: function(event) {
        root.closeRequested()
        event.accepted = true
    }
    Keys.onPressed: function(event) {
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
            var ws = event.key - Qt.Key_1 + 1
            Hyprland.dispatch("workspace " + ws)
            root.closeRequested()
            event.accepted = true
        }
    }
}
