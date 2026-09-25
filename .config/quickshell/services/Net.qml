pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Wi-Fi state, network list and connect via NetworkManager (Quickshell.Networking),
// replacing nmcli polling. Values arrive over D-Bus about 1 s after startup.
Singleton {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var wifiDevice: Networking.devices.values.find(function(d) {
        return d.type === DeviceType.Wifi
    }) || null
    readonly property string ssid: {
        var n = wifiDevice ? wifiDevice.networks.values.find(function(x) { return x.connected }) : null
        return n ? n.name : ""
    }
    // Same item shape the System tab used with nmcli: connected first, then by signal.
    readonly property var networks: wifiDevice ? sortNetworks(wifiDevice.networks.values) : []

    function entry(n) {
        return { inUse: n.connected, ssid: n.name, signal: Math.round(n.signalStrength * 100),
                 known: n.known,
                 security: n.security === WifiSecurityType.Open ? "" : WifiSecurityType.toString(n.security) }
    }
    function sortNetworks(list) {
        return list.filter(function(n) { return n.name !== "" })   // hidden networks have no name
                   .map(entry)
                   .sort(function(a, b) {
                       if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
                       return b.signal - a.signal
                   })
    }

    function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }

    // Scan for 30 s per call; the network list calls this again while it stays open.
    function scan() {
        if (!wifiDevice) return
        wifiDevice.scannerEnabled = true
        scanStop.restart()
    }
    Timer { id: scanStop; interval: 30000; onTriggered: if (root.wifiDevice) root.wifiDevice.scannerEnabled = false }

    function connect(ssid) {
        var n = wifiDevice ? wifiDevice.networks.values.find(function(x) { return x.name === ssid }) : null
        if (!n) return
        if (n.known || n.security === WifiSecurityType.Open) { n.connect(); return }
        // New secured network: no password prompt in the shell yet (Phase 6), so keep the
        // terminal fallback. The SSID is untrusted (anyone can broadcast one): single-quoted
        // for sh, then a JSON string, which Lua reads as the same string.
        // ponytail: SSIDs with control characters produce \uXXXX, which Lua rejects, so that
        // connect fails (safely); goes away with the Phase 6 prompt (connectWithPsk).
        var shellSsid = "'" + ssid.replace(/'/g, "'\\''") + "'"
        Hypr.dispatch("hl.dsp.exec_cmd(" + JSON.stringify("ghostty -e nmcli dev wifi connect " + shellSsid + " --ask")
            + ", { float = true, size = { \"40%\", \"30%\" }, center = true })")
    }
}
