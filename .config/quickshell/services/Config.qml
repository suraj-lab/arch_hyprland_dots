pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Add other settings as their services migrate; never write over user edits.
    readonly property var idle: {
        var values = settingsData.idle || {}
        return {
            lockSec: timeout(values.lockSec, 600),
            dpmsSec: timeout(values.dpmsSec, 900),
            suspendSec: timeout(values.suspendSec, 0)
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

    readonly property var appearance: {
        var values = settingsData.appearance || {}
        // Frame is the default; only an explicit "classic" brings back the top bar.
        return { layout: values.layout === "classic" ? "classic" : "frame",
                 animations: values.animations !== false }
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
