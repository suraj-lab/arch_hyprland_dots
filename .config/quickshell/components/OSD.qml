import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Item {
    id: root
    property color barAccent: "#00ffea"
    anchors.fill: parent

    // ── State ──────────────────────────────────────────────────────────────
    readonly property real volume: Audio.volume
    property real prevVolume: -1
    readonly property bool muted: Audio.muted
    property bool prevMuted: false
    property bool osdVisible: false

    // ── Show/hide logic ────────────────────────────────────────────────────
    function showOSD() {
        osdVisible = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: Theme.osdHideDelay
        onTriggered: osdVisible = false
    }

    // ── Show on change (skip the first reading), driven by PipeWire events ──
    function check() {
        if (!Audio.ready) return
        // Read Audio directly: this handler may run before root.volume's binding updates.
        var v = Audio.volume, m = Audio.muted
        if (root.prevVolume >= 0 && (Math.abs(v - root.prevVolume) > 0.005 || m !== root.prevMuted))
            root.showOSD()
        root.prevVolume = v
        root.prevMuted = m
    }
    Connections {
        target: Audio
        function onVolumeChanged() { root.check() }
        function onMutedChanged() { root.check() }
        function onReadyChanged() { root.check() }
    }
    Component.onCompleted: check()

    // ── Visual ─────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: osdVisible ? Theme.osdBottomMargin : Theme.osdBottomMargin - 20
        width: Theme.osdWidth
        height: Theme.osdHeight
        radius: Theme.osdRadius
        color: Theme.popupBg
        border.color: Theme.border
        border.width: 1
        opacity: osdVisible ? 1.0 : 0.0
        visible: opacity > 0
        scale: osdVisible ? 1.0 : 0.85
        transformOrigin: Item.Bottom

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 18
                rightMargin: 18
            }
            spacing: 14

            // Icon
            Text {
                text: {
                    if (root.muted) return "\uf6a9"
                    if (root.volume > 0.5) return "\uf028"
                    if (root.volume > 0) return "\uf027"
                    return "\uf026"
                }
                color: root.muted ? Theme.error : root.barAccent
                font.pixelSize: 18
                font.family: Theme.fontFamily
            }

            // Progress bar
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Theme.trackBg

                Rectangle {
                    width: parent.width * Math.min(1.0, root.muted ? 0 : root.volume)
                    height: parent.height
                    radius: 3
                    color: root.muted ? Theme.error : root.barAccent
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            // Percentage
            Text {
                text: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
                color: root.muted ? Theme.error : root.barAccent
                font.pixelSize: Theme.fontBar
                font.bold: true
                font.family: Theme.fontFamily
                Layout.minimumWidth: 48
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
