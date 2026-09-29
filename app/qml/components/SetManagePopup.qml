import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "StatDiff.js" as StatDiff

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
// Optional shared pane (Phase 6 Part 6.2, ItemsTab:OpenItemSetManagePopup,
// ItemsTab.lua:2125-2135: the build's sets and the cross-build shared sets
// side by side, 630 wide). Pass `sharedFn` to show it:
//   list()               -> { sets: [{ title, rawTitle, listLabel }] }
//   tooltip(i)           -> { lines }   (SharedItemSetListControl:AddValueTooltip)
//   share(setIndex, at)  build set -> shared list at `at` (ReceiveDrag)
//   importSet(i, at)     shared set -> build list at `at` (ReceiveDrag)
//   rename(i, title) / remove(i)
// Rows of each list drag onto the other (DragGhost, key "ItemSet"). Without
// `sharedFn` nothing changes (the Skills tab).
//
// Deviation (documented, same as SpecManagePopup): legacy reorders by
// dragging; here the selected row moves with Up/Down. The bridge op is the
// same list move either way.
PopupBase {
    id: root

    property var fn: ({})
    property var sharedFn: ({})
    property string noun: "set"               // "skill set"
    property string deleteTitle: "Delete Set"
    readonly property bool hasShared: sharedFn.list !== undefined

    signal listEdited()

    property var sets: []
    property int selIndex: -1
    readonly property int count: sets.length !== undefined ? sets.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count
    property var sharedSets: []
    property int sharedSel: -1
    readonly property int sharedCount: sharedSets.length !== undefined ? sharedSets.length : 0
    readonly property bool hasSharedSel: sharedSel >= 0 && sharedSel < sharedCount
    property string _nameMode: ""
    property bool _sharedFocus: false        // F2 / Delete act on the pane clicked last

    padding: 12

    function _call(name, args) {
        return luaEngine.invoke(fn[name], args || [])
    }
    function _callShared(name, args) {
        return luaEngine.invoke(sharedFn[name], args || [])
    }

    function refresh() {
        var st = _call("list")
        sets = (st && st.sets && st.sets.length !== undefined) ? st.sets : []
        if (selIndex >= count) selIndex = count - 1
        if (hasShared) {
            var sh = _callShared("list")
            sharedSets = (sh && sh.sets && sh.sets.length !== undefined) ? sh.sets : []
            if (sharedSel >= sharedCount) sharedSel = sharedCount - 1
        }
    }

    function openFresh() {
        selIndex = -1
        sharedSel = -1
        refresh()
        open()
    }

    function _run(name, args) {
        var r = _call(name, args)
        refresh()
        root.listEdited()
        return r
    }
    function _runShared(name, args) {
        var r = _callShared(name, args)
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
        } else if (_nameMode === "renameShared" && hasSharedSel) {
            _runShared("rename", [sharedSel + 1, text])
        }
    }

    function _askSharedName() {
        _nameMode = "renameShared"
        var t = sharedSets[sharedSel].rawTitle
        namePopup.title = t.length > 0 ? "Rename" : "Set Name"
        namePopup.text = t
        namePopup.open()
    }

    function _move(delta) {
        if (!hasSel) return
        var to = selIndex + delta
        if (to < 0 || to >= count) return
        var r = _run("move", [selIndex + 1, to + 1])
        if (r && r.ok) selIndex = to
    }

    // Row drag between the two lists (ListControl drag, past 10px).
    function _dragMove(ma, mouse, payload, text) {
        if (ghost.active) { ghost.moveTo(ma, mouse.x, mouse.y); return }
        var dx = mouse.x - ma.pressX, dy = mouse.y - ma.pressY
        if (hasShared && ma.pressed && dx * dx + dy * dy > 100)
            ghost.start(ma, mouse.x, mouse.y, "ItemSet", payload, text)
    }

    RowLayout {
        spacing: 12

        // A Dialog is not an Item, so the key handler lives on the content.
        ColumnLayout {
            implicitWidth: root.hasShared ? 300 : 346
            spacing: 4
            focus: true

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_F2 && root._sharedFocus && root.hasSharedSel) {
                    root._askSharedName()
                    event.accepted = true
                } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root._sharedFocus && root.hasSharedSel) {
                    sharedDeleteConfirm.openFor(root.sharedSel)
                    event.accepted = true
                } else if (event.key === Qt.Key_F2 && root.hasSel) {
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
                border.color: setDrop.containsDrag ? theme.success : theme.border
                clip: true

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 2
                    model: root.sets
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !root.hasShared
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
                            property real pressX: 0
                            property real pressY: 0
                            onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
                            onPositionChanged: function (mouse) {
                                root._dragMove(rowMa, mouse, { kind: "set", index: index }, modelData.listLabel)
                            }
                            onReleased: if (ghost.active) ghost.finish()
                            onClicked: { root.selIndex = index; root._sharedFocus = false }
                            onDoubleClicked: {
                                root.selIndex = index
                                if (!modelData.isActive) root._run("setActive", [index + 1])
                            }
                        }
                    }
                }
                // A shared set dropped here becomes a new build set (ItemSetListControl:ReceiveDrag).
                DropArea {
                    id: setDrop
                    anchors.fill: parent
                    keys: ["ItemSet"]
                    onEntered: function (drag) {
                        drag.accepted = !!drag.source && drag.source.dragValue.kind === "sharedSet"
                    }
                    onDropped: function (ev) {
                        var at = Math.max(0, Math.min(root.count, Math.round((ev.y - 2 + list.contentY) / 16)))
                        var r = root._callShared("importSet", [ev.source.dragValue.index + 1, at + 1])
                        root.refresh()
                        root.listEdited()
                        if (r && r.ok) root.selIndex = r.index - 1
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

        // Shared sets (SharedItemSetListControl: Delete left of centre,
        // Rename right of it; F2 renames).
        ColumnLayout {
            visible: root.hasShared
            implicitWidth: 300
            Layout.alignment: Qt.AlignTop
            spacing: 4

            RowLayout {
                spacing: 4
                Item { Layout.fillWidth: true }
                Button { implicitWidth: 60; implicitHeight: 18; label: "Delete"; controlEnabled: root.hasSharedSel
                    onClicked: sharedDeleteConfirm.openFor(root.sharedSel) }
                Button { implicitWidth: 60; implicitHeight: 18; label: "Rename"; controlEnabled: root.hasSharedSel
                    onClicked: root._askSharedName() }
                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                color: "transparent"
                border.width: 1
                border.color: sharedDrop.containsDrag ? theme.success : theme.border
                clip: true

                Column {
                    visible: root.sharedCount === 0
                    x: 6; y: 4
                    Repeater {
                        model: ["This is a list of item sets that will be shared",
                                "between all of your builds.",
                                "You can add sets to this list by dragging them",
                                "from the build's set list."]
                        delegate: Label { label: "^x7F7F7F" + modelData; size: 14 }
                    }
                }

                ListView {
                    id: sharedListView
                    anchors.fill: parent
                    anchors.margins: 2
                    model: root.sharedSets
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: false
                    delegate: Rectangle {
                        width: sharedListView.width
                        height: 16
                        color: index === root.sharedSel ? theme.active
                             : sharedMa.containsMouse ? theme.hover : "transparent"
                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            label: "^7" + modelData.listLabel
                            size: 14
                        }
                        MouseArea {
                            id: sharedMa
                            anchors.fill: parent
                            hoverEnabled: true
                            property real pressX: 0
                            property real pressY: 0
                            onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y; sharedTip.hide() }
                            onPositionChanged: function (mouse) {
                                root._dragMove(sharedMa, mouse, { kind: "sharedSet", index: index }, modelData.listLabel)
                            }
                            onReleased: if (ghost.active) ghost.finish()
                            onClicked: { root.sharedSel = index; root._sharedFocus = true }
                            onContainsMouseChanged: {
                                if (!containsMouse || ghost.active) { sharedTip.hide(); return }
                                sharedTip.clear()
                                StatDiff.fillFromLines(sharedTip, root._callShared("tooltip", [index + 1]))
                                var win = Window.window
                                var o = win ? sharedMa.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
                                sharedTip.showAt(0, 0, sharedMa.width, sharedMa.height,
                                    win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, width, height))
                            }
                        }
                        Tooltip { id: sharedTip }
                    }
                }
                // A build set dropped here is copied to the shared list.
                DropArea {
                    id: sharedDrop
                    anchors.fill: parent
                    keys: ["ItemSet"]
                    onEntered: function (drag) {
                        drag.accepted = !!drag.source && drag.source.dragValue.kind === "set"
                    }
                    onDropped: function (ev) {
                        var at = Math.max(0, Math.min(root.sharedCount, Math.round((ev.y - 2) / 16)))
                        var r = root._callShared("share", [ev.source.dragValue.index + 1, at + 1])
                        root.refresh()
                        if (r && r.ok) root.sharedSel = r.index - 1
                    }
                }
            }
        }
    }

    DragGhost { id: ghost }

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

    ConfirmPopup {
        id: sharedDeleteConfirm
        parent: root.parent
        title: "Delete Item Set"
        property int index: -1
        function openFor(i) {
            index = i
            message = "Are you sure you want to delete '" + root.sharedSets[i].title + "' from the shared item set list?"
            open()
        }
        confirmLabel: "Delete"
        onAccepted: {
            if (index < 0) return
            root._runShared("remove", [index + 1])
            root.sharedSel = -1
        }
    }
}
