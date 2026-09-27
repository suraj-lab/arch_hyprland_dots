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
        clipboard: root.width / 2,
        cheatsheet: root.width / 2,
        settings: root.width / 2,
        updates: row.x + updChip.x + updChip.width / 2,
        network: row.x + wifiChip.x + wifiChip.width / 2,
        devices: row.x + devChip.x + devChip.width / 2,
        // The Bluetooth chip only shows while it is on; otherwise grow from the System chip.
        bluetooth: row.x + (btChip.visible ? btChip.x + btChip.width / 2 : ccChip.x + ccChip.width / 2)
    })
    signal powerRequested()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm")

    component BarText: Text {
        color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBar
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    // Hover background for the chip it sits in (drawn behind the chip's own content), 24 px
    // high and 4 px wider each side; a tap on that padding does what the chip does.
    component ChipHighlight: Rectangle {
        id: hl
        signal tapped()
        anchors.centerIn: parent
        width: Math.max(24, parent.width + 8)
        height: Math.max(24, parent.height)
        z: -1
        radius: 8
        color: hlHover.hovered ? Theme.surfaceHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        HoverHandler { id: hlHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hl.tapped() }
    }
    // Clickable text chip: 24 px minimum target, hover background, accent and scale like the
    // other chips.
    component BarChip: Item {
        id: chip
        property alias text: label.text
        property color tint: Theme.text
        signal clicked()
        implicitWidth: Math.max(24, label.implicitWidth + 8)
        implicitHeight: 24
        scale: chipMouse.containsMouse ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: chipMouse.containsMouse ? Theme.surfaceHover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        BarText {
            id: label
            anchors.centerIn: parent
            color: chipMouse.containsMouse ? root.accent : chip.tint
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
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
        ChipHighlight { onTapped: root.surfaceRequested("dashboard") }
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
        // CPU/RAM give way on narrow bars so the right-hand chips never reach the centred clock.
        // ponytail: fixed threshold (the chips need ~330 px of the half bar); the phase4 clock
        // check on an 800 px screen catches it if the chip row grows.
        BarText { visible: root.width >= 900; color: Theme.pink; text: "\ue266 " + (Sysmon.cpu < 0 ? "--" : Sysmon.cpu) + "%" }
        BarText { visible: root.width >= 900; color: Theme.warning; text: "\uf2db " + (Sysmon.mem < 0 ? "--" : Sysmon.mem) + "%" }
        TrayArea { menuEdge: Edges.Top; Layout.fillWidth: false }   // a nested layout fills by default
        BarChip {   // removable drives (SPEC 6.3): only while one is connected
            id: devChip
            objectName: "devicesChip"
            visible: Devices.count > 0
            tint: root.accent
            text: "\uf287" + (Devices.count > 1 ? " " + Devices.count : "")
            onClicked: root.surfaceRequested("devices")
        }
        BarChip {
            id: wifiChip
            tint: Net.wifiEnabled && Net.ssid ? root.accent : Theme.textDimmer
            text: "\uf1eb"
            onClicked: root.surfaceRequested("network")
        }
        BarChip {
            id: btChip
            visible: Bt.enabled
            tint: Theme.purple
            text: "\uf294"
            onClicked: root.surfaceRequested("bluetooth")
        }
        Volume {
            id: volChip; objectName: "volChip"; barAccent: root.accent; onChipClicked: root.surfaceRequested("sound")
            ChipHighlight { onTapped: root.surfaceRequested("sound") }
        }
        Microphone { barAccent: root.accent; ChipHighlight {} }   // its click (mute) is internal
        Caffeine {
            objectName: "caffeineChip"   // always in the bar; dim while off
            barAccent: root.accent; active: true; on: Desktop.caffeine; onClicked: Desktop.toggleCaffeine()
            ChipHighlight { onTapped: Desktop.toggleCaffeine() }
        }
        GameMode {
            visible: Desktop.gameMode; barAccent: root.accent; active: true; onClicked: Desktop.toggleGameMode()
            ChipHighlight { onTapped: Desktop.toggleGameMode() }
        }
        NotificationCenter {
            id: notifChip
            barAccent: root.accent
            externalUnreadCount: Notifs.unreadCount
            dndEnabled: Notifs.dndEnabled
            onChipClicked: root.surfaceRequested("notifs")
            ChipHighlight { onTapped: root.surfaceRequested("notifs") }
        }
        ControlCenter {
            id: ccChip; barAccent: root.accent; onChipClicked: root.surfaceRequested("system")
            ChipHighlight { onTapped: root.surfaceRequested("system") }
        }
        BarChip {   // update badge (SPEC 6.4): only when something is waiting
            id: updChip
            objectName: "updateBadge"
            visible: Updates.total > 0
            tint: root.accent
            text: "\uf0ed " + Updates.total
            onClicked: root.surfaceRequested("updates")
        }
        PowerMenu { onClicked: root.powerRequested(); ChipHighlight { onTapped: root.powerRequested() } }
    }
}
