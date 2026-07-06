# QML Reference

Detailed QML patterns, examples, animations, focus handling, implementation gotchas, and file I/O notes. Use when the lean skill is not enough.

## Animation Patterns

### Popup ease — OutCubic, NOT OutBack
```qml
// On popup content Rectangle (NOT the PopupWindow itself):
scale: popupOpen ? 1.0 : 0.95
opacity: popupOpen ? 1.0 : 0.0
transformOrigin: Item.Top
Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
Behavior on opacity { NumberAnimation { duration: 150 } }
```

### Toggle press — OutBack OK for micro-interactions
```qml
Rectangle {
    id: tile
    SequentialAnimation {
        id: pressAnim
        NumberAnimation { target: tile; property: "scale"; to: 0.93; duration: 80 }
        NumberAnimation { target: tile; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
    }
    MouseArea { onClicked: { pressAnim.start(); doAction() } }
}
```

### Chip hover
```qml
scale: hoverArea.containsMouse ? 1.08 : 1.0
Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
```

### Stagger entrance
```qml
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
```

### Animated hide — decouple visible from opacity
```qml
// WRONG — visible: someCondition kills the animation:
visible: someCondition
opacity: someCondition ? 1 : 0

// CORRECT:
property bool showThis: someCondition
visible: opacity > 0
opacity: showThis ? 1.0 : 0.0
Behavior on opacity { NumberAnimation { duration: 400 } }
```

### anchors.fill vs position animation
anchors.fill locks x, y, width, height.
Cannot animate x or y when anchors.fill is active — anchor silently overrides.
Use opacity/scale only, or use explicit anchors (left/right/top) instead of fill.

### Row vs RowLayout for animated children
RowLayout repositions siblings instantly when a child width changes.
Row supports `move: Transition { NumberAnimation { properties: "x" } }`.
Use Row when siblings need to animate position (e.g. workspace pills).
Do not add `Behavior on width` to an Item bound to an already-animated child width — double-smooths and causes lag.

## HyprlandFocusGrab — Safe Binding Pattern
```qml
property bool _grabReady: false

HyprlandFocusGrab {
    id: myGrab
    windows: [myPopup]
    active: popupOpen && root._grabReady   // BINDING, not manual assignment
    onCleared: popupOpen = false
}

Timer {
    id: grabDelay
    interval: 50
    onTriggered: root._grabReady = true
}

onPopupOpenChanged: {
    if (popupOpen) {
        grabDelay.restart()
    } else {
        root._grabReady = false    // IMMEDIATE release
        grabDelay.stop()
    }
}
```
Why: `active: popupOpen && _grabReady` is always false when popup closes.
No race condition. Never use manual `grab.active = false` — can leave grab stuck.

## Layout Gotchas

### Never set implicitHeight on Layout types
ColumnLayout/RowLayout/GridLayout compute their own implicitHeight.
```qml
// WRONG:
ColumnLayout { implicitHeight: 200 }

// CORRECT:
Item {
    implicitHeight: 200
    ColumnLayout { anchors.fill: parent }
}
```

### Column padding already in implicitHeight
Column.implicitHeight includes topPadding and bottomPadding.
Don't double-count when setting Flickable contentHeight.

### Flickable needs explicit height
```qml
height: Math.min(content.implicitHeight, maxHeight)
implicitHeight: height
contentHeight: content.implicitHeight
```

### Thin sliders miss scroll events
8px slider tracks don't receive scroll reliably.
Wrap entire section (label + slider) in a parent MouseArea with onWheel.

### Flickable mouse wheel — built-in is sluggish
```qml
Flickable {
    interactive: false
    // Sibling MouseArea:
    MouseArea {
        acceptedButtons: Qt.NoButton
        onWheel: flickable.contentY += wheel.angleDelta.y > 0 ? -25 : 25
    }
}
```

### Workspace pill click targets
Pills are only 10px tall. Wrap each in Item with full bar height.
Visual pill centered inside, MouseArea fills the Item.

## Phase 1 Implementation Gotchas

### ShaderEffect texture assignment
**Issue**: `ShaderEffect: Texture t1 is not assigned a valid texture provider (std::nullptr_t)`.

**Cause**: Texture properties in ShaderEffect components are not bound to valid texture providers.

**Fix**: Always explicitly assign texture sources or use `Image` elements as texture providers.
```qml
ShaderEffect {
    property Image source: blurImage    // Bind to Image element
    width: 200; height: 200
}
Image {
    id: blurImage
    source: "path/to/image.png"
    visible: false
}
```

### Implicit `root` reference in nested components
**Issue**: `ReferenceError: root is not defined` when using `root` in nested components.

**Cause**: Nested components don't have implicit `root` access; `root` only exists at the top level.

**Fix**: Use explicit `id` references or `parent`/`parent.parent` chains instead.
```qml
Rectangle {
    id: mainPanel
    Text {
        text: mainPanel.title    // Use explicit id, not root
    }
}
```

### Signal handler assignment to non-existent properties
**Issue**: `Cannot assign to non-existent property "onPopupOpenChanged"`.

**Cause**: Trying to attach a signal handler to a property that doesn't exist or isn't a signal.

**Fix**: Verify the parent component has the signal defined, or define it explicitly.
```qml
Rectangle {
    id: panel
    signal popupOpenChanged(bool open)
    
    onPopupOpenChanged: {
        console.log("Popup state changed: " + open)
    }
}
```

### Invalid Text properties like letterSpacing
**Issue**: `letterSpacing is not a valid property on Text element`.

**Cause**: Quickshell's QML does not support all standard Qt Quick Text properties.

**Fix**: Use valid font properties instead.
```qml
Text {
    text: "Hello"
    font.pixelSize: 14
    font.letterSpacing: 1    // WRONG in Quickshell
    // Use font.pixelSize or font.pointSize instead
}
```

### Component type unavailable
**Issue**: `Type UnifiedPanel unavailable`.

**Cause**: Component file exists but has syntax errors or import issues.

**Fix**: Check component file for syntax errors and ensure all imports are correct.
```bash
# Verify UnifiedPanel.qml exists and is valid
qt6 --version
cat components/UnifiedPanel.qml
```

### StackView transitions with PopupWindow
**Quirk**: StackView transitions may not animate smoothly inside a PopupWindow.

**Workaround**: Use explicit property bindings for view state instead of relying on StackView's implicit transitions.
```qml
StackView {
    id: stack
    initialItem: soundView
    
    Component.onCompleted: {
        // Force initial load to avoid transition on first show
        stack.push(soundView, StackView.Immediate)
    }
    
    pushEnter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }
}
```

### Unified panel height variations
**Issue**: Panel height changes when switching between views, causing visual jank.

**Fix**: Animate height using Behavior instead of letting it jump.
```qml
Rectangle {
    id: panel
    width: 400
    height: currentView.implicitHeight + 40
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
}
```

## File I/O Gotchas

### Freshly-written files need a delay
```qml
// After a Process writes a file, add 100-200ms before reading:
Timer {
    interval: 150
    onTriggered: myImage.source = "file:///path/to/file"
}
// Always set cache: false on dynamically-loaded Images
Image { cache: false }
```

### wl-copy blocks the calling process
```bash
wl-copy < file &    # always background it
```
