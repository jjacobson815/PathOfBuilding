import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Generic build content shown for views that do not yet have a dedicated UI.
// Extracted from main.qml (Part 1.1); behaviour unchanged. Shows a minimal
// save/load toolbar plus the socket-group list. The parent passes the current
// `activeView` (used for the header label + save/load status). `saveLoadStatus`
// and the viewLabel() helper are local to this view (moved off the root Window —
// they are only used here). Visibility is parent-controlled (the compound
// "no dedicated view" condition lives at the instantiation site).
ColumnLayout {
    id: placeholderView
    anchors.fill: parent
    anchors.margins: theme.space3
    spacing: theme.space2

    // Current view id, supplied by the parent.
    property string activeView: ""
    // Last save/load status string shown in the content-area toolbar.
    property string saveLoadStatus: "idle"

    // Resolve a view id to its human label (for the placeholder header).
    function viewLabel(id) {
        var views = luaEngine.viewList()
        for (var i = 0; i < views.length; i++)
            if (views[i].id === id) return views[i].label
        return id
    }

    // Minimal save/load toolbar.
    RowLayout {
        spacing: theme.space2
        Button {
            text: "Save"
            onClicked: {
                saveLoadModel.saveBuild(saveLoadModel.defaultSavePath())
                placeholderView.saveLoadStatus = (saveLoadModel.lastError === "")
                    ? ("Saved → " + saveLoadModel.defaultSavePath())
                    : ("Save error: " + saveLoadModel.lastError)
            }
        }
        Button {
            text: "Load"
            onClicked: {
                saveLoadModel.loadBuildFile(saveLoadModel.defaultSavePath())
                placeholderView.saveLoadStatus = (saveLoadModel.lastError === "")
                    ? "Loaded OK"
                    : ("Load error: " + saveLoadModel.lastError)
            }
        }
        Text {
            text: "Status: " + placeholderView.saveLoadStatus
            color: theme.muted
            font.pixelSize: theme.fontSize
        }
    }

    Text {
        text: "Active view: " + placeholderView.activeView + "  (" + placeholderView.viewLabel(placeholderView.activeView) + ")"
        color: theme.text
        font.pixelSize: theme.fontSize + 4
    }
    Text {
        text: "Socket groups: " + socketGroupModel.count
        color: theme.accent
        font.bold: true
    }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: socketGroupModel
        clip: true
        delegate: Rectangle {
            width: ListView.view.width
            height: 26
            color: index % 2 ? theme.sideBarBg : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.space1
                spacing: theme.space2
                Text {
                    text: (model.enabled ? "✔" : "✖") + "  " + (model.title || "(untitled)")
                    color: theme.text
                    font.pixelSize: theme.fontSize
                    Layout.fillWidth: true
                elide: Text.ElideRight
                clip: true
                }
                Text {
                    text: model.slot ? ("[" + model.slot + "]") : ""
                    color: theme.muted
                    font.pixelSize: theme.fontSize - 1
                elide: Text.ElideRight
                clip: true
                }
                Text {
                    text: model.skillSummary
                    color: theme.muted
                    font.pixelSize: theme.fontSize - 1
                    elide: Text.ElideRight
                    Layout.preferredWidth: 320
                }
            }
        }
    }
}
