import QtQuick

// Section — Tier 1, ported from legacy SectionControl.lua: a bordered group
// box with a floating label plate that overlaps the top-left border. Uses
// Theme tokens rather than the legacy literal greys (0.66/0.1), per the
// Tier 0 "Cyber Citrus" decision already made for Chrome.qml. Geometry
// mirrors SectionClass:Draw exactly: label plate at (x+6, y-8) sized
// labelWidth+6 x 18, text centered inside it (x+9, y-6, size 14) — only the
// palette source changed.
Item {
    id: root

    property string label: ""
    default property alias content: body.data

    // Body "board": drawn first so any content declared via the default
    // property paints over it — matching legacy's DrawLayer(-10) (behind
    // everything else in the section).
    Rectangle {
        anchors.fill: parent
        color: theme.background
        border.width: 2
        border.color: theme.border
        radius: theme.radiusControl
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: 4
    }

    // Label plate: drawn last so it stacks above both the body board and any
    // content (legacy layer 0 vs the board's -10).
    Rectangle {
        id: labelPlate
        visible: root.label.length > 0
        x: 6
        y: -8
        width: labelText.width + 10
        height: 18
        color: theme.background
        border.width: 1
        border.color: theme.border
        radius: theme.radiusControl

        Label {
            id: labelText
            anchors.centerIn: parent
            label: root.label
            size: 14
        }
    }
}
