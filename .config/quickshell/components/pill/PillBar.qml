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
    signal surfaceRequested(string name)   // sound / notifs / system / dashboard
    // Where each surface's chip sits (x centre in this item), so its surface grows from it.
    readonly property var chipCenters: ({
        sound: row.x + volChip.x + volChip.width / 2,
        notifs: row.x + notifChip.x + notifChip.width / 2,
        system: row.x + ccChip.x + ccChip.width / 2,
        dashboard: root.width / 2,      // the wide surfaces open centred on the bar
        media: root.width / 2,
        launcher: root.width / 2,
        clipboard: root.width / 2
    })
    signal powerRequested()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")

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

    // Clock at the true centre of the bar, as on the rest tab; click opens the dashboard.
    // (No now-playing text: the dashboard's Media tab and the media keys cover it.)
    BarText {
        id: clockText
        objectName: "pillClock"
        anchors.centerIn: parent
        opacity: row.opacity
        visible: opacity > 0
        text: root.time; font.bold: true
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.surfaceRequested("dashboard") }
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
            id: titleText
            // Stops short of the centred clock.
            Layout.maximumWidth: Math.max(0, Math.min(280, (root.width - clockText.width) / 2 - titleText.x - row.x - 24))
            color: Theme.textDim
            text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
        }
        Item { Layout.fillWidth: true }
        BarText { color: Theme.pink; text: "\ue266 " + (Sysmon.cpu < 0 ? "--" : Sysmon.cpu) + "%" }
        BarText { color: Theme.warning; text: "\uf2db " + (Sysmon.mem < 0 ? "--" : Sysmon.mem) + "%" }
        TrayArea { menuEdge: Edges.Top; Layout.fillWidth: false }   // a nested layout fills by default
        BarText {
            color: Net.wifiEnabled && Net.ssid ? root.accent : Theme.textDimmer
            text: "\uf1eb"
        }
        BarText { visible: Bt.enabled; color: Theme.purple; text: "\uf294" }
        Volume { id: volChip; barAccent: root.accent; onChipClicked: root.surfaceRequested("sound") }
        Microphone { barAccent: root.accent }
        Caffeine { visible: Desktop.caffeine; barAccent: root.accent; active: true; onClicked: Desktop.toggleCaffeine() }
        GameMode { visible: Desktop.gameMode; barAccent: root.accent; active: true; onClicked: Desktop.toggleGameMode() }
        NotificationCenter {
            id: notifChip
            barAccent: root.accent
            externalUnreadCount: Notifs.unreadCount
            dndEnabled: Notifs.dndEnabled
            onChipClicked: root.surfaceRequested("notifs")
        }
        ControlCenter { id: ccChip; barAccent: root.accent; onChipClicked: root.surfaceRequested("system") }
        PowerMenu { onClicked: root.powerRequested() }
    }
}
