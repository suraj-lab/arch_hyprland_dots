---
name: qml
description: QML language rules, layout constraints, animation patterns, and Quickshell gotchas
---

# QML Skill

## Scope
Use this skill for:
- QML syntax and language constraints
- layout/debugging issues
- animations and transitions
- focus handling
- Quickshell QML gotchas

For detailed patterns, examples, animations, focus handling, and implementation gotchas, read:
`/home/suraj/.pi/agent/skills/qml/REFERENCE.md`

## Must-Remember Rules
- No optional chaining.
- Avoid typed custom properties unless verified supported.
- Use `property var` for arrays/objects.
- Initialize `property var` objects/arrays explicitly.
- Use explicit IDs; avoid fragile `parent.parent` chains.
- Do not assume standard Qt Quick properties exist in Quickshell.
- Do not invent imports or APIs.
- Verify unknown QML/Quickshell APIs before using them.

## Syntax Rules
No optional chaining:
```qml
// Wrong
foo?.bar

// Right
foo && foo.bar
```

Prefer `property var`:
```qml
property var items: []
property var config: ({})
```

Font properties:
```qml
font.pixelSize: 14
font.weight: Font.Medium
```

Signal handlers:
```qml
Connections {
    target: someObject
    function onSomeSignal(value) {
        // ...
    }
}
```

## Layout Rules
- Do not set `implicitHeight` directly on `ColumnLayout`, `RowLayout`, or `GridLayout`.
- Wrap layouts in an `Item` when fixed implicit size is needed.
- `Flickable` needs explicit height and content height.
- `anchors.fill` prevents animating `x`, `y`, `width`, and `height`.
- Use `Row` instead of `RowLayout` when sibling position animation matters.
- Keep click targets larger than tiny visual elements.

## Reactivity Rules
- Mutating arrays/objects in place may not trigger bindings.
- Reassign arrays/objects after mutation when UI must update.
- Keep binding ownership clear; avoid manually assigning to bound properties.
- Use `Connections` for external signal sources.

## Debugging Rules
When QML fails:
1. Check the first meaningful error.
2. Identify the file and line.
3. Check for invalid property names, missing imports, or unavailable component types.
4. Explain the root cause before editing.
5. Prefer minimal fixes.

## Common Verification
For Quickshell QML:
```bash
quickshell -r
qs log
```

For user service logs:
```bash
journalctl --user -u quickshell -n 30
```
