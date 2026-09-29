import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../theme"

// Launcher surface (SPEC 5.1): apps (the classic launcher's search, ranking and
// categories), "=" calculator (qalc), ">" shell actions, and clipboard mode (Super+V,
// cliphist). Keyboard first: typing filters, arrows move, Enter runs, Escape closes.
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false        // the surface is open
    property bool clipboard: false     // opened as the clipboard (Super+V)
    signal closeRequested()
    signal actionRequested(string id)  // runShellAction ids, run by the shell after closing

    implicitWidth: Theme.launcherSurfaceWidth
    implicitHeight: Theme.launcherSurfaceHeight - Theme.surfacePadding

    property string query: ""
    readonly property string mode: clipboard ? "clipboard"
        : query.charAt(0) === "=" ? "calc" : query.charAt(0) === ">" ? "actions" : "apps"
    readonly property string term: (mode === "calc" || mode === "actions" ? query.substring(1) : query).trim()
    property int current: 0
    property string category: "All"
    readonly property int cols: 5

    function reset() {
        query = ""; search.text = ""; current = 0; category = "All"; armed = ""
        calcFor = ""; calcResult = ""; calcError = ""
        if (clipboard) clipList.running = true
        focusLater.restart()
    }
    onActiveChanged: if (active) reset()
    onClipboardChanged: if (active) reset()
    onModeChanged: current = 0
    Timer { id: focusLater; interval: 50; onTriggered: search.forceActiveFocus() }

    // ── Apps ────────────────────────────────────────────────────────────────
    readonly property var catMap: ({
        "AudioVideo": "Media", "Audio": "Media", "Video": "Media", "Development": "Dev",
        "Game": "Games", "Graphics": "Graphics", "Network": "Internet", "WebBrowser": "Internet",
        "Office": "Office", "System": "System", "Settings": "System", "Utility": "Utilities"
    })
    readonly property var allApps: DesktopEntries.applications.values
        .filter(function(e) { return !e.noDisplay })
        .sort(function(a, b) { return a.name.localeCompare(b.name) })
    readonly property var categories: appCategories(allApps, catMap)
    readonly property var apps: mode === "apps" ? filterApps(allApps, term, category, catMap) : []

    function appCategories(list, map) {
        var seen = {}, result = ["All"]
        list.forEach(function(app) {
            (app.categories || []).forEach(function(c) {
                var name = map[c]
                if (name && !seen[name]) { seen[name] = true; result.push(name) }
            })
        })
        return result
    }
    // Category, then name / generic name / keywords; names starting with the query first.
    function filterApps(list, q, cat, map) {
        q = q.toLowerCase()
        var has = function(s) { return !!s && s.toLowerCase().indexOf(q) >= 0 }
        var result = list.filter(function(app) {
            if (cat !== "All" && !(app.categories || []).some(function(c) { return map[c] === cat })) return false
            return !q || has(app.name) || has(app.genericName) || (app.keywords || []).some(has)
        })
        if (q) result.sort(function(a, b) {
            var as = a.name.toLowerCase().indexOf(q) === 0, bs = b.name.toLowerCase().indexOf(q) === 0
            return as === bs ? a.name.localeCompare(b.name) : as ? -1 : 1
        })
        return result
    }

    // ── Calculator ──────────────────────────────────────────────────────────
    // qalc -t prints just the result. No -e: that is --exrates, a download every time.
    property string calcFor: ""        // the expression calcResult belongs to
    property string calcResult: ""
    property string calcError: ""
    property bool calcPending: false
    onTermChanged: if (mode === "calc") calcDebounce.restart()
    Timer {
        id: calcDebounce
        interval: 140
        onTriggered: {
            if (root.mode !== "calc" || !root.term) return
            if (calcProc.running) { root.calcPending = true; return }
            calcProc.expr = root.term
            calcProc.running = true
        }
    }
    Process {
        id: calcProc
        property string expr: ""
        command: ["sh", "-c", 'command -v qalc >/dev/null || exit 127; exec qalc -t -- "$1"', "sh", expr]
        stdout: StdioCollector { id: calcOut }
        stderr: StdioCollector { id: calcErr }
        onExited: function(code) {
            root.calcFor = expr
            root.calcResult = code === 0 ? calcOut.text.trim() : ""
            root.calcError = code === 127 ? "qalc is not installed (package libqalculate)"
                : code !== 0 || !root.calcResult ? (calcErr.text.trim() || "No result") : ""
            if (root.calcPending) { root.calcPending = false; calcDebounce.restart() }
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    readonly property var actions: [
        { id: "gaming", icon: "\uf11b", title: "Gaming Mode", subtitle: "Steam Big Picture in Gamescope" },
        { id: "gamemode", icon: "\uf135", title: "Desktop Game Mode", subtitle: "Toggle" },
        { id: "caffeine", icon: "\uf0f4", title: "Caffeine", subtitle: "Toggle idle inhibit" },
        { id: "nightlight", icon: "\uf186", title: "Night Light", subtitle: "Toggle" },
        { id: "dnd", icon: "\uf1f6", title: "Do Not Disturb", subtitle: "Toggle" },
        { id: "wallpaper", icon: "\uf03e", title: "Wallpaper", subtitle: "Open the picker" },
        { id: "overview", icon: "\uf009", title: "Overview", subtitle: "Workspaces" },
        { id: "cheatsheet", icon: "\uf11c", title: "Keybind cheatsheet", subtitle: "Super + /" },
        { id: "settings", icon: "\uf1de", title: "Settings", subtitle: "Appearance, sound, displays, apps, gaming" },
        { id: "screenshot", icon: "\uf030", title: "Screenshot", subtitle: "Select an area" },
        { id: "lock", icon: "\uf023", title: "Lock", subtitle: "hyprlock" },
        { id: "suspend", icon: "\uf236", title: "Suspend", subtitle: "Sleep" },
        { id: "logout", icon: "\uf2f5", title: "Log out", subtitle: "Ends the session", destructive: true },
        { id: "reboot", icon: "\uf021", title: "Reboot", subtitle: "Restart", destructive: true },
        { id: "poweroff", icon: "\uf011", title: "Power off", subtitle: "Shut down", destructive: true }
    ]
    function filterActions(list, q) {
        q = q.toLowerCase()
        var hit = list.filter(function(a) { return !q || (a.title + " " + a.id).toLowerCase().indexOf(q) >= 0 })
        return hit.filter(function(a) { return a.title.toLowerCase().indexOf(q) === 0 })
            .concat(hit.filter(function(a) { return a.title.toLowerCase().indexOf(q) !== 0 }))
    }
    // Reboot / power off / log out need a second Enter within 3 s.
    property string armed: ""
    Timer { id: armTimer; interval: 3000; onTriggered: root.armed = "" }

    // ── Clipboard ───────────────────────────────────────────────────────────
    property var clips: []
    // `cliphist list`: "<id>\t<preview>"; images preview as "[[ binary data 12 KiB png 800x600 ]]".
    function parseClips(text) {
        return text.split("\n").map(function(line) {
            var m = line.match(/^(\d+)\t(.*)$/)
            if (!m) return null
            var img = m[2].match(/^\[\[ binary data .*\b(png|jpeg|jpg|webp|gif|bmp)\b.*\]\]$/i)
            return { line: line, id: m[1], text: m[2], ext: img ? img[1].toLowerCase() : "" }
        }).filter(function(c) { return c !== null })
    }
    Process {
        id: clipList
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: root.clips = root.parseClips(text) }
    }
    Process {
        id: clipDelete
        property string line: ""
        command: ["sh", "-c", 'printf "%s" "$1" | cliphist delete', "sh", line]
        onExited: clipList.running = true
    }

    // ── Rows for the list modes ─────────────────────────────────────────────
    readonly property var rows: mode === "actions" ? filterActions(actions, term)
        : mode === "calc" ? (!term ? [] : [{ id: "calc", icon: "\uf1ec",
              title: calcFor === term ? (calcError || calcResult) : "\u2026",
              subtitle: calcFor === term && !calcError ? "= " + term + "   (Enter copies)" : term,
              error: calcFor === term && calcError !== "" }])
        : mode === "clipboard" ? clips.filter(function(c) {
              return !term || c.text.toLowerCase().indexOf(term.toLowerCase()) >= 0 })
        : []
    readonly property int count: mode === "apps" ? apps.length : rows.length

    function move(step) { if (count > 0) current = Math.max(0, Math.min(count - 1, current + step)) }

    function activate(index) {
        if (index !== undefined) current = index
        if (current >= count) return
        if (mode === "apps") {
            apps[current].execute()
            root.closeRequested()
        } else if (mode === "calc") {
            if (calcFor !== term || calcError || !calcResult) return   // no stale copies
            // qalc prints U+2212 for minus; paste a plain "-" so terminals and forms take it.
            Quickshell.execDetached(["wl-copy", "--", calcResult.replace(/\u2212/g, "-")])
            root.closeRequested()
        } else if (mode === "actions") {
            var a = rows[current]
            if (a.destructive && armed !== a.id) { armed = a.id; armTimer.restart(); return }
            armed = ""
            root.actionRequested(a.id)
        } else if (mode === "clipboard") {
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "sh", rows[current].line])
            root.closeRequested()
        }
    }
    function deleteClip(index) {
        if (mode !== "clipboard" || index >= rows.length) return
        var c = rows[index]
        clips = clips.filter(function(x) { return x.id !== c.id })   // gone at once; the list reloads after
        clipDelete.line = c.line
        clipDelete.running = true
        current = Math.min(current, Math.max(0, count - 1))
    }

    // ── View ────────────────────────────────────────────────────────────────
    component Hint: Row {
        property string key
        property string label
        spacing: 4
        Rectangle {
            width: keyText.implicitWidth + 8; height: 18; radius: 4
            color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
            Text { id: keyText; anchors.centerIn: parent; text: parent.parent.key; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textFaint }
        }
        Text { text: parent.label; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {   // search field
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: search.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Theme.borderMuted
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10
                Text {
                    text: ({ apps: "\uf002", calc: "\uf1ec", actions: "\uf120", clipboard: "\uf328" })[root.mode]
                    color: root.mode === "apps" ? Theme.textDimmer : root.accent
                    font { family: Theme.fontFamily; pixelSize: 14 }
                }
                TextInput {
                    id: search
                    objectName: "launcherSearch"
                    Layout.fillWidth: true
                    color: Theme.text
                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                    clip: true
                    selectByMouse: true
                    onTextChanged: { root.query = text; root.current = 0 }
                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: root.activate()
                    Keys.onEnterPressed: root.activate()
                    Keys.onDownPressed: root.move(root.mode === "apps" ? root.cols : 1)
                    Keys.onUpPressed: root.move(root.mode === "apps" ? -root.cols : -1)
                    Keys.onLeftPressed: function(event) {
                        event.accepted = root.mode === "apps" && cursorPosition === 0 && root.count > 0
                        if (event.accepted) root.move(-1)
                    }
                    Keys.onRightPressed: function(event) {
                        event.accepted = root.mode === "apps" && cursorPosition === text.length && root.count > 0
                        if (event.accepted) root.move(1)
                    }
                    Keys.onDeletePressed: function(event) {   // at the end of the text: delete the entry
                        event.accepted = root.mode === "clipboard" && cursorPosition === text.length
                        if (event.accepted) root.deleteClip(root.current)
                    }
                    Keys.onTabPressed: {   // next category (apps)
                        var i = root.categories.indexOf(root.category)
                        root.category = root.categories[(i + 1) % root.categories.length]
                        root.current = 0
                    }
                    Text {
                        visible: !parent.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clipboard ? "Search clipboard\u2026" : "Search apps   \u00b7   = calculate   \u00b7   > actions"
                        color: Theme.textFaint
                        font: parent.font
                    }
                }
                Text {
                    text: root.count
                    color: Theme.textFaint
                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                }
            }
        }

        Flickable {   // categories (apps)
            visible: root.mode === "apps"
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            contentWidth: catRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: catRow
                spacing: 6
                Repeater {
                    model: root.categories
                    Rectangle {
                        required property string modelData
                        readonly property bool on: modelData === root.category
                        width: catLabel.implicitWidth + 20; height: 26; radius: 8
                        color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : Theme.surface
                        border.width: 1
                        border.color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Theme.borderMuted
                        Text {
                            id: catLabel
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? root.accent : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSm; bold: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.category = parent.modelData; root.current = 0; search.forceActiveFocus() }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: root.count === 0 && !(root.mode === "calc" && !root.term)
                text: root.mode === "clipboard" ? "Clipboard history is empty" : "Nothing found"
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
            Text {
                anchors.centerIn: parent
                visible: root.mode === "calc" && !root.term
                text: "Type an expression: = 2^10, = 5 km to mi, = 80 * 20%"
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: root.mode === "apps"
                model: root.apps
                currentIndex: root.current
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                cellWidth: width / root.cols
                cellHeight: Theme.launcherIconSize + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current
                    width: grid.cellWidth; height: grid.cellHeight
                    Rectangle {
                        anchors { fill: parent; margins: 2 }
                        radius: 12
                        color: tile.selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
                             : tileMouse.containsMouse ? Theme.surfaceHover : "transparent"
                        border.width: 1
                        border.color: tile.selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : "transparent"
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Item {
                            width: Theme.launcherIconSize; height: Theme.launcherIconSize
                            anchors.horizontalCenter: parent.horizontalCenter
                            Image {
                                id: icon
                                anchors.fill: parent
                                source: tile.modelData.icon ? "image://icon/" + tile.modelData.icon : ""
                                sourceSize { width: Theme.launcherIconSize; height: Theme.launcherIconSize }
                                visible: status === Image.Ready
                                asynchronous: true
                            }
                            Rectangle {   // fallback: first letter
                                anchors.fill: parent
                                radius: 12
                                color: Theme.surface
                                visible: icon.status !== Image.Ready
                                Text {
                                    anchors.centerIn: parent
                                    text: (tile.modelData.name || "?").charAt(0).toUpperCase()
                                    color: Theme.textDim
                                    font { family: Theme.fontFamily; pixelSize: 20; bold: true }
                                }
                            }
                        }
                        Text {
                            width: grid.cellWidth - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            color: tile.selected ? root.accent : tileMouse.containsMouse ? Theme.text : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                        }
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = tile.index
                        onClicked: root.activate(tile.index)
                    }
                }
            }

            ListView {
                id: list
                objectName: "launcherList"
                anchors.fill: parent
                visible: root.mode !== "apps"
                model: root.rows
                currentIndex: root.current
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                spacing: 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current
                    readonly property bool armed: root.armed !== "" && root.armed === modelData.id
                    readonly property bool image: root.mode === "clipboard" && modelData.ext !== ""
                    width: list.width
                    height: image ? 72 : 44
                    radius: 10
                    color: armed ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                         : selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
                         : rowMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    border.width: 1
                    border.color: armed ? Theme.error
                        : selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Text {
                            visible: !row.image
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: root.mode === "clipboard" ? "\uf328" : (row.modelData.icon || "")
                            color: row.modelData.destructive || row.modelData.error ? Theme.error
                                 : row.selected ? root.accent : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: 15 }
                        }
                        Image {   // clipboard image: decoded once, lazily, into the runtime dir
                            visible: row.image
                            Layout.preferredWidth: 96; Layout.preferredHeight: 60
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize { width: 192; height: 120 }
                            source: thumb.path ? "file://" + thumb.path : ""
                            Process {
                                id: thumb
                                property string path: ""
                                // ponytail: thumbnails pile up in $XDG_RUNTIME_DIR (tmpfs, cleared at logout)
                                command: ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/quickshell-clip"; mkdir -p "$d"; f="$d/$2";'
                                    + ' [ -s "$f" ] || printf "%s" "$1" | cliphist decode > "$f"; printf "%s" "$f"',
                                    "sh", row.modelData.line || "", (row.modelData.id || "") + "." + (row.modelData.ext || "")]
                                running: row.image
                                stdout: StdioCollector { onStreamFinished: thumb.path = text }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: row.armed ? "Press Enter again: " + row.modelData.title
                                    : row.image ? "Image \u00b7 " + row.modelData.text.replace(/^\[\[ binary data | \]\]$/g, "")
                                    : root.mode === "clipboard" ? row.modelData.text : row.modelData.title
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                color: row.armed || row.modelData.error ? Theme.error : row.selected ? Theme.text : Theme.textDim
                                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: root.mode !== "clipboard" }
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: root.mode === "clipboard" ? "" : (row.modelData.subtitle || "")
                                elide: Text.ElideRight
                                color: Theme.textFaint
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                            }
                        }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = row.index
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.MiddleButton) root.deleteClip(row.index)
                            else root.activate(row.index)
                        }
                    }
                }
            }
        }

        Row {   // hints
            Layout.alignment: Qt.AlignHCenter
            spacing: 16
            Hint { key: "Esc"; label: "close" }
            Hint { key: "\u23ce"; label: ({ apps: "launch", calc: "copy result", actions: "run", clipboard: "copy" })[root.mode] }
            Hint { key: root.mode === "apps" ? "\u2190\u2191\u2193\u2192" : "\u2191\u2193"; label: "move" }
            Hint { visible: root.mode === "apps"; key: "Tab"; label: "category" }
            Hint { visible: root.mode === "clipboard"; key: "Del"; label: "delete" }
        }
    }
}
