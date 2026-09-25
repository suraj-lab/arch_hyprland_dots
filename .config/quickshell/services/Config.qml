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

    function timeout(value, fallback) {
        return typeof value === "number" && Number.isInteger(value)
            && value >= 0 && value <= 2147483647 ? value : fallback
    }

    property JsonAdapter settingsAdapter: JsonAdapter {
        id: settingsData
        property var idle: ({})
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
                if (data && typeof data === "object" && !Array.isArray(data) && !("idle" in data))
                    settingsData.idle = ({})
            } catch (error) {} // JsonAdapter reports malformed JSON and retains the last good values.
        }
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) settingsData.idle = ({})
            else console.warn("Cannot read shell settings: " + FileViewError.toString(error))
        }
    }
}
