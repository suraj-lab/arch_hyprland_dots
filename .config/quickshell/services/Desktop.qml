pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop — the "desktop environment" glue that Hyprland doesn't
// provide on its own:
//   • Idle management (lock → screens off → optional suspend). hypridle
//     handles lock-session / sleep hooks only. Respects Wayland idle
//     inhibitors, Caffeine, and Desktop Game Mode.
//   • Caffeine (manual idle inhibit; the IdleInhibitor itself lives on the
//     bar window in shell.qml because it needs a surface).
//   • Night Light (hyprsunset schedule daemon on/off).
//   • Desktop Game Mode: auto-on while gamemoded is active — DND on, blur/
//     animations off, no inactive-window dimming — restored when it ends.
//
// The SteamOS-style Gaming Mode (Super+Shift+S) is separate and untouched;
// enterGamingMode() just calls the existing switch-to-gaming helper.

Item {
    id: root
    visible: false

    // ── Settings (seconds; 0 disables that stage) ─────────────────────────
    readonly property int lockTimeout:    Config.idle.lockSec
    readonly property int dpmsTimeout:    Config.idle.dpmsSec
    readonly property int suspendTimeout: Config.idle.suspendSec
    property string nightLightCmd: "hyprsunset"   // schedule in ~/.config/hypr/hyprsunset.conf

    // ── Wiring to ShellRoot's DND state ───────────────────────────────────
    property bool dndEnabled: false
    signal dndRequested(bool enabled)

    // ── Public state ──────────────────────────────────────────────────────
    property bool caffeine: false
    property bool nightLight: false
    property bool gamemodedActive: false
    property string gameModeOverride: "auto"    // "auto" | "on" | "off"
    property bool gameMode: false             // last acknowledged backend state
    property string gameModeError: ""
    readonly property bool desiredGameMode: gameModeOverride === "on"
                                            || (gameModeOverride !== "off" && gamemodedActive)
    readonly property bool idleEnabled: !caffeine && !gameMode

    readonly property string idleStatus: caffeine ? "Paused · caffeine"
                                       : gameMode ? "Paused · game mode"
                                       : "Active"

    function toggleCaffeine()   { caffeine = !caffeine }
    function toggleNightLight() {
        if (nightReadProc.running || nightOffProc.running) return
        if (nightLight) { nightOffProc.running = true; return }
        // Detached: a shell-owned child would die whenever Quickshell restarts.
        Quickshell.execDetached(["bash", "-c", nightLightCmd])
        nightLight = true   // the 5 s poll corrects this if hyprsunset fails to start
    }
    function toggleGameMode() {
        // Off suppresses only a currently running game, never the next session.
        gameModeOverride = desiredGameMode ? (gamemodedActive ? "off" : "auto") : "on"
    }
    function enterGamingMode() {
        Quickshell.execDetached(["/usr/local/bin/switch-to-gaming"])
    }

    // ── Desktop Game Mode side effects ────────────────────────────────────
    property bool _gamemodedKnown: false
    property bool _gameChecked: false

    function syncGameMode() {
        if (gameModeProc.running || !_gamemodedKnown) return
        if (_gameChecked && desiredGameMode === gameMode && !gameModeError) return
        gameModeProc.command = ["python3", Quickshell.shellDir + "/scripts/desktop-gamemode.py",
                                desiredGameMode ? "on" : "off", dndEnabled ? "true" : "false"]
        gameModeProc.running = true
    }

    onDesiredGameModeChanged: Qt.callLater(root.syncGameMode)
    onGamemodedActiveChanged: {
        if (!gamemodedActive && gameModeOverride === "off") gameModeOverride = "auto"
    }

    Process {
        id: gameModeProc
        stdout: StdioCollector { id: gameResult }
        stderr: StdioCollector { id: gameError }
        onExited: function(code) {
            try {
                if (code !== 0) throw new Error(gameError.text.trim() || "Game Mode helper failed")
                var result = JSON.parse(gameResult.text)
                if (typeof result.gameMode !== "boolean" || typeof result.dnd !== "boolean")
                    throw new Error("Invalid Game Mode response")
                root.gameMode = result.gameMode
                root.dndRequested(result.dnd)
                root._gameChecked = true
                root.gameModeError = ""
                // A click during the previous command must not get dropped.
                Qt.callLater(root.syncGameMode)
            } catch (error) {
                root.gameModeError = String(error)
                console.warn(root.gameModeError) // retry on the next poll, not a busy loop
            }
        }
    }

    // An unreadable status is not evidence that the game exited.
    Process {
        id: gamemodedProc
        command: ["gamemoded", "-s"]
        running: true
        stdout: StdioCollector { id: gamemodedResult }
        onExited: function(code) {
            var state = gamemodedResult.text.trim()
            if (code !== 0 || (state !== "gamemode is active" && state !== "gamemode is inactive")) {
                console.warn("Cannot read gamemoded status: " + state)
                return
            }
            root.gamemodedActive = state === "gamemode is active"
            root._gamemodedKnown = true
            root.syncGameMode() // also recovers a saved snapshot on shell startup
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: {
            if (!gamemodedProc.running) gamemodedProc.running = true
            if (!nightReadProc.running) nightReadProc.running = true
            root.syncGameMode()
        }
    }

    // Reflect external starts/stops as well as our own toggles.
    Process {
        id: nightReadProc
        command: ["pgrep", "-x", "hyprsunset"]
        running: true
        onExited: function(code) { root.nightLight = (code === 0) }
    }
    Process {
        id: nightOffProc
        command: ["pkill", "-x", "hyprsunset"]
        onExited: nightReadProc.running = true
    }

    // ── Idle chain ────────────────────────────────────────────────────────
    Process { id: lockProc;    command: ["bash", "-c", "pidof hyprlock >/dev/null || hyprlock"] }
    Process { id: dpmsOffProc; command: ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\" })"] }
    Process { id: dpmsOnProc;  command: ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"on\" })"] }
    Process { id: suspendProc; command: ["systemctl", "suspend"] }

    IdleMonitor {
        enabled: root.idleEnabled && root.lockTimeout > 0
        timeout: root.lockTimeout
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) lockProc.running = true
    }

    IdleMonitor {
        enabled: root.idleEnabled && root.dpmsTimeout > 0
        timeout: root.dpmsTimeout
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) dpmsOffProc.running = true
            else        dpmsOnProc.running = true
        }
    }

    IdleMonitor {
        enabled: root.idleEnabled && root.suspendTimeout > 0
        timeout: root.suspendTimeout
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) suspendProc.running = true
    }

    // ── IPC: qs ipc call desktop <fn>─────────────────────────────────────────
    IpcHandler {
        target: "desktop"
        function toggleCaffeine():   void { root.toggleCaffeine() }
        function toggleNightLight(): void { root.toggleNightLight() }
        function toggleGameMode():   void { root.toggleGameMode() }
        function enterGamingMode():  void { root.enterGamingMode() }
        function status(): string {
            return "caffeine=" + root.caffeine + " nightLight=" + root.nightLight
                 + " gameMode=" + root.gameMode + " (override=" + root.gameModeOverride
                 + ", gamemoded=" + root.gamemodedActive + ", known=" + root._gamemodedKnown
                 + ", desired=" + root.desiredGameMode + ") idle=" + root.idleStatus
                 + " error=" + root.gameModeError
        }
    }
}
