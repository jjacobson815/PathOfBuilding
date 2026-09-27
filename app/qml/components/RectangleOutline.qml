import QtQuick

// RectangleOutline — Tier 1, ported from legacy RectangleOutlineControl.lua:
// an outline-only rectangle (no fill). Legacy draws 4 separate stroke bars
// straddling the item's outer edge; QML's native Rectangle border achieves
// the same visual (outline only, no fill) directly — `stroke` maps to
// `border.width`, `colors` (an {r,g,b} 0..1 triple, matching the legacy
// `colors` param) maps to `border.color`.
Rectangle {
    id: root

    property var colors: [1, 1, 1]
    property int stroke: 1

    color: "transparent"
    border.width: root.stroke
    border.color: Qt.rgba(root.colors[0], root.colors[1], root.colors[2], 1)
}
