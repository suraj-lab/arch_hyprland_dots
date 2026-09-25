import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight - Theme.barPadding * 2
    scale: hover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    signal chipClicked()

    readonly property real vol: Audio.volume
    readonly property bool isMuted: Audio.muted
    function setVolume(v) { Audio.setVolume(v) }
    function toggleMute() { Audio.toggleMute() }

    // ── Bar chip ──────────────────────────────────────────────────────────
    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            text: {
                if (root.isMuted) return "\uf6a9"
                var v = Math.round(root.vol * 100)
                return (v > 50 ? "\uf028" : "\uf027") + " " + v + "%"
            }
            color: hover.containsMouse ? Theme.success : root.barAccent
            font.pixelSize: Theme.fontIcon; font.bold: true; font.family: Theme.fontFamily
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) root.chipClicked()
            else toggleMute()
        }
        onWheel: wheel => {
            var step = wheel.angleDelta.y / 120 * 0.05
            setVolume(root.vol + step)
        }
    }
}
