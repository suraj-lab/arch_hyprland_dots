import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root

    property bool pickerVisible: false
    signal closeRequested()

    // ── Accent + theme ─────────────────────────────────────────────────────
    property color barAccent: "#00ffea"

    // ── View mode ──────────────────────────────────────────────────────────
    property string viewMode: "carousel"   // "carousel" | "grid"
    property bool _animReady: false        // disable Behaviors on first render

    // ── Wallpaper data ─────────────────────────────────────────────────────
    property string wallpaperDir: ""
    property var allWallpapers: []
    property var categories: ["All"]
    property string searchText: ""
    property string selectedCategory: "All"
    property var currentWallpapers: ({})
    property int selectedIndex: 0
    property int carouselIndex: 0
    property string previewPath: ""

    // ── Monitor selection ──────────────────────────────────────────────────
    property string selectedMonitor: "All"
    property var monitorNames: {
        var names = ["All"]
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) names.push(screens[i].name)
        return names
    }

    // ── Favorites ──────────────────────────────────────────────────────────
    property var favorites: []

    function isFavorite(path) {
        for (var i = 0; i < favorites.length; i++) {
            if (favorites[i] === path) return true
        }
        return false
    }

    function toggleFavorite(path) {
        var arr = favorites.slice()
        var idx = arr.indexOf(path)
        if (idx >= 0) arr.splice(idx, 1)
        else arr.unshift(path)
        favorites = arr
        saveFavorites()
    }

    Process { id: saveFavProc }
    function saveFavorites() {
        var json = JSON.stringify(favorites)
        saveFavProc.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "echo '" + json.replace(/'/g, "'\\''") + "' > \"$HOME/.cache/quickshell/favorites.json\""]
        saveFavProc.running = true
    }

    // ── Recent history ─────────────────────────────────────────────────────
    property var recentWallpapers: []

    function addToRecent(path) {
        var arr = [path]
        for (var i = 0; i < recentWallpapers.length; i++) {
            if (recentWallpapers[i] !== path) arr.push(recentWallpapers[i])
        }
        if (arr.length > 20) arr = arr.slice(0, 20)
        recentWallpapers = arr
        saveRecent()
    }

    Process { id: saveRecentProc }
    function saveRecent() {
        var json = JSON.stringify(recentWallpapers)
        saveRecentProc.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "echo '" + json.replace(/'/g, "'\\''") + "' > \"$HOME/.cache/quickshell/wallpaper-history.json\""]
        saveRecentProc.running = true
    }

    // ── Color cache ────────────────────────────────────────────────────────
    property var colorCache: ({})
    property string activeColor: "all"
    property var _colorQueue: []
    property int _colorActive: 0
    property bool _colorDirty: false

    function classifyHex(hex) {
        var r = parseInt(hex.substring(0, 2), 16) / 255
        var g = parseInt(hex.substring(2, 4), 16) / 255
        var b = parseInt(hex.substring(4, 6), 16) / 255
        var max = Math.max(r, g, b); var min = Math.min(r, g, b)
        var v = max
        if (v < 0.2) return "dark"
        if (max === min) return "all"
        var d = max - min; var h = 0
        if (max === r) h = 60 * (((g - b) / d) % 6)
        else if (max === g) h = 60 * ((b - r) / d + 2)
        else h = 60 * ((r - g) / d + 4)
        if (h < 0) h += 360
        if (h >= 300 || h < 20) return "pink"
        if (h < 90) return "warm"
        if (h < 160) return "green"
        if (h < 210) return "cyan"
        if (h < 270) return "blue"
        return "purple"
    }

    function requestColorExtract(path) {
        if (!path) return
        if (colorCache[path] !== undefined) return
        for (var i = 0; i < _colorQueue.length; i++) { if (_colorQueue[i] === path) return }
        var q = _colorQueue.slice(); q.push(path); _colorQueue = q
        processColorQueue()
    }

    property var _colorBuf: []

    Process {
        id: colorExtractProc
        property string extractingPath: ""
        stdout: SplitParser { onRead: function(line) { root._colorBuf.push(line.trim()) } }
        onRunningChanged: {
            if (!running) {
                root._colorActive = Math.max(0, root._colorActive - 1)
                var hex = root._colorBuf.join("").replace(/[^0-9a-fA-F]/g, "").substring(0, 6)
                root._colorBuf = []
                if (hex.length === 6) {
                    var bucket = root.classifyHex(hex)
                    var cc = Object.assign({}, root.colorCache)
                    cc[colorExtractProc.extractingPath] = bucket
                    root.colorCache = cc
                    root._colorDirty = true
                }
                root.processColorQueue()
            }
        }
    }

    function processColorQueue() {
        if (_colorActive >= 3 || _colorQueue.length === 0) return
        var q = _colorQueue.slice()
        var path = q.shift()
        _colorQueue = q; _colorActive++
        colorExtractProc.extractingPath = path
        colorExtractProc.command = ["bash", "-c",
            "magick \"" + path + "\" -resize 1x1! -format '%[hex:p{0,0}]' info:- 2>/dev/null"]
        colorExtractProc.running = true
    }

    Timer {
        id: colorSaveTimer; interval: 5000; repeat: false
        onTriggered: {
            if (!root._colorDirty) return
            root._colorDirty = false
            var json = JSON.stringify(root.colorCache)
            colorSaveProc.command = ["bash", "-c",
                "mkdir -p \"$HOME/.cache/quickshell\" && " +
                "echo '" + json.replace(/'/g, "'\\''") + "' > \"$HOME/.cache/quickshell/wallpaper-colors.json\""]
            colorSaveProc.running = true
        }
    }
    on_ColorDirtyChanged: if (_colorDirty) colorSaveTimer.restart()
    Process { id: colorSaveProc }

    // ── Accent preview ─────────────────────────────────────────────────────
    property string previewAccentHex: "#00ffea"
    property color previewAccent: "#00ffea"
    property var _accentBuf: []

    Process {
        id: accentPreviewProc
        stdout: SplitParser { onRead: function(line) { root._accentBuf.push(line.trim()) } }
        onRunningChanged: {
            if (!running) {
                var hex = root._accentBuf.join("").replace(/[^0-9a-fA-F]/g, "").substring(0, 6)
                root._accentBuf = []
                if (hex.length === 6) {
                    root.previewAccentHex = "#" + hex.toLowerCase()
                    root.previewAccent = "#" + hex.toLowerCase()
                }
            }
        }
    }

    Timer {
        id: accentPreviewTimer; interval: 400; repeat: false
        property string pendingPath: ""
        onTriggered: {
            if (!pendingPath) return
            root._accentBuf = []
            accentPreviewProc.command = ["bash", "-c",
                "HEX=$(magick \"" + pendingPath + "\" -resize 1x1! -format '%[hex:p{0,0}]' info:- 2>/dev/null); " +
                "python3 -c \"import colorsys,sys; h=sys.argv[1]; r,g,b=int(h[0:2],16)/255,int(h[2:4],16)/255,int(h[4:6],16)/255; " +
                "hue,s,v=colorsys.rgb_to_hsv(r,g,b); s=max(s,0.75); v=min(max(v,0.7),0.92); " +
                "r2,g2,b2=colorsys.hsv_to_rgb(hue,s,v); print(f'{int(r2*255):02x}{int(g2*255):02x}{int(b2*255):02x}')\" \"$HEX\" 2>/dev/null"]
            accentPreviewProc.running = true
        }
    }

    function updateAccentPreview(path) {
        if (!path) return
        accentPreviewTimer.pendingPath = path
        accentPreviewTimer.restart()
    }

    // ── Scan wallpapers ────────────────────────────────────────────────────
    property var _scanBuf: []

    Process {
        id: scanProc
        command: ["bash", "-c",
            "WDIR=\"$HOME/.config/hypr/wallpapers\";" +
            "echo \"DIR:$WDIR\";" +
            "find \"$WDIR\" -maxdepth 3 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) " +
            "2>/dev/null | sort | head -300"
        ]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (t === "") return
                if (t.indexOf("DIR:") === 0) root.wallpaperDir = t.substring(4)
                else root._scanBuf.push(t)
            }
        }
        onRunningChanged: {
            if (!running) {
                root.allWallpapers = root._scanBuf.slice(); root._scanBuf = []
                root.buildCategories()
                Qt.callLater(function() { root._animReady = true })
            }
        }
    }

    function rescan() {
        _scanBuf = []; allWallpapers = []; categories = ["All"]
        scanProc.running = true
    }

    function buildCategories() {
        var cats = {}; var dir = wallpaperDir + "/"
        for (var i = 0; i < allWallpapers.length; i++) {
            var rel = allWallpapers[i].replace(dir, "")
            var slash = rel.indexOf("/")
            if (slash > 0) {
                var folder = rel.substring(0, slash)
                var cap = folder.charAt(0).toUpperCase() + folder.slice(1)
                cats[cap] = folder
            }
        }
        var result = ["All", "Favorites", "Recent"]
        var keys = Object.keys(cats).sort()
        for (var j = 0; j < keys.length; j++) result.push(keys[j])
        root.categories = result
    }

    function basename(path) { return path.split("/").pop() }

    // ── Cache loading on startup ───────────────────────────────────────────
    property var _cacheBuf: []

    Process {
        id: loadColorsProc
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/wallpaper-colors.json\" 2>/dev/null || echo '{}'"]
        stdout: SplitParser { onRead: function(line) { root._cacheBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._cacheBuf.join(""); root._cacheBuf = []
                try { root.colorCache = JSON.parse(raw) } catch(e) {}
                loadFavProc.running = true
            }
        }
    }

    Process {
        id: loadFavProc
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/favorites.json\" 2>/dev/null || echo '[]'"]
        stdout: SplitParser { onRead: function(line) { root._cacheBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._cacheBuf.join(""); root._cacheBuf = []
                try { root.favorites = JSON.parse(raw) } catch(e) {}
                loadRecentProc.running = true
            }
        }
    }

    Process {
        id: loadRecentProc
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/wallpaper-history.json\" 2>/dev/null || echo '[]'"]
        stdout: SplitParser { onRead: function(line) { root._cacheBuf.push(line) } }
        onRunningChanged: {
            if (!running) {
                var raw = root._cacheBuf.join(""); root._cacheBuf = []
                try { root.recentWallpapers = JSON.parse(raw) } catch(e) {}
            }
        }
    }

    Component.onCompleted: loadColorsProc.running = true

    // ── Apply wallpaper ────────────────────────────────────────────────────
    Process { id: applyProc }
    Process { id: accentProc }

    readonly property var transitions: [
        "fade","left","right","top","bottom","wipe","grow","center","outer","wave"
    ]

    function applyWallpaper(path) {
        var t = transitions[Math.floor(Math.random() * transitions.length)]
        var cmd = ["awww", "img", path]
        if (selectedMonitor !== "All") { cmd.push("-o"); cmd.push(selectedMonitor) }
        cmd.push("--transition-type"); cmd.push(t)
        cmd.push("--transition-pos"); cmd.push("center")
        cmd.push("--transition-duration"); cmd.push("1")
        applyProc.command = cmd; applyProc.running = true

        accentProc.command = ["bash",
            Qt.resolvedUrl("../scripts/extract-accent.sh").toString().replace("file://", ""),
            path, selectedMonitor]
        accentProc.running = true

        var m = Object.assign({}, currentWallpapers)
        m[selectedMonitor] = path
        currentWallpapers = m
        addToRecent(path)
    }

    // ── Filtered wallpapers ────────────────────────────────────────────────
    property var filteredWallpapers: {
        var q = searchText.toLowerCase()
        var cat = selectedCategory
        var dir = wallpaperDir + "/"
        var col = activeColor

        var base = allWallpapers

        if (cat === "Favorites") {
            base = favorites.filter(function(p) { return allWallpapers.indexOf(p) >= 0 })
        } else if (cat === "Recent") {
            base = recentWallpapers.filter(function(p) { return allWallpapers.indexOf(p) >= 0 })
        } else if (cat !== "All") {
            base = allWallpapers.filter(function(path) {
                var rel = path.replace(dir, "")
                if (rel.indexOf("/") < 0) return false
                var folder = rel.split("/")[0]
                var cap = folder.charAt(0).toUpperCase() + folder.slice(1)
                return cap === cat
            })
        }

        return base.filter(function(path) {
            if (col !== "all") {
                var bucket = colorCache[path]
                if (bucket !== undefined && bucket !== col) return false
            }
            if (q) {
                var name = path.split("/").pop().toLowerCase()
                if (name.indexOf(q) < 0) return false
            }
            return true
        })
    }

    // ── Picker visibility ──────────────────────────────────────────────────
    onPickerVisibleChanged: {
        if (pickerVisible) {
            searchText = ""; selectedCategory = "All"; selectedIndex = 0
            carouselIndex = 0; previewPath = ""; searchInput.text = ""
            activeColor = "all"; previewAccentHex = "#00ffea"; previewAccent = "#00ffea"
            focusTimer.restart()
        }
    }

    Timer { id: focusTimer; interval: 50; onTriggered: searchInput.forceActiveFocus() }

    onCarouselIndexChanged: {
        var wp = filteredWallpapers[carouselIndex]
        if (wp) updateAccentPreview(wp)
    }
    onSelectedIndexChanged: {
        if (viewMode === "grid") {
            var wp2 = filteredWallpapers[selectedIndex]
            if (wp2) updateAccentPreview(wp2)
        }
    }

    // ── Backdrop ───────────────────────────────────────────────────────────
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }

    // ── Picker card ────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Theme.wallpickerWidth
        height: Theme.wallpickerHeight
        radius: 16; color: Theme.popupBg
        border.color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.25); border.width: 1
        clip: true

        scale: root.pickerVisible ? 1.0 : 0.92
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; spacing: 0

            // ── Header ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 12
                spacing: 6

                Text { text: "Wallpaper"; font.pixelSize: Theme.fontLg; font.bold: true; font.family: Theme.fontFamily; color: Theme.text }

                Item { Layout.fillWidth: true }

                // Monitor pills
                Repeater {
                    model: root.monitorNames
                    Rectangle {
                        required property var modelData
                        width: monLbl.implicitWidth + 16; height: 22; radius: 6
                        color: modelData === root.selectedMonitor ? Qt.rgba(198/255,120/255,221/255,0.15) : Theme.surface
                        border.color: modelData === root.selectedMonitor ? Qt.rgba(198/255,120/255,221/255,0.4) : Theme.borderMuted; border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text { id: monLbl; anchors.centerIn: parent; text: modelData; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; color: modelData === root.selectedMonitor ? Theme.purple : Theme.textDim }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedMonitor = modelData }
                    }
                }

                // Favorites pill
                Rectangle {
                    height: 22; width: favLbl.implicitWidth + 16; radius: 6
                    color: root.selectedCategory === "Favorites" ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.12) : Theme.surface
                    border.color: root.selectedCategory === "Favorites" ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { id: favLbl; anchors.centerIn: parent; text: "\uf005 Fav"; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; color: root.selectedCategory === "Favorites" ? root.barAccent : Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedCategory = root.selectedCategory === "Favorites" ? "All" : "Favorites" }
                }

                // Recent pill
                Rectangle {
                    height: 22; width: recLbl.implicitWidth + 16; radius: 6
                    color: root.selectedCategory === "Recent" ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.12) : Theme.surface
                    border.color: root.selectedCategory === "Recent" ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { id: recLbl; anchors.centerIn: parent; text: "\uf017"; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; color: root.selectedCategory === "Recent" ? root.barAccent : Theme.textDim }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedCategory = root.selectedCategory === "Recent" ? "All" : "Recent" }
                }

                // View toggle
                Row {
                    spacing: 2
                    Repeater {
                        model: [{ mode: "carousel", icon: "\uf0c9" }, { mode: "grid", icon: "\uf00a" }]
                        Rectangle {
                            required property var modelData
                            width: 26; height: 26; radius: 6
                            color: root.viewMode === modelData.mode ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.1) : Theme.surface
                            border.color: root.viewMode === modelData.mode ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text { anchors.centerIn: parent; text: modelData.icon; font.pixelSize: 11; font.family: Theme.fontFamily; color: root.viewMode === modelData.mode ? root.barAccent : Theme.textDim }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.viewMode = modelData.mode }
                        }
                    }
                }

                // Refresh
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: refreshH.containsMouse ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "\uf021"; font.pixelSize: 12; font.family: Theme.fontFamily; color: refreshH.containsMouse ? root.barAccent : Theme.textDim }
                    MouseArea { id: refreshH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rescan() }
                }

                Text { text: root.filteredWallpapers.length + " images"; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textFaint }
            }

            // ── Filter row ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 8
                spacing: 8

                // Color swatches
                Row {
                    spacing: 5
                    Repeater {
                        model: [
                            { key: "all",    isRainbow: true  },
                            { key: "purple", col: "#c678dd", isRainbow: false },
                            { key: "cyan",   col: "#00ffea", isRainbow: false },
                            { key: "warm",   col: "#ff9f43", isRainbow: false },
                            { key: "pink",   col: "#f38ba8", isRainbow: false },
                            { key: "green",  col: "#39ff14", isRainbow: false },
                            { key: "blue",   col: "#7289da", isRainbow: false },
                            { key: "dark",   col: "#2a2a3a", isRainbow: false }
                        ]
                        Rectangle {
                            required property var modelData
                            property bool isActive: root.activeColor === modelData.key
                            width: 16; height: 16; radius: 8
                            color: modelData.isRainbow ? "transparent" : (modelData.col || "transparent")
                            border.color: isActive ? "white" : Qt.rgba(255,255,255,0.15); border.width: isActive ? 2 : 1
                            scale: isActive ? 1.15 : (swH.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

                            Rectangle {
                                visible: modelData.isRainbow; anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#c678dd" }
                                    GradientStop { position: 0.33; color: "#00ffea" }
                                    GradientStop { position: 0.66; color: "#ff9f43" }
                                    GradientStop { position: 1.0; color: "#f38ba8" }
                                }
                            }

                            MouseArea { id: swH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.activeColor = modelData.key; root.selectedIndex = 0; root.carouselIndex = 0 } }
                        }
                    }
                }

                Rectangle { width: 1; height: 16; color: Theme.borderMuted }

                // Category pills
                Flickable {
                    Layout.fillWidth: true; implicitHeight: 26
                    contentWidth: catRow.implicitWidth; clip: true
                    flickableDirection: Flickable.HorizontalFlick; boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: catRow; spacing: 4
                        Repeater {
                            model: root.categories.filter(function(c) { return c !== "Favorites" && c !== "Recent" })
                            Rectangle {
                                required property var modelData
                                width: catLbl.implicitWidth + 18; height: 22; radius: 7
                                color: modelData === root.selectedCategory ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.12) : Theme.surface
                                border.color: modelData === root.selectedCategory ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text { id: catLbl; anchors.centerIn: parent; text: modelData; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; color: modelData === root.selectedCategory ? root.barAccent : Theme.textDim; Behavior on color { ColorAnimation { duration: Theme.animFast } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.selectedCategory = modelData; root.selectedIndex = 0; root.carouselIndex = 0 } }
                            }
                        }
                    }
                }

                // Search
                Item {
                    Layout.preferredWidth: 140; implicitHeight: 26
                    Rectangle {
                        anchors.fill: parent; radius: 8; color: Theme.surface
                        border.color: searchInput.activeFocus ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : Theme.borderMuted; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 6
                            Text { text: "\uf002"; font.pixelSize: 11; font.family: Theme.fontFamily; color: Theme.textDimmer }
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                TextInput {
                                    id: searchInput
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    color: Theme.text; font.pixelSize: 10; font.family: Theme.fontFamily
                                    clip: true; selectByMouse: true
                                    onTextChanged: { root.searchText = text; root.selectedIndex = 0; root.carouselIndex = 0 }
                                    Keys.onEscapePressed: { if (root.previewPath !== "") root.previewPath = ""; else root.closeRequested() }
                                    Keys.onReturnPressed: {
                                        var idx = root.viewMode === "carousel" ? root.carouselIndex : root.selectedIndex
                                        if (root.filteredWallpapers.length > 0) root.applyWallpaper(root.filteredWallpapers[Math.min(idx, root.filteredWallpapers.length - 1)])
                                    }
                                    Keys.onEnterPressed: Keys.onReturnPressed
                                    Keys.onLeftPressed: function(e) {
                                        if (root.viewMode === "carousel" && root.filteredWallpapers.length > 0) { root.carouselIndex = Math.max(0, root.carouselIndex - 1); root.selectedIndex = root.carouselIndex; e.accepted = true }
                                        else if (cursorPosition === 0 && root.filteredWallpapers.length > 0) { root.selectedIndex = Math.max(0, root.selectedIndex - 1); e.accepted = true }
                                    }
                                    Keys.onRightPressed: function(e) {
                                        if (root.viewMode === "carousel" && root.filteredWallpapers.length > 0) { root.carouselIndex = Math.min(root.filteredWallpapers.length - 1, root.carouselIndex + 1); root.selectedIndex = root.carouselIndex; e.accepted = true }
                                        else if (cursorPosition === text.length && root.filteredWallpapers.length > 0) { root.selectedIndex = Math.min(root.filteredWallpapers.length - 1, root.selectedIndex + 1); e.accepted = true }
                                    }
                                    Keys.onDownPressed: { if (root.viewMode === "grid") root.selectedIndex = Math.min(root.selectedIndex + Theme.wallpickerCols, root.filteredWallpapers.length - 1) }
                                    Keys.onUpPressed: { if (root.viewMode === "grid") root.selectedIndex = Math.max(root.selectedIndex - Theme.wallpickerCols, 0) }
                                }
                                Text {
                                    visible: !searchInput.text
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    text: "Search..."; color: Theme.textFaint; font.pixelSize: 10; font.family: Theme.fontFamily
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderLight; Layout.topMargin: 8 }

            // ── CAROUSEL VIEW ───────────────────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.viewMode === "carousel"; clip: true

                // Empty state
                Column {
                    anchors.centerIn: parent; spacing: 8
                    visible: root.filteredWallpapers.length === 0
                    Text { text: "\uf03e"; font.pixelSize: 32; font.family: Theme.fontFamily; color: Theme.textGhost; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: root.allWallpapers.length === 0 ? "No wallpapers found" : "No matches"; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.horizontalCenter: parent.horizontalCenter }
                }

                // Scroll to navigate
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.NoButton
                    property real _scrollBuf: 0; property real _lastScroll: 0
                    onWheel: function(wheel) {
                        if (root.filteredWallpapers.length === 0) return
                        var now = Date.now()
                        if (now - _lastScroll < 180) return
                        _scrollBuf += wheel.angleDelta.x || wheel.angleDelta.y
                        if (Math.abs(_scrollBuf) > 60) {
                            var dir = _scrollBuf > 0 ? 1 : -1
                            root.carouselIndex = Math.max(0, Math.min(root.filteredWallpapers.length - 1, root.carouselIndex + dir))
                            root.selectedIndex = root.carouselIndex
                            _scrollBuf = 0; _lastScroll = now
                        }
                    }
                }

                // Cards
                Item {
                    anchors.centerIn: parent; width: parent.width; height: parent.height

                    Repeater {
                        model: root.filteredWallpapers.length > 0 ? 7 : 0

                        Item {
                            id: slot
                            required property int index
                            property int offset: index - 3
                            property int wpIdx: {
                                var total = root.filteredWallpapers.length
                                if (total === 0) return -1
                                return ((root.carouselIndex + offset) % total + total) % total
                            }
                            property string wpPath: wpIdx >= 0 ? (root.filteredWallpapers[wpIdx] || "") : ""
                            property bool isCenter: offset === 0
                            property bool isCurrent: wpPath !== "" && (root.currentWallpapers[root.selectedMonitor] === wpPath)

                            onWpPathChanged: { if (wpPath) root.requestColorExtract(wpPath) }

                            width:   { var a = Math.abs(offset); return a === 0 ? 310 : a === 1 ? 140 : a === 2 ? 80 : 0 }
                            height:  { var a = Math.abs(offset); return a === 0 ? 210 : a === 1 ? 175 : a === 2 ? 148 : 0 }
                            opacity: { var a = Math.abs(offset); return a === 0 ? 1.0 : a === 1 ? 0.60 : a === 2 ? 0.25 : 0 }
                            z:       { var a = Math.abs(offset); return a === 0 ? 10  : a === 1 ? 5   : 1 }

                            Behavior on width   { enabled: root._animReady; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
                            Behavior on height  { enabled: root._animReady; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
                            Behavior on opacity { enabled: root._animReady; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }

                            x: parent.width / 2 - width / 2 + offset * 215
                            y: parent.height / 2 - height / 2
                            Behavior on x { enabled: root._animReady; NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }

                            // Skewed frame
                            Item {
                                anchors.fill: parent; clip: true
                                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.25, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "transparent"
                                    border.color: slot.isCenter ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.6) : slot.isCurrent ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.3) : "transparent"
                                    border.width: slot.isCenter ? 2 : 1

                                    Image {
                                        anchors.centerIn: parent
                                        width: parent.width * 1.35; height: parent.height * 1.1
                                        source: slot.wpPath !== "" ? slot.wpPath : ""
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true; clip: true
                                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, 0.25, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: parent.radius; color: Theme.surface
                                        visible: parent.children[0].status !== Image.Ready
                                        Text { anchors.centerIn: parent; text: "\uf03e"; font.pixelSize: 24; font.family: Theme.fontFamily; color: Theme.textGhost; opacity: 0.4 }
                                    }
                                }
                            }

                            // Current badge
                            Rectangle {
                                visible: slot.isCurrent
                                anchors { top: parent.top; right: parent.right; margins: 4 }
                                width: 16; height: 16; radius: 8
                                color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.9)
                                Text { anchors.centerIn: parent; text: "\uf00c"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textDark }
                            }

                            // Favorite star (center only)
                            Rectangle {
                                z: 20
                                visible: slot.isCenter && slot.wpPath !== ""
                                anchors { top: parent.top; left: parent.left; margins: 4 }
                                width: 24; height: 24; radius: 6
                                color: favStarH.containsMouse ? Qt.rgba(0,0,0,0.7) : Qt.rgba(0,0,0,0.5)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    anchors.centerIn: parent
                                    text: root.isFavorite(slot.wpPath) ? "\uf005" : "\uf006"
                                    font.pixelSize: 11; font.family: Theme.fontFamily
                                    color: root.isFavorite(slot.wpPath) ? Theme.warning : "white"; opacity: 0.85
                                }
                                MouseArea { id: favStarH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFavorite(slot.wpPath) }
                            }

                            // Click
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (slot.isCenter) { if (slot.wpPath) root.applyWallpaper(slot.wpPath) }
                                    else {
                                        var ni = Math.max(0, Math.min(root.filteredWallpapers.length - 1, root.carouselIndex + slot.offset))
                                        root.carouselIndex = ni; root.selectedIndex = ni
                                    }
                                }
                                onPressAndHold: { if (slot.wpPath) root.previewPath = slot.wpPath }
                            }
                        }
                    }
                }
            }

            // ── GRID VIEW ───────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 8
                visible: root.viewMode === "grid"

                Column {
                    anchors.centerIn: parent; spacing: 8
                    visible: root.filteredWallpapers.length === 0
                    Text { text: "\uf03e"; font.pixelSize: 32; font.family: Theme.fontFamily; color: Theme.textGhost; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: root.allWallpapers.length === 0 ? "No wallpapers found\nin ~/.config/hypr/wallpapers" : "No matches"; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textFaint; horizontalAlignment: Text.AlignHCenter; anchors.horizontalCenter: parent.horizontalCenter }
                }

                MouseArea {
                    anchors.fill: parent; visible: root.filteredWallpapers.length > 0; acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        var step = 25; var newY = wallFlick.contentY - (wheel.angleDelta.y > 0 ? step : -step)
                        wallFlick.contentY = Math.max(0, Math.min(newY, wallFlick.contentHeight - wallFlick.height))
                    }
                }

                Flickable {
                    id: wallFlick; anchors.fill: parent
                    visible: root.filteredWallpapers.length > 0
                    contentHeight: wallGrid.implicitHeight; clip: true
                    boundsBehavior: Flickable.StopAtBounds; interactive: false

                    Grid {
                        id: wallGrid; width: parent.width; columns: Theme.wallpickerCols; spacing: 6

                        Repeater {
                            model: root.filteredWallpapers.length

                            Item {
                                id: tile
                                required property int index
                                property string wallPath: root.filteredWallpapers[index] || ""
                                property bool isSelected: index === root.selectedIndex
                                property bool isHovered: tileH.containsMouse
                                property bool isCurrent: root.currentWallpapers[root.selectedMonitor] === wallPath

                                opacity: 0; scale: 0.9
                                Component.onCompleted: stT.start()
                                Timer { id: stT; interval: Math.min(index * 20, 500); onTriggered: { tile.opacity = 1; tile.scale = 1.0 } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                width: (wallGrid.width - (Theme.wallpickerCols - 1) * 6) / Theme.wallpickerCols
                                height: width * 10 / 16 + 20

                                onWallPathChanged: root.requestColorExtract(wallPath)

                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: "transparent"
                                    border.color: tile.isCurrent ? root.barAccent : tile.isSelected ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.4) : tile.isHovered ? Theme.borderMuted : "transparent"
                                    border.width: tile.isCurrent ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                                }

                                Item {
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 3 }
                                    height: parent.width * 10 / 16 - 4; clip: true

                                    Rectangle {
                                        anchors.fill: parent; radius: 8; color: Theme.surface; clip: true

                                        Image {
                                            id: thumbImg; anchors.fill: parent
                                            source: tile.wallPath; sourceSize.width: 200; sourceSize.height: 125
                                            fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                                            Rectangle { anchors.fill: parent; color: Theme.surface; visible: thumbImg.status === Image.Loading; Text { anchors.centerIn: parent; text: "\uf110"; font.pixelSize: 16; font.family: Theme.fontFamily; color: Theme.textGhost } }
                                        }

                                        // Current
                                        Rectangle {
                                            visible: tile.isCurrent
                                            anchors { top: parent.top; right: parent.right; margins: 4 }
                                            width: 18; height: 18; radius: 9
                                            color: Qt.rgba(0,0,0,0.6); border.color: root.barAccent; border.width: 1
                                            Text { anchors.centerIn: parent; text: "\uf00c"; font.pixelSize: 9; font.family: Theme.fontFamily; color: root.barAccent }
                                        }

                                        // Favorite
                                        Rectangle {
                                            visible: root.isFavorite(tile.wallPath) || tile.isHovered
                                            anchors { top: parent.top; left: parent.left; margins: 4 }
                                            width: 20; height: 20; radius: 4; color: Qt.rgba(0,0,0,0.6)
                                            Text { anchors.centerIn: parent; text: root.isFavorite(tile.wallPath) ? "\uf005" : "\uf006"; font.pixelSize: 10; font.family: Theme.fontFamily; color: root.isFavorite(tile.wallPath) ? Theme.warning : "white"; opacity: 0.8 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFavorite(tile.wallPath) }
                                        }

                                        // Filename
                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: 18; color: Qt.rgba(0,0,0,0.5)
                                            Text {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 5; rightMargin: 5 }
                                text: root.basename(tile.wallPath); font.pixelSize: 7; font.family: Theme.fontFamily; color: Qt.rgba(1,1,1,0.7); elide: Text.ElideMiddle
                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: tileH; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.previewPath = tile.wallPath; else root.applyWallpaper(tile.wallPath) }
                                    onEntered: root.selectedIndex = tile.index
                                }

                                onIsSelectedChanged: {
                                    if (isSelected && wallFlick.visible) {
                                        var itemY = Math.floor(index / Theme.wallpickerCols) * (height + 6)
                                        if (itemY < wallFlick.contentY) wallFlick.contentY = itemY
                                        else if (itemY + height > wallFlick.contentY + wallFlick.height) wallFlick.contentY = itemY + height - wallFlick.height
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderLight }

            // ── Footer ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.bottomMargin: 10; Layout.topMargin: 6
                spacing: 10

                Text {
                    text: { var idx = root.viewMode === "carousel" ? root.carouselIndex : root.selectedIndex; var wp = root.filteredWallpapers[idx]; return wp ? root.basename(wp) : "" }
                    font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textDim; elide: Text.ElideMiddle; Layout.maximumWidth: 170
                }

                // Accent preview
                Row {
                    spacing: 5
                    Rectangle { width: 10; height: 10; radius: 5; color: root.previewAccent; Behavior on color { ColorAnimation { duration: 400 } } }
                    Text { text: root.previewAccentHex; font.pixelSize: 9; font.bold: true; font.family: Theme.fontFamily; color: root.previewAccent; Behavior on color { ColorAnimation { duration: 400 } } }
                    Text { text: "preview"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textGhost }
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 4
                    Rectangle { width: hc.implicitWidth + 8; height: 18; radius: 4; color: Qt.rgba(1,1,1,0.06); border.color: Qt.rgba(1,1,1,0.1); border.width: 1; Text { id: hc; anchors.centerIn: parent; text: "Click"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textFaint } }
                    Text { text: "apply"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    spacing: 4
                    Rectangle { width: he.implicitWidth + 8; height: 18; radius: 4; color: Qt.rgba(1,1,1,0.06); border.color: Qt.rgba(1,1,1,0.1); border.width: 1; Text { id: he; anchors.centerIn: parent; text: "Esc"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textFaint } }
                    Text { text: "close"; font.pixelSize: 8; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        // ── Preview overlay ────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent; visible: root.previewPath !== ""
            z: 10; radius: 16; color: Qt.rgba(0,0,0,0.92)
            MouseArea { anchors.fill: parent }
            Image {
                anchors { fill: parent; margins: 20; bottomMargin: 60 }
                source: root.previewPath !== "" ? root.previewPath : ""; fillMode: Image.PreserveAspectFit; smooth: true
            }
            RowLayout {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 10
                Text { text: root.previewPath !== "" ? root.basename(root.previewPath) : ""; font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily; color: Theme.textDim; elide: Text.ElideMiddle; Layout.fillWidth: true }
                Rectangle {
                    width: aLbl.implicitWidth + 24; height: 30; radius: 8
                    color: aH.containsMouse ? Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.2) : Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.1)
                    border.color: Qt.rgba(root.barAccent.r,root.barAccent.g,root.barAccent.b,0.4); border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { id: aLbl; anchors.centerIn: parent; text: "Apply"; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; color: root.barAccent }
                    MouseArea { id: aH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.applyWallpaper(root.previewPath); root.previewPath = "" } }
                }
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: cH.containsMouse ? Qt.rgba(1,1,1,0.1) : Qt.rgba(1,1,1,0.05); border.color: Theme.borderMuted; border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: "\uf00d"; font.pixelSize: 12; font.family: Theme.fontFamily; color: cH.containsMouse ? Theme.text : Theme.textDim; Behavior on color { ColorAnimation { duration: Theme.animFast } } }
                    MouseArea { id: cH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.previewPath = "" }
                }
            }
        }
    }
}
