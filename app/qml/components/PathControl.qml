import QtQuick

// PathControl — Tier 2, ported from legacy PathControl.lua: a folder
// breadcrumb (Base > Folder1 > Folder2 > ...) built from Button instances +
// Arrow separators, with UndoHandler-backed subpath history (mirrors
// CreateUndoState/RestoreUndoState returning/restoring the plain subPath
// string).
//
// Deferred (no real consumer yet — BuildListControl/FolderListControl are
// Tier 4, not built): the drag-and-drop-onto-a-breadcrumb-segment highlight
// (legacy's `otherDragSource` green tint). DragSource/DropTarget (Tier 0)
// are the natural building blocks for it once a real caller exists to
// validate the exact drag payload shape against.
Item {
    id: root

    property string basePath: ""
    property string subPath: ""
    property var onChange: null          // function(subPath) {}

    readonly property string baseName: (function () {
        var m = root.basePath.match(/([^/]+)\/$/);
        return m ? m[1] : "Base";
    })()

    // [{label, path}] — path="" for the base, else "Folder1/Folder2/" (each
    // entry's path is everything UP TO AND INCLUDING that segment).
    readonly property var folderList: (function () {
        var out = [{ label: root.baseName, path: "" }];
        if (root.subPath.length > 0) {
            var parts = root.subPath.split("/").filter(function (p) { return p.length > 0; });
            var acc = "";
            for (var i = 0; i < parts.length; i++) {
                acc += parts[i] + "/";
                out.push({ label: parts[i], path: acc });
            }
        }
        return out;
    })()

    implicitHeight: 24
    implicitWidth: 200

    UndoHandler {
        id: undoHandler
        createState: function () { return root.subPath; }
        restoreState: function (state) { root._setSubPath(state, true); }
    }
    Component.onCompleted: undoHandler.resetUndo()

    function setSubPath(newSubPath) { _setSubPath(newSubPath, false); }
    function _setSubPath(newSubPath, noUndo) {
        if (newSubPath === root.subPath) return;
        root.subPath = newSubPath;
        if (root.onChange) root.onChange(newSubPath);
        if (!noUndo) undoHandler.addUndoState();
    }
    function canUndo() { return undoHandler.canUndo; }
    function canRedo() { return undoHandler.canRedo; }
    function undoPath() { undoHandler.undo(); }
    function redoPath() { undoHandler.redo(); }

    Chrome { anchors.fill: parent }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        spacing: 10

        Repeater {
            model: root.folderList
            delegate: Row {
                required property var modelData
                required property int index
                spacing: 6
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                Button {
                    label: modelData.label
                    height: root.height - 4
                    width: Math.max(24, textMetrics.width(root.height - 8, "VAR", modelData.label) + 10)
                    onClicked: root.setSubPath(modelData.path)
                }
                Arrow {
                    visible: index < root.folderList.length - 1
                    direction: "right"
                    width: 8
                    height: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
