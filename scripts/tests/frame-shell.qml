import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../.config/quickshell/components"
import "../../.config/quickshell/components/frame"
import "../../.config/quickshell/components/pill"
import "../../.config/quickshell/services"

// Run only in the isolated HOME/display created by check-desktop-phase4.py.
ShellRoot {
    id: root
    property bool mainFullscreen: false
    property bool secondaryFullscreen: false
    property bool classicBar: false

    property var monitorNames: ["DP-2", "HDMI-A-1"]

    // 6.1: a fake polkit AuthFlow (no polkitd here) with the real one's properties/methods.
    component FakeIdentity: QtObject {
        property string string; property string displayName; property bool isGroup: false   // (no `id`: reserved in QML)
    }
    FakeIdentity { id: idSuraj; string: "suraj"; displayName: "Suraj" }
    FakeIdentity { id: idWheel; string: "wheel"; displayName: "wheel"; isGroup: true }
    QtObject {
        id: fakeFlow
        property string message: "Authentication is needed to run `/usr/bin/true' as the super user"
        property string actionId: "org.freedesktop.policykit.exec"
        property var identities: [idSuraj]
        property var selectedIdentity: idSuraj
        property bool isResponseRequired: true
        property string inputPrompt: "Password: "
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool isCompleted: false
        property bool failed: false
        property var submitted: []
        property int cancels: 0
        function submit(value) { submitted = submitted.concat([value]); isResponseRequired = false }
        function cancelAuthenticationRequest() { cancels++; isCompleted = true }
    }
    property var polkitFlow: null
    PolkitDialog { id: polkitDialog; flow: root.polkitFlow }
    readonly property bool frameLayout: Config.appearance.layout === "frame"   // same guard as shell.qml
    property int frameBuilds: 0
    Variants {
        id: frames
        model: root.frameLayout ? root.monitorNames : []
        Frame {
            required property string modelData
            Component.onCompleted: root.frameBuilds++
            screen: Quickshell.screens[0]
            monitorName: modelData
            fullscreen: modelData === "DP-2" ? root.mainFullscreen : root.secondaryFullscreen
            reserveTop: !root.classicBar
            pillShown: !root.classicBar
        }
    }

    property var pillNames: ["DP-2"]   // one at a time: pills on the same test screen overlap
    property string lastAction: ""     // launcher ">" actions (runShellAction in the real shell)
    Variants {
        id: pills
        model: root.frameLayout ? root.pillNames : []
        PillOverlay {
            required property string modelData
            screen: Quickshell.screens[0]
            monitorName: modelData
            fullscreen: modelData === "DP-2" ? root.mainFullscreen : root.secondaryFullscreen
            onShellAction: id => root.lastAction = id
        }
    }
    function pillState(p) {
        return { name: p.monitorName, state: p.pillState, visible: p.visible, pinned: p.pinned,
                 surface: p.surface, tierW: p.tierItem.width, tierH: p.tierItem.height,
                 tierX: p.tierItem.x, tierY: p.tierItem.y, tierTarget: p.tierTarget, anchor: p.tierAnchor,
                 unread: Notifs.unreadCount, focusGrab: p.surface !== "" && p.grabReady,
                 dashTab: p.dashboard.tab, hoverW: p.hoverWidth,
                 dashMain: p.dashboard.player ? p.dashboard.player.identity : "",
                 dashOthers: p.dashboard.others.map(function(o) { return o.identity }),
                 rowItems: root.rowSpans(p), clock: root.clockSpan(p),
                 x: p.pillItem.x, y: p.pillItem.y, w: p.pillItem.width, h: p.pillItem.height,
                 winH: p.height, winW: p.width, hoverExpand: p.prefs.hoverExpand, animate: p.animate,
                 collapseMs: p.collapseDelay,
                 toasts: Notifs.toastModel.count, toast: root.box(p.drawers.toastArea),
                 osd: root.box(p.drawers.osdArea), osdKind: p.drawers.osdKind, osdShown: p.drawers.osdShown,
                 launcher: { mode: p.launcher.mode, query: p.launcher.query, count: p.launcher.count,
                             current: p.launcher.current, armed: p.launcher.armed,
                             first: p.launcher.rows.length ? (p.launcher.rows[0].text || p.launcher.rows[0].title) : "" },
                 lastAction: root.lastAction, updateBadge: root.badge(p),
                 wifiTile: root.center(p, "wifiTile"), btTile: root.center(p, "btTile"),
                 volChip: root.center(p, "volChip", p.pillItem),
                 caffeineChip: root.center(p, "caffeineChip", p.pillItem),
                 wifiSpinning: root.spinning(p, "wifiRescan"), handle: p.handle,
                 devChip: root.center(p, "devicesChip", p.pillItem),
                 openBtn: root.center(p, "open:/dev/sdb1"), ejectBtn: root.center(p, "eject:/dev/sdb"),
                 sheet: { query: p.cheatsheet.query,
                          groups: p.cheatsheet.groups.map(function(g) { return g.name }),
                          shown: p.cheatsheet.shown.map(function(g) { return g.name }),
                          items: p.cheatsheet.shown.reduce(function(n, g) { return n + g.items.length }, 0),
                          other: p.cheatsheet.groups.filter(function(g) { return g.name === "Other" }).length } }
    }

    function badge(p) { var t = find(p.pillItem, "updateBadge"); return t && t.visible ? t.text : "" }
    // Window (= screen) coordinates of a named item's centre, for real clicks; null if hidden.
    function center(p, name, within) {
        var t = find(within || p.tierItem, name)
        if (!t || !t.visible || t.width === 0) return null
        var c = t.mapToItem(null, t.width / 2, t.height / 2)
        return [Math.round(c.x), Math.round(c.y), Math.round(t.width)]
    }
    function spinning(p, name) { var t = find(p.tierItem, name); return t ? t.spinning : null }
    function box(item) { return [item.x, item.y, item.width, item.height] }
    function find(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
            var hit = find(item.children[i], name); if (hit) return hit
        }
        return null
    }
    function clockSpan(p) {
        var t = find(p.pillItem, "pillClock")
        return t && t.visible ? [t.x, t.x + t.width, t.text] : null
    }
    // x spans of the bar row's visible items, to check nothing sits under the centre text.
    function rowSpans(p) {
        var row = null, stack = [p.pillItem]
        while (stack.length && !row) {
            var it = stack.pop()
            if (it.objectName === "pillRow") row = it
            else for (var i = 0; i < it.children.length; i++) stack.push(it.children[i])
        }
        if (!row) return []
        var spans = []
        for (var j = 0; j < row.children.length; j++) {
            var c = row.children[j]
            if (c.visible && c.width > 0 && c.implicitWidth > 0)
                spans.push([row.x + c.x, row.x + c.x + c.width, c.implicitWidth])
        }
        return spans
    }

    function frameState(frame) {
        var reserves = []
        for (var i = 0; i < frame.data.length; i++) {
            var item = frame.data[i]
            if (item.edge === undefined) continue
            reserves.push({ edge: item.edge, visible: item.visible,
                zone: item.exclusiveZone, anchors: { top: item.anchors.top, bottom: item.anchors.bottom,
                    left: item.anchors.left, right: item.anchors.right },
                maskEmpty: item.mask !== null && item.mask.width === 0 && item.mask.height === 0,
                focus: item.focusable })
        }
        return { name: frame.monitorName, width: frame.width, height: frame.height,
            visible: frame.visible, fullscreen: frame.fullscreen,
            bottom: frame.bottomReserve, reserves: reserves,
            maskEmpty: frame.mask !== null && frame.mask.width === 0 && frame.mask.height === 0,
            ignoreReserves: frame.exclusionMode === ExclusionMode.Ignore,
            focus: frame.focusable }
    }

    IpcHandler {
        target: "frameTest"
        function fullscreen(main: bool, secondary: bool): void {
            root.mainFullscreen = main
            root.secondaryFullscreen = secondary
        }
        function classic(enabled: bool): void { root.classicBar = enabled }
        function secondary(enabled: bool): void {
            root.monitorNames = enabled ? ["DP-2", "HDMI-A-1"] : ["DP-2"]
        }
        function capture(): void {
            frames.instances[0].outline.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("HOME") + "/frame.png")
            })
        }
        function pill(action: string): void {
            var p = pills.instances[0]
            if (action === "open") p.open(); else if (action === "close") p.close()
            else if (action === "closeSurface") p.closeSurface()
            else if (action === "unread") Notifs.unreadCount = 3
            else if (p.surfaces.indexOf(action) >= 0) p.openSurface(action, true)
            else p.toggle()
        }
        function pillOn(name: string): void { root.pillNames = [name] }
        // Edge drawers (4.5): fake toasts straight into the model, the OSD by kind.
        property int nextToast: 1000
        function toast(count: int, timeoutMs: int): void {
            for (var i = 0; i < count; i++)
                Notifs.pushToast({ notifId: nextToast++, appName: "Test", summary: "Toast " + i,
                                   body: "body", urgency: 1, toastTimeout: timeoutMs })
        }
        function toastDismiss(): void { Notifs.dismiss(Notifs.toastModel.get(0).notifId) }
        function osd(kind: string): void { pills.instances[0].drawers.showOsd(kind) }
        function drawerCapture(): void {
            pills.instances[0].drawers.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("HOME") + "/drawers.png")
            })
        }
        function dashTab(name: string): void { pills.instances[0].dashboard.tab = name }
        function dashChoose(index: int): void {
            var d = pills.instances[0].dashboard; d.chosen = d.others[index]
        }
        function pillCapture(): void {
            pills.instances[0].shape.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("HOME") + "/pill.png")
            })
        }
        // 6.1 polkit: start (one or two identities), a failed attempt, or the request ending.
        function polkit(action: string): void {
            var f = fakeFlow
            if (action === "start" || action === "startTwo") {
                root.polkitFlow = null
                f.identities = action === "startTwo" ? [idSuraj, idWheel] : [idSuraj]
                f.selectedIdentity = idSuraj
                f.isResponseRequired = true; f.failed = false; f.isCompleted = false
                f.supplementaryMessage = ""; f.submitted = []; f.cancels = 0
                root.polkitFlow = f
            } else if (action === "fail") { f.failed = true; f.isResponseRequired = true }
            else if (action === "done") f.isCompleted = true
        }
        // fieldFocus is in-window focus: activeFocus also needs the window activated, which
        // takes a window manager (live, the prompt's exclusive keyboard focus does it).
        function polkitState(): string {
            var w = polkitDialog.window
            var field = root.find(w.contentItem, "polkitField"), err = root.find(w.contentItem, "polkitError")
            var chip = root.find(w.contentItem, "identity:wheel")
            var c = chip && chip.visible ? chip.mapToItem(null, chip.width / 2, chip.height / 2) : null
            return JSON.stringify({ open: w.visible, submitted: fakeFlow.submitted, cancels: fakeFlow.cancels,
                field: field.text, fieldFocus: field.focus, error: err.visible ? err.text : "",
                selected: fakeFlow.selectedIdentity.string, wheel: c ? [Math.round(c.x), Math.round(c.y)] : null })
        }
        // Centre of a nested named item in the open tier, "lockSec/choice:5 min"; null if hidden.
        function where(path: string): string {
            var item = pills.instances[0].tierItem
            path.split("/").forEach(function(name) { item = item ? root.find(item, name) : null })
            if (!item || !item.visible || item.width === 0) return "null"
            var c = item.mapToItem(null, item.width / 2, item.height / 2)
            return JSON.stringify([Math.round(c.x), Math.round(c.y)])
        }
        function status(): string {
            return JSON.stringify({ layout: Config.appearance.layout, builds: root.frameBuilds,
                frames: frames.instances.map(function(frame) { return root.frameState(frame) }),
                pills: pills.instances.map(function(p) { return root.pillState(p) }) })
        }
    }
}
