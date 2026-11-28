import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
// Namespaced import (avoids the components/Button.qml vs QtQuick.Controls.Button
// ambiguity — see main.qml's own note): reach the component library as
// Widgets.* for this view's Part 1.4 acceptance-gate widget adoption.
import "../components" as Widgets

// LIST-mode page — the build library browser. Extracted from main.qml (Part 1.1);
// behaviour unchanged. Bound to buildListModel. The selection state and
// openSelected() helper (previously root Window properties) are local to this page
// — they are only used here. This is Page 1 of the top-level StackLayout, so the
// root ColumnLayout carries the Layout margins (StackLayout ignores anchors).
//
// Part 1.4 acceptance gate: adopted the Tier 0/1 component kit here (Widgets.
// Button + Widgets.Label replacing hand-rolled QtQuick.Controls.Button/Text) —
// one of the two required `import "components"` consumers outside main.qml/
// OptionsDialog.qml. Mechanical swap only; the ListView delegate (bound to
// buildListModel's per-row data) is left as-is — that's real Phase 3+ work,
// not a widget-kit adoption.
Item {
    id: buildListPage
    objectName: "pob.buildlist.root"
    Layout.fillWidth: true
    Layout.fillHeight: true

    // LIST-mode selection state (local to this page).
    signal openFailed(string message)
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
        if (!luaEngine.openBuild(listSelectedFullFileName))
            buildListPage.openFailed(luaEngine.openBuildError())
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.space3
        spacing: theme.space2

        Widgets.Label {
            objectName: "pob.buildlist.header"
            label: "Build Library"
            size: theme.fontSize + 6
        }

        // Toolbar: create / import / delete / rename controls.
        RowLayout {
            Layout.fillWidth: true
            spacing: theme.space1
            Widgets.Button {
                objectName: "pob.buildlist.btn_new"
                label: "New Build"
                implicitWidth: 82
                implicitHeight: 24
                onClicked: luaEngine.createBuild()
            }
            Widgets.Button {
                objectName: "pob.buildlist.btn_open"
                label: "Open"
                implicitWidth: 56
                implicitHeight: 24
                controlEnabled: buildListPage.listSelectedIndex >= 0 && !buildListPage.listSelectedIsFolder
                onClicked: buildListPage.openSelected()
            }
            Widgets.Button {
                objectName: "pob.buildlist.btn_del"
                label: "Delete"
                implicitWidth: 64
                implicitHeight: 24
                controlEnabled: buildListPage.listSelectedIndex >= 0
                onClicked: {
                    if (buildListPage.listSelectedIsFolder)
                        luaEngine.deleteFolder(buildListPage.listSelectedName)
                    else
                        luaEngine.deleteBuild(buildListPage.listSelectedFullFileName)
                    buildListPage.listSelectedIndex = -1
                }
            }
            Item { Layout.fillWidth: true }
            Widgets.EditControl {
                id: folderNameField
                objectName: "pob.buildlist.input_folder"
                placeholder: "New folder name"
                Layout.preferredWidth: 140
                Layout.preferredHeight: 24
            }
            Widgets.Button {
                objectName: "pob.buildlist.btn_mkdir"
                label: "New Folder"
                implicitWidth: 110
                implicitHeight: 24
                controlEnabled: folderNameField.text !== ""
                onClicked: {
                    luaEngine.createFolder(folderNameField.text)
                    folderNameField.text = ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: theme.space1
            Widgets.EditControl {
                id: importUrlField
                objectName: "pob.buildlist.input_import_url"
                placeholder: "Paste build share URL"
                Layout.fillWidth: true
                Layout.preferredHeight: 24
            }
            Widgets.Button {
                objectName: "pob.buildlist.btn_import"
                label: "Import URL"
                implicitWidth: 110
                implicitHeight: 24
                controlEnabled: importUrlField.text !== ""
                onClicked: {
                    luaEngine.importBuildFromURL(importUrlField.text)
                    importUrlField.text = ""
                }
            }
        }

        // The build/folder list, bound to the BuildListModel.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            border.width: 1
            border.color: theme.border

            ListView {
                id: buildListView
                objectName: "pob.buildlist.view"
                anchors.fill: parent
                anchors.margins: 1
                model: buildListModel
                clip: true
                highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
                focus: true
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 28
                    color: ListView.isCurrentItem ? "transparent" : (index % 2 ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: theme.space2
                        anchors.rightMargin: theme.space2
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
                            objectName: "pob.buildlist.row_meta"
                            text: model.isFolder ? "folder"
                                 : ((model.ascendClassName && model.ascendClassName.length > 0 ? model.ascendClassName : (model.className ? model.className : "")) +
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
                            buildListView.currentIndex = index
                        }
                        onDoubleClicked: buildListPage.openSelected()
                    }
                }
            }
        }

        Widgets.Label {
            objectName: "pob.buildlist.count"
            label: "Builds/folders: " + buildListModel.count
            defaultColor: theme.muted
        }
    }
}
