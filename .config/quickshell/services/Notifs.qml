pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification server, toast/history models, unread count and DND.
// The server exposes no notification list or DND property, so history is ours:
// onNotification + n.tracked = true. Components get the models/functions passed in.
Singleton {
    id: root

    property bool dndEnabled: false          // DND: history only, no toast/badge
    property int  unreadCount: 0
    property var  notifMap: ({})             // notifId → Notification object
    readonly property ListModel toastModel: toasts      // active toasts (max 4)
    readonly property ListModel historyModel: history   // notification history
    readonly property bool hasToasts: toasts.count > 0
    property int _mediaToastId: -1           // negative ids never collide with the server's

    NotificationServer {
        keepOnReload: true
        onNotification: function(n) { root.add(n) }
    }
    ListModel { id: toasts }
    ListModel { id: history }

    function pushToast(entry) {
        if (toasts.count >= 4) toasts.remove(0)
        toasts.append(entry)
    }

    function add(n) {
        n.tracked = true

        // Always store in history so missed notifications are reviewable
        var body = n.body
                   ? n.body.replace(/<[^>]*>/g, "")
                           .replace(/&amp;/g, "&")
                           .replace(/&lt;/g,  "<")
                           .replace(/&gt;/g,  ">")
                   : ""
        history.append({
            notifId:   n.id,
            appName:   n.appName  || "",
            summary:   n.summary  || "",
            body:      body,
            urgency:   n.urgency,
            notifTime: Date.now()
        })
        var m = root.notifMap
        m[n.id] = n
        root.notifMap = m

        if (root.dndEnabled) return

        root.unreadCount++
        var timeout = (n.expireTimeout > 0 && n.expireTimeout <= 15000) ? n.expireTimeout : 5000
        if (n.urgency === 2) timeout = 0
        pushToast({
            notifId:      n.id,
            appName:      n.appName  || "",
            summary:      n.summary  || "",
            body:         body,
            urgency:      n.urgency,
            toastTimeout: timeout
        })
    }

    function dismiss(id) {
        var n = root.notifMap[id]
        if (n) {
            n.tracked = false
            try { n.close() } catch(e) {}
        }
        for (var t = 0; t < toasts.count; t++) {
            if (toasts.get(t).notifId === id) { toasts.remove(t); break }
        }
        for (var i = 0; i < history.count; i++) {
            if (history.get(i).notifId === id) { history.remove(i); break }
        }
        var m = Object.assign({}, root.notifMap)
        delete m[id]
        root.notifMap = m
    }

    function clearAll() {
        var ids = Object.keys(root.notifMap)
        for (var i = 0; i < ids.length; i++) {
            var n = root.notifMap[ids[i]]
            if (n) { n.tracked = false; try { n.close() } catch(e) {} }
        }
        toasts.clear()
        history.clear()
        root.notifMap = {}
    }

    // Track-change toasts. Unchanged behaviour: shown even with DND on, not in history.
    Connections {
        target: Media
        function onTrackChanged(player) {
            var artUrl = player.trackArtUrl || ""
            root.pushToast({
                notifId:      root._mediaToastId--,
                appName:      player.identity || "Media",
                summary:      player.trackTitle,
                body:         artUrl ? "art:" + artUrl : (player.trackArtist || ""),
                urgency:      0,
                toastTimeout: 3000
            })
        }
    }
}
