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
        return { layout: values.layout === "frame" ? "frame" : "classic" }
    }

    // Only restStyle is needed for the fixed bottom reserve in 4.1. Other pill
    // preferences arrive with their consumers; monitor overrides fall back to global.
    function pillFor(monitorName) {
        var global = settingsData.pill || {}
        var monitors = settingsData.monitors || {}
        var monitor = monitors[monitorName] || {}
        var local = monitor.pill || {}
        var style = local.restStyle === "tab" || local.restStyle === "handle"
            ? local.restStyle : global.restStyle
        return { restStyle: style === "handle" ? "handle" : "tab" }
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
