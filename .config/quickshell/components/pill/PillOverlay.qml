import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

// One pill per screen on the Overlay layer (SPEC 3.1-3.3). States: rest, hover, hidden.
// The window never resizes and reserves nothing, so windows never move when it expands;
// only its input mask (pill + bottom 4 px hot strip) follows the animated pill.
PanelWindow {
    id: root
    property string monitorName: screen ? screen.name : ""
    property bool fullscreen: Hypr.isFullscreen(monitorName)
    property color accent: Theme.accent
    readonly property var prefs: Config.pillFor(monitorName)
    readonly property bool animate: Config.appearance.animations && !Desktop.gameMode
    signal surfaceRequested(string name)
    signal powerRequested()

    // pinned: double-tap Super, a click on the rest tab, or IPC. On a fullscreen monitor a
    // pin is the peek. hoverOpen: the bottom-edge dwell. visited: the pointer has been on
    // the pill since it opened, so leaving it may collapse it. A peek does not wait for a
    // visit: over a game the pointer rarely goes there, so it hides 800 ms after it's away.
    property bool pinned: false
    property bool hoverOpen: false
    property bool visited: false
    readonly property bool edgeHovered: hotZone.containsMouse
    readonly property bool pillHovered: pillHover.hovered || baseHover.hovered
    readonly property bool peeking: fullscreen && pinned
    readonly property int collapseDelay: fullscreen ? Theme.peekLeaveDelay
        : prefs.collapseDelayMs >= 0 ? prefs.collapseDelayMs : Theme.collapseDelay
    readonly property string pillState: fullscreen && !pinned ? "hidden"
        : pinned || hoverOpen ? "hover" : "rest"

    function open() { pinned = true; visited = pillHovered }
    function close() { pinned = false; hoverOpen = false; visited = false }
    function toggle() { if (pillState === "hover") close(); else open() }

    onPillHoveredChanged: if (pillHovered && pillState === "hover") visited = true
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

    // Geometry (SPEC 3.2). Widths clamp to the screen; heights are fixed tokens.
    readonly property bool handle: prefs.restStyle === "handle"
    readonly property int restWidth: handle ? Theme.pillRestHandleWidth : Theme.pillRestTabWidth
    readonly property int restHeight: handle ? Theme.pillRestHandleHeight : Theme.pillRestTabHeight
    readonly property int hoverWidth: Math.max(restWidth, Math.min(Theme.pillHoverMaxWidth,
        width - 2 * Theme.frameThickness - 2 * Theme.shoulderRadius - 40))

    visible: pillState !== "hidden"
    anchors { left: true; right: true; bottom: true }
    implicitHeight: Theme.frameThickness + Theme.pillHoverHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-pill"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        item: pill
        Region { item: base }
        Region { item: hotZone }
    }

    property alias pillItem: pill
    property alias shape: shape
    PillShape {
        id: shape
        anchors.fill: parent
        pillX: pill.x; pillWidth: pill.width; pillHeight: pill.height
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
        width: root.pillState === "hover" ? root.hoverWidth : root.restWidth
        height: root.pillState === "hover" ? Theme.pillHoverHeight : root.restHeight
        x: Math.round((root.width - width) / 2)
        y: root.height - Theme.frameThickness - height
        Behavior on width { NumberAnimation { duration: root.animate ? Theme.glideDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }
        Behavior on height { NumberAnimation { duration: root.animate ? Theme.glideDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }

        HoverHandler { id: pillHover }

        // Click the rest tab to expand (the only way on rest-only monitors, besides Super).
        MouseArea {
            anchors.fill: parent
            enabled: root.pillState === "rest"
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open()
        }

        PillBar {
            anchors.fill: parent
            screenName: root.monitorName
            accent: root.accent
            showRest: !root.handle
            progress: Math.max(0, Math.min(1,
                (pill.height - root.restHeight) / (Theme.pillHoverHeight - root.restHeight)))
            onSurfaceRequested: name => root.surfaceRequested(name)
            onPowerRequested: root.powerRequested()
        }
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
