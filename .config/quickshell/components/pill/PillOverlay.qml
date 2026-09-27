import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "../views"
import "surfaces"

// One pill per screen on the Overlay layer (SPEC 3.1-3.3). States: rest, hover, surface,
// hidden. The full-height window never resizes and reserves nothing, so windows never move
// when it expands; only its input mask (pill, surface, bottom 4 px hot strip) follows the
// animated shape.
PanelWindow {
    id: root
    property string monitorName: screen ? screen.name : ""
    property bool fullscreen: Hypr.isFullscreen(monitorName)
    property color accent: Theme.accent
    property var screenTimeTracker: null
    readonly property var prefs: Config.pillFor(monitorName)
    readonly property bool animate: Config.appearance.animations && !Desktop.gameMode
    signal powerRequested()
    signal shellAction(string id)   // launcher ">" actions, run by the shell (runShellAction)

    // pinned: double-tap Super, a click on the rest tab, or IPC. On a fullscreen monitor a
    // pin is the peek. hoverOpen: the bottom-edge dwell. visited: the pointer has been on
    // the pill since it opened, so leaving it may collapse it. A peek does not wait for a
    // visit: over a game the pointer rarely goes there, so it hides 800 ms after it's away.
    // surface: "" or the open view (sound / notifs / system / dashboard); it holds the
    // pill open. "media" opens the dashboard on its Media tab (IPC); "clipboard" the
    // launcher in clipboard mode (Super+V).
    property bool pinned: false
    property bool hoverOpen: false
    property bool visited: false
    property string surface: ""
    readonly property var surfaces: ["sound", "notifs", "system", "dashboard", "media", "launcher", "clipboard", "cheatsheet", "updates", "network", "bluetooth", "devices", "settings"]
    readonly property bool edgeHovered: hotZone.containsMouse
    readonly property bool pillHovered: pillHover.hovered || baseHover.hovered || tierHover.hovered
    readonly property bool peeking: fullscreen && pinned
    readonly property int collapseDelay: fullscreen ? Theme.peekLeaveDelay
        : prefs.collapseDelayMs >= 0 ? prefs.collapseDelayMs : Theme.collapseDelay
    readonly property string pillState: fullscreen && !pinned && surface === "" ? "hidden"
        : surface !== "" ? "surface"
        : pinned || hoverOpen ? "hover" : "rest"
    // The bar stays wide until a closing surface has fully shrunk, so the surface never
    // slides with a narrowing bar; then the bar collapses on its own.
    readonly property bool expanded: pillState === "hover" || pillState === "surface" || tier.height > 0

    function open() { pinned = true; visited = pillHovered }
    function close() { surface = ""; pinned = false; hoverOpen = false; visited = false }
    function toggle() { if (expanded) close(); else open() }
    // Opening a second surface switches directly; the same one again closes it (as the
    // classic panel's chips did). Closing a surface leaves the bar row, which then
    // collapses as usual once the pointer is away.
    function openSurface(name, allowToggle) {
        if (surfaces.indexOf(name) < 0) return
        var target = name === "media" ? "dashboard" : name === "clipboard" ? "launcher" : name
        if (allowToggle && surface === target && anchorKey === name) { closeSurface(); return }
        if (target === "dashboard" && (name === "media" || surface !== "dashboard"))
            dashView.tab = name === "media" ? "media" : "dashboard"
        if (target === "launcher") launcherView.clipboard = name === "clipboard"
        anchorKey = name
        surface = target
        visited = true
        if (name === "notifs") Notifs.unreadCount = 0
    }
    function closeSurface() { surface = "" }
    // A launcher action runs once the tier has closed (a screenshot must not catch it).
    property string pendingAction: ""
    function runAction(id) { pendingAction = id; closeSurface(); actionDelay.restart() }
    Timer {
        id: actionDelay
        interval: root.animate ? Theme.morphDuration + 50 : 0
        onTriggered: root.shellAction(root.pendingAction)
    }

    onPillHoveredChanged: if (pillHovered && expanded) visited = true
    onFullscreenChanged: close()   // entering or leaving fullscreen ends a peek (SPEC 3.3)

    Timer {
        id: dwell
        interval: Theme.hoverDwell
        running: root.edgeHovered && root.prefs.hoverExpand && root.pillState === "rest"
        onTriggered: { root.hoverOpen = true; root.visited = true }
    }
    Timer {
        id: collapse
        interval: root.collapseDelay
        running: root.pillState === "hover" && (root.visited || root.peeking)
            && !root.edgeHovered && !root.pillHovered
        onTriggered: root.close()
    }

    // A click anywhere else closes the surface, as the classic panel's grab did. The short
    // delay keeps the click that opened it from clearing the grab at once.
    property bool grabReady: false
    onSurfaceChanged: {
        grabReady = false
        if (surface !== "") { lastSurface = surface; grabDelay.restart() }
    }
    Timer { id: grabDelay; interval: 50; onTriggered: root.grabReady = true }
    HyprlandFocusGrab {
        windows: [root]
        active: root.surface !== "" && root.grabReady
        onCleared: root.closeSurface()
    }

    // Geometry (SPEC 3.2). Widths clamp to the screen; heights are fixed tokens.
    readonly property bool handle: prefs.restStyle === "handle"
    readonly property int restWidth: handle ? Theme.pillRestHandleWidth : Theme.pillRestTabWidth
    readonly property int restHeight: handle ? Theme.pillRestHandleHeight : Theme.pillRestTabHeight
    readonly property int hoverWidth: Math.max(restWidth, Math.min(Theme.pillHoverMaxWidth,
        width - 2 * Theme.frameThickness - 2 * Theme.shoulderRadius - 40))
    readonly property var activeView: surface === "sound" ? soundView
        : surface === "notifs" ? notifsView : surface === "system" ? systemView
        : surface === "dashboard" ? dashView : surface === "launcher" ? launcherView
        : surface === "cheatsheet" ? cheatsheetView : surface === "updates" ? updatesView
        : surface === "network" ? networkView : surface === "bluetooth" ? bluetoothView
        : surface === "devices" ? devicesView
        : surface === "settings" ? settingsView : null
    // The tier rises only once the bar is fully wide (opening from the rest tab), so it
    // never slides with a growing bar; closing mirrors this (see `expanded`).
    readonly property int tierTarget: activeView && pill.width >= hoverWidth
        ? Math.min(activeView.implicitHeight + Theme.surfacePadding,
                   height - Theme.frameThickness - Theme.pillHoverHeight - 60) : 0

    visible: pillState !== "hidden"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-pill"
    // The launcher and cheatsheet are typed into straight away; the others only need Escape
    // (the network surface's password field takes focus on click).
    WlrLayershell.keyboardFocus: surface === "launcher" || surface === "cheatsheet" ? WlrKeyboardFocus.Exclusive : surface !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: pill
        Region { item: base }
        Region { item: tier }
        Region { item: hotZone }
        Region { item: restHit }
        Region { item: drawers.toastArea }   // toasts take clicks; the OSD stays click-through
    }

    property alias pillItem: pill
    property alias dashboard: dashView
    property alias launcher: launcherView
    property alias cheatsheet: cheatsheetView
    property alias updates: updatesView
    property alias network: networkView
    property alias bluetooth: bluetoothView
    property alias devices: devicesView
    property alias settings: settingsView
    property alias tierItem: tier
    property alias shape: shape
    PillShape {
        id: shape
        anchors.fill: parent
        pillX: pill.x; pillWidth: pill.width; pillHeight: pill.height
        tierWidth: tier.width; tierHeight: tier.height; tierX: tier.x
    }

    // The shoulders and the frame band under the pill are part of it: moving from the
    // bottom edge up to the bar must not count as leaving.
    Item {
        id: base
        x: pill.x - Theme.shoulderRadius
        width: pill.width + 2 * Theme.shoulderRadius
        y: root.height - Theme.frameThickness - Math.min(Theme.shoulderRadius, pill.height)
        height: root.height - y
        HoverHandler { id: baseHover }
    }

    Item {
        id: pill
        objectName: "pill"
        width: root.expanded ? root.hoverWidth : root.restWidth
        height: root.expanded ? Theme.pillHoverHeight : root.restHeight
        x: Math.round((root.width - width) / 2)
        y: root.height - Theme.frameThickness - height
        Behavior on width { NumberAnimation { duration: root.animate ? Theme.glideDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }
        Behavior on height { NumberAnimation { duration: root.animate ? Theme.glideDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }

        HoverHandler { id: pillHover }

        PillBar {
            id: bar
            anchors.fill: parent
            screenName: root.monitorName
            accent: root.accent
            showRest: !root.handle
            progress: Math.max(0, Math.min(1,
                (pill.height - root.restHeight) / (Theme.pillHoverHeight - root.restHeight)))
            onSurfaceRequested: name => root.openSurface(name, true)
            onPowerRequested: root.powerRequested()
        }
    }

    // Surface tier: rises from the bar row above the chip that opened it (volume, bell,
    // gear), kept clear of the bar's rounded ends so the concave joins fit. The views keep
    // their classic content and width. All three stay loaded (as in the classic panel) so
    // switching is a morph, not a reload.
    // The last opened surface and the element that opened it, kept while the tier shrinks
    // so it closes where it opened.
    property string lastSurface: "sound"
    property string anchorKey: "sound"
    readonly property real tierAnchor: bar.chipCenters[anchorKey]
    readonly property real tierInset: Theme.pillRadiusSmall + Theme.shoulderRadius
    FocusScope {
        id: tier
        objectName: "tier"
        width: Math.min(root.lastSurface === "dashboard" || root.lastSurface === "cheatsheet"
                        || root.lastSurface === "settings" ? Theme.dashboardWidth
                        : root.lastSurface === "launcher" ? Theme.launcherSurfaceWidth : Theme.surfaceWidth,
                        root.hoverWidth - 2 * root.tierInset)
        height: root.tierTarget
        x: Math.round(pill.x + Math.max(root.tierInset,
            Math.min(root.tierAnchor - width / 2, pill.width - root.tierInset - width)))
        y: pill.y - height
        clip: true
        focus: root.surface !== ""
        Keys.onEscapePressed: root.closeSurface()
        Behavior on height { NumberAnimation { duration: root.animate ? Theme.morphDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }
        HoverHandler { id: tierHover }

        // Content fades in over the last 40% of the morph (SPEC 5.3).
        Item {
            id: views
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: Theme.surfacePadding; rightMargin: Theme.surfacePadding
                      topMargin: Theme.surfacePadding }
            height: root.activeView ? root.activeView.implicitHeight : 0
            opacity: root.tierTarget > 0 ? Math.max(0, Math.min(1, (tier.height / root.tierTarget - 0.6) / 0.4)) : 0

            SoundView {
                id: soundView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                barAccent: root.accent
                viewActive: root.surface === "sound"
                visible: root.surface === "sound"
            }
            NotifsView {
                id: notifsView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                barAccent: root.accent
                notifModel: Notifs.historyModel
                dndEnabled: Notifs.dndEnabled
                visible: root.surface === "notifs"
                onDismissRequested: id => Notifs.dismiss(id)
                onClearAllRequested: Notifs.clearAll()
                onDndToggled: Notifs.dndEnabled = !Notifs.dndEnabled
            }
            Dashboard {
                id: dashView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "dashboard"
                visible: root.surface === "dashboard"
            }
            Launcher {
                id: launcherView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "launcher"
                visible: root.surface === "launcher"
                onCloseRequested: root.closeSurface()
                onActionRequested: id => root.runAction(id)
            }
            Cheatsheet {
                id: cheatsheetView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "cheatsheet"
                visible: root.surface === "cheatsheet"
                onCloseRequested: root.closeSurface()
            }
            UpdatesPanel {
                id: updatesView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                visible: root.surface === "updates"
                onCloseRequested: root.closeSurface()
            }
            NetworkPanel {
                id: networkView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "network"
                visible: root.surface === "network"
                onCloseRequested: root.closeSurface()
            }
            BluetoothPanel {
                id: bluetoothView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                active: root.surface === "bluetooth"
                visible: root.surface === "bluetooth"
                onCloseRequested: root.closeSurface()
            }
            DevicesPanel {
                id: devicesView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "devices"
                visible: root.surface === "devices"
                onCloseRequested: root.closeSurface()
            }
            SettingsPanel {
                id: settingsView
                anchors { left: parent.left; right: parent.right; top: parent.top }
                accent: root.accent
                active: root.surface === "settings"
                visible: root.surface === "settings"
                onCloseRequested: root.closeSurface()
                onActionRequested: id => root.runAction(id)
                onSurfaceRequested: name => root.openSurface(name, false)
            }
            SystemView {
                id: systemView
                surfaceLinks: true
                onSurfaceRequested: name => root.openSurface(name, false)
                anchors { left: parent.left; right: parent.right; top: parent.top }
                barAccent: root.accent
                viewActive: root.surface === "system"
                dndEnabled: Notifs.dndEnabled
                screenTimeTracker: root.screenTimeTracker
                desktop: Desktop
                visible: root.surface === "system"
                onDndToggled: Notifs.dndEnabled = !Notifs.dndEnabled
                onCloseRequested: root.closeSurface()
            }
        }
    }

    // Toast drawer (top-right corner) and OSD (right edge), SPEC 3.5.
    property alias drawers: drawers
    Drawers {
        id: drawers
        anchors.fill: parent
        accent: root.accent
        animate: root.animate
        // No Hyprland (tests): show everywhere.
        osdHere: !Hypr.focusedMonitor || Hypr.focusedMonitor.name === root.monitorName
    }

    // Click the rest shape to expand (the only way on rest-only monitors, besides Super).
    // The target is the shape plus a margin, down to the screen edge: the 6 px handle alone
    // (floating above the frame band) was nearly impossible to hit. Zero-sized otherwise.
    Item {
        id: restHit
        objectName: "restHit"
        readonly property bool on: root.pillState === "rest"
        x: pill.x - 24
        y: pill.y - 10
        width: on ? pill.width + 48 : 0
        height: on ? root.height - y : 0
        // A click here is a visit: leaving collapses it again, as after clicking the tab itself.
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.open(); root.visited = true } }
    }

    // Bottom-edge hot strip: hover only, never eats clicks.
    MouseArea {
        id: hotZone
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
