pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Monitor brightness via ddcutil (no native Quickshell module). Buses are detected
// once at startup from `ddcutil detect --brief` instead of hardcoding 8 and 10.
// One slider still drives every detected monitor; per-monitor UI arrives in Phase 4.
Singleton {
    id: root

    property var detectedBuses: ({})
    property bool detectionComplete: false
    readonly property var busMap: Object.assign({}, detectedBuses, Config.brightness.buses)
    readonly property var buses: Object.keys(busMap).map(function(k) { return busMap[k] })
        .filter(function(bus, i, list) { return list.indexOf(bus) === i })
    readonly property int readBus: buses.length ? buses[0] : -1
    readonly property bool ready: detectionComplete && buses.length > 0
    readonly property bool busy: ioProc.running
    property real brightness: 0
    property string error: ""
    property int pendingValue: -1
    property bool readRequested: false
    // Config rebuilds its objects on every settings.json change; only re-read on a real change.
    readonly property string busKey: JSON.stringify(busMap)
    onBusKeyChanged: if (detectionComplete) read()

    // `ddcutil detect --brief` lists each display's bus and connector across lines.
    function parseDetect(text) {
        var map = {}, lines = text.split("\n"), lastBus = -1, valid = false
        for (var i = 0; i < lines.length; i++) {
            if (/^\s*(?:Display\s+\d+|Invalid display|Phantom display)/.test(lines[i])) {
                valid = /^\s*Display\s+\d+\s*$/.test(lines[i])
                lastBus = -1
            }
            if (!valid) continue
            var m = /I2C bus:\s*\/dev\/i2c-(\d+)\s*$/.exec(lines[i])
            if (m) { lastBus = Number(m[1]); continue }
            m = /DRM connector:\s*(?:card\d+-)?(\S+)/.exec(lines[i])
            if (m && Number.isInteger(lastBus) && lastBus >= 0 && lastBus <= 2147483647)
                map[m[1]] = lastBus
        }
        return map
    }

    function parseReading(text) {
        var m = /^VCP 10 C (\d+) (\d+)\s*$/m.exec(text)
        return m && Number(m[2]) > 0 && Number(m[1]) <= Number(m[2])
            ? Number(m[1]) / Number(m[2]) : -1
    }

    function read() {
        error = ""
        readRequested = true
        flush()
    }

    function set(v) {
        if (!ready || typeof v !== "number" || !Number.isFinite(v)) return
        pendingValue = Math.max(5, Math.min(100, Math.round(v * 100)))
        brightness = pendingValue / 100
        error = ""
        flush()
    }

    // Process ignores a new command while running. Keep only the latest slider value,
    // and serialize reads/writes so a stale read cannot undo an in-flight drag.
    function flush() {
        if (!ready || ioProc.running) return
        if (pendingValue >= 0) {
            ioProc.writing = true
            ioProc.command = ["sh", "-c",
                'value=$1; shift; status=0; for bus do '
                + 'ddcutil setvcp 10 "$value" --bus "$bus" --noverify || status=$?; '
                + 'done; exit "$status"', "brightness", String(pendingValue)]
                .concat(buses.map(function(bus) { return String(bus) }))
            pendingValue = -1
            readRequested = true // read back once the final write completes
        } else if (readRequested) {
            ioProc.writing = false
            ioProc.command = ["ddcutil", "getvcp", "10", "--bus", String(readBus), "--brief"]
            readRequested = false
        } else return
        ioProc.running = true
    }

    Process {
        running: true
        command: ["ddcutil", "detect", "--brief"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: detection }
        onExited: (code, status) => {
            root.detectedBuses = root.parseDetect(detection.text)
            root.detectionComplete = true
            root.read()
            if (code !== 0 || status !== 0 || !root.buses.length)
                root.error = "DDC detection incomplete or no supported displays"
        }
    }
    Process {
        id: ioProc
        property bool writing: false
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) {
                root.error = "Brightness " + (writing ? "write" : "read") + " failed (" + code + ")"
            } else if (!writing) {
                var value = root.parseReading(output.text)
                if (value < 0) root.error = "Invalid DDC brightness reading"
                else if (root.pendingValue < 0) root.brightness = value
            }
            // Wait until Process has finished handling its exit before starting the next job.
            Qt.callLater(root.flush)
        }
    }
}
