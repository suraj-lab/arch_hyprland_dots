import QtQuick
import QtQuick.Shapes
import "../../theme"

// A drawer joined to the frame, drawn like the pill (SPEC 5.3): one path in the frame's
// colour, running into the frame edge, with concave shoulders where it meets it.
// corner: false - a tab out of the right edge (the OSD): tabWidth grows from the edge,
//         tabY is its top.
// corner: true  - a drawer in the top-right corner (toasts): tabHeight grows downward,
//         shoulders join both the top and the right edge.
// Parent-filling; nothing is drawn while the tab is closed.
Shape {
    id: root
    property bool corner: false
    property real tabWidth: 0
    property real tabHeight: 0
    property real tabY: 0
    property real radius: corner ? Theme.pillRadiusSurface : Theme.pillRadiusSmall
    property color fillColor: Theme.frameBg

    readonly property real f: Theme.frameThickness
    readonly property real xR: width - f                 // the right frame edge's inner side
    readonly property real xL: xR - tabWidth
    readonly property real y0: corner ? f : tabY
    readonly property real y1: y0 + tabHeight
    readonly property real r: Math.max(0, Math.min(radius, tabWidth / 2, tabHeight / 2))
    // Shoulders shrink while the tab is short, so its sides never go negative.
    readonly property real sTop: corner ? Math.max(0, Math.min(Theme.shoulderRadius, tabHeight - r))   // on the top edge
                                        : Math.max(0, Math.min(Theme.shoulderRadius, tabWidth - r))    // on the right edge
    readonly property real sBottom: Math.max(0, Math.min(Theme.shoulderRadius, tabWidth - r))          // on the right edge

    visible: tabWidth > 0 && tabHeight > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {   // right-edge tab
        strokeWidth: -1
        fillColor: root.corner ? "transparent" : root.fillColor
        startX: root.width; startY: root.y0 - root.sTop
        PathLine { x: root.xR; y: root.y0 - root.sTop }
        PathArc { x: root.xR - root.sTop; y: root.y0; radiusX: root.sTop; radiusY: root.sTop }   // concave
        PathLine { x: root.xL + root.r; y: root.y0 }
        PathArc { x: root.xL; y: root.y0 + root.r; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
        PathLine { x: root.xL; y: root.y1 - root.r }
        PathArc { x: root.xL + root.r; y: root.y1; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
        PathLine { x: root.xR - root.sBottom; y: root.y1 }
        PathArc { x: root.xR; y: root.y1 + root.sBottom; radiusX: root.sBottom; radiusY: root.sBottom }   // concave
        PathLine { x: root.width; y: root.y1 + root.sBottom }
        PathLine { x: root.width; y: root.y0 - root.sTop }
    }
    ShapePath {   // top-right corner drawer
        strokeWidth: -1
        fillColor: root.corner ? root.fillColor : "transparent"
        startX: root.xL - root.sTop; startY: 0
        PathLine { x: root.xL - root.sTop; y: root.y0 }
        PathArc { x: root.xL; y: root.y0 + root.sTop; radiusX: root.sTop; radiusY: root.sTop }   // concave
        PathLine { x: root.xL; y: root.y1 - root.r }
        PathArc { x: root.xL + root.r; y: root.y1; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
        PathLine { x: root.xR - root.sBottom; y: root.y1 }
        PathArc { x: root.xR; y: root.y1 + root.sBottom; radiusX: root.sBottom; radiusY: root.sBottom }   // concave
        PathLine { x: root.width; y: root.y1 + root.sBottom }
        PathLine { x: root.width; y: 0 }
        PathLine { x: root.xL - root.sTop; y: 0 }
    }
}
