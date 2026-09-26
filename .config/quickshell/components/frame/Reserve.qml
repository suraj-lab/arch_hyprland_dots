import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

// A transparent, input-free strip. Its exclusive zone never follows pill expansion.
PanelWindow {
    id: root
    required property string edge
    property int thickness: Theme.frameThickness
    readonly property bool horizontal: edge === "top" || edge === "bottom"

    anchors {
        top: root.edge !== "bottom"
        bottom: root.edge !== "top"
        left: root.edge !== "right"
        right: root.edge !== "left"
    }
    implicitWidth: horizontal ? 1 : thickness
    implicitHeight: horizontal ? thickness : 1
    exclusiveZone: thickness
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-reserve-" + edge
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
}
