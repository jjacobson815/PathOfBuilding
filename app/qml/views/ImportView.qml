import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// IMPORT view — paste a build share code and load it via the engine. Extracted
// from main.qml (Part 1.1). Visibility is parent-controlled.
Item {
    id: importView
    anchors.fill: parent
    clip: true
    property string importStatus: ""
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space2
        TextField {
            id: importCode
            Layout.fillWidth: true
            placeholderText: "Paste build share code..."
            color: theme.text
            font.pixelSize: theme.fontSize
            background: Rectangle { color: theme.background; radius: theme.radiusControl }
        }
        Button {
            text: "Import Build"
            onClicked: {
                var ok = luaEngine.importFromCode(importCode.text)
                importView.importStatus = ok ? "Imported OK" : "Import failed"
            }
        }
        Text {
            text: importView.importStatus
            color: theme.muted
            font.pixelSize: theme.fontSize
        }
        Item { Layout.fillHeight: true }
    }
}
