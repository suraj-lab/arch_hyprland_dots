pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / memory / CPU temperature, read from /proc and hwmon (no subprocess per sample).
// -1 = not read yet. Same meaning as the old vmstat/free chip:
// cpu = 100 - idle% (iowait counts as busy), mem = (total - available) / total.
Singleton {
    id: root

    property int cpu: -1
    property int mem: -1
    property int temp: -1           // °C
    property string tempPath: ""    // resolved once at startup
    property var _lastCpu: null

    function cpuSample(stat) {
        var f = stat.split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number)
        var total = 0
        for (var i = 0; i < f.length; i++) total += f[i]
        return { idle: f[3], total: total }
    }
    function cpuPercent(a, b) {
        var dt = b.total - a.total
        return dt > 0 ? Math.round(100 - 100 * (b.idle - a.idle) / dt) : -1
    }
    function memPercent(meminfo) {
        var t = /MemTotal:\s+(\d+)/.exec(meminfo), a = /MemAvailable:\s+(\d+)/.exec(meminfo)
        return t && a && +t[1] > 0 ? Math.round(100 * (t[1] - a[1]) / t[1]) : -1
    }

    // ponytail: always samples every 3 s (two small procfs reads); gate on chip
    // visibility if it ever shows up in a profile.
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: { stat.reload(); meminfo.reload(); if (root.tempPath) tempFile.reload() }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            var s = root.cpuSample(text())
            if (root._lastCpu) root.cpu = root.cpuPercent(root._lastCpu, s)
            root._lastCpu = s
        }
    }
    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: root.mem = root.memPercent(text())
    }
    FileView {
        id: tempFile
        path: root.tempPath
        onLoaded: { var v = parseInt(text()); root.temp = isNaN(v) ? -1 : Math.floor(v / 1000) }
    }

    // CPU package sensor: k10temp Tctl (AMD), coretemp Package (Intel), zenpower Tdie.
    // hwmon numbering changes between boots, so match by name. The old chip used the
    // first thermal zone, which on this machine is the Wi-Fi card; kept only as fallback.
    Process {
        running: true
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do case \"$(cat \"$h/name\" 2>/dev/null)\" in " +
            "k10temp|coretemp|zenpower) echo \"$h/temp1_input\"; exit;; esac; done; " +
            "[ -r /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp"]
        stdout: StdioCollector { onStreamFinished: root.tempPath = text.trim() }
    }
}
