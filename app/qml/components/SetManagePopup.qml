import QtQuick
import QtQuick.Layouts

// SetManagePopup — the generic "set manager" (control-library Tier 4): one
// component for SkillSetListControl now, and ItemSet/ConfigSet later. Ports
// SkillSetListControl.lua (buttons above the list: Copy / Delete on the left,
// New / Rename on the right; F2 rename; Delete key; double-click activates)
// inside SkillsTab:OpenSkillSetManagePopup (370x290, "Manage Skill Sets").
//
// The bridge functions are passed in `fn` (all 1-based indices):
//   list()               -> { sets: [{ title, rawTitle, listLabel, isActive }] }
//   setActive(i) / create(title) / copy(i, title) / rename(i, title)
//   remove(i) / move(from, to)
// create/copy return { ok, index } for the new row.
//
// Deviation (documented, same as SpecManagePopup): legacy reorders by
// dragging; here the selected row moves with Up/Down. The bridge op is the
// same list move either way.
PopupBase {
    id: root

    property var fn: ({})
    property string noun: "set"               // "skill set"
    property string deleteTitle: "Delete Set"

    signal listEdited()

    property var sets: []
    property int selIndex: -1
    readonly property int count: sets.length !== undefined ? sets.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count
    property string _nameMode: ""

    padding: 12

    function _call(name, args) {
        return luaEngine.invoke(fn[name], args || [])
    }

    function refresh() {
        var st = _call("list")
        sets = (st && st.sets && st.sets.length !== undefined) ? st.sets : []
        if (selIndex >= count) selIndex = count - 1
    }

    function openFresh() {
        selIndex = -1
        refresh()
        open()
    }

    function _run(name, args) {
        var r = _call(name, args)
        refresh()
        root.listEdited()
        return r
    }

    function _askName(mode, initial) {
        _nameMode = mode
        // SkillSetListControl:RenameSet — "Rename" for a titled set, else "Set Name".
        // RenameSet: "Rename" when the set already has a title, else "Set Name".
        namePopup.title = initial.length > 0 ? "Rename" : "Set Name"
        namePopup.text = initial
        namePopup.open()
    }

    function _nameAccepted(text) {
        var r
        if (_nameMode === "new") {
            r = _run("create", [text])
            if (r && r.ok) selIndex = r.index - 1
        } else if (_nameMode === "copy" && hasSel) {
            r = _run("copy", [selIndex + 1, text])
            if (r && r.ok) selIndex = r.index - 1
        } else if (_nameMode === "rename" && hasSel) {
            _run("rename", [selIndex + 1, text])
        }
    }

    function _move(delta) {
        if (!hasSel) return
        var to = selIndex + delta
        if (to < 0 || to >= count) return
        var r = _run("move", [selIndex + 1, to + 1])
        if (r && r.ok) selIndex = to
    }

    // A Dialog is not an Item, so the key handler lives on the content.
    ColumnLayout {
        implicitWidth: 346
        spacing: 4
        focus: true

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_F2 && root.hasSel) {
                root._askName("rename", root.sets[root.selIndex].rawTitle)
                event.accepted = true
            } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.hasSel && root.count > 1) {
                deleteConfirm.openFor(root.selIndex)
                event.accepted = true
            }
        }

        RowLayout {
            spacing: 4
            Button { implicitWidth: 60; implicitHeight: 18; label: "Copy"; controlEnabled: root.hasSel
                onClicked: root._askName("copy", root.sets[root.selIndex].rawTitle) }
            Button { implicitWidth: 60; implicitHeight: 18; label: "Delete"
                controlEnabled: root.hasSel && root.count > 1
                onClicked: deleteConfirm.openFor(root.selIndex) }
            Item { Layout.fillWidth: true }
            Button { implicitWidth: 60; implicitHeight: 18; label: "New"
                onClicked: root._askName("new", "") }
            Button { implicitWidth: 64; implicitHeight: 18; label: "Rename"; controlEnabled: root.hasSel
                onClicked: root._askName("rename", root.sets[root.selIndex].rawTitle) }
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
                model: root.sets
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    width: list.width
                    height: 16
                    color: index === root.selIndex ? theme.active
                         : rowMa.containsMouse ? theme.hover : "transparent"
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        label: modelData.listLabel
                        size: 14
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selIndex = index
                        onDoubleClicked: {
                            root.selIndex = index
                            if (!modelData.isActive) root._run("setActive", [index + 1])
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            Button { implicitWidth: 44; implicitHeight: 20; label: "Up"
                controlEnabled: root.hasSel && root.selIndex > 0
                tooltipText: "Move the selected " + root.noun + " up"
                onClicked: root._move(-1) }
            Button { implicitWidth: 50; implicitHeight: 20; label: "Down"
                controlEnabled: root.hasSel && root.selIndex < root.count - 1
                tooltipText: "Move the selected " + root.noun + " down"
                onClicked: root._move(1) }
            Button { implicitWidth: 90; implicitHeight: 20; label: "Done"
                onClicked: root.accept() }
        }
    }

    TextInputPopup {
        id: namePopup
        parent: root.parent
        prompt: "^7Enter name for this " + root.noun + ":"
        confirmLabel: "Save"
        onAccepted: root._nameAccepted(text)
    }

    ConfirmPopup {
        id: deleteConfirm
        parent: root.parent
        title: root.deleteTitle
        // Set when opened, not bound: a bound message re-lays out this
        // (hidden) popup on every selection change while its Repeater rows
        // are being replaced, which crashed Qt 6.4's layout engine.
        function openFor(i) {
            message = "Are you sure you want to delete '" + root.sets[i].title + "'?"
            open()
        }
        confirmLabel: "Delete"
        onAccepted: {
            if (!root.hasSel) return
            root._run("remove", [root.selIndex + 1])
            root.selIndex = -1
        }
    }
}
