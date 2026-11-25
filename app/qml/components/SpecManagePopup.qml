import QtQuick
import QtQuick.Layouts
import "QmlBridge.js" as QmlBridge

// SpecManagePopup — Phase 4 Part 4.2, ports TreeTab:OpenSpecManagePopup
// (TreeTab.lua:656-674) + PassiveSpecListControl. A list of every passive tree
// (row label from the bridge: "[ver] title (class, N points)  ^9(Current)"),
// with New / Copy / Rename / Delete, Import Tree / Export Tree and Done.
// Double-click a row to make it the active tree (OnSelClick).
//
// Deviation (documented): legacy reorders by dragging a row. Here the selected
// row moves with the Up/Down buttons; the bridge op (pob_moveSpec) is the same
// OnOrderChange fix-up either way, so a drag handle can be added later
// without touching the engine side.
PopupBase {
    id: root
    objectName: "pob.specmanage.root"

    // Raised after a successful Import so the host can refresh around it.
    signal listEdited()

    property var specs: []
    property int selIndex: -1        // 0-based row in `specs`, -1 = none
    readonly property int count: specs.length !== undefined ? specs.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count

    // Name prompt shared by New / Copy / Rename (PassiveSpecListControl:RenameSpec).
    property string _nameMode: ""

    title: "Manage Passive Trees"
    padding: 12
    acceptOnEnter: false
    onOpened: mainCol.forceActiveFocus()

    function refresh() {
        var st = luaEngine.invoke("pob_getSpecList", [])
        specs = QmlBridge.toArray(st ? st.specs : null)
        if (selIndex >= count) selIndex = count - 1
    }

    function openFresh() {
        selIndex = -1
        refresh()
        open()
    }

    function _run(fn, args) {
        var r = luaEngine.invoke(fn, args)
        refresh()
        root.listEdited()
        return r
    }

    function _askName(mode, initial, heading) {
        _nameMode = mode
        namePopup.title = heading
        namePopup.text = initial
        namePopup.open()
    }

    function _nameAccepted(text) {
        if (_nameMode === "new") {
            var r = _run("pob_newSpec", [text])
            if (r && r.ok) selIndex = r.index - 1
        } else if (_nameMode === "copy" && hasSel) {
            var c = _run("pob_copySpec", [selIndex + 1, text])
            if (c && c.ok) selIndex = c.index - 1
        } else if (_nameMode === "rename" && hasSel) {
            _run("pob_renameSpec", [selIndex + 1, text])
        }
    }

    function _move(delta) {
        if (!hasSel) return
        var to = selIndex + delta
        if (to < 0 || to >= count) return
        var r = _run("pob_moveSpec", [selIndex + 1, to + 1])
        if (r && r.ok) selIndex = to
    }

    ColumnLayout {
        id: mainCol
        width: 400
        spacing: 8
        focus: true

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_F2 && root.hasSel) {
                root._askName("rename", root.specs[root.selIndex].title, "Rename Tree")
                event.accepted = true
            } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.hasSel && root.count > 1) {
                deleteConfirm.open()
                event.accepted = true
            }
        }

        RowLayout {
            spacing: 6
            Button { objectName: "pob.specmanage.btn_new"; implicitWidth: 60; implicitHeight: 20; label: "New"
                onClicked: root._askName("new", "", "New Tree") }
            Button { objectName: "pob.specmanage.btn_copy"; implicitWidth: 60; implicitHeight: 20; label: "Copy"; controlEnabled: root.hasSel
                onClicked: root._askName("copy", root.specs[root.selIndex].title, "Copy Tree") }
            Button { objectName: "pob.specmanage.btn_ren"; implicitWidth: 70; implicitHeight: 20; label: "Rename"; controlEnabled: root.hasSel
                onClicked: root._askName("rename", root.specs[root.selIndex].title, "Rename Tree") }
            Button { objectName: "pob.specmanage.btn_del"; implicitWidth: 60; implicitHeight: 20; label: "Delete"
                controlEnabled: root.hasSel && root.count > 1
                onClicked: deleteConfirm.open() }
            Item { Layout.fillWidth: true }
            Button { objectName: "pob.specmanage.btn_up"; implicitWidth: 44; implicitHeight: 20; label: "Up"
                controlEnabled: root.hasSel && root.selIndex > 0
                tooltipText: "Move the selected tree up"
                onClicked: root._move(-1) }
            Button { objectName: "pob.specmanage.btn_down"; implicitWidth: 50; implicitHeight: 20; label: "Down"
                controlEnabled: root.hasSel && root.selIndex < root.count - 1
                tooltipText: "Move the selected tree down"
                onClicked: root._move(1) }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            color: "transparent"
            border.width: 1
            border.color: theme.border
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 2
                model: root.specs
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    width: list.width
                    height: 18
                    color: index === root.selIndex ? theme.active
                         : rowMa.containsMouse ? theme.hover : "transparent"
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        elide: Text.ElideRight
                        label: modelData.listLabel
                        size: 14
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { root.selIndex = index; mainCol.forceActiveFocus() }
                        onDoubleClicked: {
                            root.selIndex = index
                            if (!modelData.isActive) root._run("pob_setActiveSpec", [index + 1])
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button { implicitWidth: 100; implicitHeight: 20; label: "Import Tree"
                onClicked: importPopup.openFresh() }
            Button { implicitWidth: 100; implicitHeight: 20; label: "Export Tree"
                onClicked: exportPopup.openFresh() }
            Button { implicitWidth: 80; implicitHeight: 20; label: "Done"
                onClicked: root.accept() }
        }
    }

    TextInputPopup {
        id: namePopup
        parent: root.parent
        prompt: "^7Enter name for this passive tree:"
        confirmLabel: "Save"
        onAccepted: root._nameAccepted(text)
    }

    ConfirmPopup {
        id: deleteConfirm
        parent: root.parent
        title: "Delete Tree"
        message: root.hasSel ? "Are you sure you want to delete '" + root.specs[root.selIndex].title + "'?" : ""
        confirmLabel: "Delete"
        onAccepted: {
            if (!root.hasSel) return
            root._run("pob_deleteSpec", [root.selIndex + 1])
            root.selIndex = -1
        }
    }

    TreeImportPopup {
        id: importPopup
        parent: root.parent
        onImported: function (index) {
            root.refresh()
            root.selIndex = index - 1
            root.listEdited()
        }
    }

    TreeExportPopup {
        id: exportPopup
        parent: root.parent
    }
}
