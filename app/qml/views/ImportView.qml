import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
// Namespaced import (avoids the components/Button.qml vs QtQuick.Controls.Button
// ambiguity — see main.qml's own note): reach the component library as
// Widgets.* for this view's Part 1.4 acceptance-gate widget adoption.
import "../components" as Widgets

// IMPORT view — paste a build share code and load it via the engine. Extracted
// from main.qml (Part 1.1). Visibility is parent-controlled.
//
// Part 1.4 acceptance gate: adopted Widgets.Button + Widgets.ColorText here
// (the other of the two required `import "components"` consumers outside
// main.qml/OptionsDialog.qml), and set the share-code field to the bundled
// FIXED (monospace) font — share codes are opaque base64-ish blobs, exactly
// the case a fixed-width face is for — pairing with the About popup's VAR
// changelog as the acceptance gate's colour-code + font-differs evidence.
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
            font.family: theme.fontFixed
            font.pixelSize: theme.fontSize
            background: Rectangle { color: theme.background; radius: theme.radiusControl }
        }
        Widgets.Button {
            label: "Import Build"
            implicitWidth: 110
            implicitHeight: 20
            onClicked: {
                var ok = luaEngine.importFromCode(importCode.text)
                importView.importStatus = ok ? "^2Imported OK" : "^1Import failed"
            }
        }
        Widgets.ColorText {
            sourceText: importView.importStatus
            defaultColor: theme.muted
        }
        Item { Layout.fillHeight: true }
    }
}
