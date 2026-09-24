import QtQuick

// PopupButton — minimal Chrome-based button used by the canned popups
// (MessagePopup/ConfirmPopup/TextInputPopup/NewFolderPopup). NOT the future
// Tier 1 ButtonControl (Part 1.3) — this is deliberately scoped to just
// label + click, no image/+,-,x glyphs/locked/tooltip. Part 1.3's
// ButtonControl is the full-featured widget; this exists only so the four
// canned dialogs don't each hand-roll the same Chrome+MouseArea+Text.
Chrome {
    id: root

    property string label: ""
    signal clicked()

    implicitWidth: Math.max(80, labelText.implicitWidth + 20)
    implicitHeight: 24
    hovered: ma.containsMouse
    pressed: ma.pressed

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: theme.text
        font.pixelSize: theme.fontSize
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
