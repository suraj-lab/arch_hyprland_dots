import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme"

Item {
    id: root
    property color barAccent: "#00ffea"

    property bool launcherVisible: false
    signal closeRequested()

    // ── App data (DesktopEntries API) ───────────────────────────────────────
    property var allApps: {
        var entries = []
        try {
            var raw = DesktopEntries.applications.values
            for (var i = 0; i < raw.length; i++) entries.push(raw[i])
        } catch(e) { return [] }
        return entries
            .filter(function(e) { return !e.noDisplay })
            .sort(function(a, b) { return a.name.localeCompare(b.name) })
    }

    property string searchText: ""
    property string selectedCategory: "All"
    property int selectedIndex: 0

    // ── Category extraction ─────────────────────────────────────────────────
    readonly property var catMap: ({
        "AudioVideo": "Media",  "Audio": "Media",      "Video": "Media",
        "Development": "Dev",   "Game": "Games",       "Graphics": "Graphics",
        "Network": "Internet",  "WebBrowser": "Internet",
        "Office": "Office",     "System": "System",    "Settings": "System",
        "Utility": "Utilities"
    })

    readonly property var reverseCatMap: ({
        "Media":     ["AudioVideo", "Audio", "Video"],
        "Dev":       ["Development"],
        "Games":     ["Game"],
        "Graphics":  ["Graphics"],
        "Internet":  ["Network", "WebBrowser"],
        "Office":    ["Office"],
        "System":    ["System", "Settings"],
        "Utilities": ["Utility"]
    })

    property var categories: {
        var seen = {}
        var result = ["All"]
        for (var i = 0; i < allApps.length; i++) {
            var cats = allApps[i].categories
            if (!cats) continue
            for (var j = 0; j < cats.length; j++) {
                var friendly = catMap[cats[j]]
                if (friendly && !seen[friendly]) {
                    seen[friendly] = true
                    result.push(friendly)
                }
            }
        }
        return result
    }

    // ── Filtered + sorted apps ──────────────────────────────────────────────
    property var filteredApps: {
        var q = searchText.toLowerCase()
        var cat = selectedCategory

        var result = allApps.filter(function(app) {
            // Category filter
            if (cat !== "All") {
                var validCats = reverseCatMap[cat]
                if (!validCats) return false
                var appCats = app.categories
                if (!appCats) return false
                var match = false
                for (var i = 0; i < appCats.length; i++) {
                    if (validCats.indexOf(appCats[i]) >= 0) { match = true; break }
                }
                if (!match) return false
            }
            // Search filter
            if (q) {
                var nameMatch = app.name != null && app.name.toLowerCase().indexOf(q) >= 0
                var genMatch  = app.genericName != null && app.genericName.toLowerCase().indexOf(q) >= 0
                var kwMatch   = false
                if (app.keywords) {
                    for (var k = 0; k < app.keywords.length; k++) {
                        if (app.keywords[k].toLowerCase().indexOf(q) >= 0) { kwMatch = true; break }
                    }
                }
                if (!nameMatch && !genMatch && !kwMatch) return false
            }
            return true
        })

        // Smart sort: startsWith matches ranked first
        if (q) {
            result.sort(function(a, b) {
                var an = a.name.toLowerCase()
                var bn = b.name.toLowerCase()
                var aStarts = an.indexOf(q) === 0
                var bStarts = bn.indexOf(q) === 0
                if (aStarts && !bStarts) return -1
                if (!aStarts && bStarts) return 1
                return an.localeCompare(bn)
            })
        }

        return result
    }

    // ── State management ────────────────────────────────────────────────────
    onLauncherVisibleChanged: {
        if (launcherVisible) {
            searchText = ""
            selectedCategory = "All"
            selectedIndex = 0
            searchInput.text = ""
            focusTimer.restart()
        }
    }

    Timer {
        id: focusTimer
        interval: 50
        onTriggered: searchInput.forceActiveFocus()
    }

    function launchApp(entry) {
        try { entry.execute() } catch(e) { console.log("launch failed:", e) }
        root.closeRequested()
    }

    function launchFirst() {
        if (filteredApps.length > 0) {
            var idx = Math.min(selectedIndex, filteredApps.length - 1)
            launchApp(filteredApps[idx])
        }
    }

    // ── Backdrop (click-to-close, no dim) ──────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // ── Centered card ───────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Theme.launcherWidth
        height: Theme.launcherHeight
        radius: 16
        color: Theme.popupBg
        border.color: Theme.border
        border.width: 1
        clip: true

        scale: root.launcherVisible ? 1.0 : 0.92
        Behavior on scale {
            NumberAnimation { duration: 250; easing.type: Easing.OutBack }
        }

        // Prevent backdrop click-through
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Search bar ──────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 14

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.surface
                    border.color: searchInput.activeFocus
                                  ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.3) : Theme.borderMuted
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.animMedium } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 10

                        Text {
                            text: "\uf002"
                            font.pixelSize: 14; font.family: Theme.fontFamily
                            color: Theme.textDimmer
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TextInput {
                                id: searchInput
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                color: Theme.text
                                font.pixelSize: Theme.fontNormal
                                font.family: Theme.fontFamily
                                clip: true
                                selectByMouse: true

                                onTextChanged: {
                                    root.searchText = text
                                    root.selectedIndex = 0
                                }

                                Keys.onEscapePressed: root.closeRequested()
                                Keys.onReturnPressed: root.launchFirst()
                                Keys.onEnterPressed: root.launchFirst()
                                Keys.onDownPressed: {
                                    if (root.filteredApps.length > 0)
                                        root.selectedIndex = Math.min(
                                            root.selectedIndex + Theme.launcherCols,
                                            root.filteredApps.length - 1
                                        )
                                }
                                Keys.onUpPressed: {
                                    if (root.filteredApps.length > 0)
                                        root.selectedIndex = Math.max(
                                            root.selectedIndex - Theme.launcherCols, 0
                                        )
                                }
                                Keys.onLeftPressed: function(event) {
                                    if (searchInput.cursorPosition === 0 && root.filteredApps.length > 0) {
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                                        event.accepted = true
                                    }
                                }
                                Keys.onRightPressed: function(event) {
                                    if (searchInput.cursorPosition === searchInput.text.length && root.filteredApps.length > 0) {
                                        root.selectedIndex = Math.min(
                                            root.selectedIndex + 1,
                                            root.filteredApps.length - 1
                                        )
                                        event.accepted = true
                                    }
                                }
                            }

                            // Placeholder
                            Text {
                                visible: !searchInput.text
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "Search applications..."
                                color: Theme.textFaint
                                font.pixelSize: Theme.fontNormal
                                font.family: Theme.fontFamily
                            }
                        }

                        // Result count
                        Text {
                            text: root.filteredApps.length.toString()
                            font.pixelSize: Theme.fontSm
                            font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                }
            }

            // ── Category pills ──────────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 8
                contentWidth: catRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: catRow
                    spacing: 6

                    Repeater {
                        model: root.categories

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: catLabel.implicitWidth + 20
                            height: 26
                            radius: 8
                            color: modelData === root.selectedCategory
                                   ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.12) : Theme.surface
                            border.color: modelData === root.selectedCategory
                                          ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.3) : Theme.borderMuted
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                            Text {
                                id: catLabel
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Theme.fontSm
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: modelData === root.selectedCategory
                                       ? root.barAccent : Theme.textDim
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedCategory = modelData
                                    root.selectedIndex = 0
                                }
                            }
                        }
                    }
                }
            }

            // ── Divider ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Theme.borderLight
                Layout.leftMargin: 14; Layout.rightMargin: 14
                Layout.topMargin: 8
            }

            // ── App grid ────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 8

                // Empty state
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.filteredApps.length === 0

                    Text {
                        text: "\uf002"
                        font.pixelSize: 32; font.family: Theme.fontFamily
                        color: Theme.textGhost
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "No apps found"
                        font.pixelSize: Theme.fontSm; font.family: Theme.fontFamily
                        color: Theme.textFaint
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    visible: root.filteredApps.length > 0
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        var step = 25
                        var newY = appFlick.contentY - (wheel.angleDelta.y > 0 ? step : -step)
                        appFlick.contentY = Math.max(0,
                            Math.min(newY, appFlick.contentHeight - appFlick.height))
                    }
                }

                Flickable {
                    id: appFlick
                    anchors.fill: parent
                    visible: root.filteredApps.length > 0
                    contentHeight: appGrid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: false

                    Grid {
                        id: appGrid
                        width: parent.width
                        columns: Theme.launcherCols
                        spacing: 4

                        Repeater {
                            model: root.filteredApps.length

                            Item {
                                id: tile
                                required property int index

                                property var app: root.filteredApps[index]
                                property bool isSelected: index === root.selectedIndex
                                property bool isHovered: tileHover.containsMouse

                                opacity: 0
                                scale: 0.8
                                Component.onCompleted: staggerTimer.start()
                                Timer {
                                    id: staggerTimer
                                    interval: Math.min(index * 15, 400)
                                    onTriggered: { parent.opacity = 1; parent.scale = 1.0 }
                                }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                width: (appGrid.width - (Theme.launcherCols - 1) * 4) / Theme.launcherCols
                                height: Theme.launcherIconSize + 36

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: tile.isSelected
                                           ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.1)
                                           : tile.isHovered
                                             ? Theme.surfaceHover : "transparent"
                                    border.color: tile.isSelected
                                                  ? Qt.rgba(root.barAccent.r, root.barAccent.g, root.barAccent.b, 0.25)
                                                  : tile.isHovered
                                                    ? Theme.borderMuted : "transparent"
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    // Icon with fallback
                                    Item {
                                        width: Theme.launcherIconSize
                                        height: Theme.launcherIconSize
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Image {
                                            id: appIcon
                                            anchors.fill: parent
                                            source: {
                                                if (tile.app == null) return ""
                                                var icon = tile.app.icon
                                                if (icon == null || icon === "") return ""
                                                // Use Qt's built-in icon theme provider
                                                return "image://icon/" + icon
                                            }
                                            sourceSize.width: source != "" ? Theme.launcherIconSize : 0
                                            sourceSize.height: source != "" ? Theme.launcherIconSize : 0
                                            smooth: true
                                            visible: status === Image.Ready

                                            onStatusChanged: {
                                                if (status === Image.Error) {
                                                    source = "image://icon/application-x-executable"
                                                }
                                            }
                                        }

                                        // Text fallback when no icon
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: Theme.surface
                                            visible: appIcon.status !== Image.Ready
                                                     && appIcon.status !== Image.Loading

                                            Text {
                                                anchors.centerIn: parent
                                                text: tile.app != null && tile.app.name
                                                      ? tile.app.name.charAt(0).toUpperCase() : "?"
                                                font.pixelSize: 20
                                                font.bold: true
                                                font.family: Theme.fontFamily
                                                color: Theme.textDim
                                            }
                                        }
                                    }

                                    // App name
                                    Text {
                                        text: tile.app != null ? tile.app.name : ""
                                        font.pixelSize: Theme.fontSm
                                        font.family: Theme.fontFamily
                                        color: tile.isSelected ? root.barAccent
                                               : tile.isHovered ? Theme.text
                                               : Theme.textDim
                                        elide: Text.ElideRight
                                        width: (appGrid.width - (Theme.launcherCols - 1) * 4) / Theme.launcherCols - 12
                                        horizontalAlignment: Text.AlignHCenter
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    }
                                }

                                MouseArea {
                                    id: tileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (tile.app != null) root.launchApp(tile.app)
                                    }
                                    onEntered: root.selectedIndex = tile.index
                                }

                                // Scroll into view when selected via keyboard
                                onIsSelectedChanged: {
                                    if (isSelected && appFlick.visible) {
                                        var itemY = Math.floor(index / Theme.launcherCols) * (height + 4)
                                        if (itemY < appFlick.contentY) {
                                            appFlick.contentY = itemY
                                        } else if (itemY + height > appFlick.contentY + appFlick.height) {
                                            appFlick.contentY = itemY + height - appFlick.height
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer hints ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.bottomMargin: 10; Layout.topMargin: 4
                spacing: 16

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 4
                    Rectangle {
                        width: hintEsc.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hintEsc; anchors.centerIn: parent
                            text: "Esc"; font.pixelSize: 9; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "close"; font.pixelSize: 9; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: hintRet.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hintRet; anchors.centerIn: parent
                            text: "\u23ce"; font.pixelSize: 9; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "launch"; font.pixelSize: 9; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: hintArr.implicitWidth + 8; height: 18; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1
                        Text {
                            id: hintArr; anchors.centerIn: parent
                            text: "\u2191\u2193"; font.pixelSize: 9; font.family: Theme.fontFamily
                            color: Theme.textFaint
                        }
                    }
                    Text {
                        text: "navigate"; font.pixelSize: 9; font.family: Theme.fontFamily
                        color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
