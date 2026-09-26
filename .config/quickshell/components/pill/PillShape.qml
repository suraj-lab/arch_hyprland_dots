import QtQuick
import QtQuick.Shapes
import "../../theme"

// The pill, its two concave shoulders and an optional surface tier as one path (SPEC 5.3).
// The path runs down to the bottom of the parent, through the frame edge, in the frame's
// colour, so the pill joins the frame without a seam. The tier (a surface) rises from the
// bar top at tierX with concave joins; at tierHeight 0 it collapses to nothing.
Shape {
    id: root
    property real pillX: 0
    property real pillWidth: 0
    property real pillHeight: 0
    property real tierWidth: 0
    property real tierHeight: 0
    property real tierX: 0          // left edge, window coords; clamped inside the bar's corners
    property real baseY: height - Theme.frameThickness   // the frame's inner edge
    property color fillColor: Theme.frameBg

    readonly property real r: Math.max(0, Math.min(Theme.pillRadiusSmall, pillWidth / 2, pillHeight / 2))
    // Shoulders shrink with a short pill so the straight side never goes negative.
    readonly property real s: Math.max(0, Math.min(Theme.shoulderRadius, pillHeight - r))
    readonly property real x0: pillX
    readonly property real x1: pillX + pillWidth
    readonly property real pillTop: baseY - pillHeight

    // No tier: zero width, so no degenerate edge runs along the bar top. A tier never
    // overhangs the bar's rounded corners (e.g. while the bar is still growing).
    readonly property real tw: tierHeight > 0 ? Math.max(0, Math.min(tierWidth, pillWidth - 2 * r)) : 0
    readonly property real sx0: Math.max(x0 + r, Math.min(tierX, x1 - r - tw))
    readonly property real sx1: sx0 + tw
    readonly property real tierTop: pillTop - tierHeight
    readonly property real r2: Math.max(0, Math.min(Theme.pillRadiusSurface, tw / 2, tierHeight / 2))
    readonly property real s2: Math.max(0, Math.min(Theme.shoulderRadius, tierHeight - r2,
                                                    sx0 - x0 - r, x1 - r - sx1))

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
        PathLine { x: root.sx0 - root.s2; y: root.pillTop }
        PathArc {  // tier join, concave
            x: root.sx0; y: root.pillTop - root.s2
            radiusX: root.s2; radiusY: root.s2; direction: PathArc.Counterclockwise
        }
        PathLine { x: root.sx0; y: root.tierTop + root.r2 }
        PathArc { x: root.sx0 + root.r2; y: root.tierTop; radiusX: root.r2; radiusY: root.r2 }
        PathLine { x: root.sx1 - root.r2; y: root.tierTop }
        PathArc { x: root.sx1; y: root.tierTop + root.r2; radiusX: root.r2; radiusY: root.r2 }
        PathLine { x: root.sx1; y: root.pillTop - root.s2 }
        PathArc {  // tier join, concave
            x: root.sx1 + root.s2; y: root.pillTop
            radiusX: root.s2; radiusY: root.s2; direction: PathArc.Counterclockwise
        }
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
