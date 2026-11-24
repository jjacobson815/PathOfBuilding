import QtQuick
import QtQuick.Layouts

// SaveAsPopup — Phase 3 long-tail, ports Build.lua's Save As folder-browser
// popup (Build.lua:1343-1412): build name with sanitizeBuildName validation
// and overwrite guard, PathControl breadcrumb, New Folder..., Sort By Name /
// Sort By Last Edited dropdown, subfolder list (double-click to enter, Delete
// key to delete empty folder), and Save / Cancel.
PopupBase {
    id: root

    title: " Save As "
    padding: 14

    signal buildSaved()
    signal saveFailed(string error)

    property string basePath: ""
    property string subPath: ""
    property string sortMode: "NAME"
    property var folders: []
    property int selFolderIndex: -1
    readonly property int folderCount: Array.isArray(folders) ? folders.length : 0
    readonly property bool hasFolderSel: selFolderIndex >= 0 && selFolderIndex < folderCount

    property var _check: ({ valid: false, exists: false, fullPath: "" })
    readonly property bool canSave: _check.valid === true && _check.exists !== true

    Keys.onReturnPressed: if (canSave) accept()
    Keys.onEnterPressed: if (canSave) accept()

    function openForCurrentBuild() {
        var st = luaEngine.invoke("pob_saveAsGetState", [])
        if (st && st.ok) {
            basePath = st.basePath || ""
            subPath = st.subPath || ""
            sortMode = st.sortMode || "NAME"
            folders = Array.isArray(st.folders) ? st.folders : []
            selFolderIndex = -1
            nameEdit.text = st.defaultBuildName || ""
            sortDrop.currentIndex = (sortMode === "EDITED") ? 1 : 0
        } else {
            var shell = luaEngine.getShellState() || {}
            basePath = ""
            subPath = shell.dbFileSubPath || ""
            sortMode = "NAME"
            folders = []
            selFolderIndex = -1
            nameEdit.text = shell.buildName || ""
            sortDrop.currentIndex = 0
        }
        recheck()
        open()
    }

    function _refreshFolders(nextSubPath, nextSortMode) {
        var sub = (nextSubPath !== undefined) ? nextSubPath : subPath
        var mode = (nextSortMode !== undefined) ? nextSortMode : sortMode
        var st = luaEngine.invoke("pob_saveAsGetState", [sub, mode])
        if (!st || !st.ok) return
        basePath = st.basePath || ""
        subPath = st.subPath || ""
        sortMode = st.sortMode || "NAME"
        folders = Array.isArray(st.folders) ? st.folders : []
        selFolderIndex = -1
        sortDrop.currentIndex = (sortMode === "EDITED") ? 1 : 0
        recheck()
    }

    function recheck(overrideText) {
        var txt = (overrideText !== undefined) ? overrideText : nameEdit.text
        _check = luaEngine.sanitizeBuildName(txt, subPath) || { valid: false, exists: false, fullPath: "" }
    }

    onAccepted: {
        if (!canSave) return
        var r = luaEngine.saveDBFile(_check.fullPath)
        if (!r || !r.ok) {
            saveFailed(r ? r.error : "unknown error")
            return
        }
        buildSaved()
    }

    ColumnLayout {
        implicitWidth: 460
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { label: "^7Build Name:"; size: 14 }
            EditControl {
                id: nameEdit
                Layout.fillWidth: true
                placeholder: "Enter build name"
                onEdited: (t) => root.recheck(t)
            }
        }

        Label {
            visible: root._check.exists === true || (!root._check.valid && nameEdit.text.length > 0)
            label: root._check.exists === true
                ? "^1A build with that name already exists in this folder."
                : "^1Build name contains invalid characters or is empty."
            size: 13
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            PathControl {
                Layout.fillWidth: true
                basePath: root.basePath
                subPath: root.subPath
                onChange: function (newSub) {
                    root._refreshFolders(newSub, root.sortMode)
                }
            }

            Button {
                implicitWidth: 96; implicitHeight: 24
                label: "New Folder..."
                onClicked: {
                    newFolderPopup.text = ""
                    newFolderPopup.open()
                }
            }

            DropDownControl {
                id: sortDrop
                Layout.preferredWidth: 145
                Layout.preferredHeight: 24
                model: ["Sort By Name", "Sort By Last Edited"]
                onSelected: (index) => {
                    root._refreshFolders(root.subPath, index === 1 ? "EDITED" : "NAME")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            color: "transparent"
            border.width: 1
            border.color: theme.border
            clip: true
            focus: true

            Keys.onPressed: function (event) {
                if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.hasFolderSel) {
                    var folderName = root.folders[root.selFolderIndex].name
                    var res = luaEngine.invoke("pob_saveAsDeleteFolder", [root.subPath, folderName])
                    if (!res || !res.ok) {
                        folderErrorPopup.message = "^1" + (res ? res.error : "Couldn't delete folder.")
                        folderErrorPopup.open()
                    } else {
                        root._refreshFolders(root.subPath, root.sortMode)
                    }
                    event.accepted = true
                }
            }

            ListView {
                id: folderList
                anchors.fill: parent
                anchors.margins: 2
                model: root.folders
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: folderList.width
                    height: 20
                    color: index === root.selFolderIndex ? theme.active
                         : folderMa.containsMouse ? theme.hover : "transparent"

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        label: "^xCCCC66[Folder] ^7" + modelData.name
                        size: 14
                    }

                    MouseArea {
                        id: folderMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selFolderIndex = index
                        onDoubleClicked: root._refreshFolders(modelData.subPath, root.sortMode)
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Button {
                implicitWidth: 80; implicitHeight: 24
                label: "Save"
                controlEnabled: root.canSave
                onClicked: if (root.canSave) root.accept()
            }
            PopupButton {
                label: "Cancel"
                onClicked: root.reject()
            }
        }
    }

    NewFolderPopup {
        id: newFolderPopup
        parent: root.parent
        title: " New Folder "
        onAccepted: {
            var res = luaEngine.invoke("pob_saveAsCreateFolder", [root.subPath, text])
            if (!res || !res.ok) {
                folderErrorPopup.message = "^1" + (res ? res.error : "Couldn't create folder.")
                folderErrorPopup.open()
                return
            }
            root._refreshFolders(res.subPath, root.sortMode)
        }
    }

    MessagePopup {
        id: folderErrorPopup
        parent: root.parent
        title: " Folder Error "
    }
}
