pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Add other settings as their services migrate. The settings surface writes through
    // set(), which never overwrites a file that does not parse (a half-saved hand edit).
    readonly property var idle: {
        var values = settingsData.idle || {}
        return {
            lockSec: timeout(values.lockSec, 600),
            dpmsSec: timeout(values.dpmsSec, 900),
            suspendSec: timeout(values.suspendSec, 0),
            caffeine: values.caffeine === true   // remembered across restarts (Desktop)
        }
    }

    readonly property var weather: {
        var values = settingsData.weather || {}
        var location = typeof values.location === "string" ? values.location.trim() : ""
        return { location: location && location.length <= 100 ? location : "London" }
    }

    readonly property var brightness: {
        var values = settingsData.brightness || {}
        return { buses: validBuses(values.buses) }
    }

    function validBuses(values) {
        var result = {}
        if (!values || typeof values !== "object" || Array.isArray(values)) return result
        Object.keys(values).forEach(function(connector) {
            var bus = values[connector]
            if (/^[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)+$/.test(connector)
                && typeof bus === "number" && Number.isInteger(bus) && bus >= 0 && bus <= 2147483647)
                result[connector] = bus
        })
        return result
    }

    // Night light (SPEC 6.5): the shell runs the schedule (hyprsunset has no config path
    // option, and its own profiles would fight it). from/to are "HH:MM"; to may be earlier
    // than from (overnight). Defaults: the old hyprsunset.conf schedule.
    readonly property var nightLight: {
        var values = settingsData.nightLight || {}
        var t = values.temperature
        return { temperature: typeof t === "number" && Number.isInteger(t) && t >= 1000 && t <= 6500 ? t : 4000,
                 from: clock(values.from, "19:30"), to: clock(values.to, "09:00") }
    }
    function clock(value, fallback) {
        return typeof value === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) ? value : fallback
    }

    readonly property var appearance: {
        var values = settingsData.appearance || {}
        return { animations: values.animations !== false }
    }

    // Gaming (SPEC 6.5): "Game Mode follows games" is the Desktop Game Mode auto toggle.
    // Only an explicit false disables it (the previous always-on behaviour is the default).
    readonly property var gaming: {
        var values = settingsData.gaming || {}
        return { autoGameMode: values.autoGameMode !== false }
    }

    // Pill preferences; monitors.<name>.pill overrides the global pill section.
    // hoverExpand false = rest-only, click (or double-tap Super) to expand.
    function pillFor(monitorName) {
        var global = settingsData.pill || {}
        var monitors = settingsData.monitors || {}
        var monitor = monitors[monitorName] || {}
        var local = monitor.pill || {}
        function pick(key, valid) {
            return valid(local[key]) ? local[key] : valid(global[key]) ? global[key] : undefined
        }
        var style = pick("restStyle", function(v) { return v === "tab" || v === "handle" })
        var hover = pick("hoverExpand", function(v) { return typeof v === "boolean" })
        var delay = pick("collapseDelayMs", function(v) {
            return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 5000 })
        return { restStyle: style === "handle" ? "handle" : "tab",
                 hoverExpand: hover !== false,
                 collapseDelayMs: delay === undefined ? -1 : delay }   // -1: the Theme default
    }

    function timeout(value, fallback) {
        return typeof value === "number" && Number.isInteger(value)
            && value >= 0 && value <= 2147483647 ? value : fallback
    }

    // Parsed settings.json, derived synchronously from the file text. (JsonAdapter's own
    // defaults overwrote the initial preload, so startup ignored the file until it changed.)
    // Missing file: defaults. Malformed save: keep the last good object.
    function parse(text) {
        try {
            var data = JSON.parse(text)
            return data && typeof data === "object" && !Array.isArray(data) ? data : null
        } catch (error) { return null }
    }
    property var lastGood: ({})
    property bool fileMissing: false
    readonly property var settingsData: {
        if (fileMissing) return {}
        var data = parse(settingsFile.text())
        return data !== null ? data : lastGood
    }

    // Change one key ("idle.lockSec"), keeping everything else in the file, including keys
    // this shell does not know. undefined deletes the key. Returns false (and writes
    // nothing) while the file on disk does not parse.
    function set(path, value) {
        var data = fileMissing ? {} : parse(settingsFile.text())
        if (data === null) { console.warn("settings.json does not parse; not writing " + path); return false }
        var keys = path.split("."), node = data
        for (var i = 0; i < keys.length - 1; i++) {
            var next = node[keys[i]]
            if (!next || typeof next !== "object" || Array.isArray(next)) node[keys[i]] = next = {}
            node = next
        }
        if (value === undefined) delete node[keys[keys.length - 1]]
        else node[keys[keys.length - 1]] = value
        settingsFile.setText(JSON.stringify(data, null, 2) + "\n")
        lastGood = data
        fileMissing = false
        return true
    }

    property FileView settingsFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"
        preload: true
        blockLoading: true
        watchChanges: true
        printErrors: false // a missing file is normal: use the QML defaults
        onFileChanged: reload()
        onLoaded: {
            root.fileMissing = false
            var data = root.parse(text())
            if (data !== null) root.lastGood = data
            else console.warn("Ignoring invalid shell settings; keeping the last good values")
        }
        onLoadFailed: function(error) {
            // Deferred: the first read runs inside the settingsData binding itself.
            if (error === FileViewError.FileNotFound) Qt.callLater(function() {
                root.lastGood = ({}); root.fileMissing = true
            })
            else console.warn("Cannot read shell settings: " + FileViewError.toString(error))
        }
    }
}
