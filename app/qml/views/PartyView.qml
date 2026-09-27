import QtQuick
import QtQuick.Layouts

// PARTY view — list of present party buff categories (partyModel). Extracted
// from main.qml (Part 1.1). Visibility is parent-controlled.
Item {
    id: partyView
    anchors.fill: parent
    clip: true
    ListView {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space1
        model: partyModel
        delegate: Rectangle {
            width: ListView.view.width
            height: 28
            color: theme.background
            radius: theme.radiusControl
            RowLayout {
                anchors.fill: parent
                anchors.margins: theme.space1
                spacing: theme.space2
                Text { text: name; color: theme.text; font.pixelSize: theme.fontSize; elide: Text.ElideRight; clip: true }
                Text { text: "x" + count; color: theme.muted; font.pixelSize: theme.fontSize }
            }
        }
    }
}
