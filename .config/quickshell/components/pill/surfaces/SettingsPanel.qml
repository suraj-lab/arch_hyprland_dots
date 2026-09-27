import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../theme"
import "../../../services"

// Settings surface (SPEC 6.5): sections on the left, controls on the right. Every control
// writes settings.json through Config.set, so it survives a shell restart; Caffeine and the
// night light switch are live state (like their bar and System toggles).
Item {
    id: root
    property color accent: Theme.accent
    property bool active: false
    signal closeRequested()
    signal actionRequested(string id)       // run by the shell after the surface closes
    signal surfaceRequested(string name)    // switch to another surface (cheatsheet)

    implicitWidth: Theme.dashboardWidth
    implicitHeight: Theme.settingsHeight - Theme.surfacePadding

    property string section: "appearance"
    readonly property var sections: [
        { key: "appearance", icon: "\uf1fc", title: "Appearance" },
        { key: "power", icon: "\uf011", title: "Power & idle" },
        { key: "night", icon: "\uf186", title: "Night light" },
        { key: "keybinds", icon: "\uf11c", title: "Keybinds" },
        { key: "about", icon: "\uf05a", title: "About" }
    ]
    onActiveChanged: if (active && !about.running && !aboutText) about.running = true
    property date now: new Date()   // for the night light status line
    Timer { interval: 30000; running: root.active; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    // ── Pure helpers (unit-tested) ─────────────────────────────────────────
    function duration(sec) {
        return sec <= 0 ? "Off" : sec < 60 ? sec + " s" : sec % 3600 === 0 ? sec / 3600 + " h"
             : Math.round(sec / 6) / 10 + " min"
    }
    // Choices for a timeout; a value set by hand that is not among them is shown too.
    function timeoutOptions(values, current) {
        var list = values.indexOf(current) >= 0 || current === undefined ? values : values.concat([current]).sort(function(a, b) { return a - b })
        return list.map(function(v) { return { label: duration(v), value: v } })
    }
    function shiftClock(hhmm, delta) {
        var p = hhmm.split(":"), m = ((Number(p[0]) * 60 + Number(p[1]) + delta) % 1440 + 1440) % 1440
        return (m < 600 ? "0" : "") + Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + m % 60
    }
    // `hyprctl version -j`, `qs --version`, `uname -r`, PRETTY_NAME, one per line (JSON first).
    function parseAbout(text) {
        var lines = text.split("\n"), hypr = ""
        try { var j = JSON.parse(lines[0]); hypr = j.version || j.tag || "" } catch (e) {}
        var qs = (lines[1] || "").match(/Quickshell ([^ ]+)/)
        return { hyprland: hypr || "?", quickshell: qs ? qs[1] : "?", kernel: lines[2] || "?", os: lines[3] || "?" }
    }

    property string aboutText: ""
    readonly property var aboutInfo: parseAbout(aboutText)
    Process {
        id: about
        command: ["sh", "-c", "hyprctl version -j 2>/dev/null | tr -d '\\n'; echo; qs --version 2>/dev/null | head -1;"
                  + " uname -r; . /etc/os-release 2>/dev/null; echo \"${PRETTY_NAME:-Linux}\""]
        stdout: StdioCollector { onStreamFinished: root.aboutText = text }
    }

    // A labelled row: title (and hint) on the left, the control on the right.
    component Setting: RowLayout {
        id: setting
        property string title
        property string hint
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {   // fills, so the control sits on the right even without a hint
                Layout.fillWidth: true
                text: setting.title
                color: Theme.text
                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: setting.hint
                wrapMode: Text.Wrap
                color: Theme.textFaint
                font { family: Theme.fontFamily; pixelSize: Theme.fontSm }
            }
        }
        Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }
    component Heading: Text {
        color: Theme.text
        font { family: Theme.fontFamily; pixelSize: Theme.fontLg; bold: true }
    }
    // "−  19:30  +" in 30-minute steps.
    component ClockStepper: Row {
        id: stepper
        property string value
        signal picked(string value)
        spacing: 6
        SurfaceIcon { objectName: "minus"; glyph: "\uf068"; accent: root.accent; onClicked: stepper.picked(root.shiftClock(stepper.value, -30)) }
        Text {
            width: 52
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: stepper.value
            color: Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
        }
        SurfaceIcon { objectName: "plus"; glyph: "\uf067"; accent: root.accent; onClicked: stepper.picked(root.shiftClock(stepper.value, 30)) }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ── Section list ──
        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.fillWidth: false   // a nested layout fills by default
            Layout.fillHeight: true
            spacing: 2
            Repeater {
                model: root.sections
                Rectangle {
                    id: entry
                    required property var modelData
                    readonly property bool on: root.section === modelData.key
                    objectName: "section:" + modelData.key
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 10
                    color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                         : entryMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: entry.modelData.icon
                            color: entry.on ? root.accent : Theme.textDim
                            font { family: Theme.fontFamily; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.title
                            color: entry.on ? root.accent : Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: entry.on }
                        }
                    }
                    MouseArea { id: entryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.section = entry.modelData.key }
                }
            }
            Item { Layout.fillHeight: true }
        }
        Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.borderMuted }

        // ── Section content ──
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: content
                width: flick.width - 8   // not parent.width: the content item's width follows its children
                spacing: 18

                // Appearance
                ColumnLayout {
                    visible: root.section === "appearance"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Appearance" }
                    Setting {
                        title: "Wallpaper"
                        hint: "The accent colour follows the wallpaper."
                        Row {
                            spacing: 10
                            Rectangle {
                                width: 28; height: 28; radius: 8
                                color: root.accent
                                border.width: 1; border.color: Theme.borderMuted
                            }
                            SurfaceButton {
                                width: 150; height: 28
                                accent: root.accent
                                label: "Choose wallpaper\u2026"
                                onClicked: root.actionRequested("wallpaper")
                            }
                        }
                    }
                    Setting {
                        title: "Pill at rest"
                        hint: "Tab shows the workspaces and the clock; handle is a thin bar."
                        SurfaceChoice {
                            objectName: "restStyle"
                            accent: root.accent
                            options: [{ label: "Tab", value: "tab" }, { label: "Handle", value: "handle" }]
                            value: Config.pillFor("").restStyle
                            onChosen: v => Config.set("pill.restStyle", v)
                        }
                    }
                    Setting {
                        title: "Animations"
                        hint: "Off also while Desktop Game Mode is on."
                        SurfaceSwitch {
                            objectName: "animations"
                            accent: root.accent
                            on: Config.appearance.animations
                            onToggled: Config.set("appearance.animations", !Config.appearance.animations)
                        }
                    }
                }

                // Power & idle
                ColumnLayout {
                    visible: root.section === "power"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Power & idle" }
                    Setting {
                        title: "Lock after"
                        SurfaceChoice {
                            objectName: "lockSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 300, 600, 900, 1800], Config.idle.lockSec)
                            value: Config.idle.lockSec
                            onChosen: v => Config.set("idle.lockSec", v)
                        }
                    }
                    Setting {
                        title: "Screens off after"
                        SurfaceChoice {
                            objectName: "dpmsSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 300, 600, 900, 1800], Config.idle.dpmsSec)
                            value: Config.idle.dpmsSec
                            onChosen: v => Config.set("idle.dpmsSec", v)
                        }
                    }
                    Setting {
                        title: "Suspend after"
                        hint: "Off keeps the PC awake (screens still turn off)."
                        SurfaceChoice {
                            objectName: "suspendSec"
                            accent: root.accent
                            options: root.timeoutOptions([0, 1800, 3600, 7200], Config.idle.suspendSec)
                            value: Config.idle.suspendSec
                            onChosen: v => Config.set("idle.suspendSec", v)
                        }
                    }
                    Setting {
                        title: "Caffeine"
                        hint: "Keeps the screens awake until turned off. " + Desktop.idleStatus + "."
                        SurfaceSwitch { accent: root.accent; on: Desktop.caffeine; onToggled: Desktop.toggleCaffeine() }
                    }
                }

                // Night light
                ColumnLayout {
                    visible: root.section === "night"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Night light" }
                    Setting {
                        title: "Night light"
                        hint: !Desktop.nightLight ? "Off"
                            : Desktop.isNight(root.now.getHours() * 60 + root.now.getMinutes(),
                                              Desktop.minutes(Config.nightLight.from), Desktop.minutes(Config.nightLight.to))
                              ? "Warm now (" + Config.nightLight.temperature + " K)" : "Neutral now, warm from " + Config.nightLight.from
                        SurfaceSwitch { accent: root.accent; on: Desktop.nightLight; onToggled: Desktop.toggleNightLight() }
                    }
                    Setting {
                        title: "Temperature"
                        hint: "Lower is warmer."
                        SurfaceChoice {
                            objectName: "temperature"
                            accent: root.accent
                            options: [3000, 3500, 4000, 4500, 5000].concat(
                                [3000, 3500, 4000, 4500, 5000].indexOf(Config.nightLight.temperature) >= 0 ? []
                                : [Config.nightLight.temperature]).map(function(t) { return { label: t + " K", value: t } })
                            value: Config.nightLight.temperature
                            onChosen: v => Config.set("nightLight.temperature", v)
                        }
                    }
                    Setting {
                        title: "Warm from"
                        ClockStepper { objectName: "from"; value: Config.nightLight.from; onPicked: v => Config.set("nightLight.from", v) }
                    }
                    Setting {
                        title: "Until"
                        hint: "Earlier than the start means the next morning."
                        ClockStepper { objectName: "to"; value: Config.nightLight.to; onPicked: v => Config.set("nightLight.to", v) }
                    }
                }

                // Keybinds
                ColumnLayout {
                    visible: root.section === "keybinds"
                    Layout.fillWidth: true
                    spacing: 18
                    Heading { text: "Keybinds" }
                    Setting {
                        title: "Keybind cheatsheet"
                        hint: "Every Hyprland keybind, grouped and searchable. Also Super+/."
                        SurfaceButton {
                            width: 150; height: 28
                            accent: root.accent
                            primary: true
                            objectName: "openCheatsheet"
                            label: "Open cheatsheet"
                            onClicked: root.surfaceRequested("cheatsheet")
                        }
                    }
                }

                // About
                ColumnLayout {
                    visible: root.section === "about"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "About" }
                    Repeater {
                        model: [["System", root.aboutInfo.os], ["Kernel", root.aboutInfo.kernel],
                                ["Hyprland", root.aboutInfo.hyprland], ["Quickshell", root.aboutInfo.quickshell]]
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                Layout.preferredWidth: 120
                                text: parent.modelData[0]
                                color: Theme.textDim
                                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.modelData[1]
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fontNormal; bold: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
