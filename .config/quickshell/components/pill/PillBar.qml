import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../services"
import ".."

// Pill content: the resting tab (workspace dots + clock) and the hover bar row (SPEC 3.4).
// Both cross-fade from `progress` (0 = rest, 1 = hover), which follows the animated pill
// height, so the fade needs no animation of its own and stops with the morph.
Item {
    id: root
    property string screenName: ""
    property color accent: Theme.accent
    property real progress: 0
    property bool showRest: true           // the 6 px handle rest style has no content
    signal surfaceRequested(string name)   // sound / notifs / system (surfaces arrive in 4.3)
    signal powerRequested()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property var nowPlaying: Media.players.find(function(p) { return p.isPlaying }) || null

    component BarText: Text {
        color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBar
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }

    // Rest: fades out over the first 40% of the morph.
    Row {
        id: rest
        objectName: "pillRest"
        anchors.centerIn: parent
        spacing: 12
        opacity: root.showRest ? Math.max(0, Math.min(1, (0.4 - root.progress) / 0.4)) : 0
        visible: opacity > 0
        Workspaces { screenName: root.screenName; barAccent: root.accent; anchors.verticalCenter: parent.verticalCenter }
        BarText { text: root.time; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
    }

    // Hover: fades in over the last 40% of the morph.
    RowLayout {
        id: row
        objectName: "pillRow"
        anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
        spacing: Theme.barSpacing
        opacity: Math.max(0, Math.min(1, (root.progress - 0.6) / 0.4))
        visible: opacity > 0

        Workspaces {
            screenName: root.screenName; barAccent: root.accent
            WheelHandler {   // scrolling on the workspaces switches workspace (SPEC 3.4)
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => Hypr.dispatch("hl.dsp.focus({ workspace = \""
                    + (event.angleDelta.y > 0 ? "e-1" : "e+1") + "\" })")
            }
        }
        BarText {
            Layout.maximumWidth: 280
            color: Theme.textDim
            text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
        }
        Item { Layout.fillWidth: true }
        BarText {
            Layout.maximumWidth: 320
            visible: root.nowPlaying !== null
            color: Theme.media
            text: root.nowPlaying ? "\uf001  " + root.nowPlaying.trackTitle
                + (root.nowPlaying.trackArtist ? " · " + root.nowPlaying.trackArtist : "") : ""
        }
        Item { Layout.fillWidth: true }
        BarText { color: Theme.pink; text: "\ue266 " + (Sysmon.cpu < 0 ? "--" : Sysmon.cpu) + "%" }
        BarText { color: Theme.warning; text: "\uf2db " + (Sysmon.mem < 0 ? "--" : Sysmon.mem) + "%" }
        TrayArea { menuEdge: Edges.Top }
        BarText {
            color: Net.wifiEnabled && Net.ssid ? root.accent : Theme.textDimmer
            text: "\uf1eb"
        }
        BarText { visible: Bt.enabled; color: Theme.purple; text: "\uf294" }
        Volume { barAccent: root.accent; onChipClicked: root.surfaceRequested("sound") }
        Microphone { barAccent: root.accent }
        Caffeine { visible: Desktop.caffeine; barAccent: root.accent; active: true; onClicked: Desktop.toggleCaffeine() }
        GameMode { visible: Desktop.gameMode; barAccent: root.accent; active: true; onClicked: Desktop.toggleGameMode() }
        NotificationCenter {
            barAccent: root.accent
            externalUnreadCount: Notifs.unreadCount
            dndEnabled: Notifs.dndEnabled
            onChipClicked: root.surfaceRequested("notifs")
        }
        ControlCenter { barAccent: root.accent; onChipClicked: root.surfaceRequested("system") }
        BarText { text: root.time; font.bold: true }
        PowerMenu { onClicked: root.powerRequested() }
    }
}
