import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../theme"

// Keybind cheatsheet (SPEC 5.2): the live binds from `hyprctl binds -j`, grouped by their
// description prefix ("Apps: Terminal" -> Apps), in balanced columns. Typing filters;
// Escape closes.
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    signal closeRequested()

    implicitWidth: Theme.dashboardWidth
    implicitHeight: Theme.cheatsheetHeight - Theme.surfacePadding

    property var groups: []
    property string query: ""
    readonly property var shown: filterGroups(groups, query)
    readonly property var columns: balance(shown, 3)

    onActiveChanged: if (active) { query = ""; filter.text = ""; binds.running = true; focusLater.restart() }
    Timer { id: focusLater; interval: 50; onTriggered: filter.forceActiveFocus() }
    Process {
        id: binds
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.groups = root.parseBinds(JSON.parse(text)) } catch (e) { root.groups = [] }
            }
        }
    }

    // Hyprland modmask bits (SPEC 5.2), in the usual reading order.
    function modNames(mask) {
        return [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "Caps"], [16, "Mod2"],
                [32, "Mod3"], [128, "Mod5"]].filter(function(b) { return mask & b[0] }).map(function(b) { return b[1] })
    }
    function keyLabel(key) {
        var names = { "return": "Enter", space: "Space", slash: "/", left: "\u2190", right: "\u2192",
            up: "\u2191", down: "\u2193", mouse_up: "Scroll up", mouse_down: "Scroll down",
            "mouse:272": "Left drag", "mouse:273": "Right drag", Print: "Print",
            XF86AudioRaiseVolume: "Vol +", XF86AudioLowerVolume: "Vol \u2212", XF86AudioMute: "Mute",
            XF86AudioMicMute: "Mic mute", XF86AudioPlay: "Play", XF86AudioPause: "Pause",
            XF86AudioNext: "Next", XF86AudioPrev: "Prev" }
        return names[key] || names[key.toLowerCase()] || (key.length === 1 ? key.toUpperCase() : key)
    }
    // [{ name, items: [{ keys: [..], text }] }], groups in first-seen order. A bind with no
    // description lands in "Other" (every bind in binds.lua has one; see check-desktop-phase0).
    function parseBinds(list) {
        var groups = [], byName = {}
        list.forEach(function(b) {
            var d = b.has_description ? b.description : ""
            var cut = d.indexOf(": ")
            var name = cut > 0 ? d.substring(0, cut) : "Other"
            var keys = b.key === "SUPER_L" && b.modmask === 64 ? ["Super \u00d72"]   // double-tap Super
                : modNames(b.modmask).concat([keyLabel(b.key)])
            if (!byName[name]) { byName[name] = { name: name, items: [] }; groups.push(byName[name]) }
            byName[name].items.push({ keys: keys, text: cut > 0 ? d.substring(cut + 2) : (d || "No description") })
        })
        return groups
    }
    function filterGroups(list, q) {
        q = q.trim().toLowerCase()
        if (!q) return list
        return list.map(function(g) {
            var all = g.name.toLowerCase().indexOf(q) >= 0
            return { name: g.name, items: g.items.filter(function(i) {
                return all || (i.text + " " + i.keys.join(" ")).toLowerCase().indexOf(q) >= 0 }) }
        }).filter(function(g) { return g.items.length > 0 })
    }
    // Biggest groups first, each into the currently shortest column (a header counts as 1.5
    // rows); each column then keeps the groups' original order.
    function balance(list, n) {
        var cols = [], heights = []
        for (var i = 0; i < n; i++) { cols.push([]); heights.push(0) }
        list.map(function(g, i) { return { g: g, i: i } })
            .sort(function(a, b) { return b.g.items.length - a.g.items.length || a.i - b.i })
            .forEach(function(e) {
                var k = heights.indexOf(Math.min.apply(null, heights))
                cols[k].push(e); heights[k] += e.g.items.length + 1.5
            })
        return cols.map(function(c) {
            return c.sort(function(a, b) { return a.i - b.i }).map(function(e) { return e.g })
        })
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {   // filter
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: filter.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Theme.borderMuted
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10
                Text { text: "\uf11c"; color: root.accent; font { family: Theme.fontFamily; pixelSize: 14 } }
                TextInput {
                    id: filter
                    objectName: "cheatsheetFilter"
                    Layout.fillWidth: true
                    color: Theme.text
                    font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                    clip: true
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: root.closeRequested()
                    Text {
                        visible: !parent.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter keybinds\u2026"
                        color: Theme.textFaint
                        font: parent.font
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: cols.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                anchors.centerIn: parent
                visible: root.shown.length === 0
                text: root.groups.length ? "No keybind matches" : "Reading keybinds\u2026"
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
            Row {
                id: cols
                width: parent.width
                spacing: 16
                Repeater {
                    model: root.columns
                    Column {
                        id: column
                        required property var modelData
                        width: (cols.width - 2 * cols.spacing) / 3
                        spacing: 12
                        Repeater {
                            model: column.modelData
                            Column {
                                id: group
                                required property var modelData
                                width: column.width
                                spacing: 4
                                Text {
                                    text: group.modelData.name
                                    color: root.accent
                                    font { family: Theme.fontFamily; pixelSize: Theme.fontSm; bold: true }
                                }
                                Repeater {
                                    model: group.modelData.items
                                    RowLayout {
                                        id: bind
                                        required property var modelData
                                        width: group.width
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: bind.modelData.text
                                            elide: Text.ElideRight
                                            color: Theme.textDim
                                            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                        }
                                        Row {
                                            spacing: 3
                                            Repeater {
                                                model: bind.modelData.keys
                                                Rectangle {
                                                    required property string modelData
                                                    width: keyText.implicitWidth + 10; height: 18; radius: 5
                                                    color: Qt.rgba(1, 1, 1, 0.06)
                                                    border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                                                    Text {
                                                        id: keyText
                                                        anchors.centerIn: parent
                                                        text: parent.modelData
                                                        color: Theme.text
                                                        font { family: Theme.fontFamily; pixelSize: 10 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
