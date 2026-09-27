pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Update notifier (SPEC 6.4). Read-only checks, 90 s after start, then hourly, and on demand
// (`qs ipc call updates check`): checkupdates (pacman-contrib; syncs into its own temporary
// database, so pacman's is untouched), flatpak remote-ls --updates, and paru -Qua when paru
// exists (AUR, informational). Nothing here ever upgrades; update() only opens a terminal.
Singleton {
    id: root

    // Per source: { count, items, ok, present }. count -1 = not known (never checked or failed).
    property var pacman: ({ count: -1, items: [], ok: false, present: true })
    property var aur: ({ count: -1, items: [], ok: false, present: false })
    property var flatpak: ({ count: -1, items: [], ok: false, present: false })
    readonly property int total: Math.max(0, pacman.count) + Math.max(0, aur.count) + Math.max(0, flatpak.count)
    readonly property bool checking: proc.running
    property real lastChecked: 0         // ms since epoch; 0 = never

    // `name old -> new` lines (checkupdates, paru -Qua) or one app id per line (flatpak).
    // Each section ends with "@<name>-exit <code>"; 127 = tool not installed.
    function parse(text) {
        var out = {}, name = "", lines = []
        text.split("\n").forEach(function(line) {
            var head = line.match(/^@(pacman|aur|flatpak)$/)
            var tail = line.match(/^@(pacman|aur|flatpak)-exit (\d+)$/)
            if (head) { name = head[1]; lines = [] }
            else if (tail && tail[1] === name) {
                var code = Number(tail[2])
                // checkupdates: 2 = none; paru -Qua: 1 with no output = none; flatpak: 0.
                var ok = code === 0 || (name === "pacman" && code === 2) || (name === "aur" && code === 1 && !lines.length)
                out[name] = { count: ok ? lines.length : -1, items: ok ? lines : [], ok: ok, present: code !== 127 }
                name = ""
            } else if (name && line.trim()) lines.push(line.trim().split(/\s+/)[0])
        })
        return out
    }
    // The terminal command behind the Update button. paru without arguments upgrades the
    // repos and the AUR; without paru, pacman. Rechecks when done so the badge clears.
    function updateCommand(hasParu, flatpakUpdates) {
        return (hasParu ? "paru" : "sudo pacman -Syu")
            + (flatpakUpdates > 0 ? "; flatpak update" : "")
            + "; qs ipc call updates check >/dev/null 2>&1; printf '\\nDone. Press Enter to close. '; read _"
    }

    function check() { if (!proc.running) proc.running = true }
    function update() {
        var cmd = "ghostty -e sh -c " + "'" + updateCommand(aur.present, flatpak.count).replace(/'/g, "'\\''") + "'"
        Hypr.dispatch("hl.dsp.exec_cmd(" + JSON.stringify(cmd)
            + ", { float = true, size = { \"60%\", \"60%\" }, center = true })")
    }

    Process {
        id: proc
        command: ["sh", "-c",
            "printf '@pacman\\n'; timeout 120 checkupdates 2>/dev/null; printf '@pacman-exit %s\\n' $?\n"
            + "printf '@flatpak\\n'; if command -v flatpak >/dev/null; then timeout 120 flatpak remote-ls --updates --columns=application 2>/dev/null;"
            + " printf '@flatpak-exit %s\\n' $?; else printf '@flatpak-exit 127\\n'; fi\n"
            + "printf '@aur\\n'; if command -v paru >/dev/null; then timeout 120 paru -Qua 2>/dev/null;"
            + " printf '@aur-exit %s\\n' $?; else printf '@aur-exit 127\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parse(text)
                var names = ["pacman", "aur", "flatpak"]
                // A failed source keeps its last good count rather than dropping to unknown.
                names.forEach(function(n) {
                    if (!r[n]) return
                    root[n] = r[n].ok || root[n].count < 0 ? r[n] : Object.assign({}, root[n], { ok: false, present: r[n].present })
                })
                root.lastChecked = Date.now()
            }
        }
    }
    Timer { interval: 90 * 1000; running: true; onTriggered: root.check() }
    Timer { interval: 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.check() }

    IpcHandler {
        target: "updates"
        function check(): void { root.check() }
        function status(): string {
            return JSON.stringify({ checking: root.checking, total: root.total, lastChecked: root.lastChecked,
                                    pacman: root.pacman, aur: root.aur, flatpak: root.flatpak })
        }
    }
}
