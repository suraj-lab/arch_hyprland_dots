pragma Singleton
import QtQuick

QtObject {
    // Fonts
    readonly property string fontFamily:  "JetBrainsMono Nerd Font"
    readonly property int    fontSm:      10
    readonly property int    fontNormal:  12
    readonly property int    fontBar:     13
    readonly property int    fontIcon:    14
    readonly property int    fontLg:      15
    readonly property int    fontXl:      20
    readonly property int    fontXxl:     22
    readonly property int    fontHuge:    48

    // Text
    readonly property color text:       "#cdd6f4"
    readonly property color textDark:   "#0f0c14"
    readonly property color textDim:    Qt.rgba(205/255, 214/255, 244/255, 0.7)
    readonly property color textDimmer: Qt.rgba(205/255, 214/255, 244/255, 0.5)
    readonly property color textFaint:  Qt.rgba(205/255, 214/255, 244/255, 0.35)
    readonly property color textGhost:  Qt.rgba(205/255, 214/255, 244/255, 0.2)

    // Backgrounds
    readonly property color barBg:          Qt.rgba(15/255, 12/255, 20/255, 0.55)
    readonly property color popupBg:        Qt.rgba(15/255, 12/255, 20/255, 0.80)
    readonly property color surface:        Qt.rgba(255/255, 255/255, 255/255, 0.05)
    readonly property color surfaceHover:   Qt.rgba(255/255, 255/255, 255/255, 0.08)
    readonly property color trackBg:        Qt.rgba(255/255, 255/255, 255/255, 0.1)
    readonly property color mutedSlider:    Qt.rgba(205/255, 214/255, 244/255, 0.3)

    // Accents — your Waybar palette
    readonly property color accent:     "#00ffea"   // cyan
    readonly property color purple:     "#c678dd"
    readonly property color pink:       "#ff6ec7"   // CPU
    readonly property color media:      "#0adb9d"   // Spotify/teal
    readonly property color network:    "#40e0d0"   // turquoise
    readonly property color success:    "#39ff14"   // green
    readonly property color warning:    "#ff9f43"   // orange
    readonly property color error:      "#f38ba8"   // red

    // Borders
    readonly property color border:       Qt.rgba(198/255, 120/255, 221/255, 0.25)
    readonly property color borderLight:  Qt.rgba(198/255, 120/255, 221/255, 0.18)
    readonly property color borderMuted:  Qt.rgba(255/255, 255/255, 255/255, 0.1)

    // Workspace
    readonly property color wsActive:   Qt.rgba(198/255, 120/255, 221/255, 0.25)
    readonly property color wsOccupied: Qt.rgba(255/255, 255/255, 255/255, 0.08)
    readonly property color accentGlow: Qt.rgba(0, 255/255, 234/255, 0.45)

    // Error states
    readonly property color errorBg:     Qt.rgba(243/255, 139/255, 168/255, 0.2)
    readonly property color errorBorder: Qt.rgba(243/255, 139/255, 168/255, 0.4)

    // Urgency (notifications passed through to dunst — kept for popup borders)
    readonly property color urgencyNormal:   Qt.rgba(198/255, 120/255, 221/255, 0.3)
    readonly property color urgencyCritical: Qt.rgba(243/255, 139/255, 168/255, 0.6)

    // Layout
    readonly property int barHeight:     32
    readonly property int barMarginTop:  8
    readonly property int barMarginSide: 12
    readonly property int barPadding:    6
    readonly property int barSpacing:    8
    readonly property int wsSize:        28
    readonly property int wsRadius:      10
    readonly property int popupRadius:   12
    readonly property int popupPadding:  12

    // OSD
    readonly property int osdWidth:      350
    readonly property int osdHeight:     48
    readonly property int osdRadius:     24
    readonly property int osdBottomMargin: 80
    readonly property int osdHideDelay:  2000

    // Animations
    readonly property int animFast:     80
    readonly property int animNormal:   100
    readonly property int animMedium:   150
    readonly property int animSlow:     200
    readonly property int animDrawer:   250
    readonly property int animSlide:    300
    readonly property int animProgress: 500
}
