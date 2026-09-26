//@ pragma Env QT_IMAGEIO_MAXALLOC=512
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

    // ── App launcher state ──────────────────────────────────────────────────
    property bool launcherOpen: false

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

    // ── Screen time tracking (runs continuously) ──────────────────────────
    ScreenTimeTracker { id: stTracker }

    // ── Desktop services: idle, caffeine, night light, desktop game mode ──
    Binding { target: Desktop; property: "dndEnabled"; value: Notifs.dndEnabled }
    Connections {
        target: Desktop
        function onDndRequested(enabled) { Notifs.dndEnabled = enabled }
    }


    Process { id: pLock;    command: ["hyprlock"]                            }
    Process { id: pSuspend; command: ["systemctl", "suspend"]               }
    Process { id: pReboot;  command: ["systemctl", "reboot"]                }
    Process { id: pOff;     command: ["systemctl", "poweroff"]              }

    // Phase 4 preview: no extra windows in classic mode. The classic bar below stays
    // until 4.3 moves its popups (and the Caffeine inhibitor) into the pill.
    // A bool only changes on a real switch; Config rebuilds its objects on every edit.
    readonly property bool frameLayout: Config.appearance.layout === "frame"
    Variants {
        model: shellRoot.frameLayout ? Quickshell.screens : []
        Frame {
            required property ShellScreen modelData
            screen: modelData
            reserveTop: false   // the classic bar below already reserves the top edge
        }
    }
    Variants {
        id: pills
        model: shellRoot.frameLayout ? Quickshell.screens : []
        PillOverlay {
            required property ShellScreen modelData
            screen: modelData
            accent: shellRoot.accentFor(modelData.name)
            // ponytail: until 4.3 re-hosts these views in the pill, open the classic panel
            // on the same screen; remove with the classic bar in frame mode.
            onSurfaceRequested: name => {
                var bar = bars.instances.find(function(b) { return b.modelData === modelData })
                if (bar) bar.panel.open(name)
            }
            onPowerRequested: shellRoot.sessionOpen = !shellRoot.sessionOpen
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
        // Surfaces (dashboard, sound, ...) arrive in 4.3/4.4; for now every name opens the bar row.
        function open(name: string): void { var p = shellRoot.focusedPill(); if (p) p.open() }
        function close(): void { var p = shellRoot.focusedPill(); if (p) p.close() }
        function toggle(name: string): void { var p = shellRoot.focusedPill(); if (p) p.toggle() }
        function status(): string {
            return JSON.stringify(pills.instances.map(function(p) {
                return { monitor: p.monitorName, state: p.pillState, pinned: p.pinned,
                         fullscreen: p.fullscreen }
            }))
        }
    }

    // ── Per-screen bar ──────────────────────────────────────────────────────
    Variants {
        id: bars
        model: Quickshell.screens

        PanelWindow {
            id: barPanel
            required property ShellScreen modelData
            screen: modelData

            property color screenAccent: shellRoot.accentFor(modelData.name)
            Behavior on screenAccent { ColorAnimation { duration: 500 } }
            readonly property var panel: unifiedPanel   // opened by the pill's chips (4.2 bridge)

            anchors { top: true; left: true; right: true }
            // In frame mode the bar floats inside the frame with its usual gap. The side
            // reserves already push it in; only the top (no reserve beside the bar) needs this.
            margins {
                top:   Theme.barMarginTop + (shellRoot.frameLayout ? Theme.frameThickness : 0)
                left:  Theme.barMarginSide
                right: Theme.barMarginSide
            }

            implicitHeight: Theme.barHeight
            color: "transparent"

            // Caffeine: inhibit idle while enabled (needs a surface — the bar).
            IdleInhibitor {
                window: barPanel
                enabled: Desktop.caffeine
            }

            Rectangle {
                id: barRect
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: Theme.barHeight
                radius: 10
                color: Theme.barBg
                border.color: Qt.rgba(barPanel.screenAccent.r, barPanel.screenAccent.g, barPanel.screenAccent.b, 0.25)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 500 } }

                // Bar startup fade-in (opacity only — anchors.fill controls position)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }

            Item {
                id: barContent
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.barPadding }
                implicitHeight: Theme.barHeight - Theme.barPadding * 2

                // ── LEFT ───────────────────────────────────────────────────
                Row {
                    id: leftRow
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    spacing: Theme.barSpacing
                    Workspaces {
                        id: wsChip
                        screenName: barPanel.modelData.name
                        barAccent: barPanel.screenAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    SysInfo { anchors.verticalCenter: parent.verticalCenter }
                }

                // ── CENTER ─────────────────────────────────────────────────
                BarClock {
                    id: barClock
                    anchors.centerIn: parent
                    barAccent: barPanel.screenAccent
                    parentWindow: barPanel
                    onPopupOpenChanged: if (popupOpen) unifiedPanel.close()
                }

                // ── RIGHT ──────────────────────────────────────────────────
                Row {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    spacing: Theme.barSpacing
                    TrayArea    { anchors.verticalCenter: parent.verticalCenter }
                    Volume {
                        id: volChip
                        anchors.verticalCenter: parent.verticalCenter
                        barAccent: barPanel.screenAccent
                        onChipClicked: { barClock.popupOpen = false; unifiedPanel.open("sound") }
                    }
                    Microphone  { anchors.verticalCenter: parent.verticalCenter; barAccent: barPanel.screenAccent }
                    Caffeine    { anchors.verticalCenter: parent.verticalCenter; barAccent: barPanel.screenAccent; active: Desktop.caffeine; onClicked: Desktop.toggleCaffeine() }
                    GameMode    { anchors.verticalCenter: parent.verticalCenter; barAccent: barPanel.screenAccent; active: Desktop.gameMode; onClicked: Desktop.toggleGameMode() }

                    NotificationCenter {
                        id: notifChip
                        anchors.verticalCenter: parent.verticalCenter
                        barAccent: barPanel.screenAccent
                        externalUnreadCount: Notifs.unreadCount
                        dndEnabled:          Notifs.dndEnabled
                        onChipClicked: { barClock.popupOpen = false; unifiedPanel.open("notifs") }
                        onPanelOpened: Notifs.unreadCount = 0
                    }
                    ControlCenter {
                        id: ccChip
                        anchors.verticalCenter: parent.verticalCenter
                        barAccent: barPanel.screenAccent
                        onChipClicked: { barClock.popupOpen = false; unifiedPanel.open("system") }
                    }
                    PowerMenu {
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: sessionOpen = !sessionOpen
                    }
                }

                // Unified panel — anchored to bottom-right, outside the Row
                UnifiedPanel {
                    id: unifiedPanel
                    anchors { right: parent.right; bottom: parent.bottom; bottomMargin: -8 }
                    parentWindow: barPanel
                    barAccent: barPanel.screenAccent
                    screenTimeTracker: stTracker
                    desktop: Desktop
                    notifModel:  Notifs.historyModel
                    dndEnabled:  Notifs.dndEnabled
                    onDismissRequested:  function(id) { Notifs.dismiss(id) }
                    onClearAllRequested: Notifs.clearAll()
                    onDndToggled:        Notifs.dndEnabled = !Notifs.dndEnabled
                    onPanelOpened:       Notifs.unreadCount = 0
                    onPanelOpenChanged:  if (panelOpen) barClock.popupOpen = false
                }
            }

        }
    }

    // ── App launcher overlay (focused monitor only) ─────────────────────────
    // Capture which screen was focused when launcher opens
    property var launcherScreen: null

    IpcHandler {
        target: "launcher"
        function toggle() {
            if (!shellRoot.launcherOpen) {
                // Capture focused monitor before opening
                shellRoot.launcherScreen = Hypr.focusedMonitor != null
                    ? Hypr.focusedMonitor.name : null
            }
            shellRoot.launcherOpen = !shellRoot.launcherOpen
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            visible: shellRoot.launcherOpen
                     && shellRoot.launcherScreen != null
                     && modelData.name === shellRoot.launcherScreen

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-launcher"

            AppLauncher {
                anchors.fill: parent
                barAccent: shellRoot.accentFor(shellRoot.launcherScreen || "")
                launcherVisible: shellRoot.launcherOpen
                onCloseRequested: shellRoot.launcherOpen = false
            }
        }
    }

    // ── Wallpaper picker overlay (focused monitor only) ──────────────────────
    property var wallpickerScreen: null

    IpcHandler {
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
                                MouseArea { id: h1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { pLock.running = true; sessionOpen = false } }
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

    // ── Per-screen OSD overlay ─────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData

            anchors { bottom: true; left: true; right: true }
            implicitHeight: 160
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay

            visible: osdItem.osdVisible
                     && Hypr.focusedMonitor !== null
                     && Hypr.focusedMonitor.name === modelData.name

            OSD {
                id: osdItem
                barAccent: shellRoot.accentFor(modelData.name)
            }
        }
    }

    // ── Per-screen notification toasts ─────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData

            anchors { top: true; right: true }
            implicitHeight: Theme.barHeight + Theme.barMarginTop + 4 * 90
            implicitWidth:  360 + 32

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay

            // Shown only while a toast is up (Notifs.hasToasts)
            visible: Notifs.hasToasts

            NotificationToasts {
                id: toastsItem
                anchors {
                    top:      parent.top
                    right:    parent.right
                    topMargin: Theme.barHeight + Theme.barMarginTop + 8
                }
                width:  parent.width
                height: parent.height - (Theme.barHeight + Theme.barMarginTop + 8)
                toastModel:  Notifs.toastModel
                dismissFunc: function(id) { Notifs.dismiss(id) }
            }
        }
    }
}
