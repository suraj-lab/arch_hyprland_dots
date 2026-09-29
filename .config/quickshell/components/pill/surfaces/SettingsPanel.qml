import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../theme"
import "../../../services"

// Settings surface (SPEC 6.5): sections on the left, controls on the right. Every control
// writes settings.json through Config.set, so it survives a shell restart; Caffeine and the
// night light switch are live state (like their bar and System toggles).
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    signal closeRequested()
    signal actionRequested(string id)       // run by the shell after the surface closes
    signal surfaceRequested(string name)    // switch to another surface (cheatsheet)

    implicitWidth: Theme.dashboardWidth
    implicitHeight: Theme.settingsHeight - Theme.surfacePadding

    property string section: "appearance"
    readonly property var sections: [
        { key: "appearance", icon: "\uf1fc", title: "Appearance" },
        { key: "displays", icon: "\uf108", title: "Displays" },
        { key: "sound", icon: "\uf028", title: "Sound" },
        { key: "connections", icon: "\uf1eb", title: "Network & Bluetooth" },
        { key: "power", icon: "\uf011", title: "Power & idle" },
        { key: "night", icon: "\uf186", title: "Night light" },
        { key: "defaults", icon: "\uf1de", title: "Default apps" },
        { key: "gaming", icon: "\uf11b", title: "Gaming" },
        { key: "keybinds", icon: "\uf11c", title: "Keybinds" },
        { key: "about", icon: "\uf05a", title: "About" }
    ]
    onActiveChanged: {
        if (!active) return
        if (!about.running && !aboutText) about.running = true
        if (!monitorsProc.running) monitorsProc.running = true
        if (!gamingProc.running) gamingProc.running = true
        if (!defaultsProc.running) defaultsProc.running = true
    }
    property date now: new Date()   // for the night light status line
    Timer { interval: 30000; running: root.active; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    // ── Pure helpers (unit-tested) ─────────────────────────────────────────
    function duration(sec) {
        return sec <= 0 ? "Off" : sec < 60 ? sec + " s" : sec % 3600 === 0 ? sec / 3600 + " h"
             : Math.round(sec / 6) / 10 + " min"
    }
    // Choices for a timeout; a value set by hand that is not among them is shown too.
    function timeoutOptions(values, current) {
        var list = values.indexOf(current) >= 0 || current === undefined ? values : values.concat([current]).sort(function(a, b) { return a - b })
        return list.map(function(v) { return { label: duration(v), value: v } })
    }
    function shiftClock(hhmm, delta) {
        var p = hhmm.split(":"), m = ((Number(p[0]) * 60 + Number(p[1]) + delta) % 1440 + 1440) % 1440
        return (m < 600 ? "0" : "") + Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + m % 60
    }
    // `hyprctl version -j`, `qs --version`, `uname -r`, PRETTY_NAME, one per line (JSON first).
    function parseAbout(text) {
        var lines = text.split("\n"), hypr = ""
        try { var j = JSON.parse(lines[0]); hypr = j.version || j.tag || "" } catch (e) {}
        var qs = (lines[1] || "").match(/Quickshell ([^ ]+)/)
        return { hyprland: hypr || "?", quickshell: qs ? qs[1] : "?", kernel: lines[2] || "?", os: lines[3] || "?" }
    }

    // `hyprctl monitors -j`: a top-level array; sorted by x. Never throws.
    function parseMonitors(text) {
        try {
            var arr = JSON.parse(text)
            if (!Array.isArray(arr)) return []
            var result = []
            for (var i = 0; i < arr.length; i++) {
                var m = arr[i]
                if (!m || typeof m.name !== "string") continue
                var w = typeof m.width === "number" ? m.width : 0
                var h = typeof m.height === "number" ? m.height : 0
                var hz = typeof m.refreshRate === "number" ? Math.round(m.refreshRate) : 0
                result.push({ name: m.name, description: m.description || m.model || m.name,
                              mode: w + "x" + h + " @ " + hz + " Hz",
                              scale: typeof m.scale === "number" ? m.scale : 1,
                              position: (m.x || 0) + ", " + (m.y || 0),
                              vrr: m.vrr === true, focused: m.focused === true })
            }
            result.sort(function(a, b) { return parseInt(a.position, 10) - parseInt(b.position, 10) })
            return result
        } catch (error) { return [] }
    }
    // `D=<mime>=<desktop-id>` lines, one per queried type, prefixing the cache blob.
    function parseDefaults(text) {
        var result = {}
        text.split("\n").forEach(function(line) {
            var m = line.match(/^D=([^=]+)=(.*)$/)
            if (m) result[m[1]] = m[2]
        })
        return result
    }
    // Desktop ids for `type` from concatenated mimeinfo.cache files, in order, deduped.
    function candidates(cacheText, type) {
        var seen = {}, result = []
        cacheText.split("\n").forEach(function(line) {
            var i = line.indexOf("=")
            if (i <= 0 || line.slice(0, i) !== type) return
            line.slice(i + 1).split(";").forEach(function(id) {
                id = id.trim()
                if (id && !seen[id]) { seen[id] = true; result.push(id) }
            })
        })
        return result
    }
    // Gaming prerequisites: `helper=yes|no` and `daemon=<path|missing>` lines.
    function parseGaming(text) {
        var helper = false, daemon = ""
        text.split("\n").forEach(function(line) {
            if (line.indexOf("helper=yes") === 0) helper = true
            if (line.indexOf("daemon=") === 0) daemon = line.slice(7)
        })
        return { helper: helper, daemon: daemon !== "" && daemon !== "missing" ? daemon : "" }
    }

    property string aboutText: ""
    readonly property var aboutInfo: parseAbout(aboutText)
    Process {
        id: about
        command: ["sh", "-c", "hyprctl version -j 2>/dev/null | tr -d '\\n'; echo; qs --version 2>/dev/null | head -1;"
                  + " uname -r; . /etc/os-release 2>/dev/null; echo \"${PRETTY_NAME:-Linux}\""]
        stdout: StdioCollector { onStreamFinished: root.aboutText = text }
    }

    // ── 6.5b: monitors, default apps and gaming (read-only status + one xdg-mime action) ──
    property string monitorsText: ""
    readonly property var monitors: parseMonitors(monitorsText)

    property string defaultsText: ""
    readonly property var defaultMime: parseDefaults(defaultsText)
    readonly property var defaultAppTypes: [
        { key: "browser", title: "Web browser",
          types: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml"] },
        { key: "files", title: "Files", types: ["inode/directory"] },
        { key: "text", title: "Text editor",
          types: ["text/plain", "text/markdown", "text/x-python", "text/x-csrc", "text/x-chdr",
                  "text/x-lua", "application/x-shellscript", "application/json", "application/xml",
                  "application/toml", "application/x-yaml"] },
        { key: "images", title: "Images",
          types: ["image/png", "image/jpeg", "image/gif", "image/bmp", "image/tiff", "image/svg+xml"] }
    ]
    property string defaultsError: ""
    property string expanded: ""         // the open default-app chooser
    function defaultTypes(key) {
        for (var i = 0; i < defaultAppTypes.length; i++)
            if (defaultAppTypes[i].key === key) return defaultAppTypes[i]
        return null
    }
    function currentDefault(key) {
        var spec = defaultTypes(key)
        if (!spec) return ""
        var value = defaultMime[spec.types[0]]
        return value === undefined ? "" : value
    }
    function appName(id) {
        var entry = DesktopEntries.byId(id.replace(/\.desktop$/, ""))
        return entry ? entry.name : id.replace(/\.desktop$/, "")
    }
    function appIcon(id) {
        var entry = DesktopEntries.byId(id.replace(/\.desktop$/, ""))
        return entry ? entry.icon : ""
    }
    function appCandidates(key) {
        var spec = defaultTypes(key)
        if (!spec) return []
        var current = currentDefault(key)
        var ids = candidates(defaultsText, spec.types[0])
        if (current && ids.indexOf(current) < 0) ids.unshift(current)   // current first, even if unlisted
        var result = []
        for (var i = 0; i < ids.length; i++) {
            var entry = DesktopEntries.byId(ids[i].replace(/\.desktop$/, ""))
            if (!entry || entry.noDisplay) continue
            result.push({ id: ids[i], name: entry.name || ids[i], icon: entry.icon || "" })
        }
        return result
    }
    function chooseDefault(key, id) {
        var spec = defaultTypes(key)
        if (!spec || setDefaultProc.running) return
        expanded = ""
        defaultsError = ""
        setDefaultProc.command = ["xdg-mime", "default", id].concat(spec.types)
        setDefaultProc.running = true
    }

    property string gamingText: ""
    readonly property var gaming: parseGaming(gamingText)

    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { onStreamFinished: root.monitorsText = text }
    }
    Process {
        id: gamingProc
        command: ["sh", "-c",
            "if [ -x /usr/local/bin/switch-to-gaming ]; then echo helper=yes; else echo helper=no; fi; "
            + "d=$(command -v gamemoded 2>/dev/null || true); echo \"daemon=${d:-missing}\""]
        stdout: StdioCollector { onStreamFinished: root.gamingText = text }
    }
    Process {
        id: defaultsProc
        command: ["bash", "-c",
            ": \"${XDG_DATA_HOME:=$HOME/.local/share}\"; : \"${XDG_DATA_DIRS:=/usr/local/share:/usr/share}\"; "
            + "for t in x-scheme-handler/https inode/directory text/plain image/png; do "
            + "printf \"D=%s=%s\\n\" \"$t\" \"$(xdg-mime query default \"$t\" 2>/dev/null)\"; done; "
            + "IFS=: read -ra dirs <<< \"$XDG_DATA_DIRS\"; "
            + "for d in \"$XDG_DATA_HOME\" \"${dirs[@]}\"; do f=\"$d/applications/mimeinfo.cache\"; "
            + "[ -f \"$f\" ] && cat \"$f\" 2>/dev/null; done"]
        stdout: StdioCollector { onStreamFinished: root.defaultsText = text }
    }
    Process {
        id: setDefaultProc
        stderr: StdioCollector { id: setDefaultErr }
        onExited: code => {
            if (code !== 0) root.defaultsError = setDefaultErr.text.trim().split("\n").pop() || "Could not set the default app"
            else defaultsProc.running = true       // re-query, so the row shows the new app
        }
    }

    // A labelled row: title (and hint) on the left, the control on the right.
    component Setting: RowLayout {
        id: setting
        property string title
        property string hint
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {   // fills, so the control sits on the right even without a hint
                Layout.fillWidth: true
                text: setting.title
                color: Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: setting.hint
                wrapMode: Text.Wrap
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
        }
        Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }
    component Heading: Text {
        color: Theme.text
        font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true }
    }
    // "−  19:30  +" in 30-minute steps.
    component ClockStepper: Row {
        id: stepper
        property string value
        signal picked(string value)
        spacing: 6
        SurfaceIcon { objectName: "minus"; glyph: "\uf068"; accent: root.accent; onClicked: stepper.picked(root.shiftClock(stepper.value, -30)) }
        Text {
            width: 52
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: stepper.value
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
        }
        SurfaceIcon { objectName: "plus"; glyph: "\uf067"; accent: root.accent; onClicked: stepper.picked(root.shiftClock(stepper.value, 30)) }
    }
    // A read-only status line for the Gaming section: label left, check/cross + text right.
    component StatusRow: RowLayout {
        id: status
        property string label
        property bool ok
        property string yesText: "Present"
        property string noText: "Missing"
        property color noColor: Theme.error
        Layout.fillWidth: true
        Text {
            Layout.preferredWidth: 160
            text: status.label
            color: Theme.textDim
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
        }
        Text {
            Layout.fillWidth: true
            text: status.ok ? "\uf00c " + status.yesText : "\uf00d " + status.noText
            color: status.ok ? Theme.success : status.noColor
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ── Section list ──
        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.fillWidth: false   // a nested layout fills by default
            Layout.fillHeight: true
            spacing: 2
            Repeater {
                model: root.sections
                Rectangle {
                    id: entry
                    required property var modelData
                    readonly property bool on: root.section === modelData.key
                    objectName: "section:" + modelData.key
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 10
                    color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                         : entryMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: entry.modelData.icon
                            color: entry.on ? root.accent : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.title
                            elide: Text.ElideRight
                            color: entry.on ? root.accent : Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: entry.on }
                        }
                    }
                    MouseArea { id: entryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.section = entry.modelData.key }
                }
            }
            Item { Layout.fillHeight: true }
        }
        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.borderMuted }

        // ── Section content ──
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: content
                width: flick.width - 8   // not parent.width: the content item's width follows its children
                spacing: 18

                // Appearance
                ColumnLayout {
                    visible: root.section === "appearance"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Appearance" }
                    Setting {
                        title: "Wallpaper"
                        hint: "The accent colour follows the wallpaper."
                        Row {
                            spacing: 10
                            Rectangle {
                                width: 28; height: 28; radius: 8
                                color: root.accent
                                border.width: 1; border.color: Theme.borderMuted
                            }
                            SurfaceButton {
                                width: 150; height: 28
                                accent: root.accent
                                label: "Choose wallpaper\u2026"
                                onClicked: root.actionRequested("wallpaper")
                            }
                        }
                    }
                    Setting {
                        title: "Pill at rest"
                        hint: "Tab shows the workspaces and the clock; handle is a thin bar."
                        SurfaceChoice {
                            objectName: "restStyle"
                            accent: root.accent
                            options: [{ label: "Tab", value: "tab" }, { label: "Handle", value: "handle" }]
                            value: Config.pillFor("").restStyle
                            onChosen: v => Config.set("pill.restStyle", v)
                        }
                    }
                    Setting {
                        title: "Animations"
                        hint: "Off also while Desktop Game Mode is on."
                        SurfaceSwitch {
                            objectName: "animations"
                            accent: root.accent
                            on: Config.appearance.animations
                            onToggled: Config.set("appearance.animations", !Config.appearance.animations)
                        }
                    }
                }

                // Displays
                ColumnLayout {
                    visible: root.section === "displays"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "Displays" }
                    Text {
                        visible: root.monitors.length === 0
                        Layout.fillWidth: true
                        text: "No monitors"
                        color: Theme.textFaint
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                    Repeater {
                        model: root.monitors
                        Rectangle {
                            id: card
                            required property var modelData
                            objectName: "monitor:" + modelData.name
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: 10
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.borderMuted
                            RowLayout {
                                anchors { fill: parent; margins: 12 }
                                spacing: 12
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.name
                                        elide: Text.ElideRight
                                        color: card.modelData.focused ? root.accent : Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.description
                                        elide: Text.ElideRight
                                        color: Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                    }
                                }
                                ColumnLayout {
                                    spacing: 2
                                    Text {
                                        Layout.alignment: Qt.AlignRight
                                        text: card.modelData.mode
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignRight
                                        text: "Scale " + card.modelData.scale + " · " + card.modelData.position + " · " + (card.modelData.vrr ? "VRR on" : "VRR off")
                                        color: Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Edit hypr/modules/monitors.lua to change the layout."
                        wrapMode: Text.Wrap
                        color: Theme.textFaint
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                }

                // Sound
                ColumnLayout {
                    visible: root.section === "sound"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "Sound" }
                    Text {
                        visible: Audio.sinks.length === 0 && Audio.sources.length === 0
                        Layout.fillWidth: true
                        text: "No audio devices"
                        color: Theme.textFaint
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                    ColumnLayout {
                        visible: Audio.sinks.length > 0
                        Layout.fillWidth: true
                        spacing: 4
                        Text { text: "Output"; color: Theme.textFaint; font { family: Theme.fontFamily; pixelSize: Theme.fontSm } }
                        Repeater {
                            model: Audio.sinks
                            Rectangle {
                                id: sinkRow
                                required property var modelData
                                objectName: "sink:" + modelData.name
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 10
                                color: sinkMouse.containsMouse ? Theme.surfaceHover
                                     : modelData.isDefault ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1) : "transparent"
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 10
                                    Text {
                                        Layout.preferredWidth: 14
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "\uf111"
                                        color: sinkRow.modelData.isDefault ? root.accent : Theme.textGhost
                                        font { family: Theme.fontFamily; pixelSize: 11 }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: sinkRow.modelData.desc
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                                    }
                                    Text {
                                        visible: sinkRow.modelData.state !== ""
                                        text: sinkRow.modelData.state
                                        color: Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                    }
                                }
                                MouseArea {
                                    id: sinkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Audio.setDefaultSink(sinkRow.modelData.name)
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: Audio.sources.length > 0
                        Layout.fillWidth: true
                        spacing: 4
                        Text { text: "Input"; color: Theme.textFaint; font { family: Theme.fontFamily; pixelSize: Theme.fontSm } }
                        Repeater {
                            model: Audio.sources
                            Rectangle {
                                id: sourceRow
                                required property var modelData
                                objectName: "source:" + modelData.name
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 10
                                color: sourceMouse.containsMouse ? Theme.surfaceHover
                                     : modelData.isDefault ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1) : "transparent"
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 10
                                    Text {
                                        Layout.preferredWidth: 14
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "\uf111"
                                        color: sourceRow.modelData.isDefault ? root.accent : Theme.textGhost
                                        font { family: Theme.fontFamily; pixelSize: 11 }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: sourceRow.modelData.desc
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                                    }
                                    Text {
                                        visible: sourceRow.modelData.state !== ""
                                        text: sourceRow.modelData.state
                                        color: Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                    }
                                }
                                MouseArea {
                                    id: sourceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Audio.setDefaultSource(sourceRow.modelData.name)
                                }
                            }
                        }
                    }
                    Setting {
                        title: "Volume and apps"
                        hint: "The default device is saved by WirePlumber, not settings.json."
                        SurfaceButton {
                            objectName: "openSound"
                            width: 120; height: 28
                            accent: root.accent
                            label: "Open"
                            onClicked: root.surfaceRequested("sound")
                        }
                    }
                }

                // Network & Bluetooth
                ColumnLayout {
                    visible: root.section === "connections"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Network & Bluetooth" }
                    Setting {
                        title: "Wi-Fi"
                        hint: Net.wifiEnabled ? (Net.ssid || "Not connected") : "Off"
                        SurfaceButton {
                            objectName: "openNetwork"
                            width: 120; height: 28
                            accent: root.accent
                            label: "Open"
                            onClicked: root.surfaceRequested("network")
                        }
                    }
                    Setting {
                        title: "Bluetooth"
                        hint: Bt.enabled ? (Bt.devices.filter(function(d) { return d.connected }).length + " connected") : "Off"
                        SurfaceButton {
                            objectName: "openBluetooth"
                            width: 120; height: 28
                            accent: root.accent
                            label: "Open"
                            onClicked: root.surfaceRequested("bluetooth")
                        }
                    }
                }

                // Power & idle
                ColumnLayout {
                    visible: root.section === "power"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Power & idle" }
                    Setting {
                        title: "Lock after"
                        SurfaceChoice {
                            objectName: "lockSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 300, 600, 900, 1800], Config.idle.lockSec)
                            value: Config.idle.lockSec
                            onChosen: v => Config.set("idle.lockSec", v)
                        }
                    }
                    Setting {
                        title: "Screens off after"
                        SurfaceChoice {
                            objectName: "dpmsSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 300, 600, 900, 1800], Config.idle.dpmsSec)
                            value: Config.idle.dpmsSec
                            onChosen: v => Config.set("idle.dpmsSec", v)
                        }
                    }
                    Setting {
                        title: "Suspend after"
                        hint: "Off keeps the PC awake (screens still turn off)."
                        SurfaceChoice {
                            objectName: "suspendSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 1800, 3600, 7200], Config.idle.suspendSec)
                            value: Config.idle.suspendSec
                            onChosen: v => Config.set("idle.suspendSec", v)
                        }
                    }
                    Setting {
                        title: "Caffeine"
                        hint: "Keeps the screens awake until turned off. " + Desktop.idleStatus + "."
                        SurfaceSwitch { accent: root.accent; on: Desktop.caffeine; onToggled: Desktop.toggleCaffeine() }
                    }
                }

                // Night light
                ColumnLayout {
                    visible: root.section === "night"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Night light" }
                    Setting {
                        title: "Night light"
                        hint: !Desktop.nightLight ? "Off"
                            : Desktop.isNight(root.now.getHours() * 60 + root.now.getMinutes(),
                                              Desktop.minutes(Config.nightLight.from), Desktop.minutes(Config.nightLight.to))
                              ? "Warm now (" + Config.nightLight.temperature + " K)" : "Neutral now, warm from " + Config.nightLight.from
                        SurfaceSwitch { accent: root.accent; on: Desktop.nightLight; onToggled: Desktop.toggleNightLight() }
                    }
                    Setting {
                        title: "Temperature"
                        hint: "Lower is warmer."
                        SurfaceChoice {
                            objectName: "temperature"
                            accent: root.accent
                            options: [3000, 3500, 4000, 4500, 5000].concat(
                                [3000, 3500, 4000, 4500, 5000].indexOf(Config.nightLight.temperature) >= 0 ? []
                                : [Config.nightLight.temperature]).map(function(t) { return { label: t + " K", value: t } })
                            value: Config.nightLight.temperature
                            onChosen: v => Config.set("nightLight.temperature", v)
                        }
                    }
                    Setting {
                        title: "Warm from"
                        ClockStepper { objectName: "from"; value: Config.nightLight.from; onPicked: v => Config.set("nightLight.from", v) }
                    }
                    Setting {
                        title: "Until"
                        hint: "Earlier than the start means the next morning."
                        ClockStepper { objectName: "to"; value: Config.nightLight.to; onPicked: v => Config.set("nightLight.to", v) }
                    }
                }

                // Default apps
                ColumnLayout {
                    visible: root.section === "defaults"
                    Layout.fillWidth: true
                    spacing: 10
                    Heading { text: "Default apps" }
                    Text {
                        Layout.fillWidth: true
                        text: "Set with xdg-mime; applies to newly opened files and links."
                        wrapMode: Text.Wrap
                        color: Theme.textFaint
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                    Text {
                        visible: root.defaultsError !== ""
                        Layout.fillWidth: true
                        text: root.defaultsError
                        wrapMode: Text.Wrap
                        color: Theme.error
                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                    }
                    Repeater {
                        model: root.defaultAppTypes
                        ColumnLayout {
                            id: category
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            readonly property string key: modelData.key
                            readonly property string current: root.currentDefault(key)
                            readonly property bool open: root.expanded === key
                            Text {
                                text: category.modelData.title
                                color: Theme.textFaint
                                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                            }
                            Rectangle {
                                objectName: "default:" + category.key
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 10
                                color: chooserMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                                border.width: 1
                                border.color: Theme.borderMuted
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 10
                                    Image {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        visible: root.appIcon(category.current) !== ""
                                        source: visible ? "image://icon/" + root.appIcon(category.current) : ""
                                        sourceSize: Qt.size(16, 16)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: category.current ? root.appName(category.current) : "Not set"
                                        elide: Text.ElideRight
                                        color: category.current ? Theme.text : Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                                    }
                                    Text {
                                        text: category.open ? "\uf106" : "\uf107"
                                        color: Theme.textFaint
                                        font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                    }
                                }
                                MouseArea {
                                    id: chooserMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.expanded = root.expanded === category.key ? "" : category.key
                                }
                            }
                            Repeater {
                                model: category.open ? root.appCandidates(category.key) : []
                                Rectangle {
                                    id: candRow
                                    required property var modelData
                                    objectName: "candidate:" + modelData.id
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16
                                    implicitHeight: 32
                                    radius: 8
                                    color: candMouse.containsMouse ? Theme.surfaceHover : "transparent"
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                        spacing: 10
                                        Image {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            visible: candRow.modelData.icon !== ""
                                            source: visible ? "image://icon/" + candRow.modelData.icon : ""
                                            sourceSize: Qt.size(16, 16)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: candRow.modelData.name
                                            elide: Text.ElideRight
                                            color: Theme.text
                                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                                        }
                                        Text {
                                            visible: candRow.modelData.id === category.current
                                            text: "\uf00c"
                                            color: root.accent
                                            font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
                                        }
                                    }
                                    MouseArea {
                                        id: candMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.chooseDefault(category.key, candRow.modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Gaming
                ColumnLayout {
                    visible: root.section === "gaming"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "Gaming" }
                    StatusRow { label: "Gaming Mode helper"; ok: root.gaming.helper }
                    StatusRow { label: "GameMode daemon"; ok: root.gaming.daemon !== "" }
                    StatusRow { label: "Game mode active"; ok: Desktop.gamemodedActive; yesText: "On"; noText: "Off"; noColor: Theme.textFaint }
                    Setting {
                        title: "Game Mode follows games"
                        hint: "Apply Game Mode (DND on, effects off) automatically while a game runs."
                        SurfaceSwitch {
                            objectName: "autoGameMode"
                            accent: root.accent
                            on: Config.gaming.autoGameMode
                            onToggled: Config.set("gaming.autoGameMode", !Config.gaming.autoGameMode)
                        }
                    }
                }

                // Keybinds
                ColumnLayout {
                    visible: root.section === "keybinds"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Keybinds" }
                    Setting {
                        title: "Keybind cheatsheet"
                        hint: "Every Hyprland keybind, grouped and searchable. Also Super+/."
                        SurfaceButton {
                            width: 150; height: 28
                            accent: root.accent
                            primary: true
                            objectName: "openCheatsheet"
                            label: "Open cheatsheet"
                            onClicked: root.surfaceRequested("cheatsheet")
                        }
                    }
                }

                // About
                ColumnLayout {
                    visible: root.section === "about"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "About" }
                    Repeater {
                        model: [["System", root.aboutInfo.os], ["Kernel", root.aboutInfo.kernel],
                                ["Hyprland", root.aboutInfo.hyprland], ["Quickshell", root.aboutInfo.quickshell]]
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                Layout.preferredWidth: 120
                                text: parent.modelData[0]
                                color: Theme.textDim
                                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.modelData[1]
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
