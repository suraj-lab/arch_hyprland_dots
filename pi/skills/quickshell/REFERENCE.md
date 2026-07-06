# Quickshell Reference

Detailed Quickshell APIs, system integrations, and component-specific notes. Use when the lean skill is not enough.

## Quickshell APIs

### NotificationServer
```qml
import Quickshell.Services.Notifications

NotificationServer { id: notifServerInst; keepOnReload: true }

Connections {
    target: notifServerInst
    function onNotification(n) {
        n.tracked = true
        // n.id, n.appName, n.summary, n.body, n.urgency, n.expireTimeout
    }
}

// Dismiss:
n.tracked = false
n.close()

// DOES NOT EXIST:
// notifServerInst.notifications
// notifServerInst.doNotDisturb
// Must manage own: history ListModel, DND state, unread count
```

### Mpris
```qml
import Quickshell.Services.Mpris

// Singleton — do not instantiate
Mpris.players.values
// player: trackTitle, trackArtist, trackAlbum, trackArtUrl,
//         identity, playbackState, position, length,
//         canTogglePlaying, canGoNext, canGoPrevious, canSeek
// player.togglePlaying(), player.next(), player.previous()
// player.position = seconds (seek)
// MprisPlaybackState.Playing / .Paused / .Stopped
```

### IpcHandler
```qml
import Quickshell.Io

IpcHandler {
    target: "launcher"
    function toggle() { ... }
}
// Called via: qs msg launcher toggle
// Function names map directly to qs msg arguments
```

### Hyprland.toplevels — reactive window list
```qml
import Quickshell.Hyprland

// Reactive binding — re-evaluates whenever refreshToplevels() is called
property var allClients: {
    var result = []
    var tvs = Hyprland.toplevels.values
    for (var i = 0; i < tvs.length; i++) {
        var t = tvs[i]
        var info = (t.lastIpcObject != null) ? t.lastIpcObject : {}
        result.push({
            wayland:   t.wayland,        // Wayland handle for ScreencopyView
            address:   info.address,     // Use info.address NOT t.address — info has "0x" prefix
            at:        info.at,          // [x, y] array
            size:      info.size,        // [w, h] array
            workspace: info.workspace,   // { id: int, name: str }
            monitor:   info.monitor,     // monitor ID integer
            title:     info.title,
            "class":   info["class"]     // bracket notation — class is reserved word
        })
    }
    return result
}

// CRITICAL: toplevels.values does NOT self-update — must call this to trigger binding:
Hyprland.refreshToplevels()

// Subscribe to window events to keep data live:
Connections {
    target: Hyprland
    function onRawEvent(ev) {
        var n = ev.name
        if (n === "openwindow" || n === "closewindow" || n === "movewindow") {
            Hyprland.refreshToplevels()
        }
    }
}

// GOTCHA: Hyprland.monitors reactive API is unverified — use hyprctl monitors -j Process instead
// GOTCHA: Special workspace windows have negative workspace IDs (e.g. -98)
// GOTCHA: t.address has NO "0x" prefix — use info.address from lastIpcObject instead
```

### ScreencopyView — live window thumbnails
```qml
import Quickshell.Wayland   // required — NOT Quickshell.Widgets (does not exist)

// Pattern: Loader inside Rectangle with clip:true
Rectangle {
    radius: 4
    clip: true   // REQUIRED — ScreencopyView ignores radius without this

    // Coloured fallback stays as background — ScreencopyView overlays it when ready
    color: Qt.rgba(winCol.r, winCol.g, winCol.b, 0.08)
    border.color: Qt.rgba(winCol.r, winCol.g, winCol.b, 0.4)

    Loader {
        anchors.fill: parent
        anchors.margins: 1
        active: modelData.wayland != null   // REQUIRED — null handle crashes
        sourceComponent: Component {
            ScreencopyView {
                anchors.fill: parent
                captureSource: modelData.wayland   // t.wayland from toplevels
                live: false          // static capture on instantiation; true = GPU-expensive
                paintCursor: false
                visible: hasContent  // REQUIRED — hides blank holes for minimised/X11 windows
            }
        }
    }
}
// live: false captures once when Loader activates. Re-activating the Loader re-captures.
// live: true follows monitor refresh rate — only use while overview is actually visible.
```

### DesktopEntries
```qml
var apps = DesktopEntries.applications.values
    .filter(e => !e.noDisplay)
    .sort((a, b) => a.name.localeCompare(b.name))
// entry.execute()
// Quickshell.iconPath(entry.icon ?? "")
```

### SystemClock
```qml
SystemClock { id: clock; precision: SystemClock.Minutes }
// clock.date → JS Date object
// Qt.formatDateTime(clock.date, "HH:mm")
```

### PanelWindow / PopupWindow
```qml
// Bar panel
PanelWindow {
    anchors { top: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell"
    exclusionMode: ExclusionMode.Normal
}

// Full-screen overlay
PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
}

// Dropdown popup
PopupWindow {
    anchor.item: root
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
}
```

### Shell pragmas
```qml
//@ pragma Env QT_IMAGEIO_MAXALLOC=512
//@ pragma UseQApplication
//@ pragma Env QT_QPA_PLATFORMTHEME=gtk3
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
```

## Notification System

### Data flow
```
App → D-Bus → NotificationServer.onNotification(n)
  → n.tracked = true
  → Strip HTML from body
  → Append to notifHistoryModel
  → Store in notifMap[n.id]
  → IF DND: return (stored, no toast/badge)
  → Increment notifUnreadCount
  → Limit toasts to 4 (remove oldest)
  → Calculate timeout (default 5000ms, urgency 2 → infinite)
  → Append to toastModelInst
```

### Dismissal
```qml
function dismissNotif(id) {
    var n = notifMap[id]
    if (n) { n.tracked = false; try { n.close() } catch(e) {} }

    // Remove from toast model, history model, notifMap (new reference)
}
```

### ListModel delegate access
Use `model.roleName` NOT `modelData.roleName` in Repeater delegates.

## MPRIS Track Toasts
```qml
property int _mprisToastId: -1  // small negative int, NOT Date.now()

// "art:" prefix triggers album art thumbnail in NotificationToasts.qml
toastModelInst.append({
    notifId:      _mprisToastId--,
    appName:      player.identity,
    summary:      player.trackTitle,
    body:         "art:" + player.trackArtUrl,
    urgency:      0,
    toastTimeout: 3000
})
// Wrap all player access in try/catch — players can be destroyed mid-access
```

## Hardware Integration

### Brightness (DDC/CI — no backlight on desktop)
```bash
# ViewSonic VX2476: bus 8 | Dell AW3423DWF: bus 10
ddcutil getvcp 10 --bus 8 --brief
ddcutil setvcp 10 X --bus 8 --noverify & ddcutil setvcp 10 X --bus 10 --noverify & wait
```
- DDC/CI is slow (~1-2s) — use --noverify + optimistic UI updates
- Only read on popup open, NOT polled — prevents slider reset race
- Minimum clamped to 5%
- Requires i2c-dev kernel module loaded

### Volume (wpctl)
```bash
wpctl get-volume @DEFAULT_AUDIO_SINK@    # returns "Volume: 0.50 [MUTED]"
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.65
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
```
Polled every 1000ms for OSD change detection.

### Audio devices (pactl)
```bash
pactl -f json list sinks
pactl -f json list sources          # filter out .monitor entries
pactl -f json list sink-inputs      # often lack application.name
pactl -f json list clients          # cross-reference for app names
pactl get-default-sink
pactl set-default-sink <name>
```

### Wallpaper (awww — swww is deprecated)
```bash
awww img /path/to/image -o DP-2 --transition-type fade --transition-pos center --transition-duration 1
# Transitions: fade, left, right, top, bottom, wipe, grow, center, outer, wave
```

### Screenshots
```bash
# Always background wl-copy — it blocks otherwise
wl-copy < file &
```
Add 100-200ms Timer before loading freshly-written PNG into Image.
Set `cache: false` on dynamically-loaded Images.

### Accent extraction pipeline
1. `extract-accent.sh <image> <monitor-name>`
2. matugen: `matugen image "$IMG" -j hex --dry-run --source-color-index 0 --type scheme-vibrant -m dark`
   - `--source-color-index 0` is required (without it: interactive prompt → fails in scripts)
3. Falls back to ImageMagick + Python saturation picker
4. Boosts saturation ≥0.75, value 0.7-0.92 (Material You colors too muted for neon aesthetic)
5. Writes to `~/.cache/quickshell/accent-<monitor>`
6. Notifies via `qs msg accent update`
