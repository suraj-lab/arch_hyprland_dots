import QtQuick
import Quickshell.Io
import "../theme"

// Non-visual component — tracks per-app window focus time.
// Polls hyprctl activewindow every 5s, accumulates seconds per app class.
// Persists to ~/.cache/quickshell/screentime.json every 60s.
// Instantiated at ShellRoot level so it runs continuously.

Item {
    id: root
    visible: false  // non-visual

    // ── Exposed state for SystemView ──────────────────────────────────────
    property int todayTotal: 0                // total seconds today
    property var todayApps: ({})              // { "Code": 3600, "firefox": 1200, ... }
    property var weekHistory: []              // [ { date: "2026-05-02", total: 28800 }, ... ]
    property int yesterdayTotal: 0            // for comparison

    // ── Internal tracking state ──────────────────────────────────────────
    property string _currentApp: ""
    property string _todayDate: ""
    property bool _initialized: false

    // ── Formatted accessors ──────────────────────────────────────────────
    function formatTime(secs) {
        if (secs < 60) return "< 1m"
        var h = Math.floor(secs / 3600)
        var m = Math.floor((secs % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    function topApps(limit) {
        var entries = []
        var apps = root.todayApps
        var keys = Object.keys(apps)
        for (var i = 0; i < keys.length; i++) {
            entries.push({ name: keys[i], seconds: apps[keys[i]] })
        }
        entries.sort(function(a, b) { return b.seconds - a.seconds })
        return entries.slice(0, limit || 5)
    }

    function changePercent() {
        if (yesterdayTotal <= 0) return 0
        return Math.round((todayTotal - yesterdayTotal) / yesterdayTotal * 100)
    }

    // ── Date helpers ─────────────────────────────────────────────────────
    function dateStr() {
        var d = new Date()
        return d.getFullYear() + "-" +
               String(d.getMonth() + 1).padStart(2, "0") + "-" +
               String(d.getDate()).padStart(2, "0")
    }

    function dayLabel(dateString) {
        var d = new Date(dateString)
        return ["Su","Mo","Tu","We","Th","Fr","Sa"][d.getDay()]
    }

    // ── Initialization ───────────────────────────────────────────────────
    Component.onCompleted: {
        root._todayDate = dateStr()
        loadProc.running = true
    }

    // ── Load persisted data ──────────────────────────────────────────────
    property var _loadBuf: []

    Process {
        id: loadProc
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/screentime.json\" 2>/dev/null || echo '{}'"]
        stdout: SplitParser {
            onRead: function(line) { root._loadBuf.push(line) }
        }
        onRunningChanged: {
            if (!running) {
                var raw = root._loadBuf.join(""); root._loadBuf = []
                try {
                    var d = JSON.parse(raw)
                    if (d.today === root._todayDate && d.apps) {
                        root.todayApps = d.apps
                        // Recalculate total
                        var total = 0
                        var keys = Object.keys(d.apps)
                        for (var i = 0; i < keys.length; i++) total += d.apps[keys[i]]
                        root.todayTotal = total
                    } else if (d.today && d.apps) {
                        // Data is from a previous day — roll into history
                        var prevTotal = 0
                        var pkeys = Object.keys(d.apps)
                        for (var j = 0; j < pkeys.length; j++) prevTotal += d.apps[pkeys[j]]

                        var hist = d.history || []
                        hist.unshift({ date: d.today, total: prevTotal })
                        if (hist.length > 7) hist = hist.slice(0, 7)
                        root.weekHistory = hist
                        root.todayApps = {}
                        root.todayTotal = 0
                    }

                    if (d.history) {
                        root.weekHistory = (d.history || []).slice(0, 7)
                    }

                    // Set yesterday's total for comparison
                    if (root.weekHistory.length > 0) {
                        root.yesterdayTotal = root.weekHistory[0].total || 0
                    }
                } catch(e) {}
                root._initialized = true
            }
        }
    }

    // ── Poll active window ───────────────────────────────────────────────
    property var _pollBuf: []

    Process {
        id: pollProc
        command: ["hyprctl", "activewindow", "-j"]
        stdout: SplitParser {
            onRead: function(line) { root._pollBuf.push(line) }
        }
        onRunningChanged: {
            if (!running && root._initialized) {
                var raw = root._pollBuf.join(""); root._pollBuf = []
                try {
                    var w = JSON.parse(raw)
                    var cls = w["class"] || ""
                    if (!cls) return

                    // Check for day rollover
                    var today = dateStr()
                    if (today !== root._todayDate) {
                        rollDay()
                        root._todayDate = today
                    }

                    // Accumulate time for the PREVIOUS app (5 seconds since last poll)
                    if (root._currentApp && root._currentApp !== "") {
                        var apps = Object.assign({}, root.todayApps)
                        apps[root._currentApp] = (apps[root._currentApp] || 0) + 5
                        root.todayApps = apps
                        root.todayTotal = root.todayTotal + 5
                    }

                    root._currentApp = cls
                } catch(e) {
                    // No active window (e.g., locked screen)
                    root._currentApp = ""
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true; repeat: true
        onTriggered: pollProc.running = true
    }

    // ── Day rollover ─────────────────────────────────────────────────────
    function rollDay() {
        var hist = root.weekHistory.slice()
        hist.unshift({ date: root._todayDate, total: root.todayTotal })
        if (hist.length > 7) hist = hist.slice(0, 7)
        root.weekHistory = hist
        root.yesterdayTotal = root.todayTotal
        root.todayApps = {}
        root.todayTotal = 0
        saveData()
    }

    // ── Persist to disk ──────────────────────────────────────────────────
    Process { id: saveProc }

    function saveData() {
        var data = {
            today: root._todayDate,
            apps: root.todayApps,
            history: root.weekHistory
        }
        var json = JSON.stringify(data)
        saveProc.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "echo '" + json.replace(/'/g, "'\\''") + "' > \"$HOME/.cache/quickshell/screentime.json\""]
        saveProc.running = true
    }

    Timer {
        interval: 60000  // save every 60 seconds
        running: root._initialized; repeat: true
        onTriggered: saveData()
    }
}
