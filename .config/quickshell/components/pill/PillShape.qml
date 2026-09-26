import QtQuick
import QtQuick.Shapes
import "../../theme"

// The pill and its two concave shoulders as one path (SPEC 5.3). The path runs down to
// the bottom of the parent, through the frame edge, in the frame's colour, so the pill
// joins the frame without a seam. Bind pillX/pillWidth/pillHeight to animated values.
Shape {
    id: root
    property real pillX: 0
    property real pillWidth: 0
    property real pillHeight: 0
    property real baseY: height - Theme.frameThickness   // the frame's inner edge
    property color fillColor: Theme.frameBg

    readonly property real r: Math.max(0, Math.min(Theme.pillRadiusSmall, pillWidth / 2, pillHeight / 2))
    // Shoulders shrink with a short pill so the straight side never goes negative.
    readonly property real s: Math.max(0, Math.min(Theme.shoulderRadius, pillHeight - r))
    readonly property real x0: pillX
    readonly property real x1: pillX + pillWidth
    readonly property real pillTop: baseY - pillHeight

    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillColor: root.fillColor
        startX: root.x0 - root.s; startY: root.height
        PathLine { x: root.x0 - root.s; y: root.baseY }
        PathArc {  // left shoulder, concave
            x: root.x0; y: root.baseY - root.s
            radiusX: root.s; radiusY: root.s; direction: PathArc.Counterclockwise
        }
        PathLine { x: root.x0; y: root.pillTop + root.r }
        PathArc { x: root.x0 + root.r; y: root.pillTop; radiusX: root.r; radiusY: root.r }
        PathLine { x: root.x1 - root.r; y: root.pillTop }
        PathArc { x: root.x1; y: root.pillTop + root.r; radiusX: root.r; radiusY: root.r }
        PathLine { x: root.x1; y: root.baseY - root.s }
        PathArc {  // right shoulder, concave
            x: root.x1 + root.s; y: root.baseY
            radiusX: root.s; radiusY: root.s; direction: PathArc.Counterclockwise
        }
        PathLine { x: root.x1 + root.s; y: root.height }
        PathLine { x: root.x0 - root.s; y: root.height }
    }
}
