pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS players for the Sound tab, and track-change detection for toasts.
// Which player a Sound tab shows stays per view (per monitor), in SoundView.
Singleton {
    id: root

    property var players: []            // controllable players (same filter as before)
    signal trackChanged(var player)     // a new track started (not the first one seen)
    property string _lastTrackKey: ""

    function refresh() {
        var list = Mpris.players.values
        var result = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].canTogglePlaying || list[i].trackTitle) result.push(list[i])
        }
        root.players = result
    }

    function checkTrack() {
        try {
            var list = Mpris.players.values
            if (!list || list.length === 0) return
            var active = null
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                if (p && p.playbackState === MprisPlaybackState.Playing) { active = p; break }
            }
            if (!active || !active.trackTitle) return

            var key = (active.identity || "") + "|" + active.trackTitle + "|" + (active.trackArtist || "")
            if (key === root._lastTrackKey) return
            var isFirst = root._lastTrackKey === ""
            root._lastTrackKey = key
            if (!isFirst) root.trackChanged(active)
        } catch(e) {}
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { root.refresh(); root.checkTrack() }
    }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.checkTrack() }
    Component.onCompleted: refresh()
}
