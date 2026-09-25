pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Default output/input, device lists and per-app playback streams via native PipeWire
// (replaces ~8 wpctl/pactl processes per second). Volumes use the same scale as
// wpctl/pactl (checked live: 0.29 both), so percentages are unchanged.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: !!(sink && sink.audio)
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    readonly property var streams: Pipewire.nodes.values.filter(function(n) {
        return n.type === PwNodeType.AudioOutStream && n.audio
    })

    // Same item shapes the Sound tab used with pactl.
    readonly property var sinks: devices(PwNodeType.AudioSink, sink)
    readonly property var sources: devices(PwNodeType.AudioSource, source)
    readonly property var apps: streams.map(appEntry)

    // PwNode has no running/idle/suspended state; the device picker shows it, so read it
    // with one pactl call when the picker opens (as before), not by polling.
    property var states: ({})

    function devices(type, current) {
        var nodes = Pipewire.nodes.values, result = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            if (n.type !== type) continue
            result.push({ name: n.name, desc: n.description || n.name, index: n.id,
                          state: root.states[n.name] || "", isDefault: n === current })
        }
        return result
    }

    function appEntry(n) {
        var p = n.properties || {}
        return { index: n.id, volume: Math.round(n.audio.volume * 100), muted: n.audio.muted,
                 appName: p["application.name"] || p["application.process.binary"] || n.name || "Unknown" }
    }
    // `pactl list short sinks/sources`: index name driver spec STATE
    function parseStates(text) {
        var map = {}, lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].trim().split(/\s+/)
            if (f.length >= 3) map[f[1]] = f[f.length - 1].toLowerCase()
        }
        return map
    }

    function setVolume(v) { if (ready) sink.audio.volume = Math.max(0, Math.min(1.5, v)) }
    function toggleMute() { if (ready) sink.audio.muted = !sink.audio.muted }
    function setDefaultSink(name) { setPreferred(name, true) }
    function setDefaultSource(name) { setPreferred(name, false) }
    function setPreferred(name, isSink) {
        var n = Pipewire.nodes.values.find(function(x) { return x.name === name })
        if (!n) return
        if (isSink) Pipewire.preferredDefaultAudioSink = n
        else Pipewire.preferredDefaultAudioSource = n
    }
    function setAppVolume(id, pct) {
        var n = root.streams.find(function(x) { return x.id === id })
        if (n) n.audio.volume = Math.max(0, Math.min(100, pct)) / 100
    }
    function refreshStates() { if (!stateProc.running) stateProc.running = true }

    // Audio properties are only live for tracked nodes.
    PwObjectTracker { objects: [root.sink, root.source].concat(root.streams) }

    Process {
        id: stateProc
        command: ["sh", "-c", "pactl list short sinks; pactl list short sources"]
        stdout: StdioCollector { onStreamFinished: root.states = root.parseStates(text) }
    }
}
