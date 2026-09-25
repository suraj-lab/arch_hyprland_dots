pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth power via BlueZ (Quickshell.Bluetooth), replacing bluetoothctl polling.
// Device list/pairing arrive with the Phase 6 Bluetooth UI.
Singleton {
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: !!(adapter && adapter.enabled)
    function toggle() { if (adapter) adapter.enabled = !adapter.enabled }
}
