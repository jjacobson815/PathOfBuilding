import QtQuick
import QtQuick.Controls

// NOTES view — a notes editor bound to notesController.notes. Extracted from
// main.qml (Part 1.1). Visibility is controlled by the parent
// (visible: activeView === "NOTES"); this component is just the view body.
Item {
    id: notesView
    anchors.fill: parent
    clip: true
    Flickable {
        anchors.fill: parent
        anchors.margins: theme.space3
        contentHeight: notesEdit.height
        clip: true
        TextArea {
            id: notesEdit
            width: parent.width
            text: notesController.notes
            color: theme.text
            font.pixelSize: theme.fontSize
            wrapMode: Text.WordWrap
            background: Rectangle { color: theme.background; radius: theme.radiusControl }
            onTextChanged: notesController.setNotes(text)
        }
    }
}
