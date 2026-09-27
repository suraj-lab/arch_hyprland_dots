pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth via BlueZ (Quickshell.Bluetooth): power, device list, scan, pair/trust/connect
// (SPEC 6.2). No pairing agent: devices that ask for a PIN or passkey cannot pair here.
Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: !!(adapter && adapter.enabled)
    readonly property bool scanning: !!(adapter && adapter.discovering)
    function toggle() { if (adapter) adapter.enabled = !adapter.enabled }

    readonly property var devices: adapter ? sortDevices(adapter.devices.values.map(entry)) : []
    function entry(d) {
        return { address: d.address, name: d.name || d.deviceName, icon: d.icon, connected: d.connected,
                 paired: d.paired, trusted: d.trusted, pairing: d.pairing,
                 busy: d.pairing || d.state === BluetoothDeviceState.Connecting
                       || d.state === BluetoothDeviceState.Disconnecting,
                 battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1 }
    }
    // Connected, then paired, then by name; unnamed unpaired devices (BLE beacons that only
    // show an address) are left out.
    function sortDevices(list) {
        return list.filter(function(d) { return d.paired || (d.name !== "" && d.name.replace(/[-:]/g, "") !== d.address.replace(/:/g, "")) })
                   .sort(function(a, b) {
                       if (a.connected !== b.connected) return a.connected ? -1 : 1
                       if (a.paired !== b.paired) return a.paired ? -1 : 1
                       return a.name.localeCompare(b.name)
                   })
    }
    function find(address) {
        return adapter ? adapter.devices.values.find(function(d) { return d.address === address }) || null : null
    }

    // Scan for 30 s per call; the surface calls it again while it stays open.
    function scan() {
        if (!enabled) return
        adapter.discovering = true
        scanStop.restart()
    }
    Timer { id: scanStop; interval: 30000; onTriggered: if (root.adapter) root.adapter.discovering = false }

    // A new device: pair, then trust (so it reconnects by itself), then connect.
    property string pending: ""
    readonly property var pendingDevice: find(pending)
    function connect(address) {
        var d = find(address)
        if (!d) return
        if (d.paired) { d.connect(); return }
        pending = address
        d.pair()
    }
    function disconnect(address) { var d = find(address); if (d) d.disconnect() }
    function forget(address) { var d = find(address); if (d) d.forget() }
    Connections {
        target: root.pendingDevice
        function onPairedChanged() {
            var d = root.pendingDevice
            if (!d.paired) return
            d.trusted = true
            d.connect()
            root.pending = ""
        }
        function onPairingChanged() { if (!root.pendingDevice.pairing && !root.pendingDevice.paired) root.pending = "" }
    }
}
