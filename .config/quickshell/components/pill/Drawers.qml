import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

// Edge drawers in frame mode (SPEC 3.5): notification toasts grow from the frame's
// top-right corner; the volume / mic / brightness OSD grows from the right edge. Both are
// the frame's material (EdgeTab). Hosted by PillOverlay, so they hide with it on
// fullscreen. Only the toast drawer takes input (see PillOverlay's mask).
Item {
    id: root
    property color accent: Theme.accent
    property bool animate: true
    property bool osdHere: true      // the OSD shows on the focused monitor only
    property alias toastArea: toastArea
    property alias osdArea: osdArea
    readonly property int toastPadding: 16   // NotificationToasts' own margins

    // ── Toasts ──────────────────────────────────────────────────────────────
    EdgeTab {
        anchors.fill: parent
        corner: true
        tabWidth: toastArea.width
        tabHeight: toastArea.height
    }
    Item {
        id: toastArea
        objectName: "toastDrawer"
        x: parent.width - Theme.frameThickness - width
        y: Theme.frameThickness
        width: Theme.notifDrawerWidth + 2 * root.toastPadding
        height: toasts.implicitHeight
        clip: true
        Behavior on height { NumberAnimation { duration: root.animate ? Theme.morphDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }

        NotificationToasts {
            id: toasts
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: implicitHeight
            toastModel: Notifs.toastModel
            dismissFunc: function(id) { Notifs.dismiss(id) }
        }
    }

    // ── OSD ─────────────────────────────────────────────────────────────────
    property string osdKind: "volume"   // volume / mic / brightness
    property bool osdShown: false
    function showOsd(kind) {
        osdKind = kind
        osdShown = true
        osdHide.restart()
    }
    Timer { id: osdHide; interval: Theme.osdHideDelay; onTriggered: root.osdShown = false }

    // Show on a change, never on the first reading.
    property real prevVolume: -1
    property bool prevMuted: false
    function checkVolume() {
        if (!Audio.ready) return
        var v = Audio.volume, m = Audio.muted   // direct: bindings may not have updated yet
        if (prevVolume >= 0 && (Math.abs(v - prevVolume) > 0.005 || m !== prevMuted)) showOsd("volume")
        prevVolume = v
        prevMuted = m
    }
    readonly property bool micReady: !!(Audio.source && Audio.source.audio)
    readonly property bool micMuted: micReady && Audio.source.audio.muted
    property var prevMic: null
    function checkMic() {
        if (!micReady) return
        if (prevMic !== null && micMuted !== prevMic) showOsd("mic")
        prevMic = micMuted
    }
    property real prevBrightness: -1
    function checkBrightness() {
        if (!Brightness.ready) return
        var b = Brightness.brightness
        if (prevBrightness >= 0 && Math.abs(b - prevBrightness) > 0.005) showOsd("brightness")
        prevBrightness = b
    }
    Connections {
        target: Audio
        function onVolumeChanged() { root.checkVolume() }
        function onMutedChanged() { root.checkVolume() }
        function onReadyChanged() { root.checkVolume() }
    }
    onMicMutedChanged: checkMic()
    onMicReadyChanged: checkMic()
    Connections {
        target: Brightness
        function onBrightnessChanged() { root.checkBrightness() }
        function onReadyChanged() { root.checkBrightness() }
    }
    Component.onCompleted: { checkVolume(); checkMic(); checkBrightness() }

    readonly property real osdLevel: osdKind === "brightness" ? Brightness.brightness
        : osdKind === "mic" ? (micMuted ? 0 : 1) : (Audio.muted ? 0 : Audio.volume)
    readonly property bool osdOff: osdKind === "mic" ? micMuted : osdKind === "volume" && Audio.muted
    readonly property color osdColor: osdOff ? Theme.error : osdKind === "brightness" ? Theme.warning : accent
    readonly property string osdIcon: osdKind === "brightness" ? "\uf185"
        : osdKind === "mic" ? (micMuted ? "\uf131" : "\uf130")
        : Audio.muted ? "\uf6a9" : Audio.volume > 0.5 ? "\uf028" : Audio.volume > 0 ? "\uf027" : "\uf026"
    readonly property string osdText: osdKind === "mic" ? (micMuted ? "off" : "on")
        : osdOff ? "off" : Math.round(osdLevel * 100) + ""

    EdgeTab {
        anchors.fill: parent
        tabWidth: osdArea.width
        tabHeight: osdArea.height
        tabY: osdArea.y
    }
    Item {
        id: osdArea
        objectName: "osdTab"
        width: root.osdShown && root.osdHere ? Theme.osdTabWidth : 0
        height: Theme.osdTabHeight
        x: parent.width - Theme.frameThickness - width
        y: Math.round((parent.height - height) / 2)
        clip: true
        Behavior on width { NumberAnimation { duration: root.animate ? Theme.glideDuration : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.morphCurve } }

        // Content fades in over the last 40% of the growth (SPEC 5.3); laid out at full
        // width so it doesn't squash while the tab grows.
        ColumnLayout {
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 12 }
            width: Theme.osdTabWidth - 24
            spacing: 10
            opacity: Math.max(0, Math.min(1, (osdArea.width / Theme.osdTabWidth - 0.6) / 0.4))

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.osdText
                color: root.osdColor
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm; bold: true }
            }
            Rectangle {   // level, filling from the bottom
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                width: 6; radius: 3
                color: Theme.trackBg
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * Math.max(0, Math.min(1, root.osdLevel))
                    radius: 3
                    color: root.osdColor
                    Behavior on height { NumberAnimation { duration: root.animate ? 150 : 0; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.osdIcon
                color: root.osdColor
                font { family: Theme.fontFamily; pixelSize: 16 }
            }
        }
    }
}
