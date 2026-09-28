import QtQuick
import QtQuick.Window
import "../components" as Widgets
import "../components/StatDiff.js" as StatDiff

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
// Part 5.2: group detail panel (SkillsTab.lua:160-315) — label, "Socketed in"
//   (row tooltip = the equipped item), Enabled, Include in Full DPS, Count +
//   source note for item/node groups, Imbued Support (a GemSelect in imbued
//   mode + clear "x") — and the "Gem Options" section (121-150).
//   Text edits apply 300 ms after the last keystroke or on Enter/focus-out
//   (legacy applies every keystroke; each is a recalc + undo state here).
//   Control values are pushed imperatively after each refresh because the
//   components write their own state (a binding would break on first edit).
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
        _pushDetail()
    }

    function _pushDetail() {
        const d = detail
        const o = st.options || {}
        sortByDps.state = !!o.sortGemsByDPS
        sortField.currentIndex = (o.sortField || 1) - 1
        defaultLevel.currentIndex = (o.defaultGemLevel || 1) - 1
        if (!defaultQuality.editing) defaultQuality.text = o.defaultGemQuality || "0"
        supportTypes.currentIndex = (o.showSupportGemTypes || 1) - 1
        showLegacy.state = !!o.showLegacyGems
        if (!d) return
        if (!groupLabel.editing) groupLabel.text = d.label
        groupSlot.currentIndex = (d.slotIndex || 1) - 1
        groupEnabled.state = d.enabled
        groupFullDPS.state = d.includeInFullDPS
        if (!groupCount.editing) groupCount.text = String(d.groupCount)
    }

    // Debounced text edits: `apply` runs 300 ms after the last keystroke,
    // or at once on commit.
    component Debounce: Timer {
        property var apply: null
        property string value: ""
        interval: 300
        function push(v) { value = v; restart() }
        function flush(v) { stop(); value = v; if (apply) apply(value) }
        onTriggered: if (apply) apply(value)
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

            // --- Gem Options (SkillsTab.lua:121-150), under the list ---
            Widgets.Section {
                x: 20
                y: groupList.y + 20 + 300 + 45 + 50
                width: 360; height: 156
                label: "Gem Options"
            }
            Item {
                id: opts
                x: 20 + 170
                y: groupList.y + 20 + 300 + 45
                Widgets.CheckBox {
                    id: sortByDps
                    y: 70; width: 20; height: 20
                    label: "Sort gems by DPS:"
                    onToggled: function (s) { root.call("pob_skillsSetOption", ["sortGemsByDPS", s]) }
                }
                Widgets.DropDownControl {
                    id: sortField
                    x: 30; y: 70; width: 140; height: 20
                    model: root.lists.sortFields || []
                    onSelected: function (i) { root.call("pob_skillsSetOption", ["sortField", i + 1]) }
                }
                Widgets.Label {
                    anchors.right: defaultLevel.left; anchors.rightMargin: 4
                    anchors.verticalCenter: defaultLevel.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    label: "^7Default gem level:"; size: 16
                }
                Widgets.DropDownControl {
                    id: defaultLevel
                    y: 94; width: 170; height: 20
                    model: root.lists.defaultLevels || []
                    tooltipForItem: function (item, tt) {
                        const i = (root.lists.defaultLevels || []).indexOf(item)
                        const d = (root.lists.defaultLevelDescriptions || [])[i]
                        if (d) d.split("\n").forEach(function (l) { tt.addLine(16, "^7" + l) })
                    }
                    onSelected: function (i) { root.call("pob_skillsSetOption", ["defaultGemLevel", i + 1]) }
                }
                Widgets.Label {
                    anchors.right: defaultQuality.left; anchors.rightMargin: 4
                    anchors.verticalCenter: defaultQuality.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    label: "^7Default gem quality:"; size: 16
                }
                Widgets.EditControl {
                    id: defaultQuality
                    y: 118; width: 60; height: 20
                    isNumeric: true; maxChars: 2
                    onEdited: function (t) { root.call("pob_skillsSetOption", ["defaultGemQuality", t]) }
                }
                Widgets.Label {
                    anchors.right: supportTypes.left; anchors.rightMargin: 4
                    anchors.verticalCenter: supportTypes.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    label: "^7Show support gems:"; size: 16
                }
                Widgets.DropDownControl {
                    id: supportTypes
                    y: 142; width: 170; height: 20
                    model: root.lists.supportTypes || []
                    onSelected: function (i) { root.call("pob_skillsSetOption", ["showSupportGemTypes", i + 1]) }
                }
                Widgets.CheckBox {
                    id: showLegacy
                    y: 166; width: 20; height: 20
                    label: "^7Show legacy gems:"
                    onToggled: function (s) { root.call("pob_skillsSetOption", ["showLegacyGems", s]) }
                }
            }

            // --- Group detail (SkillsTab.lua:160-315), 20px right of the list ---
            Item {
                id: groupDetail
                x: 20 + 360 + 20
                y: groupList.y + 20
                visible: root.detail !== null
                readonly property int gi: root.st.displayIndex || 0
                readonly property bool isSource: !!(root.detail && root.detail.source)

                Debounce { id: labelDebounce; apply: function (v) { root.call("pob_skillsSetGroupLabel", [groupDetail.gi, v]) } }
                Debounce { id: countDebounce; apply: function (v) { root.call("pob_skillsSetGroupCount", [groupDetail.gi, v]) } }

                Widgets.EditControl {
                    id: groupLabel
                    width: 380; height: 20
                    placeholder: "Label"
                    maxChars: 50
                    onEdited: function (t) { labelDebounce.push(t) }
                    onCommitted: function (t) { labelDebounce.flush(t) }
                }
                Widgets.Label {
                    y: 30
                    width: 83
                    horizontalAlignment: Text.AlignRight
                    label: "^7Socketed in:"; size: 16
                }
                Widgets.DropDownControl {
                    id: groupSlot
                    x: 85; y: 28; width: 130; height: 20
                    model: root.lists.slots || []
                    popupMinWidth: 150
                    controlEnabled: !groupDetail.isSource
                    tooltipForItem: function (item, tt) {
                        const i = (root.lists.slots || []).indexOf(item)
                        const t = luaEngine.invoke("pob_skillsSlotTooltip", [i + 1])
                        StatDiff.fillFromLines(tt, t)
                    }
                    tooltipFunc: function (tt) {
                        StatDiff.fillFromLines(tt, luaEngine.invoke("pob_skillsSlotTooltip", [0]))
                    }
                    onSelected: function (i) { root.call("pob_skillsSetGroupSlot", [groupDetail.gi, i + 1]) }
                }
                Widgets.CheckBox {
                    id: groupEnabled
                    x: 85 + 130 + 70; y: 28; width: 20; height: 20
                    label: "Enabled:"
                    onToggled: function (s) { root.call("pob_skillsSetGroupEnabled", [groupDetail.gi, s]) }
                }
                Widgets.CheckBox {
                    id: groupFullDPS
                    x: groupEnabled.x + 20 + 145; y: 28; width: 20; height: 20
                    label: "Include in Full DPS:"
                    onToggled: function (s) { root.call("pob_skillsSetGroupFullDPS", [groupDetail.gi, s]) }
                }
                Widgets.Label {
                    id: countLabel
                    visible: groupDetail.isSource
                    x: groupFullDPS.x + 20 + 16; y: 30
                    label: "Count:"; size: 16
                }
                Widgets.EditControl {
                    id: groupCount
                    visible: groupDetail.isSource
                    x: countLabel.x + countLabel.implicitWidth + 4; y: 28; width: 60; height: 20
                    isNumeric: true; maxChars: 2
                    onEdited: function (t) { countDebounce.push(t) }
                    onCommitted: function (t) { countDebounce.flush(t) }
                }

                // Imbued Support (hidden for item/node-provided groups).
                Item {
                    visible: root.detail !== null && root.detail.imbuedShown
                    Widgets.Label {
                        id: imbuedLabel
                        x: 86; y: 58
                        label: "^xB8DAF1Imbued Support:"; size: 16
                    }
                    Widgets.GemSelect {
                        id: imbuedSelect
                        x: imbuedLabel.x + imbuedLabel.width + 8; y: 56
                        width: 250; height: 20
                        groupIndex: groupDetail.gi
                        row: 0
                        text: root.detail ? root.detail.imbuedName : ""
                        textColor: root.detail ? root.detail.imbuedColor : "^7"
                        controlEnabled: !!(root.detail && root.detail.imbuedEnabled)
                        onPicked: function (id) {
                            if (id !== (root.detail ? root.detail.imbuedId : ""))
                                root.call("pob_skillsSetImbued", [groupDetail.gi, id])
                        }
                    }
                    Widgets.Button {
                        x: imbuedSelect.x + 252; y: 56; width: 20; height: 20
                        label: "x"
                        controlEnabled: !!(root.detail && root.detail.imbuedEnabled)
                        tooltipText: "Remove this imbued support."
                        onClicked: root.call("pob_skillsSetImbued", [groupDetail.gi, ""])
                    }
                }

                // Source note for item / node / explode-provided groups.
                Widgets.ColorText {
                    visible: groupDetail.isSource
                    y: 60
                    sourceText: root.detail ? root.detail.sourceNote : ""
                    defaultColor: theme.text
                    font.pixelSize: 16
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
