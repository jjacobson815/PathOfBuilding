import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// LIST-mode page — the build library browser. Extracted from main.qml (Part 1.1);
// behaviour unchanged. Bound to buildListModel. The selection state and
// openSelected() helper (previously root Window properties) are local to this page
// — they are only used here. This is Page 1 of the top-level StackLayout, so the
// root ColumnLayout carries the Layout margins (StackLayout ignores anchors).
ColumnLayout {
    id: buildListPage
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: theme.space2
    // StackLayout sets child geometry directly and IGNORES `anchors`, so the 12px
    // inset must be expressed via Layout margins (which StackLayout honours) —
    // otherwise content touches the window edges.
    Layout.leftMargin: theme.space3
    Layout.rightMargin: theme.space3
    Layout.topMargin: theme.space3
    Layout.bottomMargin: theme.space3

    // LIST-mode selection state (local to this page).
    property int listSelectedIndex: -1
    property string listSelectedName: ""
    property string listSelectedFullFileName: ""
    property bool listSelectedIsFolder: false

    // Open the selected build/folder from the library.
    function openSelected() {
        if (listSelectedIndex < 0) return
        if (listSelectedIsFolder) {
            // Folders are not openable as builds; ignore (UI disables Open).
            return
        }
        luaEngine.openBuild(listSelectedFullFileName)
    }

    Text {
        text: "Build Library"
        color: theme.text
        font.bold: true
        font.pixelSize: theme.fontSize + 6
    }

    // Toolbar: create / import / delete / rename controls.
    RowLayout {
        spacing: theme.space1
        Button {
            text: "New Build"
            onClicked: luaEngine.createBuild()
        }
        Button {
            text: "Open"
            enabled: buildListPage.listSelectedIndex >= 0 && !buildListPage.listSelectedIsFolder
            onClicked: buildListPage.openSelected()
        }
        Button {
            text: "Delete"
            enabled: buildListPage.listSelectedIndex >= 0
            onClicked: {
                if (buildListPage.listSelectedIsFolder)
                    luaEngine.deleteFolder(buildListPage.listSelectedName)
                else
                    luaEngine.deleteBuild(buildListPage.listSelectedFullFileName)
                buildListPage.listSelectedIndex = -1
            }
        }
        Item { Layout.fillWidth: true }
        TextField {
            id: folderNameField
            placeholderText: "New folder name"
            Layout.preferredWidth: 160
            font.pixelSize: theme.fontSize
        }
        Button {
            text: "New Folder"
            enabled: folderNameField.text !== ""
            onClicked: {
                luaEngine.createFolder(folderNameField.text)
                folderNameField.text = ""
            }
        }
    }

    RowLayout {
        spacing: theme.space1
        TextField {
            id: importUrlField
            placeholderText: "Paste build share URL"
            Layout.fillWidth: true
            font.pixelSize: theme.fontSize
        }
        Button {
            text: "Import URL"
            enabled: importUrlField.text !== ""
            onClicked: {
                luaEngine.importBuildFromURL(importUrlField.text)
                importUrlField.text = ""
            }
        }
    }

    // The build/folder list, bound to the BuildListModel.
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: buildListModel
        clip: true
        highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
        focus: true
        delegate: Rectangle {
            width: ListView.view.width
            height: 28
            color: (ListView.isCurrentItem ? theme.accent : (index % 2 ? theme.sideBarBg : "transparent"))
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.space2
                spacing: theme.space2
                Text {
                    text: model.isFolder ? ("📁 " + model.displayName) : (model.displayName || model.fileName)
                    color: ListView.isCurrentItem ? theme.background : theme.text
                    font.pixelSize: theme.fontSize
                    font.bold: model.isFolder
                    Layout.fillWidth: true
                elide: Text.ElideRight
                clip: true
                }
                Text {
                    text: model.isFolder ? "folder"
                         : ((model.className ? model.className : "") +
                            (model.level ? ("  Lv" + model.level) : ""))
                    color: ListView.isCurrentItem ? theme.background : theme.muted
                    font.pixelSize: theme.fontSize - 1
                elide: Text.ElideRight
                clip: true
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    buildListPage.listSelectedIndex = index
                    buildListPage.listSelectedName = model.isFolder ? model.folderName : model.buildName
                    buildListPage.listSelectedFullFileName = model.fullFileName
                    buildListPage.listSelectedIsFolder = model.isFolder
                    ListView.view.currentIndex = index
                }
                onDoubleClicked: buildListPage.openSelected()
            }
        }
    }

    Text {
        text: "Builds/folders: " + buildListModel.count
        color: theme.muted
        font.pixelSize: theme.fontSize
    }
}
