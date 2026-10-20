import QtQuick
import "StatDiff.js" as StatDiff

// ItemDBPanel — Phase 6 Part 6.2: the "Import from:" Uniques / Rare
// Templates switch plus one ItemDBControl (ItemDBControl.lua): slot / type
// filters, for uniques also sort / league / requirement / obtainable, and the
// search box + search mode, over the DB list.
//
// The filters ARE the live legacy controls (pob_itemsDBSetFilter sets
// selIndex / search.buf and runs the control's own callback). The list is
// legacy's ListBuilder coroutine; its only driver (ItemDBControl:Draw) never
// runs in the host, so `stepTimer` pumps pob_itemsDBStep in slices — first
// the Main.lua item loader while the DB is still loading, then the list
// build ("Sorting... (N%)" on the stat-sort path). The timer is job-scoped:
// it starts when the panel is shown or a filter / recalc invalidates the list
// and stops as soon as the step reports nothing left to do (invariant #7).
//
// Layout follows ItemsTab.lua:271-294 for a tab shorter than 980px (one DB
// at a time, chosen by the selector); y = 0 is the "Import from:" row.
Item {
    id: root

    property var st: ({})
    readonly property string which: st.selectDB === 2 ? "rare" : "unique"
    readonly property bool isUnique: which === "unique"
    readonly property var rows: st.rows && st.rows.length !== undefined ? st.rows : []
    readonly property int listTop: isUnique ? 104 : 64

    signal requestEdit()          // a row was opened in the display item

    function call(name, args) { return luaEngine.invoke(name, args || []) }

    function refresh() {
        const s = call("pob_itemsDBState", [which])
        st = s ? s : ({})
        _push()
        if (st.building && visible && !stepTimer.running) stepTimer.start()
    }

    // Filter dropdowns / search own their state once edited: push after reads.
    function _push() {
        const f = st.filters || {}
        const set = function (dd, key) {
            const x = f[key]
            dd.model = x && x.list && x.list.length !== undefined ? x.list : []
            dd.currentIndex = x ? x.sel - 1 : -1
        }
        set(slotDrop, "slot"); set(typeDrop, "type"); set(searchModeDrop, "searchMode")
        if (isUnique) {
            set(sortDrop, "sort"); set(leagueDrop, "league")
            set(reqDrop, "requirement"); set(obtainDrop, "obtainable")
        }
        if (!search.editing) search.text = st.search || ""
        selectDB.currentIndex = (st.selectDB || 1) - 1
    }

    function setFilter(name, value) {
        call("pob_itemsDBSetFilter", [which, name, value])
        refresh()
    }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Connections {
        target: luaEngine
        // A recalc bumps outputRevision; legacy rebuilds the list on the next Draw.
        function onCalcsChanged() { if (root.visible) root.refresh() }
        function onModeChanged() { if (root.visible) root.refresh() }
    }

    Timer {
        id: stepTimer
        interval: 1
        repeat: true
        onTriggered: {
            const r = root.call("pob_itemsDBStep", [root.which])
            if (!r || !r.running) {
                stop()
                if (r && r.error) console.warn("item DB: " + r.error)
            }
            root.refresh()
        }
    }

    // "Import from:" (ItemsTab.lua:271-276)
    Label {
        id: selectLbl
        x: 0; y: 0
        label: "^7Import from:"
        size: 16
    }
    DropDownControl {
        id: selectDB
        // Fixed x, not anchored to the label: its TextMetrics width is the
        // legacy measurement and Qt paints wider (invariant #8).
        x: 96
        anchors.verticalCenter: selectLbl.verticalCenter
        width: 150; height: 18
        model: ["Uniques", "Rare Templates"]
        onSelected: function (i) { root.setFilter("selectDB", i + 1) }
    }

    // Filters (ItemDBControl.lua:30-56), anchored above the list.
    DropDownControl {
        id: slotDrop
        x: 0; y: root.listTop - (root.isUnique ? 62 : 22) - 18
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("slot", i + 1) }
    }
    DropDownControl {
        id: typeDrop
        anchors.left: slotDrop.right; anchors.leftMargin: 2
        y: slotDrop.y
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("type", i + 1) }
    }
    DropDownControl {
        id: sortDrop
        visible: root.isUnique
        x: 0; y: root.listTop - 42 - 18
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("sort", i + 1) }
    }
    DropDownControl {
        id: leagueDrop
        visible: root.isUnique
        anchors.left: sortDrop.right; anchors.leftMargin: 2
        y: sortDrop.y
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("league", i + 1) }
    }
    DropDownControl {
        id: reqDrop
        visible: root.isUnique
        x: 0; y: sortDrop.y + 18 + 11 - 9
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("requirement", i + 1) }
    }
    DropDownControl {
        id: obtainDrop
        visible: root.isUnique
        anchors.left: reqDrop.right; anchors.leftMargin: 2
        y: reqDrop.y
        width: 179; height: 18
        onSelected: function (i) { root.setFilter("obtainable", i + 1) }
    }
    EditControl {
        id: search
        x: 0; y: root.listTop - 2 - 18
        width: 258; height: 18
        placeholder: "Search"
        onEdited: function (text) { root.setFilter("search", text) }
    }
    DropDownControl {
        id: searchModeDrop
        anchors.left: search.right; anchors.leftMargin: 2
        y: search.y
        width: 100; height: 18
        onSelected: function (i) { root.setFilter("searchMode", i + 1) }
    }

    ItemListBox {
        id: dbList
        y: root.listTop
        width: 360
        height: Math.max(40, Math.min(root.isUnique ? 244 : 260, root.height - root.listTop))
        rows: root.st.building ? [] : root.rows
        defaultText: root.st.text || ""
        dragKind: root.which
        tooltipFn: function (i, tt, shift) {
            StatDiff.fillFromLines(tt, root.call("pob_itemsTooltip", [root.which, root.rows[i].key, shift]))
        }
        onCtrlClicked: function (i, shift) { root.call("pob_itemsCtrlClick", [root.which, root.rows[i].key, shift]) }
        onDoubleClicked: function (i) {
            if (root.call("pob_itemsOpenForEdit", [root.which, root.rows[i].key]).ok) root.requestEdit()
        }
        onCopyRequested: function (i) { root.call("pob_itemsCopy", [root.which, root.rows[i].key]) }
    }
}
