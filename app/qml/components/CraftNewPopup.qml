import QtQuick
import "StatDiff.js" as StatDiff

// CraftNewPopup — Phase 6 Part 6.3 item 4: ItemsTab:CraftItem
// (ItemsTab.lua:2774-2858). Pick rarity, optional title (for Rare/Unique/Relic),
// item base type and base (with live base-item tooltip on control + dropdown
// rows). Create builds the display item and, when non-crafted & non-NORMAL
// (Unique / Relic), triggers ItemTextPopup via the `created` signal.
PopupBase {
    id: root

    title: "Craft Item"
    padding: 8

    signal created(bool openEditText)

    function _setBases(list, sel) {
        const arr = (list && list.length !== undefined) ? list : []
        const mapped = []
        for (let i = 0; i < arr.length; i++) mapped.push({ idx: i + 1, label: arr[i] })
        baseDrop.model = mapped
        baseDrop.currentIndex = Math.max(0, Math.min(mapped.length - 1, (sel || 1) - 1))
    }

    function openFresh() {
        const init = luaEngine.invoke("pob_itemsCraftNewInit", []) || {}
        const rars = (init.rarities && init.rarities.length !== undefined) ? init.rarities : []
        const types = (init.types && init.types.length !== undefined) ? init.types : []
        rarityDrop.model = rars
        rarityDrop.currentIndex = Math.max(0, Math.min(rars.length - 1, (init.raritySel || 3) - 1))
        titleEdit.text = ""
        typeDrop.model = types
        typeDrop.currentIndex = Math.max(0, Math.min(types.length - 1, (init.typeSel || 1) - 1))
        _setBases(init.bases, init.baseSel)
        open()
    }

    function _onTypeSelected(i) {
        const r = luaEngine.invoke("pob_itemsCraftNewInit", [i + 1])
        if (r && r.ok) _setBases(r.bases, r.baseSel)
    }

    function _fillBaseTooltip(tt, baseIdx) {
        if (rarityDrop.currentIndex < 0 || typeDrop.currentIndex < 0 || baseIdx < 1) return
        const r = luaEngine.invoke("pob_itemsCraftNewTooltip", [
            rarityDrop.currentIndex + 1,
            titleEdit.text,
            typeDrop.currentIndex + 1,
            baseIdx
        ])
        StatDiff.fillFromLines(tt, r)
    }

    function _create() {
        if (rarityDrop.currentIndex < 0 || typeDrop.currentIndex < 0 || baseDrop.currentIndex < 0) return
        const r = luaEngine.invoke("pob_itemsCraftNewCreate", [
            rarityDrop.currentIndex + 1,
            titleEdit.text,
            typeDrop.currentIndex + 1,
            baseDrop.currentIndex + 1
        ])
        if (r && r.ok) {
            accept()
            created(r.openEditText === true)
        }
    }

    Item {
        implicitWidth: 360
        implicitHeight: 130

        Label {
            x: 0; y: 20
            width: 50; height: 18
            horizontalAlignment: Text.AlignRight
            label: "^7Rarity:"
            size: 16
        }
        DropDownControl {
            id: rarityDrop
            x: 55; y: 20
            width: 100; height: 18
        }
        EditControl {
            id: titleEdit
            visible: rarityDrop.currentIndex >= 2
            x: 160; y: 20
            width: 190; height: 18
            placeholder: "Name"
        }

        Label {
            x: 0; y: 45
            width: 50; height: 18
            horizontalAlignment: Text.AlignRight
            label: "^7Type:"
            size: 16
        }
        DropDownControl {
            id: typeDrop
            x: 55; y: 45
            width: 295; height: 18
            searchable: true
            onSelected: function (i) { root._onTypeSelected(i) }
        }

        Label {
            x: 0; y: 70
            width: 50; height: 18
            horizontalAlignment: Text.AlignRight
            label: "^7Base:"
            size: 16
        }
        DropDownControl {
            id: baseDrop
            x: 55; y: 70
            width: 200; height: 18
            searchable: true
            labelFor: function (x) { return x.label }
            tooltipFunc: function (tt) { root._fillBaseTooltip(tt, baseDrop.currentIndex + 1) }
            tooltipForItem: function (item, tt) { root._fillBaseTooltip(tt, item.idx) }
        }

        Button {
            x: 180 - 45 - 40; y: 100
            width: 80; height: 20
            label: "Create"
            onClicked: root._create()
        }
        Button {
            x: 180 + 45 - 40; y: 100
            width: 80; height: 20
            label: "Cancel"
            onClicked: root.reject()
        }
    }
}
