import QtQuick
import "StatDiff.js" as StatDiff

// ItemAffixRow — one crafted-affix row of the display-item editor (Phase 6
// Part 6.3 item 3; ItemsTab.lua:756-984): the "Prefix:" / "Suffix:" /
// "Explicit:" label, the LIVE displayItemAffixN dropdown (one row per tier
// series, type-to-filter, row tooltip from the control's own tooltipFunc) and,
// when the picked series has a range, the displayItemAffixRangeN "Roll:"
// slider spanning all of its tiers (300 wide, or 100 for a single tier).
// `rec` is one pob_itemsGetLists().display.editor.affix.rows entry; every
// pick / move goes to the live control (pob_itemsDisplaySetControl).
Item {
    id: root

    property var rec: ({})
    readonly property string dropName: "displayItemAffix" + (rec.n || 0)
    readonly property string sliderName: "displayItemAffixRange" + (rec.n || 0)

    width: 460
    height: 24 + (rec.sliderShown === true ? 18 : 0)

    function call(name, args) { return luaEngine.invoke(name, args || []) }

    // Imperative push: DropDownControl writes its own currentIndex on a pick,
    // and a bound Slider.value would break on the first drag.
    function push() {
        const l = rec.list && rec.list.length !== undefined ? rec.list : []
        const m = []
        for (let i = 0; i < l.length; i++) m.push({ label: l[i], i: i + 1 })
        drop.model = m
        drop.currentIndex = (rec.sel || 1) - 1
        if (!slider.dragging && rec.val !== undefined) {
            slider.pushing = true
            slider.divCount = rec.divCount > 1 ? rec.divCount : 0
            slider.value = rec.val
            slider.pushing = false
        }
    }
    onRecChanged: push()
    Component.onCompleted: push()

    // Labels sit right of x 36, 4 px left of the controls (legacy anchors them
    // {"RIGHT", control, "LEFT"}); Qt paints wider than TextMetrics, so each
    // gets a real box with Qt's own right alignment (invariant #8).
    Label {
        x: 36 - width; y: 3
        width: 80
        horizontalAlignment: Text.AlignRight
        label: root.rec.label || ""
        size: 14
    }
    DropDownControl {
        id: drop
        x: 40
        width: 418; height: 20
        searchable: true
        maxVisibleItems: 14
        tooltipForItem: function (item, tt) {
            StatDiff.fillFromLines(tt, root.call("pob_itemsDisplayTooltip", [root.dropName, item.i]))
        }
        onSelected: function (i) { root.call("pob_itemsDisplaySetControl", [root.dropName, i + 1]) }
    }

    Label {
        visible: root.rec.sliderShown === true
        x: 36 - width; y: 24
        width: 80
        horizontalAlignment: Text.AlignRight
        label: root.rec.rollLabel || ""
        size: 14
    }
    Slider {
        id: slider
        property bool pushing: false
        property real pending: -1
        visible: root.rec.sliderShown === true
        x: 40; y: 22
        width: root.rec.sliderWidth || 100
        height: 16
        // The rolled lines + tier at the value under the cursor (or the live
        // value while dragging): the slider's own tooltipFunc.
        tooltipFunc: function (tt, v) {
            StatDiff.fillFromLines(tt, root.call("pob_itemsDisplayTooltip", [root.sliderName, 0, v]))
        }
        // Sent coalesced: every value re-crafts the item and rebuilds its tooltip.
        onValueChanged: {
            if (pushing) return
            const first = pending < 0
            pending = value
            if (first) Qt.callLater(function () {
                const v = slider.pending
                slider.pending = -1
                if (v >= 0) root.call("pob_itemsDisplaySetControl", [root.sliderName, v])
            })
        }
    }
}
