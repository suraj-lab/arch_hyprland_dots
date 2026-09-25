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
    function icon(code) {
        var c = parseInt(code)
        if (c === 113) return "\uf185"  // sun — clear/sunny
        if (c === 116) return "\uf6c4"  // cloud-sun — partly cloudy
        if (c === 119 || c === 122) return "\uf0c2"  // cloud — cloudy/overcast
        if (c === 143 || c === 248 || c === 260) return "\uf0c2"  // cloud — fog/mist
        if (c >= 176 && c <= 314) return "\uf043"  // tint — rain variants
        if (c >= 317 && c <= 338 || c === 179 || c === 182 || c === 185
            || c === 227 || c === 230 || c === 350) return "\uf2dc"  // snowflake
        if (c === 200 || c >= 386) return "\uf0e7"  // bolt — thunder
        return "\uf0c2"  // cloud — fallback
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
