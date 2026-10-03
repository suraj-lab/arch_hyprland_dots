import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

// One visual frame and four fixed reserves per monitor. No input or keyboard grab.
PanelWindow {
    id: root
    property string monitorName: screen ? screen.name : ""
    property bool fullscreen: Hypr.isFullscreen(monitorName)
    readonly property int bottomReserve: Theme.frameThickness
        + (Config.pillFor(monitorName).restStyle === "handle" ? Theme.pillRestHandleHeight : Theme.pillRestTabHeight)

    property alias outline: outline
    visible: !fullscreen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore // draw at physical screen edges, outside all reserves
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-frame"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Reserve { screen: root.screen; edge: "top"; visible: root.visible }
    Reserve { screen: root.screen; edge: "left"; visible: root.visible }
    Reserve { screen: root.screen; edge: "right"; visible: root.visible }
    Reserve { screen: root.screen; edge: "bottom"; thickness: root.bottomReserve; visible: root.visible }

    Shape {
        id: outline
        anchors.fill: parent
        readonly property real inset: Math.min(Theme.frameThickness, width / 2, height / 2)
        readonly property real radius: Math.max(0, Math.min(Theme.frameRadius,
            (width - 2 * inset) / 2, (height - 2 * inset) / 2))

        // Odd-even fill cuts the rounded inner rectangle out of the screen rectangle.
        ShapePath {
            strokeWidth: -1
            fillColor: Theme.frameBg
            fillRule: ShapePath.OddEvenFill
            startX: 0; startY: 0
            PathLine { x: outline.width; y: 0 }
            PathLine { x: outline.width; y: outline.height }
            PathLine { x: 0; y: outline.height }
            PathLine { x: 0; y: 0 }
            PathMove { x: outline.inset + outline.radius; y: outline.inset }
            PathLine { x: outline.width - outline.inset - outline.radius; y: outline.inset }
            PathArc { x: outline.width - outline.inset; y: outline.inset + outline.radius; radiusX: outline.radius; radiusY: outline.radius }
            PathLine { x: outline.width - outline.inset; y: outline.height - outline.inset - outline.radius }
            PathArc { x: outline.width - outline.inset - outline.radius; y: outline.height - outline.inset; radiusX: outline.radius; radiusY: outline.radius }
            PathLine { x: outline.inset + outline.radius; y: outline.height - outline.inset }
            PathArc { x: outline.inset; y: outline.height - outline.inset - outline.radius; radiusX: outline.radius; radiusY: outline.radius }
            PathLine { x: outline.inset; y: outline.inset + outline.radius }
            PathArc { x: outline.inset + outline.radius; y: outline.inset; radiusX: outline.radius; radiusY: outline.radius }
        }
    }
}
