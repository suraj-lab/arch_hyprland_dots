import QtQuick
import Quickshell
import "../../.config/quickshell/services"

// Loaded only by check-desktop-phase3.py in a scratch HOME, without a compositor,
// D-Bus or network (curl, gamemoded etc. are stubs from the runner).
ShellRoot {
    id: root

    // Same DND wiring as shell.qml. Starts on; the stubbed Game Mode helper reports off.
    Component.onCompleted: { Notifs.dndEnabled = true; report() }
    Binding { target: Desktop; property: "dndEnabled"; value: Notifs.dndEnabled }
    Connections {
        target: Desktop
        function onDndRequested(enabled) { Notifs.dndEnabled = enabled }
    }

    function report() {
        console.log("CONFIG " + JSON.stringify({ idle: Config.idle, weather: Config.weather }))
    }
    Connections {
        target: Config
        function onIdleChanged() { root.report() }
        function onWeatherChanged() { root.report() }
    }
    Connections {
        target: Weather
        function onLastFetchChanged() {
            console.log("WEATHER " + JSON.stringify({ location: Weather.location, temp: Weather.temp,
                desc: Weather.desc, days: Weather.forecastDays.length, error: Weather.error }))
        }
    }

    // Brightness with stubbed ddcutil: detect must resolve both buses and read 28%.
    Connections {
        target: Brightness
        function onBrightnessChanged() {
            if (!Brightness.ready) return
            console.log("BRIGHT " + JSON.stringify({ ready: Brightness.ready,
                brightness: Brightness.brightness, buses: Brightness.buses.length }))
        }
    }

    // Audio with no PipeWire reachable: must load quietly and report "not ready".
    Connections {
        target: Audio
        function onStatesChanged() {
            console.log("AUDIO " + JSON.stringify({ ready: Audio.ready, volume: Audio.volume,
                sinks: Audio.sinks.length, apps: Audio.apps.length, states: Audio.states }))
        }
    }

    // Exercise Notifs with fake notification objects once the Desktop wiring has settled.
    property bool notifsTested: false
    function notifsTest() {
        var closed = []
        function fake(id, extra) {
            var n = { id: id, appName: "app", summary: "s" + id, body: "<b>x</b> &amp; y",
                      urgency: 1, expireTimeout: -1, tracked: false,
                      close: function() { closed.push(id) } }
            for (var k in extra) n[k] = extra[k]
            return n
        }
        var r = {}
        for (var i = 1; i <= 5; i++) Notifs.add(fake(i))
        r.toasts = Notifs.toastModel.count
        r.history = Notifs.historyModel.count
        r.unread = Notifs.unreadCount
        r.oldestToast = Notifs.toastModel.get(0).notifId
        r.body = Notifs.historyModel.get(0).body
        Notifs.add(fake(6, { urgency: 2 }))
        r.criticalTimeout = Notifs.toastModel.get(3).toastTimeout
        Notifs.add(fake(7, { expireTimeout: 9000 }))
        r.customTimeout = Notifs.toastModel.get(3).toastTimeout
        Notifs.dndEnabled = true
        r.deskDnd = Desktop.dndEnabled
        Notifs.add(fake(8))
        r.dnd = [Notifs.historyModel.count, Notifs.unreadCount, Notifs.toastModel.get(3).notifId]
        Notifs.dndEnabled = false
        Notifs.dismiss(7)
        r.dismissed = [closed.indexOf(7) >= 0, Notifs.historyModel.count, Notifs.toastModel.count]
        Media.trackChanged({ identity: "Spotify", trackTitle: "Song", trackArtist: "Artist", trackArtUrl: "" })
        var t = Notifs.toastModel.get(Notifs.toastModel.count - 1)
        r.media = [t.notifId, t.appName, t.summary, t.body, t.toastTimeout, Notifs.historyModel.count]
        Notifs.clearAll()
        r.cleared = [Notifs.toastModel.count, Notifs.historyModel.count, closed.length, Notifs.hasToasts]
        console.log("NOTIFS " + JSON.stringify(r))
    }

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!Desktop._gameChecked) return
            if (!root.notifsTested) {
                root.notifsTested = true; root.notifsTest(); Audio.refreshStates()
                console.log("NETBT " + JSON.stringify({ wifi: Net.wifiEnabled, ssid: Net.ssid,
                    networks: Net.networks.length, bt: Bt.enabled }))
                Net.scan(); Net.connect("anything"); Bt.toggle()   // no device/adapter: must be no-ops
            }
            console.log("DESKTOP " + JSON.stringify({
                lockSec: Desktop.lockTimeout, dpmsSec: Desktop.dpmsTimeout,
                suspendSec: Desktop.suspendTimeout, dnd: Notifs.dndEnabled,
                backendDnd: Desktop.dndEnabled, gameMode: Desktop.gameMode
            }))
            if (Sysmon.cpu >= 0 && Sysmon.temp >= 0)
                console.log("SYSMON " + JSON.stringify({ cpu: Sysmon.cpu, mem: Sysmon.mem,
                    temp: Sysmon.temp, path: Sysmon.tempPath }))
        }
    }
}
