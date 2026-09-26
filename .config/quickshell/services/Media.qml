pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS players for the Sound tab, and track-change detection for toasts.
// Which player a Sound tab shows stays per view (per monitor), in SoundView.
Singleton {
    id: root

    property var players: []            // controllable players (same filter as before)
    // Spotify first (Suraj usually has Spotify and a browser playing together), then any
    // other player that is playing, then the rest; ties keep MPRIS order.
    readonly property var ordered: order(players)
    function isSpotify(p) {
        return ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase().indexOf("spotify") >= 0
    }
    function rank(p) { return isSpotify(p) ? 0 : p.isPlaying ? 1 : 2 }
    function order(list) {
        return list.map(function(p, i) { return { p: p, i: i, r: rank(p) } })
                   .sort(function(a, b) { return a.r - b.r || a.i - b.i })
                   .map(function(x) { return x.p })
    }
    signal trackChanged(var player)     // a new track started (not the first one seen)
    property string _lastTrackKey: ""

    // Controllable players only. playerctld is a proxy that mirrors the active player
    // (same identity and track), so listing it would show that player twice.
    function controllable(list) {
        return list.filter(function(p) {
            return (p.canTogglePlaying || p.trackTitle) && (p.dbusName || "").indexOf("playerctld") < 0
        })
    }
    function refresh() { root.players = controllable(Mpris.players.values) }

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
