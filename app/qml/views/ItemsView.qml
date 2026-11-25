import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
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
    property string hoveredSlotName: ""
    property int hoveredSlotItemId: 0
    property bool _pending: false
    readonly property bool _typing: !!Window.activeFocusItem && (Window.activeFocusItem instanceof TextInput || Window.activeFocusItem instanceof TextEdit)
    readonly property bool _popupOpen: setManage.opened || textPopup.opened || craftNewPopup.opened
        || craftEnchant.opened || craftAnoint.opened || craftCorrupt.opened
        || craftImplicit.opened || craftCustom.opened || craftCrucible.opened
        || specManage.opened || deleteConfirm.opened || deleteAllConfirm.opened
        || sharedConfirm.opened
    readonly property bool _shortcutsActive: itemsView.visible && luaEngine.currentMode === "BUILD" && !_popupOpen

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
        const wasShown = display.shown === true
        const l = call("pob_itemsGetLists")
        lists = l ? l : ({})
        // SetDisplayItem snaps the tab right, Cancel snaps it left (snapHScroll).
        if (display.shown === true && !wasShown) snapRight()
        else if (display.shown !== true && wasShown) hflick.contentX = 0
    }

    // Double-click on any list row: open it as the display item and scroll
    // it into view (SetDisplayItem: snapHScroll = "RIGHT").
    function openEdit(kind, key) { call("pob_itemsOpenForEdit", [kind, key]) }
    // Craft buttons -> popups (Part 6.3 items 2-3).
    function openCraft(kind, slot) {
        const p = kind === "enchant" ? craftEnchant : kind === "anoint" ? craftAnoint
                : kind === "corrupt" ? craftCorrupt : kind === "custom" ? craftCustom
                : kind === "crucible" ? craftCrucible : craftImplicit
        p.openCraft(kind, slot)
    }
    // Absolute paths from the bridge; Windows ones ("C:/...") need a third slash.
    function fileUrl(p) { return p ? (p.charAt(0) === "/" ? "file://" : "file:///") + p : "" }
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
        enabled: itemsView._shortcutsActive && !itemsView._typing
        onActivated: itemsView.call("pob_itemsUndo")
    }
    Shortcut {
        sequences: ["Ctrl+Y", "Ctrl+Shift+Z"]
        enabled: itemsView._shortcutsActive && !itemsView._typing
        onActivated: itemsView.call("pob_itemsRedo")
    }
    Shortcut {
        sequence: "Ctrl+V"
        enabled: itemsView._shortcutsActive && !itemsView._typing
        onActivated: itemsView.call("pob_itemsPaste")
    }
    Shortcut {
        sequence: "E"
        enabled: itemsView._shortcutsActive && !itemsView._typing
        onActivated: {
            if (itemsView.hoveredSlotItemId > 0)
                itemsView.openEdit("item", itemsView.hoveredSlotItemId)
        }
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: itemsView._shortcutsActive
        onActivated: dbPanel.focusSearch()
    }
    Shortcut {
        sequence: "Ctrl+D"
        enabled: itemsView._shortcutsActive
        onActivated: {
            itemsView.call("pob_itemsToggleStatDiff")
            itemList.refreshTip()
            sharedList.refreshTip()
            dbPanel.refreshTip()
        }
    }

    Flickable {
        id: hflick
        anchors.fill: parent
        // Column 3 is as wide as the display item when one is shown.
        contentWidth: Math.max(width, 810 + (itemsView.display.shown === true ? displayPane.width : 340) + 20)
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
                                if (dd.hovered) {
                                    itemsView.hoveredSlotName = rec.slotName
                                    itemsView.hoveredSlotItemId = rec.selItemId
                                }
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
                                tooltipFunc: function (tt) {
                                    if (!rec || rec.selItemId === 0) return
                                    StatDiff.fillFromLines(tt, itemsView.call("pob_itemsSlotTooltip", [rec.slotName, rec.selItemId, false]))
                                }
                                tooltipForItem: function (item, tt) {
                                    if (item.id === 0) return
                                    StatDiff.fillFromLines(tt, itemsView.call("pob_itemsSlotTooltip", [rec.slotName, item.id, false]))
                                }
                                onHoveredChanged: {
                                    if (hovered && rec) {
                                        itemsView.hoveredSlotName = rec.slotName
                                        itemsView.hoveredSlotItemId = rec.selItemId
                                    } else if (rec && itemsView.hoveredSlotName === rec.slotName) {
                                        itemsView.hoveredSlotName = ""
                                        itemsView.hoveredSlotItemId = 0
                                    }
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

            // Craft / create buttons (ItemsTab.lua:296-304), shown with no display item.
            Widgets.Button {
                visible: !itemsView.display.shown
                x: 0; y: 8
                width: 120; height: 20
                label: "Craft item..."
                onClicked: craftNewPopup.openFresh()
            }
            Widgets.Button {
                visible: !itemsView.display.shown
                x: 128; y: 8
                width: 120; height: 20
                label: "Create custom..."
                onClicked: textPopup.openFor(false)
            }

            // Display item editor (ItemsTab.lua:323-472): Save / Edit / Cancel /
            // Buy similar, variant dropdowns, socket colours + links + "+", then
            // the item tooltip. Every edit goes to the LIVE legacy control.
            Item {
                id: displayPane
                visible: itemsView.display.shown === true
                x: 0; y: 8
                width: Math.max(470, tipCol.width + 16)
                height: parent.height - 8
                readonly property var ed: itemsView.display.editor ? itemsView.display.editor : ({})
                readonly property var variants: ed.variants && ed.variants.length !== undefined ? ed.variants : []
                readonly property var sockets: ed.sockets && ed.sockets.length !== undefined ? ed.sockets : []
                readonly property var socketList: ed.socketList && ed.socketList.length !== undefined ? ed.socketList : []
                readonly property var influence: ed.influence ? ed.influence : ({})
                readonly property var quality: ed.quality ? ed.quality : ({})
                readonly property var catalyst: ed.catalyst ? ed.catalyst : ({})
                readonly property var cluster: ed.cluster ? ed.cluster : ({})
                readonly property var affix: ed.affix ? ed.affix : ({})
                readonly property var affixRows: affix.rows && affix.rows.length !== undefined ? affix.rows : []
                readonly property var custom: ed.custom ? ed.custom : ({})
                readonly property var customRows: custom.rows && custom.rows.length !== undefined ? custom.rows : []
                readonly property var range: ed.range ? ed.range : ({})
                readonly property var stackedRows: range.stacked && range.stacked.length !== undefined ? range.stacked : []

                // Sliders send coalesced (Qt.callLater): every value re-crafts the
                // item and rebuilds its tooltip, so one send per event-loop pass.
                function sendSlider(slider, name) {
                    if (slider.pushing) return
                    const first = slider.pending < 0
                    slider.pending = slider.value
                    if (first) Qt.callLater(function () {
                        const v = slider.pending
                        slider.pending = -1
                        if (v >= 0) itemsView.call("pob_itemsDisplaySetControl", [name, v])
                    })
                }
                function pushSlider(slider, val, divCount) {
                    if (slider.dragging || val === undefined) return
                    slider.pushing = true
                    if (divCount !== undefined) slider.divCount = divCount
                    slider.value = val
                    slider.pushing = false
                }

                // Imperative pushes: EditControl.text / Slider.value break an
                // outside binding on the first user edit, so each refresh writes them.
                // A different display item drops whatever the user was typing:
                // the text belonged to the previous item.
                property var syncedKey: undefined
                function pushSections() {
                    // Read from `display` (not the derived properties): onEdChanged can
                    // fire during construction, before those later bindings exist.
                    const d = itemsView.display
                    const e = d.editor || ({})
                    const force = d.key !== syncedKey
                    syncedKey = d.key
                    const inf = e.influence || ({}), q = e.quality || ({})
                    const cat = e.catalyst || ({}), cl = e.cluster || ({})
                    if (inf.shown === true) {
                        infl1.model = inf.list; infl1.currentIndex = inf.sel1 - 1
                        infl2.model = inf.list; infl2.currentIndex = inf.sel2 - 1
                    }
                    // Not while typing: an unrelated refresh would eat the keystroke.
                    if (q.shown === true && (force || !qualEdit.editing)) qualEdit.text = q.text
                    if (cat.shown === true) { catDrop.model = cat.list; catDrop.currentIndex = cat.sel - 1 }
                    if (cat.qualityShown === true && (force || !catQual.editing)) catQual.text = cat.qualityText
                    if (cl.shown === true) {
                        clusterDrop.model = cl.list; clusterDrop.currentIndex = cl.sel - 1
                        if (!clusterSlider.dragging) {
                            clusterSlider.pushing = true
                            clusterSlider.divCount = cl.divCount || 0
                            clusterSlider.value = cl.val
                            clusterSlider.lastSent = cl.val
                            clusterSlider.pushing = false
                        }
                    }
                    const af = e.affix || ({}), rg = e.range || ({})
                    if (af.sortShown === true) { sortDrop.model = af.sortList; sortDrop.currentIndex = af.sortSel - 1 }
                    if (rg.shown === true) {
                        rangeDrop.model = rg.list; rangeDrop.currentIndex = rg.sel - 1
                        mutateBox.state = rg.mutate === true
                        pushSlider(rangeSlider, rg.val)
                    }
                }
                onEdChanged: pushSections()
                Component.onCompleted: pushSections()

                Row {
                    spacing: 8
                    Widgets.Button {
                        width: 100; height: 20
                        label: itemsView.display.addLabel || "Add to build"
                        onClicked: itemsView.call("pob_itemsAddDisplayItem")
                    }
                    Widgets.Button {
                        width: 60; height: 20
                        label: "Edit..."
                        onClicked: textPopup.openFor(false)
                    }
                    Widgets.Button {
                        width: 60; height: 20
                        label: "Cancel"
                        onClicked: itemsView.call("pob_itemsCloseDisplayItem")
                    }
                    // Buy similar is deferred to a future release (v1.1 trade integration).
                    Widgets.Button {
                        width: 100; height: 20
                        label: "Buy similar"
                        controlEnabled: false
                        tooltipText: "Coming in a future release."
                    }
                }

                Column {
                    id: editCol
                    y: 28
                    // Variants (ItemsTab.lua:351-421): 300 wide, 24 apart.
                    Item {
                        width: 300
                        height: displayPane.variants.length > 0 ? 28 + 24 * (displayPane.variants.length - 1) : 0
                        visible: height > 0
                        Repeater {
                            model: displayPane.variants.length
                            delegate: Widgets.DropDownControl {
                                readonly property var v: displayPane.variants[index]
                                y: index * 24
                                width: 300; height: 20
                                function push() { model = v.list; currentIndex = v.sel - 1 }
                                onVChanged: if (v) push()
                                Component.onCompleted: if (v) push()
                                onSelected: function (i) { itemsView.call("pob_itemsDisplaySetVariant", [v.n, i + 1]) }
                            }
                        }
                    }
                    // Sockets and links (ItemsTab.lua:423-472): colour boxes 64 apart.
                    Item {
                        width: 400
                        height: displayPane.ed.socketSection ? 28 : 0
                        visible: height > 0
                        Repeater {
                            model: 6
                            delegate: Item {
                                readonly property var s: displayPane.sockets[index]
                                x: index * 64
                                width: 64; height: 20
                                function push() {
                                    sockDrop.model = displayPane.socketList
                                    sockDrop.currentIndex = s.sel - 1
                                    linkBox.state = s.link
                                }
                                onSChanged: if (s) push()
                                Component.onCompleted: if (s) push()
                                Widgets.DropDownControl {
                                    id: sockDrop
                                    visible: !!(s && s.shown)
                                    width: 36; height: 20
                                    onSelected: function (i) { itemsView.call("pob_itemsDisplaySetSocket", [index + 1, i + 1]) }
                                }
                                Widgets.CheckBox {
                                    id: linkBox
                                    visible: !!(s && s.linkShown)
                                    x: 40
                                    width: 20; height: 20
                                    onToggled: function (st) { itemsView.call("pob_itemsDisplaySetLink", [index + 1, st]) }
                                }
                            }
                        }
                        Widgets.Button {
                            visible: displayPane.ed.addSocketShown === true
                            x: (displayPane.ed.addSocketAt || 0) * 64 - 12
                            width: 20; height: 20
                            label: "+"
                            onClicked: itemsView.call("pob_itemsDisplayAddSocket")
                        }
                    }
                    // Craft buttons (ItemsTab.lua:475-545): hidden ones collapse,
                    // the row wraps when wider than the pane.
                    Item {
                        width: displayPane.width
                        readonly property bool any: {
                            const b = displayPane.ed.craftButtons
                            if (!b) return false
                            for (const k in b) if (b[k] === true) return true
                            return false
                        }
                        height: any ? craftFlow.height + 8 : 0
                        visible: any
                        Flow {
                            id: craftFlow
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: [
                                    { key: "enchant1", label: "Apply Enchantment...", w: 160, kind: "enchant", slot: 1 },
                                    { key: "enchant2", label: "Apply Enchantment 2...", w: 160, kind: "enchant", slot: 2 },
                                    { key: "anoint1", label: "Anoint...", w: 100, kind: "anoint", slot: 1 },
                                    { key: "anoint2", label: "Anoint 2...", w: 100, kind: "anoint", slot: 2 },
                                    { key: "anoint3", label: "Anoint 3...", w: 100, kind: "anoint", slot: 3 },
                                    { key: "anoint4", label: "Anoint 4...", w: 100, kind: "anoint", slot: 4 },
                                    { key: "corrupt", label: "Corrupt...", w: 100, kind: "corrupt", slot: 1 },
                                    { key: "addImplicit", label: "Add Implicit...", w: 120, kind: "implicit", slot: 1 }
                                ]
                                delegate: Widgets.Button {
                                    visible: !!(displayPane.ed.craftButtons && displayPane.ed.craftButtons[modelData.key] === true)
                                    width: modelData.w; height: 20
                                    label: modelData.label
                                    onClicked: itemsView.openCraft(modelData.kind, modelData.slot)
                                }
                            }
                        }
                    }
                    // Influence (ItemsTab.lua:547-592): two 100-wide dropdowns.
                    Item {
                        width: 400
                        height: displayPane.influence.shown === true ? 28 : 0
                        visible: height > 0
                        Widgets.DropDownControl {
                            id: infl1
                            width: 100; height: 20
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemInfluence", i + 1]) }
                        }
                        Widgets.DropDownControl {
                            id: infl2
                            x: 108
                            width: 100; height: 20
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemInfluence2", i + 1]) }
                        }
                    }
                    // Quality (ItemsTab.lua:594-610).
                    Item {
                        width: 400
                        height: displayPane.quality.shown === true ? 28 : 0
                        visible: height > 0
                        Widgets.Label { id: qualLbl; y: 2; label: "^7Quality:"; size: 16 }
                        Widgets.EditControl {
                            id: qualEdit
                            x: qualLbl.width + 6
                            width: 60; height: 20
                            isNumeric: true
                            maxChars: 2
                            // Per keystroke like legacy's changeFunc. Esc reverts the box
                            // text, so send that too; on focus-out show the stored value
                            // (an emptied box reads back as 0).
                            onEdited: function (t) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemQualityEdit", t]) }
                            onReverted: itemsView.call("pob_itemsDisplaySetControl", ["displayItemQualityEdit", text])
                            onEditingChanged: if (!editing) displayPane.pushSections()
                        }
                    }
                    // Catalyst (ItemsTab.lua:612-652): 250-wide dropdown + 60-wide quality.
                    Item {
                        width: 400
                        height: (displayPane.catalyst.shown === true || displayPane.catalyst.qualityShown === true) ? 28 : 0
                        visible: height > 0
                        Widgets.DropDownControl {
                            id: catDrop
                            visible: displayPane.catalyst.shown === true
                            width: 250; height: 20
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemCatalyst", i + 1]) }
                        }
                        Widgets.EditControl {
                            id: catQual
                            visible: displayPane.catalyst.qualityShown === true
                            x: 252
                            width: 60; height: 20
                            isNumeric: true
                            maxChars: 2
                            onEdited: function (t) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemCatalystQualityEdit", t]) }
                            onReverted: itemsView.call("pob_itemsDisplaySetControl", ["displayItemCatalystQualityEdit", text])
                            onEditingChanged: if (!editing) displayPane.pushSections()
                        }
                    }
                    // Cluster jewel (ItemsTab.lua:654-674): skill dropdown + node count.
                    Item {
                        width: 400
                        height: displayPane.cluster.shown === true ? 52 : 0
                        visible: height > 0
                        Widgets.DropDownControl {
                            id: clusterDrop
                            width: 300; height: 20
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemClusterJewelSkill", i + 1]) }
                        }
                        Widgets.Label { id: clusterLbl; y: 27; label: "^7Added Passives:"; size: 14 }
                        Widgets.Slider {
                            id: clusterSlider
                            property bool pushing: false
                            // Last detent sent; legacy's val is continuous but only the
                            // rounded node count matters, and each call re-crafts the jewel.
                            property real lastSent: -1
                            x: clusterLbl.width + 6; y: 24
                            width: 150; height: 20
                            onValueChanged: {
                                if (pushing || divCount < 1) return
                                const snapped = Math.round(value * divCount) / divCount
                                if (snapped === lastSent) return
                                lastSent = snapped
                                itemsView.call("pob_itemsDisplaySetControl", ["displayItemClusterJewelNodeCount", snapped])
                            }
                        }
                        Widgets.Label {
                            x: clusterSlider.x + clusterSlider.width + 8; y: 27
                            label: "^7" + (displayPane.cluster.count !== undefined ? displayPane.cluster.count : "")
                            size: 14
                        }
                    }
                    // Modifier sorting (ItemsTab.lua:720-728): re-sorts every affix
                    // list by the stat picked (one calc per tier series, as legacy).
                    Item {
                        width: 400
                        height: displayPane.affix.sortShown === true ? 28 : 0
                        visible: height > 0
                        Widgets.Label { id: sortLbl; y: 2; label: "^7Modifier sorting:"; size: 16 }
                        Widgets.DropDownControl {
                            id: sortDrop
                            x: sortLbl.width + 4
                            width: 200; height: 20
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["craftingSorting", i + 1]) }
                        }
                    }
                    // Crafted affixes (ItemsTab.lua:730-984): one tier-series
                    // dropdown per prefix / suffix slot, each with its roll slider.
                    Item {
                        width: 460
                        height: affixCol.height > 0 ? affixCol.height + 6 : 0
                        visible: height > 0
                        Column {
                            id: affixCol
                            Repeater {
                                // A COUNT model: the rows array is new on every refresh,
                                // and a model over it would recreate a slider mid-drag.
                                model: displayPane.affixRows.length
                                delegate: Widgets.ItemAffixRow { rec: displayPane.affixRows[index] || ({}) }
                            }
                        }
                    }
                    // Custom modifiers (ItemsTab.lua:986-1010, rows :2430-2477):
                    // "Add modifier..." / "Add Crucible mod..." and a Remove row for
                    // each crafted, custom or crucible line.
                    Item {
                        id: customSec
                        readonly property var cu: displayPane.custom
                        width: 470
                        height: (cu.addShown === true || cu.crucibleShown === true) ? 28 + displayPane.customRows.length * 22 : 0
                        visible: height > 0
                        Widgets.Button {
                            visible: customSec.cu.addShown === true
                            width: 120; height: 20
                            label: "Add modifier..."
                            onClicked: itemsView.openCraft("custom", 1)
                        }
                        Widgets.Button {
                            visible: customSec.cu.crucibleShown === true
                            x: customSec.cu.addShown === true ? 128 : 0
                            width: 150; height: 20
                            label: "Add Crucible mod..."
                            onClicked: itemsView.openCraft("crucible", 1)
                        }
                        Repeater {
                            model: displayPane.customRows.length
                            delegate: Item {
                                readonly property var row: displayPane.customRows[index] || ({})
                                y: (index + 1) * 22 + 4
                                width: 470; height: 20
                                Widgets.Button {
                                    width: 70; height: 20
                                    label: "Remove"
                                    onClicked: itemsView.call("pob_itemsDisplayRemoveCustom", [index + 1])
                                }
                                Widgets.Label { x: 75; y: 2; label: row.kind || ""; size: 16 }
                                // Legacy cuts the text at 330 px (TextMetrics); Qt paints
                                // wider, so the box clips too (invariant #8).
                                Widgets.Label { x: 135; y: 2; width: 330; clip: true; label: row.text || ""; size: 16 }
                            }
                        }
                    }
                    // Modifier ranges (ItemsTab.lua:1012-1179): a line dropdown, the
                    // Foulborn swap box and a roll slider; with the Options "Show all
                    // item affixes sliders" a unique stacks one row per line instead.
                    Item {
                        id: rangeSec
                        readonly property var rg: displayPane.range
                        readonly property var rows: displayPane.stackedRows
                        // Row k sits max(22, 14 * lines) below row k-1 (ItemsTab.lua:1118-1122).
                        readonly property var rowY: {
                            const out = []
                            let y = 2
                            for (let k = 0; k < rows.length; k++) {
                                out.push(y)
                                y += Math.max(22, 14 * (rows[k].lines && rows[k].lines.length ? rows[k].lines.length : 1))
                            }
                            out.push(y)
                            return out
                        }
                        width: 470
                        height: rg.shown === true ? 28 : (rows.length > 0 ? rowY[rows.length] + 2 : 0)
                        visible: height > 0

                        Widgets.DropDownControl {
                            id: rangeDrop
                            visible: rangeSec.rg.shown === true
                            width: 350; height: 18
                            onSelected: function (i) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemRangeLine", i + 1]) }
                        }
                        Image {
                            visible: rangeSec.rg.shown === true && rangeSec.rg.mutateShown === true
                            x: 351; y: -1
                            width: 20; height: 20
                            source: rangeSec.rg.mutateShown === true ? itemsView.fileUrl(rangeSec.rg.icon) : ""
                        }
                        Widgets.CheckBox {
                            id: mutateBox
                            visible: rangeSec.rg.shown === true && rangeSec.rg.mutateShown === true
                            x: 375
                            width: 18; height: 18
                            onToggled: function (s) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemMutatedCheckbox", s]) }
                        }
                        Widgets.Slider {
                            id: rangeSlider
                            property bool pushing: false
                            property real pending: -1
                            visible: rangeSec.rg.sliderShown === true
                            // Left of a hidden Foulborn box the slider takes its place
                            // (collapsed anchor, ItemsTab.lua:1069-1077).
                            x: rangeSec.rg.mutateShown === true ? 397 : 358
                            width: 100; height: 18
                            onValueChanged: displayPane.sendSlider(rangeSlider, "displayItemRangeSlider")
                        }

                        Repeater {
                            model: rangeSec.rows.length
                            delegate: Item {
                                id: srow
                                readonly property var r: rangeSec.rows[index] || ({})
                                readonly property real lineX: r.sliderShown === true ? sslider.x + 104 : (r.mutateShown === true ? 46 : 0)
                                y: rangeSec.rowY[index] || 0
                                width: 470
                                height: Math.max(22, 14 * (r.lines && r.lines.length ? r.lines.length : 1))
                                function push() {
                                    sbox.state = r.mutate === true
                                    displayPane.pushSlider(sslider, r.val)
                                }
                                onRChanged: push()
                                Component.onCompleted: push()
                                Image {
                                    visible: srow.r.mutateShown === true
                                    width: 20; height: 20
                                    source: srow.r.mutateShown === true ? itemsView.fileUrl(rangeSec.rg.icon) : ""
                                }
                                Widgets.CheckBox {
                                    id: sbox
                                    visible: srow.r.mutateShown === true
                                    x: 24
                                    width: 18; height: 18
                                    onToggled: function (s) { itemsView.call("pob_itemsDisplaySetControl", ["displayItemStackedMutatedCheckbox" + srow.r.i, s]) }
                                }
                                Widgets.Slider {
                                    id: sslider
                                    property bool pushing: false
                                    property real pending: -1
                                    visible: srow.r.sliderShown === true
                                    x: srow.r.mutateShown === true ? 46 : 0
                                    width: 100; height: 18
                                    onValueChanged: displayPane.sendSlider(sslider, "displayItemStackedRangeSlider" + srow.r.i)
                                }
                                Column {
                                    x: srow.lineX
                                    y: 0
                                    Repeater {
                                        model: srow.r.lines && srow.r.lines.length !== undefined ? srow.r.lines : []
                                        delegate: Widgets.Label { label: modelData; size: 14 }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: tipBox
                    y: 28 + editCol.height
                    width: tipCol.width + 16
                    height: Math.min(parent.height - y, tipCol.height + 12)
                    color: theme.background
                    border.width: 1
                    border.color: (itemsView.display.color && itemsView.display.color !== "") ? itemsView.display.color : theme.border
                    clip: true
                    // Rarity header art + influence icons (Tooltip.lua:486-561).
                    Item {
                        visible: itemsView.display.showHeaderArt === true && !!itemsView.display.headerLeft && itemsView.displayLines.length > 0
                        x: 1; y: 1
                        width: Math.max(0, tipBox.width - 2)
                        height: itemsView.display.headerHeight || 0
                        clip: true
                        Image {
                            x: 0; y: 0
                            width: itemsView.display.headerSideWidth || 0; height: parent.height
                            source: parent.visible ? itemsView.fileUrl(itemsView.display.headerLeft) : ""
                        }
                        Image {
                            x: itemsView.display.headerSideWidth || 0; y: 0
                            width: Math.max(0, parent.width - 2 * (itemsView.display.headerSideWidth || 0))
                            height: parent.height
                            fillMode: Image.TileHorizontally
                            source: parent.visible ? itemsView.fileUrl(itemsView.display.headerMiddle) : ""
                        }
                        Image {
                            x: Math.max(0, parent.width - (itemsView.display.headerSideWidth || 0)); y: 0
                            width: itemsView.display.headerSideWidth || 0; height: parent.height
                            source: parent.visible ? itemsView.fileUrl(itemsView.display.headerRight) : ""
                        }
                        Image {
                            visible: !!(itemsView.display.influenceIcon1 && itemsView.display.influenceIcon1 !== "")
                            x: 4; anchors.verticalCenter: parent.verticalCenter
                            width: parent.height / 2; height: parent.height / 2
                            source: visible ? itemsView.fileUrl(itemsView.display.influenceIcon1) : ""
                        }
                        Image {
                            visible: !!(itemsView.display.influenceIcon2 && itemsView.display.influenceIcon2 !== "")
                            x: Math.max(0, parent.width - width - 4); anchors.verticalCenter: parent.verticalCenter
                            width: parent.height / 2; height: parent.height / 2
                            source: visible ? itemsView.fileUrl(itemsView.display.influenceIcon2) : ""
                        }
                    }
                    Column {
                        id: tipCol
                        x: 8; y: 6
                        Repeater {
                            model: itemsView.displayLines.length
                            delegate: Item {
                                readonly property var ln: itemsView.displayLines[index]
                                // Painted width (implicitWidth), not the TextMetrics
                                // one: Qt's font is wider (invariant #8).
                                width: Math.max(lineLbl.implicitWidth, itemsView.display.showHeaderArt === true ? 340 : 300)
                                height: ln.sep ? ln.size : ln.size + 2
                                Rectangle {
                                    visible: !!ln.sep
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: tipCol.width; height: 1
                                    color: theme.border
                                }
                                // A modifier line: hover highlight, any click disables /
                                // re-enables it (ItemsTab.lua:1529-1548); disabled lines
                                // are struck through (Tooltip.lua:302).
                                Rectangle {
                                    anchors.fill: parent
                                    visible: !!ln.toggle && lineMa.containsMouse
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                }
                                Widgets.Label {
                                    id: lineLbl
                                    visible: !ln.sep
                                    width: tipCol.width
                                    horizontalAlignment: ln.center ? Text.AlignHCenter : Text.AlignLeft
                                    label: ln.sep ? "" : (ln.text.length > 0 ? ln.text : " ")
                                    size: ln.size || 14
                                    font.strikeout: !!ln.strike
                                }
                                MouseArea {
                                    id: lineMa
                                    anchors.fill: parent
                                    enabled: !!ln.toggle
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    onClicked: itemsView.call("pob_itemsDisplayToggleLine", [index + 1])
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
    Widgets.ItemTextPopup {
        id: textPopup
        parent: itemsView
    }
    Widgets.CraftNewPopup {
        id: craftNewPopup
        parent: itemsView
        onCreated: function (openEditText) {
            if (openEditText) Qt.callLater(function () { textPopup.openFor(false) })
        }
    }
    // Craft popups over the captured legacy controls (Part 6.3 item 2).
    Widgets.CraftEnchantPopup { id: craftEnchant; parent: itemsView }
    Widgets.CraftAnointPopup { id: craftAnoint; parent: itemsView }
    Widgets.CraftCorruptPopup { id: craftCorrupt; parent: itemsView }
    Widgets.CraftImplicitPopup { id: craftImplicit; parent: itemsView }
    Widgets.CraftCustomPopup { id: craftCustom; parent: itemsView }
    Widgets.CraftCruciblePopup { id: craftCrucible; parent: itemsView }
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
