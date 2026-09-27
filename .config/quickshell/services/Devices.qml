pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Removable drives (SPEC 6.3). There is no Quickshell UDisks module: the list comes from
// `lsblk -J`, refreshed whenever `udisksctl monitor` reports a change; actions go through
// udisksctl (polkit asks, via the shell's agent, only if a rule requires it). udiskie
// (autostart) automounts and sends the "device added" toast.
Singleton {
    id: root

    // [{ path, name, size, tran, volumes: [{ path, name, size, fstype, mountpoint }] }]
    property var drives: []
    readonly property int count: drives.length
    property string error: ""
    property string busy: ""              // path of the drive/volume an action is running on

    // Only hotplug/removable disks, and never one with anything mounted outside
    // /run/media (a system disk can never show up here with an Eject button).
    function parse(text) {
        var devices
        try { devices = JSON.parse(text).blockdevices || [] } catch (e) { return [] }
        var out = []
        devices.forEach(function(d) {
            if (d.type !== "disk" || !(d.hotplug || d.rm)) return
            var parts = (d.children || []).length ? d.children : [d]
            var vols = [], system = false
            parts.forEach(function(p) {
                var mounts = (p.mountpoints || []).filter(function(m) { return m })
                if (mounts.some(function(m) { return m.indexOf("/run/media/") !== 0 })) system = true
                if (p.fstype && p.fstype !== "swap")
                    vols.push({ path: p.path, name: p.label || p.name, size: p.size, fstype: p.fstype,
                                mountpoint: mounts[0] || "" })
            })
            if (system || !vols.length) return
            out.push({ path: d.path, name: [d.vendor, d.model].filter(function(x) { return x && x.trim() })
                                             .map(function(x) { return x.trim() }).join(" ")
                                   || (d.tran === "mmc" ? "SD card" : d.name),
                       size: d.size, tran: d.tran || "", volumes: vols })
        })
        return out
    }

    function refresh() { if (!list.running) list.running = true; else pendingRefresh = true }
    property bool pendingRefresh: false
    Process {
        id: list
        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,SIZE,FSTYPE,MOUNTPOINTS,HOTPLUG,RM,TYPE,VENDOR,MODEL,TRAN"]
        stdout: StdioCollector { onStreamFinished: { root.drives = root.parse(text); if (root.pendingOpen && !act.running) root.openPending() } }
        onExited: if (root.pendingRefresh) { root.pendingRefresh = false; running = true }
    }
    Component.onCompleted: refresh()

    // Every udisks change prints a line; a burst (plugging in one stick) becomes one refresh.
    Process {
        id: monitor
        command: ["udisksctl", "monitor"]
        running: true
        stdout: SplitParser { onRead: debounce.restart() }
        onExited: restartMonitor.start()    // udisks restarted or not yet up: try again
    }
    Timer { id: debounce; interval: 300; onTriggered: root.refresh() }
    Timer { id: restartMonitor; interval: 5000; onTriggered: monitor.running = true }

    // Open: mount first when needed; the refresh after it finds the mount point, then thunar.
    property string pendingOpen: ""
    function open(volume) {
        if (volume.mountpoint) { Quickshell.execDetached(["thunar", volume.mountpoint]); return }
        pendingOpen = volume.path
        mount(volume)
    }
    function openPending() {
        var path = pendingOpen
        pendingOpen = ""
        drives.forEach(function(d) { d.volumes.forEach(function(v) {
            if (v.path === path && v.mountpoint) Quickshell.execDetached(["thunar", v.mountpoint])
        }) })
    }
    function mount(volume) { run(volume.path, ["udisksctl", "mount", "-b", volume.path]) }
    function unmount(volume) { run(volume.path, ["udisksctl", "unmount", "-b", volume.path]) }
    // Eject: unmount each mounted volume, then power the drive off (safe to unplug).
    function eject(drive) {
        var mounted = drive.volumes.filter(function(v) { return v.mountpoint }).map(function(v) { return v.path })
        run(drive.path, ["sh", "-c", 'd=$1; shift; for p; do udisksctl unmount -b "$p" || exit 1; done; udisksctl power-off -b "$d"',
                         "sh", drive.path].concat(mounted))
    }
    function run(path, command) {
        if (act.running) return
        error = ""
        busy = path
        act.command = command
        act.running = true
    }
    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            // udisksctl: "Error unmounting /dev/sdb1: ...: target is busy" -> the part after the path.
            if (code !== 0) {
                root.pendingOpen = ""
                root.error = (actErr.text.trim().split("\n").pop() || "Failed").replace(/^Error [^:]*: (GDBus\.Error:[^ ]+ )?/, "")
            }
            root.busy = ""
            root.refresh()
        }
    }
}
