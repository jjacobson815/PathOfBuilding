import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components" as Widgets
import "../components/StatDiff.js" as StatDiff

// ITEMS view — Phase 6. Bridge: app/lua/pob_items.lua over the LIVE itemsTab.
// STATE MODEL: `st` = pob_itemsGetState() (sets + slot panel) and `lists` =
// pob_itemsGetLists() (all-items rows, shared rows, the display item),
// re-read (coalesced) on items/tree/calcs/build/mode signals only — no frame
// loop (invariant #7). Everything is addressed by slot name / 1-based index /
// item id because legacy replaces item and set tables on undo.
//
// Layout (ItemsTab.lua, landscape): column 1 (x 0-424) = Part 6.1: item-set
// row, Weapon Set I/II, slot panel, passive tree selector. Column 2 (x 430)
// = Part 6.2: "All items" (ItemListControl) and below it the Uniques / Rare
// Templates DB (ItemDBPanel). Column 3 (x 810) = the display item (Part 6.3
// builds the editor on it) or the help text, and the shared item list. The
// tab scrolls horizontally like legacy (scrollBarH); a display item snaps it
// to the right (SetDisplayItem's snapHScroll).
//
// Drag-drop matrix (ItemsTab.lua:1002-1017): rows of the all-items, DB and
// shared lists drag (Widgets.DragGhost, payload { kind, key, shift }) onto
// slot rows, the all-items list, the shared list and the sidebar minion
// dropdown (MainSkillPanel).
Item {
    id: itemsView
    anchors.fill: parent
    clip: true

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    property var st: ({})
    readonly property var sets: st && st.sets && st.sets.length !== undefined ? st.sets : []
    readonly property var allSlots: st && st.slots && st.slots.length !== undefined ? st.slots : []
    // Visible rows: legacy shows a slot when its shown() is true (which also
    // hides inactive sockets / abyssal sockets the item does not have).
    property var shownSlots: []
    property var specList: ({})
    property var lists: ({})
    readonly property var itemRows: lists.items && lists.items.length !== undefined ? lists.items : []
    readonly property var sharedRows: lists.shared && lists.shared.length !== undefined ? lists.shared : []
    readonly property var display: lists.display ? lists.display : ({ shown: false })
    readonly property var displayLines: display.lines && display.lines.length !== undefined ? display.lines : []
    property bool _pending: false

    function call(name, args) { return luaEngine.invoke(name, args || []) }

    function refresh() {
        if (_pending) return
        _pending = true
        Qt.callLater(_doRefresh)
    }
    function _doRefresh() {
        _pending = false
        if (luaEngine.currentMode !== "BUILD") return
        const s = call("pob_itemsGetState")
        st = s ? s : ({})
        const rows = []
        for (let i = 0; i < allSlots.length; i++)
            if (allSlots[i].shown && !allSlots[i].inactive) rows.push(allSlots[i])
        shownSlots = rows
        const sp = call("pob_getSpecList")
        specList = sp ? sp : ({})
        setSelect.model = sets
        setSelect.currentIndex = (st.activeSet || 1) - 1
        const specs = (specList.specs && specList.specs.length !== undefined) ? specList.specs : []
        specSelect.model = specs.map(function (x) { return x.label })
        specSelect.currentIndex = (specList.active || 1) - 1
        const l = call("pob_itemsGetLists")
        lists = l ? l : ({})
    }

    // Double-click on any list row: open it as the display item and scroll
    // it into view (SetDisplayItem: snapHScroll = "RIGHT").
    function openEdit(kind, key) {
        if (call("pob_itemsOpenForEdit", [kind, key]).ok) snapRight()
    }
    function snapRight() { Qt.callLater(function () { hflick.contentX = Math.max(0, hflick.contentWidth - hflick.width) }) }

    // ItemListControl:OnSelDelete — ask only when the item is in use.
    function askDelete(itemId) {
        const q = call("pob_itemsDeleteQuery", [itemId])
        if (!q || !q.ok) return
        if (q.message === "") { call("pob_itemsDeleteItem", [itemId]); return }
        deleteConfirm.itemId = itemId
        deleteConfirm.message = q.message
        deleteConfirm.open()
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onItemsChanged() { itemsView.refresh() }
        function onTreeChanged() { itemsView.refresh() }
        function onCalcsChanged() { itemsView.refresh() }
        function onModeChanged() { itemsView.refresh() }
    }

    Shortcut {
        sequence: "Ctrl+Z"
        enabled: itemsView.visible && luaEngine.currentMode === "BUILD"
        onActivated: itemsView.call("pob_itemsUndo")
    }
    Shortcut {
        sequences: ["Ctrl+Y", "Ctrl+Shift+Z"]
        enabled: itemsView.visible && luaEngine.currentMode === "BUILD"
        onActivated: itemsView.call("pob_itemsRedo")
    }

    Flickable {
        id: hflick
        anchors.fill: parent
        contentWidth: Math.max(width, 810 + 340 + 20)
        contentHeight: height
        // Not draggable: mouse drags belong to the item lists (drag-drop).
        interactive: false
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar {
            policy: hflick.contentWidth > hflick.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        // --------------------------------------------------------------
        // Part 6.1 — column 1 (legacy: slotAnchor at x 96)
        // --------------------------------------------------------------
        Item {
            id: leftCol
            x: 0; y: 0
            width: 424
            height: hflick.height

            // Item set row (ItemsTab.lua:96-112)
            Widgets.Label {
                anchors.right: setSelect.left
                anchors.rightMargin: 2
                anchors.verticalCenter: setSelect.verticalCenter
                horizontalAlignment: Text.AlignRight
                label: "^7Item set:"
                size: 16
            }
            Widgets.DropDownControl {
                id: setSelect
                x: 96; y: 8
                width: 216; height: 20
                controlEnabled: itemsView.sets.length > 1
                labelFor: function (x) { return x.title }
                tooltipForItem: function (item, tt) {
                    const i = itemsView.sets.indexOf(item)
                    StatDiff.fillFromLines(tt, itemsView.call("pob_itemsSetTooltip", [i + 1]))
                }
                onSelected: function (i) { itemsView.call("pob_itemsSetActiveSet", [i + 1]) }
            }
            Widgets.Button {
                anchors.left: setSelect.right
                anchors.leftMargin: 4
                anchors.verticalCenter: setSelect.verticalCenter
                width: 90; height: 20
                label: "Manage..."
                onClicked: setManage.openFresh()
            }

            // "Equipped items:" header + Weapon Set I / II (ItemsTab.lua:221-266)
            Widgets.Label {
                x: 96; y: 44
                label: "^7Equipped items:"
                size: 16
            }
            Widgets.Label {
                anchors.right: ws1.left
                anchors.rightMargin: 4
                anchors.verticalCenter: ws1.verticalCenter
                horizontalAlignment: Text.AlignRight
                label: "^7Weapon Set:"
                size: 14
            }
            Widgets.Button {
                id: ws1
                x: 96 + 310 - 20 - 18; y: 42
                width: 18; height: 18
                label: "I"
                locked: !(itemsView.st.useSecondWeaponSet)
                onClicked: itemsView.call("pob_itemsSetWeaponSet", [1])
            }
            Widgets.Button {
                id: ws2
                x: 96 + 310 - 18; y: 42
                width: 18; height: 18
                label: "II"
                locked: !!itemsView.st.useSecondWeaponSet
                onClicked: itemsView.call("pob_itemsSetWeaponSet", [2])
            }

            // Slot panel + passive tree selector, scrolled together.
            Flickable {
                id: slotFlick
                x: 0; y: 64
                width: parent.width
                height: parent.height - 64
                contentWidth: width
                contentHeight: slotCol.height + 60
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }

                Column {
                    id: slotCol
                    x: 0
                    width: 96 + 310
                    spacing: 2

                    Repeater {
                        model: itemsView.shownSlots.length
                        delegate: Item {
                            id: row
                            readonly property var rec: itemsView.shownSlots[index]
                            width: slotCol.width; height: 20
                            function selIdx() {
                                const o = rec.options
                                for (let i = 0; i < o.length; i++) if (o[i].id === rec.selItemId) return i
                                return 0
                            }
                            function push() {
                                dd.model = rec.options
                                dd.currentIndex = selIdx()
                                if (rec.isFlask) activeBox.state = rec.flaskActive
                            }
                            onRecChanged: if (rec) push()
                            Component.onCompleted: if (rec) push()

                            Widgets.Label {
                                anchors.right: dd.left
                                anchors.rightMargin: rec && rec.isFlask ? 24 : 2
                                anchors.verticalCenter: dd.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                label: "^7" + (rec ? rec.label : "") + ":"
                                size: 16
                            }
                            Widgets.CheckBox {
                                id: activeBox
                                visible: !!(rec && rec.isFlask)
                                anchors.right: dd.left
                                anchors.rightMargin: 2
                                anchors.verticalCenter: dd.verticalCenter
                                width: 20; height: 20
                                controlEnabled: !!(rec && rec.selItemId !== 0)
                                tooltipText: "Activate this flask."
                                onToggled: function (s) { itemsView.call("pob_itemsSetFlaskActive", [rec.slotName, s]) }
                            }
                            Widgets.DropDownControl {
                                id: dd
                                x: 96; width: 310; height: 20
                                controlEnabled: !!(rec && rec.options.length > 1)
                                tooltipForItem: function (item, tt) {
                                    if (item.id === 0) return
                                    StatDiff.fillFromLines(tt, itemsView.call("pob_itemsSlotTooltip", [rec.slotName, item.id]))
                                }
                                onSelected: function (i) { itemsView.call("pob_itemsEquip", [rec.slotName, rec.options[i].id]) }
                            }
                            // Drag-receive (ItemSlotControl:CanReceiveDrag / ReceiveDrag).
                            DropArea {
                                id: slotDrop
                                anchors.fill: dd
                                keys: ["Item"]
                                onEntered: function (drag) {
                                    const p = drag.source ? drag.source.dragValue : null
                                    drag.accepted = !!p && itemsView.call("pob_itemsCanDropOnSlot", [rec.slotName, p.kind, p.key]) === true
                                }
                                onDropped: function (ev) {
                                    const p = ev.source ? ev.source.dragValue : null
                                    if (p) itemsView.call("pob_itemsDropOnSlot", [rec.slotName, p.kind, p.key])
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: slotDrop.containsDrag
                                    color: "transparent"
                                    border.width: 2
                                    border.color: theme.success
                                }
                            }
                        }
                    }

                    // Passive tree selector (ItemsTab.lua:191-204)
                    Item {
                        width: slotCol.width; height: 30
                        Widgets.Label {
                            anchors.right: specSelect.left
                            anchors.rightMargin: 2
                            anchors.verticalCenter: specSelect.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            label: "^7Passive tree:"
                            size: 16
                        }
                        Widgets.DropDownControl {
                            id: specSelect
                            x: 96; y: 8
                            width: 216; height: 20
                            controlEnabled: (specSelect.model ? specSelect.model.length : 0) > 1
                            onSelected: function (i) { itemsView.call("pob_setActiveSpec", [i + 1]) }
                        }
                        Widgets.Button {
                            x: 96 + 216 + 4; y: 8
                            width: 90; height: 20
                            label: "Manage..."
                            onClicked: specManage.openFresh()
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------------
        // Part 6.2 — column 2: all items + item DB (ItemsTab.lua:264-294)
        // --------------------------------------------------------------
        Widgets.ItemListBox {
            id: itemList
            x: 430; y: 8
            width: 360; height: 20 + 308
            title: "^7All items:"
            defaultText: "^x7F7F7FThis is the list of items that have been added to this build.\nYou can add items to this list by dragging them from\none of the other lists, or by clicking 'Add to build' when\nviewing an item."
            rows: itemsView.itemRows
            dragKind: "item"
            reorderable: true
            acceptKinds: ["unique", "rare", "shared"]
            tooltipFn: function (i, tt, shift) {
                StatDiff.fillFromLines(tt, itemsView.call("pob_itemsTooltip", ["item", itemsView.itemRows[i].key, shift]))
            }
            onCtrlClicked: function (i, shift) { itemsView.call("pob_itemsCtrlClick", ["item", itemsView.itemRows[i].key, shift]) }
            onDoubleClicked: function (i) { itemsView.openEdit("item", itemsView.itemRows[i].key) }
            onCopyRequested: function (i) { itemsView.call("pob_itemsCopy", ["item", itemsView.itemRows[i].key]) }
            onDeleteRequested: function (i) { itemsView.askDelete(itemsView.itemRows[i].key) }
            onMoved: function (from, to) { itemsView.call("pob_itemsMoveItem", [from + 1, to + 1]) }
            onDroppedIn: function (p, at) { itemsView.call("pob_itemsDropOnList", [p.kind, p.key, at + 1]) }
        }
        // ItemListControl buttons (ItemListControl.lua:15-67), right to left.
        Row {
            anchors.right: itemList.right
            y: itemList.y
            spacing: 4
            Widgets.Button { width: 60; height: 18; label: "Sort"
                onClicked: itemsView.call("pob_itemsSortList") }
            Widgets.Button { width: 100; height: 18; label: "Delete Unused"; controlEnabled: itemList.count > 0
                onClicked: itemsView.call("pob_itemsDeleteUnused") }
            Widgets.Button { width: 70; height: 18; label: "Delete All"; controlEnabled: itemList.count > 0
                onClicked: deleteAllConfirm.open() }
            Widgets.Button { width: 60; height: 18; label: "Delete"; controlEnabled: itemList.hasSel
                onClicked: itemsView.askDelete(itemsView.itemRows[itemList.selIndex].key) }
        }

        Widgets.ItemDBPanel {
            id: dbPanel
            x: 430; y: itemList.y + itemList.height + 14
            width: 360
            height: hflick.height - y - 14
            onRequestEdit: itemsView.snapRight()
        }

        // --------------------------------------------------------------
        // Column 3: display item (Part 6.3 editor) / help text, shared items
        // --------------------------------------------------------------
        Item {
            id: col3
            x: 810; y: 0
            width: 340
            height: hflick.height

            // ItemsTab.lua:305-316 (shown while there is no display item).
            Column {
                visible: !itemsView.display.shown
                x: 0; y: 36
                Repeater {
                    model: [
                        "Double-click an item from one of the lists,",
                        "or copy and paste an item from in game",
                        "(hover over the item and Ctrl+C) to view or edit",
                        "the item and add it to your build. You can ",
                        "also clone an item within Path of Building by ",
                        "copying and pasting it with Ctrl+C and Ctrl+V.",
                        "",
                        "You can Control + Click an item to equip it, or ",
                        "drag it onto the slot.  This will also add it to ",
                        "your build if it's from the unique/template list.",
                        "If there's 2 slots an item can go in, ",
                        "holding Shift will put it in the second."
                    ]
                    delegate: Widgets.Label { label: "^7" + modelData; size: 16 }
                }
            }

            // Display item (read-only until the Part 6.3 editor lands).
            Item {
                id: displayPane
                visible: itemsView.display.shown === true
                x: 0; y: 8
                width: 470
                height: parent.height - 8
                Row {
                    spacing: 8
                    Widgets.Button {
                        width: 100; height: 20
                        label: itemsView.display.addLabel || "Add to build"
                        controlEnabled: false
                        tooltipText: "The item editor arrives in Phase 6 Part 6.3."
                    }
                    Widgets.Button {
                        width: 100; height: 20
                        label: "Cancel"
                        onClicked: itemsView.call("pob_itemsCloseDisplayItem")
                    }
                }
                Rectangle {
                    y: 28
                    width: tipCol.width + 16
                    height: Math.min(parent.height - 28, tipCol.height + 12)
                    color: theme.background
                    border.width: 1
                    border.color: theme.border
                    clip: true
                    Column {
                        id: tipCol
                        x: 8; y: 6
                        Repeater {
                            model: itemsView.displayLines.length
                            delegate: Item {
                                readonly property var ln: itemsView.displayLines[index]
                                width: Math.max(lineLbl.width, 300)
                                height: ln.sep ? ln.size : ln.size + 2
                                Rectangle {
                                    visible: !!ln.sep
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 1
                                    color: theme.border
                                }
                                Widgets.Label {
                                    id: lineLbl
                                    visible: !ln.sep
                                    x: ln.center ? (parent.width - width) / 2 : 0
                                    label: ln.sep ? "" : (ln.text.length > 0 ? ln.text : " ")
                                    size: ln.size || 14
                                }
                            }
                        }
                    }
                }
            }

            // Shared items (ItemsTab.lua:318; SharedItemListControl). Hidden
            // under a display item (legacy draws the item over it).
            Widgets.ItemListBox {
                id: sharedList
                visible: !itemsView.display.shown
                x: 0; y: 8 + 20 + 232
                width: 340; height: 20 + 308
                title: "^7Shared items:"
                defaultText: "^x7F7F7FThis is a list of items that will be shared between all of\nyour builds.\nYou can add items to this list by dragging them from\none of the other lists."
                rows: itemsView.sharedRows
                dragKind: "shared"
                reorderable: true
                acceptKinds: ["item", "unique", "rare"]
                tooltipFn: function (i, tt, shift) {
                    StatDiff.fillFromLines(tt, itemsView.call("pob_itemsTooltip", ["shared", i + 1, shift]))
                }
                onDoubleClicked: function (i) { itemsView.openEdit("shared", i + 1) }
                onCopyRequested: function (i) { itemsView.call("pob_itemsCopy", ["shared", i + 1]) }
                onDeleteRequested: function (i) { sharedConfirm.openFor(i) }
                onMoved: function (from, to) { itemsView.call("pob_itemsMoveShared", [from + 1, to + 1]) }
                onDroppedIn: function (p, at) { itemsView.call("pob_itemsDropOnShared", [p.kind, p.key, at + 1]) }
            }
            Widgets.Button {
                visible: sharedList.visible
                anchors.right: sharedList.right
                y: sharedList.y
                width: 60; height: 18
                label: "Delete"
                controlEnabled: sharedList.hasSel
                onClicked: sharedConfirm.openFor(sharedList.selIndex)
            }
        }
    }

    Widgets.SetManagePopup {
        id: setManage
        parent: itemsView
        title: "Manage Item Sets"
        noun: "item set"
        deleteTitle: "Delete Item Set"
        fn: ({
            list: "pob_itemsGetSetList",
            setActive: "pob_itemsSetActiveSet",
            create: "pob_itemsNewSet",
            copy: "pob_itemsCopySet",
            rename: "pob_itemsRenameSet",
            remove: "pob_itemsDeleteSet",
            move: "pob_itemsMoveSet",
        })
        // Shared item sets pane (ItemsTab:OpenItemSetManagePopup, 2125-2135).
        sharedFn: ({
            list: "pob_itemsGetSharedSets",
            tooltip: "pob_itemsSharedSetTooltip",
            share: "pob_itemsShareSet",
            importSet: "pob_itemsImportSharedSet",
            rename: "pob_itemsRenameSharedSet",
            remove: "pob_itemsDeleteSharedSet",
        })
        onListEdited: itemsView.refresh()
    }
    Widgets.SpecManagePopup {
        id: specManage
        parent: itemsView
        onListEdited: itemsView.refresh()
    }

    // Confirms (message set when opened: a bound message crashed Qt 6.4).
    Widgets.ConfirmPopup {
        id: deleteConfirm
        parent: itemsView
        property var itemId: 0
        title: "Delete Item"
        confirmLabel: "Delete"
        onAccepted: itemsView.call("pob_itemsDeleteItem", [itemId])
    }
    Widgets.ConfirmPopup {
        id: deleteAllConfirm
        parent: itemsView
        title: "Delete All"
        message: "Are you sure you want to delete all items in this build?"
        confirmLabel: "Delete"
        onAccepted: itemsView.call("pob_itemsDeleteAll")
    }
    Widgets.ConfirmPopup {
        id: sharedConfirm
        parent: itemsView
        property int index: -1
        function openFor(i) {
            if (i < 0 || i >= itemsView.sharedRows.length) return
            index = i
            message = "Are you sure you want to remove '" + itemsView.sharedRows[i].name + "' from the shared item list?"
            open()
        }
        title: "Delete Item"
        confirmLabel: "Delete"
        onAccepted: itemsView.call("pob_itemsDeleteShared", [index + 1])
    }
}
