pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Monitor brightness via ddcutil (no native Quickshell module). Buses are detected
// once at startup from `ddcutil detect --brief` instead of hardcoding 8 and 10.
// One slider still drives every detected monitor; per-monitor UI arrives in Phase 4.
Singleton {
    id: root

    property var busMap: ({})   // DRM connector → I2C bus, e.g. { "DP-2": 10, "HDMI-A-1": 8 }
    property bool ready: false
    property real brightness: 0
    readonly property var buses: Object.keys(busMap).map(function(k) { return busMap[k] })
    readonly property var readBus: buses.length ? buses[0] : 0

    // `ddcutil detect --brief` lists each display's bus and connector across lines.
    function parseDetect(text) {
        var map = {}, lines = text.split("\n"), lastBus = 0
        for (var i = 0; i < lines.length; i++) {
            var m = /I2C bus:\s*\/dev\/i2c-(\d+)/.exec(lines[i])
            if (m) { lastBus = parseInt(m[1]); continue }
            m = /DRM connector:\s*(?:card\d+-)?(\S+)/.exec(lines[i])
            if (m && lastBus) map[m[1]] = lastBus
        }
        return map
    }

    function read() {
        if (!readBus) return
        readProc.command = ["bash", "-c",
            "ddcutil getvcp 10 --bus " + readBus + " --brief 2>/dev/null | awk '{print $4, $5}'"]
        readProc.running = true
    }

    function set(v) {
        var pct = Math.max(5, Math.min(100, Math.round(v * 100)))
        root.brightness = pct / 100
        var cmd = ""
        for (var i = 0; i < buses.length; i++)
            cmd += "ddcutil setvcp 10 " + pct + " --bus " + buses[i] + " --noverify & "
        if (!cmd) return
        setProc.command = ["bash", "-c", cmd + "wait"]
        setProc.running = true
    }

    Process {
        running: true
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: { root.busMap = root.parseDetect(text); root.ready = true; root.read() }
        }
    }
    Process {
        id: readProc
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(/\s+/)
                if (parts.length >= 2) {
                    var current = parseInt(parts[0]), max = parseInt(parts[1])
                    if (!isNaN(current) && !isNaN(max) && max > 0) root.brightness = current / max
                }
            }
        }
    }
    Process { id: setProc }
}
