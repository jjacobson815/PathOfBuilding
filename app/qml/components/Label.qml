import QtQuick

// Label — Tier 1, ported from legacy LabelControl.lua. Just a color-code-aware
// string (legacy DrawString itself understands ^0-^9/^xRRGGBB, so any label
// text is implicitly "color-code" — hence ColorText, not a plain Text).
// Legacy passes the control's rect `height` straight through as the
// DrawString font-size argument; `size` is that same parameter here (default
// theme.fontSize), and `width`/`height` mirror the dynamic
// `DrawStringWidth(height, "VAR", label)` width property so a Row/Layout can
// size to it without a rebind. (Text's `implicitWidth`/`implicitHeight` are
// read-only — computed from content via Qt's own font metrics — so the
// TextMetrics-based measurement is applied to the real `width`/`height`
// instead, which IS assignable.)
ColorText {
    id: root

    property string label: ""
    property int size: theme.fontSize

    sourceText: root.label
    defaultColor: theme.text
    font.pixelSize: root.size
    width: textMetrics.width(root.size, "VAR", root.label)
    height: root.size
}
