import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../../theme"
import "../../../services"

// Dashboard surface (SPEC 4.4): Dashboard / Media / Performance / Weather tabs.
// Reads files only while open (GPU and disk only on the Performance tab); CPU, RAM and
// weather come from the shared services. wttr.in gives 3 forecast days, not 7.
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    property string tab: "dashboard"
    readonly property var tabs: [["dashboard", "\uf015", "Dashboard"], ["media", "\uf001", "Media"],
                                 ["performance", "\uf0e4", "Performance"], ["weather", "\ue302", "Weather"]]
    implicitHeight: 410

    // ── Pure helpers (unit-tested in scripts/tests/test_shell_services.js) ──
    function formatUptime(seconds) {
        var s = Math.floor(seconds)
        if (!(s >= 0)) return ""
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return "up " + (d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + m + "m" : m + "m")
    }
    function parseDf(text) {   // `df -B1 --output=size,used /`
        var f = (text.split("\n")[1] || "").trim().split(/\s+/).map(Number)
        return f.length === 2 && f[0] > 0 && f[1] >= 0 ? { size: f[0], used: f[1] } : null
    }
    function gib(bytes) { return (bytes / 1073741824).toFixed(bytes >= 107374182400 ? 0 : 1) + " GiB" }
    function monthOffset(year, month) { var d = new Date(year, month, 1).getDay(); return d === 0 ? 6 : d - 1 }

    // ── Data ─────────────────────────────────────────────────────────────
    SystemClock { id: clock; precision: SystemClock.Minutes }
    // Main player: Spotify when running (Media.ordered), or the one picked in the "also
    // playing" list for as long as the dashboard stays open. The rest are listed with it.
    property var chosen: null
    readonly property var ordered: Media.ordered
    readonly property var player: ordered.indexOf(chosen) >= 0 ? chosen : (ordered[0] || null)
    readonly property var others: ordered.filter(function(p) { return p !== root.player })
    function playerColor(p) {   // same colours as the Sound panel
        var id = p ? (p.identity || "").toLowerCase() : ""
        if (id.indexOf("spotify") >= 0) return Theme.media
        if (id.indexOf("firefox") >= 0 || id.indexOf("chrom") >= 0) return Theme.warning
        if (id.indexOf("vlc") >= 0) return Theme.purple
        return root.accent
    }
    function formatTime(seconds) {
        var s = Math.floor(seconds)
        if (!(s >= 0)) return "0:00"
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }
    property real pos: 0
    Timer {   // MPRIS position is read, not pushed: poll once a second while playing and open
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.active && root.player !== null && root.player.isPlaying
        onTriggered: root.pos = root.player ? root.player.position : 0
    }
    onPlayerChanged: pos = player ? player.position : 0
    property real uptime: -1
    FileView { id: uptimeFile; path: "/proc/uptime"; onLoaded: root.uptime = parseFloat(text()) }
    FileView { id: kernelFile; path: "/proc/sys/kernel/osrelease" }
    readonly property string userName: Quickshell.env("USER") || "user"
    // ~/.face is optional: load it only if it exists (no "Cannot open" warning otherwise),
    // and pick it up when it is added later.
    property bool hasFace: false
    FileView {
        path: Quickshell.env("HOME") + "/.face"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.hasFace = true
        onLoadFailed: root.hasFace = false
    }

    property string gpuDevice: ""      // device dir of the GPU driving a connected display
    property string gpuTempPath: ""
    property int gpuBusy: -1
    property real vramUsed: -1
    property real vramTotal: -1
    property int gpuTemp: -1
    property var disk: null
    Process {
        id: gpuFind
        command: ["sh", "-c", "for c in /sys/class/drm/card[0-9]*; do " +
            "[ -e \"$c/device/gpu_busy_percent\" ] || continue; " +
            "for k in \"$c\"-*/status; do if [ \"$(cat \"$k\" 2>/dev/null)\" = connected ]; then " +
            "d=$(readlink -f \"$c/device\"); echo \"$d\"; ls \"$d\"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n1; exit; fi; done; done"]
        stdout: StdioCollector {
            onStreamFinished: { var l = text.trim().split("\n"); root.gpuDevice = l[0] || ""; root.gpuTempPath = l[1] || "" }
        }
    }
    FileView { id: busyFile; path: root.gpuDevice ? root.gpuDevice + "/gpu_busy_percent" : ""; onLoaded: root.gpuBusy = parseInt(text()) }
    FileView { id: vramUsedFile; path: root.gpuDevice ? root.gpuDevice + "/mem_info_vram_used" : ""; onLoaded: root.vramUsed = parseFloat(text()) }
    FileView { id: vramTotalFile; path: root.gpuDevice ? root.gpuDevice + "/mem_info_vram_total" : ""; onLoaded: root.vramTotal = parseFloat(text()) }
    FileView { id: gpuTempFile; path: root.gpuTempPath; onLoaded: root.gpuTemp = Math.floor(parseInt(text()) / 1000) }
    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector { onStreamFinished: root.disk = root.parseDf(text) }
    }

    onActiveChanged: {
        if (active) { uptimeFile.reload(); kernelFile.reload(); Weather.refreshIfStale() }
        else chosen = null   // each opening starts again with Spotify as the main player
    }
    Timer { interval: 60000; running: root.active; repeat: true; onTriggered: uptimeFile.reload() }
    readonly property bool perf: active && tab === "performance"
    onPerfChanged: if (perf && !gpuFind.running && !gpuDevice) gpuFind.running = true
    Timer {
        interval: 2000; running: root.perf; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (root.gpuDevice) { busyFile.reload(); vramUsedFile.reload(); vramTotalFile.reload() }
            if (root.gpuTempPath) gpuTempFile.reload()
        }
    }
    Timer { interval: 30000; running: root.perf; repeat: true; triggeredOnStart: true; onTriggered: if (!dfProc.running) dfProc.running = true }

    // ── Building blocks ──────────────────────────────────────────────────
    component Card: Rectangle {
        color: Theme.surface; radius: 14; border.color: Theme.borderMuted; border.width: 1
    }
    component Label: Text {
        color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontNormal
        elide: Text.ElideRight
    }
    component IconButton: Rectangle {
        id: btn
        property string icon: ""
        property bool enabledState: true
        signal activated()
        width: 34; height: 34; radius: 10
        color: btnArea.containsMouse && enabledState ? Theme.surfaceHover : "transparent"
        opacity: enabledState ? 1 : 0.35
        Text { anchors.centerIn: parent; text: btn.icon; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontLg }
        MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (btn.enabledState) btn.activated() }
    }
    component Controls: Row {
        id: ctl
        property var p: root.player
        spacing: 6
        IconButton { icon: "\uf048"; enabledState: !!(ctl.p && ctl.p.canGoPrevious); onActivated: ctl.p.previous() }
        IconButton {
            icon: ctl.p && ctl.p.isPlaying ? "\uf04c" : "\uf04b"
            enabledState: !!(ctl.p && ctl.p.canTogglePlaying)
            onActivated: ctl.p.togglePlaying()
        }
        IconButton { icon: "\uf051"; enabledState: !!(ctl.p && ctl.p.canGoNext); onActivated: ctl.p.next() }
    }
    component Art: Rectangle {
        property int size: 96
        property var p: root.player
        width: size; height: size; radius: size > 60 ? 12 : 8; color: Theme.trackBg; clip: true
        Text { anchors.centerIn: parent; text: "\uf001"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: parent.size / 3; visible: art.status !== Image.Ready }
        Image {
            id: art; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
            source: parent.p ? (parent.p.trackArtUrl || "") : ""
            sourceSize.width: parent.size * 2; sourceSize.height: parent.size * 2
        }
    }
    component Progress: Column {   // main player; click or drag to seek when supported
        id: prog
        property bool showTimes: true
        readonly property real length: root.player ? root.player.length : 0
        spacing: 4
        Rectangle {
            width: prog.width; height: 5; radius: 3; color: Theme.trackBg
            Rectangle {
                height: parent.height; radius: 3; color: root.playerColor(root.player)
                width: prog.length > 0 ? Math.min(1, root.pos / prog.length) * parent.width : 0
            }
            MouseArea {
                anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                enabled: !!(root.player && root.player.canSeek && prog.length > 0)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                function seek(x) { root.pos = Math.max(0, Math.min(1, x / width)) * prog.length; root.player.position = root.pos }
                onPressed: mouse => seek(mouse.x)
                onPositionChanged: mouse => { if (pressed) seek(mouse.x) }
            }
        }
        Item {
            visible: prog.showTimes && prog.length > 0
            width: prog.width; height: 14
            Label { anchors.left: parent.left; text: root.formatTime(root.pos); color: Theme.textFaint; font.pixelSize: Theme.fontSm }
            Label { anchors.right: parent.right; text: root.formatTime(prog.length); color: Theme.textFaint; font.pixelSize: Theme.fontSm }
        }
    }
    component PlayerChip: Rectangle {   // another player: click to make it the main one
        id: chip
        required property var modelData
        readonly property color c: root.playerColor(modelData)
        height: 26; radius: 8; width: chipRow.implicitWidth + 16
        color: chipArea.containsMouse ? Qt.rgba(c.r, c.g, c.b, 0.15) : Theme.surface
        border.color: Qt.rgba(c.r, c.g, c.b, 0.3)
        Row {
            id: chipRow; anchors.centerIn: parent; spacing: 6
            Rectangle { width: 6; height: 6; radius: 3; color: chip.c; anchors.verticalCenter: parent.verticalCenter }
            Label { text: (chip.modelData.isPlaying ? "\uf04b " : "") + (chip.modelData.identity || "Media"); color: chip.c; font.pixelSize: Theme.fontSm }
        }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chosen = chip.modelData }
    }
    component Ring: Item {
        id: ring
        property real value: -1          // 0..1, -1 = unknown
        property color color: root.accent
        property string title: ""
        property string main: ""
        property string sub: ""
        width: 170; height: 210
        Shape {
            id: arcs
            width: 150; height: 150; anchors.horizontalCenter: parent.horizontalCenter
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.trackBg; strokeWidth: 12; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 75; centerY: 75; radiusX: 63; radiusY: 63; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {
                strokeColor: ring.color; strokeWidth: 12; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 75; centerY: 75; radiusX: 63; radiusY: 63; startAngle: 135
                               sweepAngle: 270 * Math.max(0.001, Math.min(1, ring.value)) }
            }
            visible: true
            Label { anchors.centerIn: parent; text: ring.main; font.pixelSize: Theme.fontXl; font.bold: true; color: ring.color }
        }
        Label {
            anchors.top: arcs.bottom; anchors.topMargin: 2; anchors.horizontalCenter: parent.horizontalCenter
            text: ring.title; font.bold: true
        }
        Label {
            anchors.top: arcs.bottom; anchors.topMargin: 22; anchors.horizontalCenter: parent.horizontalCenter
            text: ring.sub; color: Theme.textDim; font.pixelSize: Theme.fontSm
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Row {   // tabs
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            Repeater {
                model: root.tabs
                Rectangle {
                    required property var modelData
                    readonly property bool current: root.tab === modelData[0]
                    width: tabLabel.implicitWidth + 28; height: 30; radius: 10
                    color: current ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                                   : tabArea.containsMouse ? Theme.surfaceHover : "transparent"
                    border.color: current ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : "transparent"
                    Label {
                        id: tabLabel; anchors.centerIn: parent
                        text: modelData[1] + "  " + modelData[2]
                        color: parent.current ? root.accent : Theme.textDim; font.bold: parent.current
                    }
                    MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = modelData[0] }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: Math.max(0, root.tabs.findIndex(function(t) { return t[0] === root.tab }))

            // Dashboard: user + weather | calendar | media
            RowLayout {
                spacing: 10
                ColumnLayout {
                    Layout.preferredWidth: 250; Layout.fillWidth: false; Layout.fillHeight: true; spacing: 10
                    Card {
                        Layout.fillWidth: true; implicitHeight: 110
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 14 }
                            spacing: 14
                            Rectangle {
                                width: 64; height: 64; radius: 32; clip: true
                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                Label { anchors.centerIn: parent; text: root.userName.charAt(0).toUpperCase(); font.pixelSize: Theme.fontXxl; font.bold: true; color: root.accent; visible: face.status !== Image.Ready }
                                Image { id: face; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: root.hasFace ? "file://" + Quickshell.env("HOME") + "/.face" : ""; sourceSize.width: 128; sourceSize.height: 128 }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Label { text: root.userName; font.pixelSize: Theme.fontLg; font.bold: true }
                                Label { text: root.formatUptime(root.uptime); color: Theme.textDim }
                                Label { text: kernelFile.text().trim(); color: Theme.textFaint; font.pixelSize: Theme.fontSm; width: 150 }
                            }
                        }
                    }
                    Card {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Column {
                            anchors.centerIn: parent; spacing: 6
                            visible: Weather.loaded
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter; spacing: 12
                                Label { text: Weather.icon(Weather.code); font.pixelSize: 40; color: Theme.warning }
                                Label { text: Weather.temp + "°"; font.pixelSize: 36; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.desc + "  ·  " + Weather.location; color: Theme.textDim; width: Math.min(implicitWidth, 220) }
                            Item { width: 1; height: 6 }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter; spacing: 18
                                Repeater {
                                    model: Weather.forecastDays
                                    Column {
                                        required property var modelData
                                        spacing: 2
                                        Label { anchors.horizontalCenter: parent.horizontalCenter; color: Theme.textFaint; font.pixelSize: Theme.fontSm
                                                text: Qt.locale().dayName(new Date(modelData.date + "T12:00:00").getDay(), Locale.ShortFormat) }
                                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.icon(modelData.code); font.pixelSize: 20; color: Theme.warning }
                                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.high + "°/" + modelData.low + "°"; color: Theme.textDim; font.pixelSize: Theme.fontSm }
                                    }
                                }
                            }
                        }
                        Label { anchors.centerIn: parent; visible: !Weather.loaded; text: Weather.error ? "Weather unavailable" : "\uf110  Loading…"; color: Theme.textFaint }
                    }
                }

                Card {   // calendar
                    id: cal
                    Layout.fillWidth: true; Layout.fillHeight: true
                    property int month: clock.date.getMonth()
                    property int year: clock.date.getFullYear()
                    function nav(dir) { var d = new Date(year, month + dir, 1); month = d.getMonth(); year = d.getFullYear() }
                    Connections { target: root; function onActiveChanged() { if (root.active) { cal.month = clock.date.getMonth(); cal.year = clock.date.getFullYear() } } }
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            IconButton { icon: "\uf053"; width: 28; height: 28; onActivated: cal.nav(-1) }
                            Label {
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true
                                text: Qt.locale().standaloneMonthName(cal.month) + " " + cal.year
                            }
                            IconButton { icon: "\uf054"; width: 28; height: 28; onActivated: cal.nav(1) }
                        }
                        Grid {
                            id: grid
                            Layout.fillWidth: true; Layout.fillHeight: true
                            columns: 7; rowSpacing: 2
                            readonly property int offset: root.monthOffset(cal.year, cal.month)
                            readonly property int days: new Date(cal.year, cal.month + 1, 0).getDate()
                            readonly property real cell: width / 7
                            Repeater {
                                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                Label { required property var modelData; width: grid.cell; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.textFaint; font.pixelSize: Theme.fontSm; font.bold: true }
                            }
                            Repeater {
                                model: 42
                                Rectangle {
                                    required property int index
                                    readonly property int day: index - grid.offset + 1
                                    readonly property bool valid: day >= 1 && day <= grid.days
                                    readonly property bool today: valid && cal.year === clock.date.getFullYear()
                                        && cal.month === clock.date.getMonth() && day === clock.date.getDate()
                                    width: grid.cell; height: 30; radius: 8
                                    color: today ? root.accent : "transparent"
                                    Label {
                                        anchors.centerIn: parent; text: parent.valid ? parent.day : ""
                                        color: parent.today ? Theme.textDark : index % 7 >= 5 ? Theme.textFaint : Theme.text
                                        font.bold: parent.today
                                    }
                                }
                            }
                        }
                    }
                }

                Card {   // media
                    Layout.preferredWidth: 250; Layout.fillWidth: false; Layout.fillHeight: true
                    Column {
                        anchors.centerIn: parent; spacing: 8; width: parent.width - 28
                        visible: root.player !== null
                        Art { size: 120; anchors.horizontalCenter: parent.horizontalCenter }
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.bold: true; text: root.player ? (root.player.trackTitle || "Unknown") : "" }
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; color: Theme.textDim; text: root.player ? (root.player.trackArtist || root.player.identity || "") : "" }
                        Progress { width: parent.width; showTimes: false }
                        Controls { anchors.horizontalCenter: parent.horizontalCenter }
                        Flow {
                            width: parent.width; spacing: 6; visible: root.others.length > 0
                            Repeater { model: root.others; PlayerChip {} }
                        }
                    }
                    Label { anchors.centerIn: parent; visible: root.player === null; text: "\uf001  Nothing playing"; color: Theme.textFaint }
                }
            }

            // Media: the main player centred; other players listed beside it
            Item {
                Card { anchors.fill: parent }
                Row {
                    anchors.centerIn: parent; spacing: 40
                    visible: root.player !== null
                    Column {
                        width: 360; spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Art { size: 170; anchors.horizontalCenter: parent.horizontalCenter }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.player ? (root.player.identity || "") : ""
                            color: root.playerColor(root.player); font.pixelSize: Theme.fontSm; font.bold: true
                        }
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Theme.fontXl; font.bold: true
                                text: root.player ? (root.player.trackTitle || "Unknown") : "" }
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; color: Theme.textDim
                                text: root.player ? [root.player.trackArtist, root.player.trackAlbum].filter(function(x) { return x }).join(" · ") : "" }
                        Progress { width: parent.width }
                        Controls { anchors.horizontalCenter: parent.horizontalCenter }
                    }
                    Column {
                        visible: root.others.length > 0
                        width: 300; spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Label { text: "Also playing"; color: Theme.textFaint; font.pixelSize: Theme.fontSm; font.bold: true }
                        Repeater {
                            model: root.others
                            Rectangle {
                                id: other
                                required property var modelData
                                width: 300; height: 64; radius: 12
                                color: otherArea.containsMouse ? Theme.surfaceHover : Theme.surface
                                border.color: Theme.borderMuted
                                MouseArea { id: otherArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chosen = other.modelData }
                                Row {
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 10
                                    Art { size: 48; p: other.modelData }
                                    Column {
                                        width: 180; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                        Label { width: parent.width; text: other.modelData.trackTitle || "Unknown"; font.bold: true }
                                        Label { width: parent.width; text: other.modelData.identity || ""; color: root.playerColor(other.modelData); font.pixelSize: Theme.fontSm }
                                    }
                                }
                                IconButton {
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    icon: other.modelData.isPlaying ? "\uf04c" : "\uf04b"
                                    enabledState: other.modelData.canTogglePlaying
                                    onActivated: other.modelData.togglePlaying()
                                }
                            }
                        }
                    }
                }
                Label { anchors.centerIn: parent; visible: root.player === null; text: "\uf001  Nothing playing"; color: Theme.textFaint; font.pixelSize: Theme.fontLg }
            }

            // Performance: CPU / GPU / RAM / storage rings
            Item {
                Card { anchors.fill: parent }
                Row {
                    anchors.centerIn: parent; spacing: 20
                    Ring { title: "CPU"; color: Theme.pink; value: Sysmon.cpu / 100
                           main: Sysmon.cpu < 0 ? "--" : Sysmon.cpu + "%"; sub: Sysmon.temp < 0 ? "" : Sysmon.temp + "°C" }
                    Ring { title: "GPU"; color: root.accent; value: root.gpuBusy / 100
                           main: root.gpuBusy < 0 ? "--" : root.gpuBusy + "%"
                           sub: (root.gpuTemp < 0 ? "" : root.gpuTemp + "°C  ")
                                + (root.vramTotal > 0 ? root.gib(root.vramUsed) + " / " + root.gib(root.vramTotal) : "") }
                    Ring { title: "RAM"; color: Theme.warning; value: Sysmon.mem / 100
                           main: Sysmon.mem < 0 ? "--" : Sysmon.mem + "%" }
                    Ring { title: "Storage /"; color: Theme.success
                           value: root.disk ? root.disk.used / root.disk.size : -1
                           main: root.disk ? Math.round(100 * root.disk.used / root.disk.size) + "%" : "--"
                           sub: root.disk ? root.gib(root.disk.used) + " / " + root.gib(root.disk.size) : "" }
                }
            }

            // Weather: current details + the forecast days wttr.in provides
            Item {
                Card { anchors.fill: parent }
                Row {
                    anchors.centerIn: parent; spacing: 40
                    visible: Weather.loaded
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Row {
                            spacing: 14
                            Label { text: Weather.icon(Weather.code); font.pixelSize: 64; color: Theme.warning }
                            Label { text: Weather.temp + "°C"; font.pixelSize: 48; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Label { text: Weather.desc; font.pixelSize: Theme.fontLg }
                        Label { text: "Feels " + Weather.feels + "°  ·  Humidity " + Weather.humidity + "%  ·  Wind " + Weather.wind + " km/h"; color: Theme.textDim }
                        Label { text: Weather.location; color: Theme.textFaint; font.pixelSize: Theme.fontSm }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: Weather.forecastDays
                            Card {
                                required property var modelData
                                width: 110; height: 150
                                Column {
                                    anchors.centerIn: parent; spacing: 8
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; font.bold: true
                                            text: Qt.locale().dayName(new Date(modelData.date + "T12:00:00").getDay(), Locale.ShortFormat) }
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.icon(modelData.code); font.pixelSize: 30; color: Theme.warning }
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.high + "° / " + modelData.low + "°"; color: Theme.textDim }
                                }
                            }
                        }
                    }
                }
                Label { anchors.centerIn: parent; visible: !Weather.loaded; text: Weather.error ? "Weather unavailable" : "\uf110  Loading…"; color: Theme.textFaint }
            }
        }
    }
}
