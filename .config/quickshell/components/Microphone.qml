import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    scale: hover.containsMouse ? 1.08 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [Pipewire.defaultAudioSource] }

    RowLayout {
        id: row
        spacing: 4
        Text {
            text: {
                if (!source) return "\uf131"
                if (source.audio.muted) return "\uf131"
                return "\uf130"
            }
            color: {
                if (!source || source.audio.muted) return Theme.error
                return hover.containsMouse ? root.barAccent : Theme.purple
            }
            font.pixelSize: Theme.fontIcon; font.family: Theme.fontFamily
            Behavior on color { ColorAnimation { duration: Theme.animMedium } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: { if (source) source.audio.muted = !source.audio.muted }
        onWheel: wheel => {
            if (!source) return
            source.audio.volume = Math.max(0, Math.min(1.0, source.audio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
        }
    }
}
