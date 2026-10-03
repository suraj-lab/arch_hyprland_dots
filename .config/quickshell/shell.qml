//@ pragma Env QT_IMAGEIO_MAXALLOC=512
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import "theme"
import "components"
import "components/frame"
import "components/pill"
import "services"

ShellRoot {
    id: shellRoot
    settings.watchFiles: true

    Component.onCompleted: accentReadProc.running = true   // read cached accents on startup

    // ── Per-monitor dynamic accent colors from wallpaper ──────────────────
    property var monitorAccents: ({})       // { "DP-2": "#ab12cd", ... }
    property color globalAccent: "#00ffea"  // fallback from generic accent file

    function accentFor(screenName) {
        return monitorAccents[screenName] || globalAccent
    }

    IpcHandler {
        target: "accent"
        function update() { accentReadProc.running = true }
    }

    Process {
        id: accentReadProc
        command: ["bash", "-c",
            "cd \"$HOME/.cache/quickshell\" 2>/dev/null || exit 0; " +
            "[ -f accent ] && echo \"ALL=$(cat accent)\"; " +
            "for f in accent-*; do [ -f \"$f\" ] && echo \"${f#accent-}=$(cat \"$f\")\"; done"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var eq = line.indexOf("=")
                if (eq < 0) return
                var key = line.substring(0, eq).trim()
                var hex = line.substring(eq + 1).trim()
                if (!hex.match(/^#[0-9a-fA-F]{6}$/)) return

                if (key === "ALL") {
                    shellRoot.globalAccent = hex
                    Theme.accent = hex
                } else {
                    var m = Object.assign({}, shellRoot.monitorAccents)
                    m[key] = hex
                    shellRoot.monitorAccents = m
                }
            }
        }
    }

    // ── Wallpaper picker state ─────────────────────────────────────────────
    property bool wallpickerOpen: false

    // ── Workspace overview state ──────────────────────────────────────────
    property bool overviewOpen: false
    property var  overviewScreen: null

    // ── Screenshot state ──────────────────────────────────────────────────
    property string screenshotMode: ""   // "" | "area" | "screen"
    property var screenshotScreen: null

    // ── Session overlay state + processes ──────────────────────────────────
    property bool sessionOpen: false

    // ── Polkit agent (SPEC 6.1): the password prompt for pkexec, systemctl, GParted... ──
    // Polkit allows one agent per session and this registers once, at startup: if another
    // agent (polkit-kde-agent) already holds the session, this one stays unregistered.
    PolkitAgent {
        id: polkitAgent
        onIsRegisteredChanged: console.info("polkit agent registered:", isRegistered)
    }
    Timer {
        interval: 5000; running: true
        onTriggered: if (!polkitAgent.isRegistered)
            console.warn("polkit agent not registered (another agent running?); prompts go to it instead")
    }
    PolkitDialog { flow: polkitAgent.flow; accent: shellRoot.accentFor(Hypr.focusedMonitor ? Hypr.focusedMonitor.name : "") }

    // ── Screen time tracking (runs continuously) ──────────────────────────
    ScreenTimeTracker { id: stTracker }

    // ── Desktop services: idle, caffeine, night light, desktop game mode ──
    Binding { target: Desktop; property: "dndEnabled"; value: Notifs.dndEnabled }
    Connections {
        target: Desktop
        function onDndRequested(enabled) { Notifs.dndEnabled = enabled }
    }


    Process { id: pSuspend; command: ["systemctl", "suspend"]               }
    Process { id: pReboot;  command: ["systemctl", "reboot"]                }
    Process { id: pOff;     command: ["systemctl", "poweroff"]              }

    // Launcher ">" actions (SPEC 5.1), run after the launcher has closed.
    function runShellAction(id) {
        switch (id) {
        case "gaming": Desktop.enterGamingMode(); break
        case "gamemode": Desktop.toggleGameMode(); break
        case "caffeine": Desktop.toggleCaffeine(); break
        case "nightlight": Desktop.toggleNightLight(); break
        case "dnd": Notifs.dndEnabled = !Notifs.dndEnabled; break
        case "wallpaper": wallpickerIpc.toggle(); break
        case "overview": overviewIpc.toggle(); break
        case "cheatsheet": { const p = focusedPill(); if (p) p.openSurface("cheatsheet", false); break }
        case "settings": { const p = focusedPill(); if (p) p.openSurface("settings", false); break }
        case "screenshot": screenshotIpc.area(); break
        case "lock": Desktop.lock(); break
        case "suspend": pSuspend.running = true; break
        case "logout": Hypr.dispatch("hl.dsp.exit()"); break
        case "reboot": pReboot.running = true; break
        case "poweroff": pOff.running = true; break
        default: console.warn("runShellAction: unknown action", id)
        }
    }

    // Frame + pill per monitor (SPEC Phase 4).
    Variants {
        model: Quickshell.screens
        Frame {
            required property ShellScreen modelData
            screen: modelData
        }
    }
    Variants {
        id: pills
        model: Quickshell.screens
        PillOverlay {
            required property ShellScreen modelData
            screen: modelData
            accent: shellRoot.accentFor(modelData.name)
            screenTimeTracker: stTracker
            onPowerRequested: shellRoot.sessionOpen = !shellRoot.sessionOpen
            onShellAction: id => shellRoot.runShellAction(id)
        }
    }

    // Caffeine. An idle inhibitor needs a mapped surface; the frame and pill
    // unmap on fullscreen, so it gets its own invisible 1x1 window on the Background layer
    // (below everything, never in the way of direct scanout).
    PanelWindow {
        id: inhibitorWindow
        anchors { top: true; left: true }
        implicitWidth: 1
        implicitHeight: 1
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell-inhibitor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        IdleInhibitor {
            window: inhibitorWindow
            enabled: Desktop.caffeine
        }
    }

    // IPC target `pill` (SPEC 4.2); acts on the focused monitor's pill. Double-tap Super
    // is counted in binds.lua and calls peek().
    function focusedPill() {
        var name = Hypr.focusedMonitor ? Hypr.focusedMonitor.name : ""
        return pills.instances.find(function(p) { return p.monitorName === name }) || null
    }
    IpcHandler {
        target: "pill"
        function peek(): void { var p = shellRoot.focusedPill(); if (p) p.toggle() }
        // name: sound / notifs / system opens that surface; anything else ("", "bar") the
        // bar row. The dashboard surface arrives in 4.4.
        function open(name: string): void {
            var p = shellRoot.focusedPill(); if (!p) return
            if (p.surfaces.indexOf(name) >= 0) p.openSurface(name, false); else p.open()
        }
        function close(): void { var p = shellRoot.focusedPill(); if (p) p.close() }
        function toggle(name: string): void {
            var p = shellRoot.focusedPill(); if (!p) return
            if (p.surfaces.indexOf(name) >= 0) p.openSurface(name, true); else p.toggle()
        }
        function status(): string {
            return JSON.stringify(pills.instances.map(function(p) {
                return { monitor: p.monitorName, state: p.pillState, surface: p.surface,
                         pinned: p.pinned, fullscreen: p.fullscreen }
            }))
        }
    }

    // ── Launcher IPC: the pill's launcher / clipboard surface on the focused monitor ──
    IpcHandler {
        target: "launcher"
        function toggle() { var p = shellRoot.focusedPill(); if (p) p.openSurface("launcher", true) }
        function clipboard(): void { var p = shellRoot.focusedPill(); if (p) p.openSurface("clipboard", true) }
    }

    // ── Wallpaper picker overlay (focused monitor only) ──────────────────────
    property var wallpickerScreen: null

    IpcHandler {
        id: wallpickerIpc
        target: "wallpicker"
        function toggle() {
            if (!shellRoot.wallpickerOpen) {
                shellRoot.wallpickerScreen = Hypr.focusedMonitor != null
                    ? Hypr.focusedMonitor.name : null
            }
            shellRoot.wallpickerOpen = !shellRoot.wallpickerOpen
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: shellRoot.wallpickerOpen
                     && shellRoot.wallpickerScreen != null
                     && modelData.name === shellRoot.wallpickerScreen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-wallpicker"

            WallpaperPicker {
                anchors.fill: parent
                barAccent: shellRoot.accentFor(shellRoot.wallpickerScreen || "")
                pickerVisible: shellRoot.wallpickerOpen
                onCloseRequested: shellRoot.wallpickerOpen = false
            }
        }
    }

    // ── Screenshot overlay (focused monitor only) ────────────────────────────
    IpcHandler {
        id: screenshotIpc
        target: "screenshot"
        function area() {
            shellRoot.screenshotScreen = Hypr.focusedMonitor != null
                ? Hypr.focusedMonitor.name : null
            shellRoot.screenshotMode = "area"
        }
        function screen() {
            shellRoot.screenshotScreen = Hypr.focusedMonitor != null
                ? Hypr.focusedMonitor.name : null
            shellRoot.screenshotMode = "screen"
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: shellRoot.screenshotMode !== ""
                     && shellRoot.screenshotScreen != null
                     && modelData.name === shellRoot.screenshotScreen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-screenshot"

            ScreenshotOverlay {
                anchors.fill: parent
                barAccent: shellRoot.accentFor(shellRoot.screenshotScreen || "")
                mode: shellRoot.screenshotMode
                screenName: modelData.name
                onCloseRequested: shellRoot.screenshotMode = ""
            }
        }
    }

    // ── Workspace overview overlay (focused monitor only) ──────────────
    IpcHandler {
        id: overviewIpc
        target: "overview"
        function toggle() {
            if (!shellRoot.overviewOpen) {
                shellRoot.overviewScreen = Hypr.focusedMonitor != null
                    ? Hypr.focusedMonitor.name : null
            }
            shellRoot.overviewOpen = !shellRoot.overviewOpen
        }
        function close() {
            shellRoot.overviewOpen = false
        }
        function open() {
            shellRoot.overviewScreen = Hypr.focusedMonitor != null
                ? Hypr.focusedMonitor.name : null
            shellRoot.overviewOpen = true
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overviewPanel
            required property ShellScreen modelData
            screen: modelData
            visible: shellRoot.overviewOpen
                     && shellRoot.overviewScreen != null
                     && modelData.name === shellRoot.overviewScreen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-overview"

            implicitWidth:  screen.width
            implicitHeight: screen.height

            Component {
                id: overviewComp
                Overview {
                    anchors.fill: parent
                    barAccent: shellRoot.accentFor(shellRoot.overviewScreen || "")
                    screenName: overviewPanel.modelData.name
                    onCloseRequested: shellRoot.overviewOpen = false
                }
            }

            Loader {
                anchors.fill: parent
                active: shellRoot.overviewOpen
                        && overviewPanel.modelData.name === shellRoot.overviewScreen
                sourceComponent: overviewComp
            }
        }
    }

    // ── Per-screen session overlay ──────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: sessionOpen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-session"

            Rectangle {
                id: backdrop
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.65)
                opacity: sessionOpen ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                focus: sessionOpen
                Keys.onEscapePressed: sessionOpen = false

                MouseArea { anchors.fill: parent; onClicked: sessionOpen = false }

                Rectangle {
                    anchors.centerIn: parent
                    width: 662; height: 210
                    radius: 20
                    color: Theme.popupBg
                    border.color: Theme.border; border.width: 1
                    scale: sessionOpen ? 1.0 : 0.88
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                    MouseArea { anchors.fill: parent }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 20

                        Text {
                            text: "Session"
                            color: Theme.text; font.pixelSize: Theme.fontXl
                            font.bold: true; font.family: Theme.fontFamily
                            Layout.alignment: Qt.AlignHCenter
                        }

                        RowLayout {
                            spacing: 12; Layout.alignment: Qt.AlignHCenter

                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h1.containsMouse ? Qt.rgba(0,1,0.92,0.15) : Theme.surface
                                border.color: h1.containsMouse ? Qt.rgba(0,1,0.92,0.4) : Theme.borderMuted; border.width: 1
                                scale: h1.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Desktop.lock(); sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf023"; color: h1.containsMouse ? Theme.accent : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Lock"; color: h1.containsMouse ? Theme.accent : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h2.containsMouse ? Qt.rgba(1,0.62,0.27,0.15) : Theme.surface
                                border.color: h2.containsMouse ? Qt.rgba(1,0.62,0.27,0.4) : Theme.borderMuted; border.width: 1
                                scale: h2.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Hypr.dispatch("hl.dsp.exit()"); sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf2f5"; color: h2.containsMouse ? Theme.warning : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Logout"; color: h2.containsMouse ? Theme.warning : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h3.containsMouse ? Qt.rgba(0.78,0.47,0.87,0.15) : Theme.surface
                                border.color: h3.containsMouse ? Qt.rgba(0.78,0.47,0.87,0.4) : Theme.borderMuted; border.width: 1
                                scale: h3.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h3; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pSuspend.running = true; sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf186"; color: h3.containsMouse ? Theme.purple : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Suspend"; color: h3.containsMouse ? Theme.purple : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h4.containsMouse ? Qt.rgba(0.04,0.86,0.62,0.15) : Theme.surface
                                border.color: h4.containsMouse ? Qt.rgba(0.04,0.86,0.62,0.4) : Theme.borderMuted; border.width: 1
                                scale: h4.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h4; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pReboot.running = true; sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf021"; color: h4.containsMouse ? Theme.media : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Reboot"; color: h4.containsMouse ? Theme.media : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h6.containsMouse ? Qt.rgba(0.22,1,0.08,0.12) : Theme.surface
                                border.color: h6.containsMouse ? Qt.rgba(0.22,1,0.08,0.35) : Theme.borderMuted; border.width: 1
                                scale: h6.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h6; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Desktop.enterGamingMode(); sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf11b"; color: h6.containsMouse ? Theme.success : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Gaming"; color: h6.containsMouse ? Theme.success : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                            Rectangle {
                                width: 90; height: 90; radius: 14
                                color: h5.containsMouse ? Qt.rgba(0.95,0.55,0.66,0.15) : Theme.surface
                                border.color: h5.containsMouse ? Qt.rgba(0.95,0.55,0.66,0.4) : Theme.borderMuted; border.width: 1
                                scale: h5.containsMouse ? 1.07 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: h5; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pOff.running = true; sessionOpen = false } }
                                ColumnLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "\uf011"; color: h5.containsMouse ? Theme.error : Theme.textDimmer; font.pixelSize: 26; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                    Text { text: "Shutdown"; color: h5.containsMouse ? Theme.error : Theme.textDim; font.pixelSize: Theme.fontSm; font.bold: true; font.family: Theme.fontFamily; Layout.alignment: Qt.AlignHCenter; Behavior on color { ColorAnimation { duration: 150 } } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
