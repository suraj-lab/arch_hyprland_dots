import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../.config/quickshell/components/frame"
import "../../.config/quickshell/services"

// Run only in the isolated HOME/display created by check-desktop-phase4.py.
ShellRoot {
    id: root
    property bool mainFullscreen: false
    property bool secondaryFullscreen: false

    property var monitorNames: ["DP-2", "HDMI-A-1"]
    Variants {
        id: frames
        model: Config.appearance.layout === "frame" ? root.monitorNames : []
        Frame {
            required property string modelData
            screen: Quickshell.screens[0]
            monitorName: modelData
            fullscreen: modelData === "DP-2" ? root.mainFullscreen : root.secondaryFullscreen
        }
    }

    function frameState(frame) {
        var reserves = []
        for (var i = 0; i < frame.data.length; i++) {
            var item = frame.data[i]
            if (item.edge === undefined) continue
            reserves.push({ edge: item.edge, visible: item.visible,
                zone: item.exclusiveZone, anchors: { top: item.anchors.top, bottom: item.anchors.bottom,
                    left: item.anchors.left, right: item.anchors.right },
                maskEmpty: item.mask !== null && item.mask.width === 0 && item.mask.height === 0,
                focus: item.focusable })
        }
        return { name: frame.monitorName, width: frame.width, height: frame.height,
            visible: frame.visible, fullscreen: frame.fullscreen,
            bottom: frame.bottomReserve, reserves: reserves,
            maskEmpty: frame.mask !== null && frame.mask.width === 0 && frame.mask.height === 0,
            ignoreReserves: frame.exclusionMode === ExclusionMode.Ignore,
            focus: frame.focusable }
    }

    IpcHandler {
        target: "frameTest"
        function fullscreen(main: bool, secondary: bool): void {
            root.mainFullscreen = main
            root.secondaryFullscreen = secondary
        }
        function secondary(enabled: bool): void {
            root.monitorNames = enabled ? ["DP-2", "HDMI-A-1"] : ["DP-2"]
        }
        function capture(): void {
            frames.instances[0].outline.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("HOME") + "/frame.png")
            })
        }
        function status(): string {
            return JSON.stringify({ layout: Config.appearance.layout,
                frames: frames.instances.map(function(frame) { return root.frameState(frame) }) })
        }
    }
}
