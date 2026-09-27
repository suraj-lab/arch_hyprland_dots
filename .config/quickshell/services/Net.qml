pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
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
                 known: n.known, busy: n.stateChanging,
                 enterprise: [WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap,
                              WifiSecurityType.Wpa3SuiteB192].indexOf(n.security) >= 0,
                 security: n.security === WifiSecurityType.Open ? "" : WifiSecurityType.toString(n.security) }
    }
    function find(ssid) {
        return wifiDevice ? wifiDevice.networks.values.find(function(x) { return x.name === ssid }) || null : null
    }
    // WPA passphrases are 8-63 characters, or exactly 64 hex digits.
    function validPsk(psk) { return (psk.length >= 8 && psk.length <= 63) || /^[0-9a-fA-F]{64}$/.test(psk) }
    function failText(reason) {
        return reason === ConnectionFailReason.NoSecrets ? "Wrong password"
            : reason === ConnectionFailReason.WifiAuthTimeout ? "Authentication timed out"
            : reason === ConnectionFailReason.WifiNetworkLost ? "Network lost"
            : "Could not connect"
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

    // The network surface (SPEC 6.2) connects inline; failures land in `error` for `pending`.
    property string pending: ""
    property bool pendingNew: false       // a new profile from connectPsk: forget it on failure
    property var error: ({ ssid: "", text: "" })
    readonly property var pendingNetwork: find(pending)
    function track(ssid, isNew) { pending = ssid; pendingNew = isNew; error = { ssid: "", text: "" } }
    function connectKnown(ssid) { var n = find(ssid); if (n) { track(ssid, false); n.connect() } }
    function connectPsk(ssid, psk) {
        var n = find(ssid)
        if (!n || !validPsk(psk)) return
        track(ssid, !n.known)
        n.connectWithPsk(psk)
    }
    function disconnect(ssid) { var n = find(ssid); if (n) n.disconnect() }
    function forget(ssid) { var n = find(ssid); if (n) n.forget() }
    Connections {
        target: root.pendingNetwork
        function onConnectionFailed(reason) {
            root.error = { ssid: root.pending, text: root.failText(reason) }
            if (root.pendingNew) root.pendingNetwork.forget()
            root.pending = ""
        }
        function onConnectedChanged() { if (root.pendingNetwork.connected) root.pending = "" }
    }

    // Hidden networks never appear in the list, so they go through nmcli. The password goes
    // in on stdin (--ask), never in argv, which any process can read from /proc.
    property bool hiddenBusy: hidden.running
    function connectHidden(ssid, psk) {
        if (hidden.running || ssid === "" || (psk !== "" && !validPsk(psk))) return
        error = { ssid: "", text: "" }
        hidden.psk = psk
        hidden.stdinEnabled = true
        hidden.command = ["nmcli", "--ask", "--wait", "45", "device", "wifi", "connect", ssid, "hidden", "yes"]
        hidden.running = true
    }
    Process {
        id: hidden
        property string psk: ""
        // Close stdin after the one answer: a second prompt (wrong password) then fails at
        // once instead of waiting out --wait.
        onStarted: { write(psk + "\n"); psk = ""; stdinEnabled = false }
        stderr: StdioCollector { id: hiddenErr }
        onExited: code => {
            if (code !== 0)
                root.error = { ssid: "(hidden)", text: hiddenErr.text.trim().split("\n").pop() || "Could not connect" }
        }
    }

    function connect(ssid) {
        var n = find(ssid)
        if (!n) return
        if (n.known || n.security === WifiSecurityType.Open) { n.connect(); return }
        // Classic panel only (the frame's network surface asks inline): new secured network,
        // terminal fallback. The SSID is untrusted (anyone can broadcast one): single-quoted
        // for sh, then a JSON string, which Lua reads as the same string.
        // ponytail: SSIDs with control characters produce \uXXXX, which Lua rejects, so that
        // connect fails (safely); the frame's network surface uses connectPsk instead.
        var shellSsid = "'" + ssid.replace(/'/g, "'\\''") + "'"
        Hypr.dispatch("hl.dsp.exec_cmd(" + JSON.stringify("ghostty -e nmcli dev wifi connect " + shellSsid + " --ask")
            + ", { float = true, size = { \"40%\", \"30%\" }, center = true })")
    }
}
