import QtQuick
import QtQuick.Window

// WarningsBar — Phase 3 sidebar warnings row, ported from the anonymous
// `self.controls.warnings` control legacy builds inline in
// buildMode:Init (src/Modules/Build.lua:581-600): a one-line "<n> Warnings"
// count in NEGATIVE red, drawn at 16px FIXED, whose width is the string width
// plus 8, and whose hover pops a tooltip with one line per warning.
//
// The warning strings come from TWO bridge payloads, because legacy fills the
// single `warnings.lines` list from two different places in the frame:
//   * pob_getOutput().warnings — AddDisplayStatList's warnFunc results, the
//     cost-exceeds-pool lists, and InsertItemWarnings (Build.lua:1698, 1752);
//   * pob_getShellState().points.warnings — the three point-overflow strings
//     EstimatePlayerProgress appends (Build.lua:916-918). Those exist ONLY in
//     the shell payload: pob_getShellState wipes and re-reads
//     bm.controls.warnings.lines around its EstimatePlayerProgress call, since
//     that function is not a pure getter.
// refresh() merges them de-duplicated and order-preserving, which is what
// legacy's InsertIfNew does across both sources.
//
// Neither getter may appear in a binding expression: both force a recalc and
// EstimatePlayerProgress additionally mutates characterLevel in auto mode.
// They are called only from refresh(), and the results are cached.
//
// Deviations from legacy (documented, not gaps):
//   - Singular "1 Warning" instead of legacy's unconditional "%d Warnings".
//   - Tooltip lines are 14px (the Button/DropDownControl tooltip default in
//     this port) rather than legacy's AddLine(16, ...).
//   - The NEGATIVE red is theme.danger re-encoded as a colour escape rather
//     than the literal "^1"/colorCodes.NEGATIVE from Data/Global.lua, per the
//     Tier 0 "nothing hardcoded" rule.
Item {
    id: root

    // Legacy row geometry (Build.lua:581 rect height, Draw's y+2 text offset,
    // and the +8 width pad from the control's width function).
    readonly property int rowHeight: 18
    readonly property int textSize: 16
    readonly property int widthPad: 8

    property var warnings: []
    // Live Options toggle (main.showWarnings). Legacy gates both this row and
    // the statBox height reservation on it (Build.lua:581).
    property bool showWarnings: true

    visible: warnings.length > 0 && showWarnings
    implicitHeight: visible ? rowHeight : 0
    implicitWidth: countLabel.width + widthPad

    function refresh() {
        var out = luaEngine.getOutput() || {}
        var shell = luaEngine.getShellState() || {}
        var merged = []
        var seen = ({})
        function add(list) {
            if (!list) return
            for (var i = 0; i < list.length; i++) {
                var w = list[i]
                if (!w || seen[w] === true) continue
                seen[w] = true
                merged.push(w)
            }
        }
        add(out.warnings)
        add(shell.points ? shell.points.warnings : null)
        root.warnings = merged
        root.showWarnings = shell.showWarnings !== false
    }

    Component.onCompleted: refresh()

    Connections {
        target: luaEngine
        function onCalcsChanged() { root.refresh() }
        function onBuildDataChanged() { root.refresh() }
    }

    // colorCodes.NEGATIVE, sourced from the theme instead of the legacy
    // palette literal. Colour escapes are zero-width in TextMetrics, so the
    // FIXED-font measurement below is unaffected by the prefix.
    function _code(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16)
            return s.length < 2 ? "0" + s : s
        }
        return "^x" + (h(c.r) + h(c.g) + h(c.b)).toUpperCase()
    }
    readonly property string ccNegative: _code(theme.danger)

    Label {
        id: countLabel
        x: 0
        y: 2
        size: root.textSize
        label: root.ccNegative + root.warnings.length
               + (root.warnings.length === 1 ? " Warning" : " Warnings")
        // Legacy draws this one string in FIXED, not VAR, so both the family
        // and the measurement have to be overridden off Label's VAR default.
        // (`width` is assignable; `implicitWidth` on a Text-derived item is
        // read-only and must never be touched.)
        font.family: theme.fontFixed
        width: textMetrics.width(root.textSize, "FIXED", label)
    }

    // Hover region matches the drawn text, which is exactly legacy's hit box:
    // the control's own width IS the string width + 8 (Build.lua:583-585).
    MouseArea {
        id: ma
        x: 0
        y: 0
        width: root.implicitWidth
        height: root.rowHeight
        hoverEnabled: true
        onContainsMouseChanged: root._showTooltip()
    }

    Tooltip { id: tt }

    // Same hover/tooltip/viewport-flip flow as Button.qml's _showTooltip():
    // map to the window contentItem, build the viewport rect in the item's own
    // local space, then let Tooltip.showAt do the flip.
    function _showTooltip() {
        if (!ma.containsMouse || !root.visible) { tt.hide(); return }
        tt.clear()
        for (var i = 0; i < root.warnings.length; i++) tt.addLine(14, root.warnings[i])
        if (tt.lines.length > 0) {
            var win = Window.window
            var origin = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
            var viewport = win ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                               : Qt.rect(0, 0, root.width, root.height)
            tt.showAt(0, 0, root.width, root.height, viewport)
            return
        }
        tt.hide()
    }

    onWarningsChanged: _showTooltip()
    onVisibleChanged: _showTooltip()
}
