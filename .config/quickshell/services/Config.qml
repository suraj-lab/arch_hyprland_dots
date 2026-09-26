pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Add other settings as their services migrate; never write over user edits.
    readonly property var idle: {
        settingsFile.text() // finish the initial read before enabling idle monitors
        var values = settingsData.idle || {}
        return {
            lockSec: timeout(values.lockSec, 600),
            dpmsSec: timeout(values.dpmsSec, 900),
            suspendSec: timeout(values.suspendSec, 0)
        }
    }

    readonly property var weather: {
        settingsFile.text()
        var values = settingsData.weather || {}
        var location = typeof values.location === "string" ? values.location.trim() : ""
        return { location: location && location.length <= 100 ? location : "London" }
    }

    readonly property var brightness: {
        settingsFile.text()
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
        settingsFile.text()
        var values = settingsData.appearance || {}
        return { layout: values.layout === "frame" ? "frame" : "classic" }
    }

    // Only restStyle is needed for the fixed bottom reserve in 4.1. Other pill
    // preferences arrive with their consumers; monitor overrides fall back to global.
    function pillFor(monitorName) {
        settingsFile.text()
        var global = settingsData.pill || {}
        var monitors = settingsData.monitors || {}
        var monitor = monitors[monitorName] || {}
        var local = monitor.pill || {}
        var style = local.restStyle === "tab" || local.restStyle === "handle"
            ? local.restStyle : global.restStyle
        return { restStyle: style === "handle" ? "handle" : "tab" }
    }

    readonly property var sections: ["idle", "weather", "brightness", "appearance", "pill", "monitors"]
    function resetSections(data) {
        for (var i = 0; i < sections.length; i++)
            if (!data || !(sections[i] in data)) settingsData[sections[i]] = ({})
    }

    function timeout(value, fallback) {
        return typeof value === "number" && Number.isInteger(value)
            && value >= 0 && value <= 2147483647 ? value : fallback
    }

    property JsonAdapter settingsAdapter: JsonAdapter {
        id: settingsData
        property var idle: ({})
        property var weather: ({})
        property var brightness: ({})
        property var appearance: ({})
        property var pill: ({})
        property var monitors: ({})
    }

    property FileView settingsFile: FileView {
        adapter: root.settingsAdapter
        path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"
        preload: true
        blockLoading: true
        watchChanges: true
        printErrors: false // a missing file is normal: use the QML defaults
        onFileChanged: reload()
        onLoaded: {
            // JsonAdapter retains omitted properties; deleting a section should restore defaults.
            try {
                var data = JSON.parse(text())
                if (data && typeof data === "object" && !Array.isArray(data)) root.resetSections(data)
            } catch (error) {} // JsonAdapter reports malformed JSON and retains the last good values.
        }
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) root.resetSections(null)
            else console.warn("Cannot read shell settings: " + FileViewError.toString(error))
        }
    }
}
