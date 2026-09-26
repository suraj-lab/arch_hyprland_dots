pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// wttr.in current conditions + 3-day forecast, fetched once for all monitors.
Singleton {
    id: root

    property bool loaded: false
    property bool error: false
    property string temp: ""
    property string desc: ""
    property string feels: ""
    property string humidity: ""
    property string wind: ""
    property string code: ""
    property var forecastDays: []
    property real lastFetch: 0
    readonly property string location: Config.weather.location

    // Weather code → Nerd Font icon mapping (wttr.in codes)
    // wttr.in weather code -> Weather Icons glyph (U+E3xx, present in the Nerd Font; the
    // old U+F6C4 "cloud-sun" is missing). Specific codes before the rain catch-all.
    function icon(code) {
        var c = parseInt(code)
        if (c === 113) return "\ue30d"                                  // clear / sunny
        if (c === 116) return "\ue302"                                  // partly cloudy
        if (c === 119 || c === 122) return "\ue312"                     // cloudy / overcast
        if (c === 143 || c === 248 || c === 260) return "\ue313"        // mist / fog
        if ([200, 386, 389, 392, 395].indexOf(c) >= 0) return "\ue31d"  // thunder
        if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371].indexOf(c) >= 0)
            return "\ue31a"                                             // snow
        if (c >= 176) return "\ue318"                                   // rain, drizzle, sleet
        return "\ue312"                                                 // unknown: cloud
    }

    // Throws on malformed data; the caller keeps the last good values.
    function parse(raw) {
        var d = JSON.parse(raw)
        var cc = d.current_condition[0]
        var fc = []
        for (var i = 0; i < Math.min(3, d.weather.length); i++) {
            var day = d.weather[i]
            fc.push({ date: day.date, high: day.maxtempC, low: day.mintempC,
                      code: day.hourly[4].weatherCode })  // midday hour
        }
        return { temp: cc.temp_C, desc: cc.weatherDesc[0].value, feels: cc.FeelsLikeC,
                 humidity: cc.humidity, wind: cc.windspeedKmph, code: cc.weatherCode,
                 forecastDays: fc }
    }

    function refresh() { if (!proc.running) proc.running = true }
    function refreshIfStale() { if (Date.now() - root.lastFetch > 600000) refresh() }

    onLocationChanged: refresh()

    Process {
        id: proc
        // No shell: the location is a single URL-encoded argument.
        command: ["curl", "-sf", "--max-time", "10",
                  "wttr.in/" + encodeURIComponent(root.location) + "?format=j1"]
        // Empty output (curl failed) fails to parse: error, keep the last good values.
        stdout: StdioCollector { onStreamFinished: root.apply(text) }
    }

    function apply(raw) {
        try {
            var w = root.parse(raw)
            root.temp = w.temp; root.desc = w.desc; root.feels = w.feels
            root.humidity = w.humidity; root.wind = w.wind; root.code = w.code
            root.forecastDays = w.forecastDays
            root.loaded = true
            root.error = false
            root.lastFetch = Date.now()
        } catch (e) {
            root.error = true
        }
    }

    Timer { interval: 1800000; running: true; repeat: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
