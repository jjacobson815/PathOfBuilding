import QtQuick

// CraftLabel — a legacy LabelControl of a captured craft popup, right-aligned
// to `rx` (legacy anchors these as {"TOPRIGHT", popup, "TOPLEFT"}). Record
// driven when `name` is set (text and shown come from the live control),
// otherwise `staticLabel`. Qt paints wider than TextMetrics (invariant #8), so
// the text gets a real box and Qt's own right alignment.
Label {
    id: root

    property var craft: null
    property string name: ""
    property string staticLabel: ""
    property real rx: 95
    readonly property var r: (craft && name !== "") ? craft.rec(name) : ({})

    x: rx - width
    width: 300
    horizontalAlignment: Text.AlignRight
    size: 16
    label: name !== "" ? (r.label || "") : staticLabel
    visible: name === "" || r.shown === true
}
