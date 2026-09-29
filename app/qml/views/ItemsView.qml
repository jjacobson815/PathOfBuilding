import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components" as Widgets
import "../components/StatDiff.js" as StatDiff

// ITEMS view — Phase 6. Part 6.1 (this file's left column): item-set row
// (dropdown, tooltip = set contents, Manage... popup), Weapon Set I/II
// buttons, the slot panel (one dropdown per slot, flask "active" boxes,
// jewel sockets that are allocated, abyssal sockets that the item has) and the
// passive-tree selector. Bridge: app/lua/pob_items.lua over the LIVE itemsTab.
// STATE MODEL: `st` = pob_itemsGetState(), re-read (coalesced) on
// items/tree/calcs/build/mode signals only — no frame loop (invariant #7).
// Everything is addressed by slot name / 1-based index / item id because
// legacy replaces item and set tables on undo.
// The right column is the OLD item browser (below), replaced by Part 6.2.
//
// ITEMS view (item browser). Extracted from main.qml (Part 1.1); behaviour
// unchanged. Bound to itemModel (the build's item list). Selecting an item
// shows its details (mods) in a side panel. A themed "Add from text" TextArea +
// button calls luaEngine.addItemFromRaw(text). Rarity colours come from the
// theme singleton via the local rarityColor() helper (moved here from the root
// Window — it is only used by this view). Visibility is parent-controlled.
Item {
    id: itemsView
    anchors.fill: parent
    clip: true

    // Currently selected item's map (from itemModel) so the details panel can
    // show its mods. Local to this view (was a root Window property).
    property var selectedItem: null

    // Map an item rarity string to its theme colour (no hex hardcoded in QML).
    function rarityColor(r) {
        if (r === "NORMAL") return theme.rarityNormal
        if (r === "MAGIC") return theme.rarityMagic
        if (r === "RARE") return theme.rarityRare
        if (r === "UNIQUE") return theme.rarityUnique
        if (r === "RELIC") return theme.rarityRelic
        return theme.text
    }

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

    // ------------------------------------------------------------------
    // Part 6.1 — left column (legacy: slotAnchor at x 96)
    // ------------------------------------------------------------------
    Item {
        id: leftCol
        x: 0; y: 0
        width: 424
        height: parent.height

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
    }
    Widgets.SpecManagePopup {
        id: specManage
        parent: itemsView
        onListEdited: itemsView.refresh()
    }

    // ------------------------------------------------------------------
    // Old item browser (replaced by Part 6.2)
    // ------------------------------------------------------------------
    Item {
        id: browserPane
        x: 430
        width: parent.width - 430
        height: parent.height
        clip: true

        // "Add from text" panel (top)
        ColumnLayout {
            id: itemsAddPanel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: theme.space2
            spacing: theme.space1
            Text {
                text: "Add item from text"
                color: theme.text
                font.bold: true
                font.pixelSize: theme.fontSize
            }
            RowLayout {
                spacing: theme.space1
                TextArea {
                    id: itemRawInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: theme.text
                    background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                    placeholderText: "Paste item text (Rarity: ...)"
                    font.pixelSize: theme.fontSize - 1
                    wrapMode: Text.WordWrap
                }
                Button {
                    text: "Add"
                    onClicked: {
                        if (itemRawInput.text.trim() !== "") {
                            luaEngine.addItemFromRaw(itemRawInput.text)
                            itemRawInput.text = ""
                        }
                    }
                }
            }
        }

        // Body: item list (left) + details (right)
        RowLayout {
            anchors.top: itemsAddPanel.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: theme.space2
            spacing: theme.space2

            // Item list
            ListView {
                id: itemListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.45
                model: itemModel
                clip: true
                highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
                focus: true
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 30
                    color: (ListView.isCurrentItem ? theme.accent
                           : (index % 2 ? theme.sideBarBg : "transparent"))
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: theme.space1
                        spacing: theme.space1
                        Text {
                            text: (model.isEquipped ? "● " : "") + (model.name || "?")
                            color: ListView.isCurrentItem ? theme.background : itemsView.rarityColor(model.rarity)
                            font.pixelSize: theme.fontSize
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        clip: true
                        }
                        Text {
                            text: model.baseName || model.type || ""
                            color: ListView.isCurrentItem ? theme.background : theme.muted
                            font.pixelSize: theme.fontSize - 2
                            elide: Text.ElideRight
                            Layout.preferredWidth: 120
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            itemListView.currentIndex = index
                            itemsView.selectedItem = itemModel.get(index)
                        }
                    }
                }
            }

            // Details panel
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.55
                color: theme.sideBarBg
                border.color: theme.section
                radius: theme.radiusControl
                clip: true
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: theme.space2
                    contentWidth: width
                    ColumnLayout {
                        spacing: theme.space1
                        width: parent.width
                        Text {
                            text: itemsView.selectedItem ? itemsView.selectedItem.name : "Select an item"
                            color: itemsView.selectedItem ? itemsView.rarityColor(itemsView.selectedItem.rarity) : theme.muted
                            font.bold: true
                            font.pixelSize: theme.fontSize + 2
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: itemsView.selectedItem
                            text: (itemsView.selectedItem ? (itemsView.selectedItem.baseName || itemsView.selectedItem.type || "") : "")
                                  + (itemsView.selectedItem && itemsView.selectedItem.quality ? ("  (Quality: " + itemsView.selectedItem.quality + ")") : "")
                                  + (itemsView.selectedItem && itemsView.selectedItem.level ? ("  (ilvl " + itemsView.selectedItem.level + ")") : "")
                            color: theme.muted
                            font.pixelSize: theme.fontSize - 1
                            Layout.fillWidth: true
                        elide: Text.ElideRight
                        clip: true
                        }
                        Text {
                            visible: itemsView.selectedItem && itemsView.selectedItem.isEquipped
                            text: "Equipped in: " + (itemsView.selectedItem ? itemsView.selectedItem.slotName : "")
                            color: theme.accent
                            font.pixelSize: theme.fontSize - 1
                            Layout.fillWidth: true
                        elide: Text.ElideRight
                        clip: true
                        }
                        Repeater {
                            model: itemsView.selectedItem ? itemsView.selectedItem.modLines : []
                            delegate: Text {
                                text: modelData
                                color: theme.text
                                font.pixelSize: theme.fontSize - 1
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
}
}
