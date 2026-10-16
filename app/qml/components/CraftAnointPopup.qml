import QtQuick

// CraftAnointPopup — ItemsTab:AnointDisplayItem (ItemsTab.lua:2597-2634),
// "Anoint Item" 380 x 448: a NotableDBControl (sort, search + mode, the
// 360 x 360 notable list) and a save button whose label reads "Anoint X" /
// "Remove X" / "No Anoint". The list build is a coroutine that legacy drives
// from the control's Draw, which never runs in the host: a job-scoped Timer
// pumps pob_itemsCraftStep until it finishes (stat sorts report their
// "Sorting... (N%)" through the list's default text).
CraftPopupBase {
    id: root

    readonly property var notables: rec("notableDB")
    readonly property var rows: notables.rows && notables.rows.length !== undefined ? notables.rows : []
    property string _lastText: ""

    Timer {
        interval: 15
        repeat: true
        running: root.visible && root.live && root.notables.building === true
        onTriggered: {
            const r = root._invoke("pob_itemsCraftStep")
            if (!r || r.error || r.running === false || r.text !== root._lastText) {
                root._lastText = r ? (r.text || "") : ""
                root.refresh()
            }
        }
    }

    Item {
        implicitWidth: 380
        implicitHeight: root.frameH

        CraftDrop { craft: root; name: "notableDB.sort"; x: 10; y: 20; width: 360; height: 18 }
        CraftEdit { craft: root; name: "notableDB.search"; x: 10; y: 40; width: 258; height: 18 }
        CraftDrop { craft: root; name: "notableDB.searchMode"; x: 270; y: 40; width: 100; height: 18 }

        ItemListBox {
            id: list
            x: 10; y: 60; width: 360; height: 360
            rows: root.rows
            defaultText: root.notables.text || ""
            tooltipFn: function (i, tt) { root.fillTip(tt, "notableDB", i + 1) }
            // Imperative push of the live selection; a user click forwards it.
            property bool pushing: false
            function push() {
                pushing = true
                selIndex = root.notables.sel !== undefined ? root.notables.sel - 1 : -1
                pushing = false
            }
            Connections { target: root; function onStChanged() { list.push() } }
            onSelIndexChanged: if (!pushing && selIndex >= 0) root.set("notableDB", selIndex + 1)
        }

        Row {
            x: (380 - width) / 2
            y: root.frameH - 24
            spacing: 10
            CraftButton {
                craft: root; name: "save"
                tip: true
                // Qt paints wider than TextMetrics (invariant #8): leave headroom.
                width: Math.max(80, textMetrics.width(16, "VAR", r.label || "") * 1.2 + 24)
            }
            CraftButton { craft: root; name: "close"; width: 80 }
        }
    }
}
