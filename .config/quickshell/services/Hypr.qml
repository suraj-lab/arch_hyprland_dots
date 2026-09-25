pragma Singleton
import QtQuick
import Quickshell.Hyprland

QtObject {
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    // Callers supply the existing hl.dsp.* Lua expressions, never legacy dispatchers.
    function dispatch(lua) { Hyprland.dispatch(lua) }

    function isFullscreen(monitorName) {
        var monitor = Hyprland.monitors.values.find(function(m) { return m.name === monitorName })
        return !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)
    }
}
