import QtQuick
import QtQuick.Window
import "../components" as Widgets

// SKILLS view — Phase 5, ports src/Classes/SkillsTab.lua over the live
// skillsTab (bridge: app/lua/pob_skills.lua). Legacy geometry (non-portrait):
// skill-set row at y 8, socket-group list at (20, 54) 360x300, usage tips and
// the "Gem Options" section under it, the group detail panel 20px right of
// the list.
//
// Part 5.1: skill-set dropdown (enabled with > 1 set) + "Manage..." (generic
//   SetManagePopup), the socket-group list (SocketGroupList), Ctrl+V paste
//   anywhere in the tab, Ctrl+Z / Ctrl+Y undo/redo (SkillsTab:Draw 544-556,
//   which the host never runs).
//
// STATE MODEL: `st` is pob_skillsGetState(), re-read (coalesced with
// Qt.callLater) on skills/calcs/items/tree/mode signals only — no frame loop
// (invariant #7). Everything is addressed by 1-based index because legacy
// replaces the group/gem tables on undo.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property var st: ({})
    property var lists: ({})
    readonly property var groups: st && st.groups && st.groups.length !== undefined ? st.groups : []
    readonly property var sets: st && st.sets && st.sets.length !== undefined ? st.sets : []
    readonly property var detail: st && st.detail ? st.detail : null

    property bool _pending: false
    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }
    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        if (!lists.slots) {
            const l = luaEngine.invoke("pob_skillsGetLists", [])
            if (l) lists = l
        }
        const s = luaEngine.invoke("pob_skillsGetState", [])
        st = s ? s : ({})
        setSelect.model = sets
        setSelect.currentIndex = (st.activeSet || 1) - 1
    }

    function call(name, args) { return luaEngine.invoke(name, args || []) }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onSkillsChanged() { root.refresh() }
        function onCalcsChanged() { root.refresh() }
        function onItemsChanged() { root.refresh() }
        function onTreeChanged() { root.refresh() }
        function onModeChanged() { root.lists = ({}); root.refresh() }
    }

    Shortcut {
        sequence: "Ctrl+V"
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: root.call("pob_skillsPasteGroup")
    }
    Shortcut {
        sequence: "Ctrl+Z"
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: root.call("pob_skillsUndo")
    }
    Shortcut {
        sequences: ["Ctrl+Y", "Ctrl+Shift+Z"]
        enabled: root.visible && luaEngine.currentMode === "BUILD"
        onActivated: root.call("pob_skillsRedo")
    }

    Flickable {
        id: page
        anchors.fill: parent
        contentWidth: Math.max(width, content.implicitWidth)
        contentHeight: Math.max(height, content.implicitHeight)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: content
            implicitWidth: 400 + 700
            implicitHeight: 560

            // --- Skill set row (SkillsTab.lua:95-106) ---
            Widgets.Label {
                anchors.right: setSelect.left
                anchors.rightMargin: 2
                anchors.verticalCenter: setSelect.verticalCenter
                horizontalAlignment: Text.AlignRight
                label: "^7Skill set:"
                size: 16
            }
            Widgets.DropDownControl {
                id: setSelect
                x: 76; y: 8
                width: 210; height: 20
                controlEnabled: root.sets.length > 1
                onSelected: function (index) { root.call("pob_skillsSetActiveSet", [index + 1]) }
            }
            Widgets.Button {
                anchors.left: setSelect.right
                anchors.leftMargin: 4
                anchors.verticalCenter: setSelect.verticalCenter
                width: 90; height: 20
                label: "Manage..."
                onClicked: setManage.openFresh()
            }

            // --- Socket group list (SkillsTab.lua:109) ---
            Widgets.SocketGroupList {
                id: groupList
                x: 20; y: 34
                width: 360; height: 320
                groups: root.groups
                selIndex: (root.st.displayIndex || 0) - 1
                onDeleteRequested: function (i) { deleteGroupConfirm.openFor(i) }
                onDeleteAllRequested: deleteAllConfirm.open()
                onMessageRequested: function (title, text) {
                    messagePopup.title = title
                    messagePopup.message = text
                    messagePopup.open()
                }
            }

            // Usage tips (SkillsTab.lua:110-118).
            Column {
                id: tips
                x: 20
                y: groupList.y + groupList.height + 8
                Repeater {
                    model: [
                        "^7Usage Tips:",
                        "- You can copy/paste socket groups using Ctrl+C and Ctrl+V.",
                        "- Ctrl + Click to enable/disable socket groups.",
                        "- Ctrl + Right click to include/exclude in FullDPS calculations.",
                        "- Right click to set as the Main skill group.",
                    ]
                    delegate: Widgets.Label { label: modelData; size: 14 }
                }
            }
        }
    }

    Widgets.SetManagePopup {
        id: setManage
        parent: root
        title: "Manage Skill Sets"
        noun: "skill set"
        deleteTitle: "Delete Item Set"      // legacy's own title (SkillSetListControl.lua:102)
        fn: ({
            list: "pob_skillsGetSetList",
            setActive: "pob_skillsSetActiveSet",
            create: "pob_skillsNewSet",
            copy: "pob_skillsCopySet",
            rename: "pob_skillsRenameSet",
            remove: "pob_skillsDeleteSet",
            move: "pob_skillsMoveSet",
        })
    }

    Widgets.ConfirmPopup {
        id: deleteGroupConfirm
        parent: root
        property int index: -1
        title: "Delete Socket Group"
        confirmLabel: "Delete"
        function openFor(i) {
            index = i
            message = "Are you sure you want to delete '" + root.groups[i].displayLabel + "'?"
            open()
        }
        onAccepted: root.call("pob_skillsDeleteGroup", [index + 1])
    }

    Widgets.ConfirmPopup {
        id: deleteAllConfirm
        parent: root
        title: "Delete All"
        message: "Are you sure you want to delete all socket groups in this build?"
        confirmLabel: "Delete"
        onAccepted: root.call("pob_skillsDeleteAllGroups")
    }

    Widgets.MessagePopup {
        id: messagePopup
        parent: root
    }
}
