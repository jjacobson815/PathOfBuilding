import QtQuick

// StatPanel — Phase 3 sidebar stat list, ported from legacy
// buildMode:RefreshStatList (src/Modules/Build.lua:1769) plus the
// buildMode:AddDisplayStatList row emitter it calls (Build.lua:1637), rendered
// over the Part 2.3 output bridge (pob_getOutput / LuaEngine::getOutput)
// instead of legacy's mutable `self.controls.statBox.list` draw list.
//
// Legacy renders this through TextListControl with the column spec
// `{{x=170,align="RIGHT_X"},{x=174,align="LEFT"}}` (Build.lua:578). Those x
// values are ANCHOR POINTS, not box offsets — RIGHT_X means the text's right
// edge lands on 170 — so the label column is positioned as `x: 170 - width`
// here rather than as a right-aligned text box. Same for the CENTER_X rows,
// whose x=140 is the text's centre. (This is exactly the anchor-point
// precision TextListControl.qml's header documents as deliberately simplified;
// a real consumer now exists, so StatPanel does it properly rather than
// reusing that component.)
//
// Row heights are the legacy per-row constants (18 header / 16 stat / 14
// sub-row / 10 spacer) and double as the DrawString font size, because legacy
// passes each row's height straight through as the size argument. They are
// ported geometry, not theme tokens — same status as ScrollBar.qml's 500/50ms
// hold timings and Section.qml's label-plate offsets. Every COLOUR, by
// contrast, comes from `theme`: the legacy `^7`/`^8`/CUSTOM/WARNING codes that
// Build.lua bakes into these strings are re-derived from theme tokens by
// `_code()` below, so the row text keeps its legacy shape without hardcoding
// Data/Global.lua's palette (Tier 0 "Cyber Citrus" rule).
//
// Deviations from legacy (documented, not gaps):
//   - SkillDPS rows come AFTER all other player stats. Legacy emits them at
//     the position "SkillDPS" occupies inside displayStats (near the top,
//     after FullDPS) because it walks one list; the bridge splits the payload
//     into `stats` and `skillDPS`, which loses that interleave point. Ordering
//     within each group is preserved exactly (the bridge keeps the legacy
//     dps*count sort).
//   - mainSkill.infoMessage / infoMessage2 (the CENTER_X rows legacy puts
//     above the Minion block, Build.lua:1772-1783, and inside it) are not
//     reproduced: pob_getOutput does not marshal them, and adding a field is a
//     bridge change, out of scope for a QML-only pass.
//   - Header rows ("Minion:", "Player:", "Skill disabled:") render full width
//     from x=0. Legacy has no header row kind — those rows fall through to
//     column 1 and are therefore right-anchored at x=170 like a stat label.
//   - Warning rows need no special casing: pob_buildStatRecords already bakes
//     colorCodes.NEGATIVE into `valueStr` when a stat is over its pool, and
//     surfaces the same fact as `warning` for consumers that want it.
Item {
    id: root

    // --- Legacy geometry (Build.lua:578 column spec + per-row heights) ------
    readonly property int colLabelX: 170     // RIGHT_X anchor for the label column
    readonly property int colValueX: 174     // LEFT anchor for the value column
    readonly property int colCenterX: 140    // CENTER_X anchor for centred rows
    readonly property int rowHeightHeader: 18
    readonly property int rowHeightStat: 16
    readonly property int rowHeightSub: 14
    readonly property int rowHeightSpacer: 10

    // --- Bridge data --------------------------------------------------------
    // getOutput() FORCES a recalc, so it must never appear in a binding
    // expression. It is called only from refresh(), and the result is cached
    // here; everything downstream is a pure function of this snapshot.
    property var output: ({})

    function refresh() {
        output = luaEngine.getOutput() || {}
    }

    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onCalcsChanged() { root.refresh() }
    }

    // --- Derived row list ---------------------------------------------------
    // Pure function of `output`, hence safe as a binding.
    readonly property var rows: buildRows(output)
    readonly property int statCount: rows.length
    readonly property real contentHeight: {
        var h = 0
        for (var i = 0; i < rows.length; i++) h += rows[i].height
        return h
    }

    // Legacy colour codes, re-derived from theme tokens. `_code(theme.text)`
    // stands in for "^7", theme.muted for "^8", theme.accentAlt for
    // colorCodes.CUSTOM (the SkillDPS label colour) and theme.warning for
    // colorCodes.WARNING (trigger / "from <source>"). Colour escapes measure
    // as zero width in TextMetrics, so embedding them does not disturb the
    // right-anchored column.
    function _code(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "^x" + (h(c.r) + h(c.g) + h(c.b)).toUpperCase()
    }
    readonly property string ccText: _code(theme.text)
    readonly property string ccDim: _code(theme.muted)
    readonly property string ccSkill: _code(theme.accentAlt)
    readonly property string ccTrigger: _code(theme.warning)

    // Mirrors RefreshStatList's insertion order exactly (Build.lua:1769-1809).
    function buildRows(o) {
        var out = []
        if (!o) return out
        if (o.minion) {
            out.push({ kind: "header", left: ccText + "Minion:", right: "",
                       height: rowHeightHeader })
            _pushStats(out, o.minion.stats)
            out.push({ kind: "spacer", left: "", right: "",
                       height: rowHeightSpacer })
            out.push({ kind: "header", left: ccText + "Player:", right: "",
                       height: rowHeightHeader })
        }
        if (o.disableReason) {
            out.push({ kind: "header", left: ccText + "Skill disabled:", right: "",
                       height: rowHeightStat })
            out.push({ kind: "center", left: o.disableReason, right: "",
                       height: rowHeightSub })
        }
        if (o.player) {
            _pushStats(out, o.player.stats)
            _pushSkillDPS(out, o.player.skillDPS)
        }
        return out
    }

    // AddDisplayStatList's plain-stat branch (Build.lua:1691-1695): the label
    // column is `labelColor..label..":"`, the value column is the already
    // FormatStat'd string the bridge produced.
    function _pushStats(out, stats) {
        if (!stats) return
        for (var i = 0; i < stats.length; i++) {
            var s = stats[i]
            out.push({
                kind: "stat",
                left: (s.color && s.color.length > 0 ? s.color : ccText)
                      + (s.label || "") + ":",
                right: s.valueStr || "",
                height: rowHeightStat
            })
        }
    }

    // AddDisplayStatList's SkillDPS branch (Build.lua:1656-1683): "Nx " prefix
    // at count >= 2, a WARNING-coloured "(trigger)" suffix, then the optional
    // skillPart / "from <source>" CENTER_X sub-rows.
    function _pushSkillDPS(out, list) {
        if (!list) return
        for (var i = 0; i < list.length; i++) {
            var d = list[i]
            var trigger = (d.trigger && d.trigger.length > 0)
                ? ccTrigger + " (" + d.trigger + ")" + ccSkill : ""
            var name = (d.count >= 2 ? String(d.count) + "x " : "") + (d.name || "")
            out.push({
                kind: "stat",
                left: ccSkill + name + trigger + ":",
                right: d.dpsStr || "",
                height: rowHeightStat
            })
            if (d.skillPart && d.skillPart.length > 0) {
                out.push({ kind: "center", left: ccDim + d.skillPart, right: "",
                           height: rowHeightSub })
            }
            if (d.source && d.source.length > 0) {
                out.push({ kind: "center", left: ccTrigger + "from " + d.source,
                           right: "", height: rowHeightSub })
            }
        }
    }

    // --- Layout -------------------------------------------------------------
    // Legacy sizes statBox to the remaining sidebar height minus the warnings
    // row (Build.lua:579-583); under Qt the parent owns that clamp, so the
    // implicit height here is just the natural content height.
    implicitWidth: theme.sideBarWidth
    implicitHeight: contentHeight

    ListView {
        id: list
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: scrollBar.visible ? scrollBar.left : parent.right
        anchors.rightMargin: scrollBar.visible ? theme.space1 : 0
        clip: true
        // Scrolling is driven by our own ScrollBar so this matches every other
        // scrollable surface in the app (same pattern as DropDownControl).
        interactive: false
        contentY: scrollBar.offset
        model: root.rows

        delegate: Item {
            id: rowItem
            required property var modelData
            width: list.width
            height: modelData.height

            // "stat" — the two-column legacy row. Left label's RIGHT edge sits
            // on colLabelX (RIGHT_X anchor), value starts at colValueX.
            Label {
                visible: rowItem.modelData.kind === "stat"
                label: rowItem.modelData.left
                size: rowItem.modelData.height
                // Right-align inside a REAL box ending at colLabelX rather than
                // positioning by `x: colLabelX - width`.
                //
                // Label sizes itself from TextMetrics (the .tgf bitmap atlas,
                // which is what legacy measured with) but Qt PAINTS it with the
                // bundled TTF. Those two widths are close but not equal, so any
                // width-arithmetic anchor lets the painted glyphs overrun the
                // anchor point — which is exactly what collided the label and
                // value columns here. Handing the right edge to Qt's own
                // alignment makes it exact by construction, because the same
                // metrics that lay the text out also paint it.
                x: 0
                width: root.colLabelX - 2
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
            Label {
                visible: rowItem.modelData.kind === "stat"
                label: rowItem.modelData.right
                size: rowItem.modelData.height
                x: root.colValueX
            }

            // "header" — Minion:/Player:/Skill disabled:.
            Label {
                visible: rowItem.modelData.kind === "header"
                label: rowItem.modelData.left
                size: rowItem.modelData.height
                font.bold: true
                x: 0
            }

            // "center" — CENTER_X rows (disable reason, skillPart, source):
            // colCenterX is the text's centre point, not a box origin.
            Label {
                visible: rowItem.modelData.kind === "center"
                label: rowItem.modelData.left
                size: rowItem.modelData.height
                x: root.colCenterX - width / 2
            }

            // "spacer" — nothing to draw; the row's own height IS the gap.
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => scrollBar.handleWheel(event.angleDelta.y)
        }
    }

    ScrollBar {
        id: scrollBar
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 18
        dir: "VERTICAL"
        step: 40
        autoHide: true
        contentDim: root.contentHeight
        viewDim: list.height
    }
}
