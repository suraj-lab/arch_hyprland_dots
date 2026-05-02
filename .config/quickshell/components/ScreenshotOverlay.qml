import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    property string mode: ""        // "area" or "screen"
    property string screenName: ""  // monitor name for grim -o
    signal closeRequested()

    // ── Selection state ───────────────────────────────────────────────────
    property bool selecting: false
    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0
    property bool previewOpen: false
    property string screenshotPath: ""
    property string screenshotDims: ""
    property bool copied: false
    property bool saved: false

    // Selection rectangle (normalized)
    property real selX: Math.min(startX, endX)
    property real selY: Math.min(startY, endY)
    property real selW: Math.abs(endX - startX)
    property real selH: Math.abs(endY - startY)

    // ── Auto-trigger screen mode ──────────────────────────────────────────
    onModeChanged: {
        if (mode === "screen") {
            captureFullScreen()
        }
    }

    function captureFullScreen() {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmmss")
        var path = "/tmp/qs-screenshot-" + ts + ".png"
        screenshotPath = path
        captureProc.command = ["grim", "-o", screenName, path]
        captureProc.running = true
    }

    function captureArea() {
        var screens = Quickshell.screens
        var monX = 0
        var monY = 0
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                monX = screens[i].x || 0
                monY = screens[i].y || 0
                break
            }
        }

        var gx = Math.round(monX + selX)
        var gy = Math.round(monY + selY)
        var gw = Math.round(selW)
        var gh = Math.round(selH)

        if (gw < 5 || gh < 5) {
            root.closeRequested()
            return
        }

        screenshotDims = gw + " x " + gh

        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmmss")
        var path = "/tmp/qs-screenshot-" + ts + ".png"
        screenshotPath = path

        captureProc.command = ["grim", "-g", gx + "," + gy + " " + gw + "x" + gh, path]
        captureProc.running = true
    }

    // ── Capture process (grim only — wl-copy runs separately) ─────────────
    Process {
        id: captureProc
        onRunningChanged: {
            if (!running) {
                root.selecting = false
                // Delay slightly to ensure file is flushed to disk
                previewDelayTimer.restart()
            }
        }
    }

    Timer {
        id: previewDelayTimer
        interval: 200
        onTriggered: {
            // Auto-save
            root.saveScreenshot()
            // Copy to clipboard (background — wl-copy lingers)
            copyProc.command = ["bash", "-c", "wl-copy < '" + root.screenshotPath + "' &"]
            copyProc.running = true
            root.copied = true
            // Get dimensions if needed
            if (root.screenshotDims === "") {
                dimProc.command = ["bash", "-c",
                    "file '" + root.screenshotPath + "' | grep -oP '\\d+ x \\d+' | head -1"]
                dimProc.running = true
            }
            // Show preview
            root.previewOpen = true
        }
    }

    Process { id: copyProc }

    Process {
        id: dimProc
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (t) root.screenshotDims = t
            }
        }
    }

    Process { id: saveProc }

    function saveScreenshot() {
        var filename = screenshotPath.split("/").pop()
        saveProc.command = ["bash", "-c",
            "mkdir -p $HOME/Pictures/Screenshots && cp '" + screenshotPath + "' $HOME/Pictures/Screenshots/" + filename
        ]
        saveProc.running = true
        root.saved = true
    }

    // ── Reset on close ────────────────────────────────────────────────────
    function reset() {
        selecting = false
        previewOpen = false
        startX = 0; startY = 0; endX = 0; endY = 0
        screenshotPath = ""
        screenshotDims = ""
        copied = false
        saved = false
    }

    // ── ESC handler ───────────────────────────────────────────────────────
    Keys.onEscapePressed: {
        if (previewOpen) {
            reset()
            root.closeRequested()
        } else {
            reset()
            root.closeRequested()
        }
    }

    focus: mode !== ""

    // ── Dim overlay (outside selection) ───────────────────────────────────
    // Top
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.selecting ? root.selY : parent.height
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: !root.previewOpen && mode === "area"
    }
    // Bottom
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.selecting ? parent.height - root.selY - root.selH : 0
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: !root.previewOpen && mode === "area" && root.selecting
    }
    // Left
    Rectangle {
        x: 0; y: root.selY
        width: root.selecting ? root.selX : 0
        height: root.selH
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: !root.previewOpen && mode === "area" && root.selecting
    }
    // Right
    Rectangle {
        x: root.selX + root.selW; y: root.selY
        width: root.selecting ? parent.width - root.selX - root.selW : 0
        height: root.selH
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: !root.previewOpen && mode === "area" && root.selecting
    }

    // ── Selection rectangle border ────────────────────────────────────────
    Rectangle {
        x: root.selX; y: root.selY
        width: root.selW; height: root.selH
        color: "transparent"
        border.color: root.barAccent; border.width: 2
        visible: root.selecting && !root.previewOpen

        // Dimensions label
        Rectangle {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.bottom; topMargin: 6
            }
            width: dimText.implicitWidth + 16; height: 20; radius: 6
            color: Qt.rgba(0, 0, 0, 0.8)
            border.color: Qt.rgba(0, 255, 234, 0.3); border.width: 1

            Text {
                id: dimText
                anchors.centerIn: parent
                text: Math.round(root.selW) + " x " + Math.round(root.selH)
                font.pixelSize: 10; font.bold: true
                font.family: Theme.fontFamily; color: root.barAccent
            }
        }
    }

    // ── Selection MouseArea ───────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: !root.previewOpen && mode === "area"
        cursorShape: Qt.CrossCursor

        onPressed: function(mouse) {
            root.startX = mouse.x
            root.startY = mouse.y
            root.endX = mouse.x
            root.endY = mouse.y
            root.selecting = true
        }

        onPositionChanged: function(mouse) {
            if (root.selecting) {
                root.endX = mouse.x
                root.endY = mouse.y
            }
        }

        onReleased: function(mouse) {
            root.endX = mouse.x
            root.endY = mouse.y
            root.captureArea()
        }
    }

    // ── Hint bar (during selection) ───────────────────────────────────────
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom; bottomMargin: 24
        }
        width: hintRow.implicitWidth + 28; height: 32; radius: 10
        color: Qt.rgba(0, 0, 0, 0.7)
        border.color: Qt.rgba(255, 255, 255, 0.1); border.width: 1
        visible: !root.previewOpen && !root.selecting && mode === "area"

        RowLayout {
            id: hintRow
            anchors.centerIn: parent
            spacing: 16

            Row {
                spacing: 4
                Rectangle {
                    width: dragKey.implicitWidth + 8; height: 18; radius: 4
                    color: Qt.rgba(255, 255, 255, 0.1)
                    border.color: Qt.rgba(255, 255, 255, 0.15); border.width: 1
                    Text {
                        id: dragKey; anchors.centerIn: parent
                        text: "Drag"; font.pixelSize: 9; font.family: Theme.fontFamily
                        color: Theme.textFaint
                    }
                }
                Text { text: "select area"; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                spacing: 4
                Rectangle {
                    width: escKey.implicitWidth + 8; height: 18; radius: 4
                    color: Qt.rgba(255, 255, 255, 0.1)
                    border.color: Qt.rgba(255, 255, 255, 0.15); border.width: 1
                    Text {
                        id: escKey; anchors.centerIn: parent
                        text: "Esc"; font.pixelSize: 9; font.family: Theme.fontFamily
                        color: Theme.textFaint
                    }
                }
                Text { text: "cancel"; font.pixelSize: 9; font.family: Theme.fontFamily; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ── Preview popup ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: root.previewOpen

        MouseArea { anchors.fill: parent; onClicked: { root.reset(); root.closeRequested() } }

        Rectangle {
            id: previewCard
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.6, 500)
            height: previewCol.implicitHeight + 32
            radius: 16
            color: Theme.popupBg
            border.color: Theme.border; border.width: 1
            scale: root.previewOpen ? 1.0 : 0.92
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: previewCol
                anchors { fill: parent; margins: 16 }
                spacing: 12

                // Screenshot image
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: width * 0.5
                    radius: 10; color: Theme.surface; clip: true
                    border.color: Qt.rgba(255, 255, 255, 0.1); border.width: 1

                    Image {
                        anchors.fill: parent
                        source: root.previewOpen && root.screenshotPath !== ""
                                ? "file://" + root.screenshotPath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        smooth: true
                    }
                }

                // Info row
                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: root.screenshotPath !== "" ? root.screenshotPath.split("/").pop() : ""
                            font.pixelSize: 11; font.bold: true
                            font.family: Theme.fontFamily; color: Theme.text
                        }
                        Text {
                            text: root.screenshotDims || "Captured"
                            font.pixelSize: 9; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: root.copied
                        text: "\uf00c Copied to clipboard"
                        font.pixelSize: 9; font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.success
                    }
                }

                // Status + close
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 8
                        color: Qt.rgba(57/255, 255/255, 20/255, 0.1)
                        border.color: Qt.rgba(57/255, 255/255, 20/255, 0.3); border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00c  Copied"
                            font.pixelSize: 11; font.bold: true
                            font.family: Theme.fontFamily; color: Theme.success
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 8
                        color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.1)
                        border.color: Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.3); border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00c  Saved"
                            font.pixelSize: 11; font.bold: true
                            font.family: Theme.fontFamily; color: root.barAccent
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 8
                        color: closeH.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d  Close"
                            font.pixelSize: 11; font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textDim
                        }

                        MouseArea {
                            id: closeH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.reset(); root.closeRequested() }
                        }
                    }
                }
            }
        }
    }
}
