import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"

    property bool pickerVisible: false
    signal closeRequested()

    // ── Wallpaper data ─────────────────────────────────────────────────
    property string wallpaperDir: ""
    property var allWallpapers: []
    property var categories: ["All"]
    property string searchText: ""
    property string selectedCategory: "All"
    property var currentWallpapers: ({})
    property int selectedIndex: 0
    property string previewPath: ""

    // ── Monitor selection ──────────────────────────────────────────────
    property string selectedMonitor: "All"
    property var monitorNames: {
        var names = ["All"]
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
            names.push(screens[i].name)
        }
        return names
    }

    // ── Scan wallpapers on startup ─────────────────────────────────────
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
                if (t.indexOf("DIR:") === 0) {
                    root.wallpaperDir = t.substring(4)
                } else {
                    root._scanBuf.push(t)
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                root.allWallpapers = root._scanBuf.slice()
                root._scanBuf = []
                root.buildCategories()
            }
        }
    }

    function rescan() {
        _scanBuf = []
        allWallpapers = []
        categories = ["All"]
        scanProc.running = true
    }

    function buildCategories() {
        var cats = {}
        var dir = wallpaperDir + "/"
        for (var i = 0; i < allWallpapers.length; i++) {
            var rel = allWallpapers[i].replace(dir, "")
            var slash = rel.indexOf("/")
            if (slash > 0) {
                var folder = rel.substring(0, slash)
                var cap = folder.charAt(0).toUpperCase() + folder.slice(1)
                cats[cap] = folder
            }
        }
        var result = ["All"]
        var keys = Object.keys(cats).sort()
        for (var j = 0; j < keys.length; j++) result.push(keys[j])
        root.categories = result
    }

    function basename(path) {
        return path.split("/").pop()
    }

    // ── Filtered wallpapers ────────────────────────────────────────────
    property var filteredWallpapers: {
        var q = searchText.toLowerCase()
        var cat = selectedCategory
        var dir = wallpaperDir + "/"

        return allWallpapers.filter(function(path) {
            if (cat !== "All") {
                var rel = path.replace(dir, "")
                if (rel.indexOf("/") < 0) return false
                var folder = rel.split("/")[0]
                var cap = folder.charAt(0).toUpperCase() + folder.slice(1)
                if (cap !== cat) return false
            }
            if (q) {
                var name = path.split("/").pop().toLowerCase()
                if (name.indexOf(q) < 0) return false
            }
            return true
        })
    }

    // ── Apply wallpaper via awww ───────────────────────────────────────
    Process { id: applyProc }
    Process { id: accentProc }

    readonly property var transitions: [
        "fade", "left", "right", "top", "bottom",
        "wipe", "grow", "center", "outer", "wave"
    ]

    function applyWallpaper(path) {
        var t = transitions[Math.floor(Math.random() * transitions.length)]
        var cmd = ["awww", "img", path]
        if (selectedMonitor !== "All") {
            cmd.push("-o")
            cmd.push(selectedMonitor)
        }
        cmd.push("--transition-type")
        cmd.push(t)
        cmd.push("--transition-pos")
        cmd.push("center")
        cmd.push("--transition-duration")
        cmd.push("1")
        applyProc.command = cmd
        applyProc.running = true

        // Extract accent color from new wallpaper (pass monitor name for per-monitor accents)
        accentProc.command = ["bash",
            Qt.resolvedUrl("../scripts/extract-accent.sh").toString().replace("file://", ""),
            path, selectedMonitor]
        accentProc.running = true

        var m = Object.assign({}, currentWallpapers)
        m[selectedMonitor] = path
        currentWallpapers = m
    }

    // ── State management ───────────────────────────────────────────────
    onPickerVisibleChanged: {
        if (pickerVisible) {
            searchText = ""
            selectedCategory = "All"
            selectedIndex = 0
            previewPath = ""
            searchInput.text = ""
            focusTimer.restart()
        }
    }

    Timer {
        id: focusTimer
        interval: 50
        onTriggered: searchInput.forceActiveFocus()
    }

    // ── Backdrop (click-to-close, no dim) ──────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // ── Centered card ──────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Theme.wallpickerWidth
        height: Theme.wallpickerHeight
        radius: 16
        color: Theme.popupBg
        border.color: Theme.border
        border.width: 1
        clip: true

        scale: root.pickerVisible ? 1.0 : 0.92
        Behavior on scale {
            NumberAnimation { duration: 250; easing.type: Easing.OutBack }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Header ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 12

                Text {
                    text: "Wallpaper"
                    font.pixelSize: Theme.fontLg; font.bold: true
                    font.family: Theme.fontFamily; color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.filteredWallpapers.length + " images"
                    font.pixelSize: Theme.fontSm
                    font.family: Theme.fontFamily
                    color: Theme.textFaint
                }

                // Refresh button
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: refreshHover.containsMouse
                           ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf021"
                        font.pixelSize: 12; font.family: Theme.fontFamily
                        color: refreshHover.containsMouse ? root.barAccent : Theme.textDim
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    MouseArea {
                        id: refreshHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.rescan()
                    }
                }
            }

            // ── Monitor selector ────────────────────────────────────────
            Row {
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 6
                spacing: 6

                Text {
                    text: "\uf108"
                    font.pixelSize: 10; font.family: Theme.fontFamily
                    color: Theme.textDimmer
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: root.monitorNames

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: monLabel.implicitWidth + 16
                        height: 22
                        radius: 6
                        color: modelData === root.selectedMonitor
                               ? Qt.rgba(198/255, 120/255, 221/255, 0.15) : Theme.surface
                        border.color: modelData === root.selectedMonitor
                                      ? Qt.rgba(198/255, 120/255, 221/255, 0.4) : Theme.borderMuted
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            id: monLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 9
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: modelData === root.selectedMonitor
                                   ? Theme.purple : Theme.textDim
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMonitor = modelData
                        }
                    }
                }
            }

            // ── Search bar ─────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 10

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.surface
                    border.color: searchInput.activeFocus
                                  ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.3) : Theme.borderMuted
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 10

                        Text {
                            text: "\uf002"
                            font.pixelSize: 13; font.family: Theme.fontFamily
                            color: Theme.textDimmer
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TextInput {
                                id: searchInput
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                color: Theme.text
                                font.pixelSize: Theme.fontNormal
                                font.family: Theme.fontFamily
                                clip: true
                                selectByMouse: true

                                onTextChanged: {
                                    root.searchText = text
                                    root.selectedIndex = 0
                                }

                                Keys.onEscapePressed: {
                                    if (root.previewPath !== "") {
                                        root.previewPath = ""
                                    } else {
                                        root.closeRequested()
                                    }
                                }
                                Keys.onReturnPressed: {
                                    if (root.filteredWallpapers.length > 0) {
                                        var idx = Math.min(root.selectedIndex, root.filteredWallpapers.length - 1)
                                        root.applyWallpaper(root.filteredWallpapers[idx])
                                    }
                                }
                                Keys.onEnterPressed: Keys.onReturnPressed
                                Keys.onDownPressed: {
                                    if (root.filteredWallpapers.length > 0)
                                        root.selectedIndex = Math.min(
                                            root.selectedIndex + Theme.wallpickerCols,
                                            root.filteredWallpapers.length - 1)
                                }
                                Keys.onUpPressed: {
                                    if (root.filteredWallpapers.length > 0)
                                        root.selectedIndex = Math.max(
                                            root.selectedIndex - Theme.wallpickerCols, 0)
                                }
                                Keys.onLeftPressed: function(event) {
                                    if (searchInput.cursorPosition === 0 && root.filteredWallpapers.length > 0) {
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                                        event.accepted = true
                                    }
                                }
                                Keys.onRightPressed: function(event) {
                                    if (searchInput.cursorPosition === searchInput.text.length && root.filteredWallpapers.length > 0) {
                                        root.selectedIndex = Math.min(
                                            root.selectedIndex + 1,
                                            root.filteredWallpapers.length - 1)
                                        event.accepted = true
                                    }
                                }
                            }

                            Text {
                                visible: !searchInput.text
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "Search wallpapers..."
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontNormal
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }

            // ── Category pills ─────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 8
                contentWidth: catRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: catRow
                    spacing: 6

                    Repeater {
                        model: root.categories

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: catLabel.implicitWidth + 18
                            height: 24
                            radius: 7
                            color: modelData === root.selectedCategory
                                   ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.12) : Theme.surface
                            border.color: modelData === root.selectedCategory
                                          ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.3) : Theme.borderMuted
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                            Text {
                                id: catLabel
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 9
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: modelData === root.selectedCategory
                                       ? root.barAccent : Theme.textDim
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedCategory = modelData
                                    root.selectedIndex = 0
                                }
                            }
                        }
                    }
                }
            }

            // ── Divider ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Theme.borderLight
                Layout.leftMargin: 14; Layout.rightMargin: 14
                Layout.topMargin: 6
            }

            // ── Wallpaper grid ─────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 8

                // Empty state
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.filteredWallpapers.length === 0

                    Text {
                        text: "\uf03e"
                        font.pixelSize: 32; font.family: Theme.fontFamily
                        color: Theme.textGhost
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: root.allWallpapers.length === 0
                              ? "No wallpapers found in\n~/.config/hypr/wallpapers"
                              : "No matches"
                        font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                        color: Theme.textFaint; horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // Scroll handler
                MouseArea {
                    anchors.fill: parent
                    visible: root.filteredWallpapers.length > 0
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        var step = 25
                        var newY = wallFlick.contentY - (wheel.angleDelta.y > 0 ? step : -step)
                        wallFlick.contentY = Math.max(0,
                            Math.min(newY, wallFlick.contentHeight - wallFlick.height))
                    }
                }

                Flickable {
                    id: wallFlick
                    anchors.fill: parent
                    visible: root.filteredWallpapers.length > 0
                    contentHeight: wallGrid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: false

                    Grid {
                        id: wallGrid
                        width: parent.width
                        columns: Theme.wallpickerCols
                        spacing: 6

                        Repeater {
                            model: root.filteredWallpapers.length

                            Item {
                                id: tile
                                required property int index

                                property string wallPath: root.filteredWallpapers[index] || ""
                                property bool isSelected: index === root.selectedIndex
                                property bool isHovered: tileHover.containsMouse
                                property bool isCurrent: root.currentWallpapers[root.selectedMonitor] === wallPath

                                opacity: 0
                                scale: 0.9
                                Component.onCompleted: wpStaggerTimer.start()
                                Timer {
                                    id: wpStaggerTimer
                                    interval: Math.min(index * 20, 500)
                                    onTriggered: { tile.opacity = 1; tile.scale = 1.0 }
                                }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                width: (wallGrid.width - (Theme.wallpickerCols - 1) * 6) / Theme.wallpickerCols
                                height: width * 10 / 16 + 20

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: "transparent"
                                    border.color: tile.isCurrent
                                                  ? root.barAccent
                                                  : tile.isSelected
                                                    ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.4)
                                                    : tile.isHovered
                                                      ? Theme.borderMuted : "transparent"
                                    border.width: tile.isCurrent ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                                }

                                // Thumbnail
                                Item {
                                    id: thumbClip
                                    anchors {
                                        left: parent.left; right: parent.right; top: parent.top
                                        margins: 3
                                    }
                                    height: parent.width * 10 / 16 - 4
                                    clip: true

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: Theme.surface
                                        clip: true

                                        Image {
                                            id: thumbImg
                                            anchors.fill: parent
                                            source: tile.wallPath
                                            sourceSize.width: 200
                                            sourceSize.height: 125
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true

                                            // Loading indicator
                                            Rectangle {
                                                anchors.fill: parent
                                                color: Theme.surface
                                                visible: thumbImg.status === Image.Loading
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "\uf110"
                                                    font.pixelSize: 16
                                                    font.family: Theme.fontFamily
                                                    color: Theme.textGhost
                                                }
                                            }
                                        }

                                        // Current wallpaper checkmark
                                        Rectangle {
                                            visible: tile.isCurrent
                                            anchors { top: parent.top; right: parent.right; margins: 4 }
                                            width: 18; height: 18; radius: 9
                                            color: Qt.rgba(0, 0, 0, 0.6)
                                            border.color: root.barAccent; border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf00c"
                                                font.pixelSize: 9
                                                font.family: Theme.fontFamily
                                                color: root.barAccent
                                            }
                                        }

                                        // Filename overlay
                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: 18; radius: 0
                                            color: Qt.rgba(0, 0, 0, 0.5)

                                            // Round only bottom corners
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.topMargin: -8
                                                radius: 8
                                                color: parent.color
                                                clip: true
                                                visible: false
                                            }

                                            Text {
                                                anchors {
                                                    left: parent.left; right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                    leftMargin: 5; rightMargin: 5
                                                }
                                                text: root.basename(tile.wallPath)
                                                font.pixelSize: 7
                                                font.family: Theme.fontFamily
                                                color: Qt.rgba(1, 1, 1, 0.7)
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: tileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            root.previewPath = tile.wallPath
                                        } else {
                                            root.applyWallpaper(tile.wallPath)
                                        }
                                    }
                                    onEntered: root.selectedIndex = tile.index
                                }

                                // Scroll into view when selected via keyboard
                                onIsSelectedChanged: {
                                    if (isSelected && wallFlick.visible) {
                                        var itemY = Math.floor(index / Theme.wallpickerCols) * (height + 6)
                                        if (itemY < wallFlick.contentY) {
                                            wallFlick.contentY = itemY
                                        } else if (itemY + height > wallFlick.contentY + wallFlick.height) {
                                            wallFlick.contentY = itemY + height - wallFlick.height
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.bottomMargin: 10; Layout.topMargin: 4
                spacing: 16

                Text {
                    text: "awww · " + (root.selectedMonitor === "All" ? "all monitors" : root.selectedMonitor)
                    font.pixelSize: 8; font.family: Theme.fontFamily
                    color: Theme.textFaint
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 4
                    Rectangle {
                        width: hClick.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hClick; anchors.centerIn: parent
                            text: "Click"; font.pixelSize: 8; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "apply"
                        font.pixelSize: 8; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: hRClick.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hRClick; anchors.centerIn: parent
                            text: "Right-click"; font.pixelSize: 8; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "preview"
                        font.pixelSize: 8; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: hEsc.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hEsc; anchors.centerIn: parent
                            text: "Esc"; font.pixelSize: 8; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "close"
                        font.pixelSize: 8; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ── Preview overlay ────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            visible: root.previewPath !== ""
            z: 10
            radius: 16
            color: Qt.rgba(0, 0, 0, 0.92)

            MouseArea { anchors.fill: parent }

            Image {
                anchors {
                    fill: parent
                    margins: 20
                    bottomMargin: 60
                }
                source: root.previewPath !== "" ? root.previewPath : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // Bottom bar
            RowLayout {
                anchors {
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    margins: 16
                }
                spacing: 10

                Text {
                    text: root.previewPath !== "" ? root.basename(root.previewPath) : ""
                    font.pixelSize: Theme.fontSm
                    font.family: Theme.fontFamily
                    color: Theme.textDim
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }

                // Apply button
                Rectangle {
                    width: applyLabel.implicitWidth + 24; height: 30; radius: 8
                    color: applyHover.containsMouse ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.2) : Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.1)
                    border.color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.4); border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: applyLabel; anchors.centerIn: parent
                        text: "Apply"
                        font.pixelSize: Theme.fontSm; font.bold: true
                        font.family: Theme.fontFamily; color: root.barAccent
                    }

                    MouseArea {
                        id: applyHover; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.applyWallpaper(root.previewPath)
                            root.previewPath = ""
                        }
                    }
                }

                // Close preview
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: closeHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: Theme.borderMuted; border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        font.pixelSize: 12; font.family: Theme.fontFamily
                        color: closeHover.containsMouse ? Theme.text : Theme.textDim
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    MouseArea {
                        id: closeHover; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.previewPath = ""
                    }
                }
            }
        }
    }
}
