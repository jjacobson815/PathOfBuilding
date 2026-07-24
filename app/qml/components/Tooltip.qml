import QtQuick

// Tooltip — Tier 0 shared hover-tooltip framework, ported from the legacy
// `Tooltip` class (src/Classes/Tooltip.lua, 643 lines). Programmatic API:
// `clear()` / `addLine(size, text, font)` / `addSeparator(size)`, a
// param-memoized rebuild gate (`checkForUpdate(params)`, the `CheckForUpdate`
// equivalent), and hover placement with viewport flip (`showAt`, ported from
// `Tooltip:Draw`'s `isHoverToolTip` branch).
//
// SCOPE (this pass): single-column layout, plain border+fill chrome, no
// rarity header art. Deliberately DEFERRED until a real content view needs
// them (no item/gem/tree tooltip call site exists yet to validate pixel
// offsets against — building blind risks wrong asset paths/geometry):
//   - multi-column overflow (`CalculateColumns`'s column-break logic)
//   - the 13-config rarity header art + influence icons + RELIC foil tints
//   - the oil/recipe row (`SetRecipe`)
//   - child tooltips (item-granted-skill sub-tooltips)
// A future pass extends this component in place; callers written against
// this API (clear/addLine/addSeparator/checkForUpdate/showAt) do not need
// to change when it does.
//
// Usage: instantiate under a window-covering overlay Item (z-order: legacy
// tooltip layer is 100, hence z:100 below) so viewport coordinates and
// stacking are correct:
//   Tooltip { id: tt }
//   ... on hover: tt.clear(); tt.addLine(16, "Title"); tt.addLine(14, body)
//       tt.showAt(mouseX, mouseY, hoveredW, hoveredH, viewportRect)
//   ... on unhover: tt.hide()
Rectangle {
    id: root

    readonly property int hPad: 12
    readonly property int vPad: 10

    property var lines: []          // [{size,text,font,center}] or [{isSeparator:true,size}]
    property bool center: false     // default per-line centering (AddLine's self.center)
    property int maxWidth: 0        // 0 = no wrapping; else wrap AddLine text to this width
    property var _updateParams: null

    visible: false
    z: 100
    color: Qt.rgba(0, 0, 0, 0.85)
    border.width: 1
    border.color: theme.borderStrong
    radius: theme.radiusControl

    // --- Programmatic content API (mirrors Tooltip.lua) --------------------

    // Mirrors Tooltip:Clear — also resets the per-tooltip config (maxWidth/
    // center), not just the content, since the typical call pattern is
    // checkForUpdate() -> clear() -> reconfigure -> addLine(...).
    function clear() {
        lines = [];
        maxWidth = 0;
        center = false;
    }

    // Word-wraps `text` to `width` px at `height` px font size (VAR), mirroring
    // legacy main:WrapString's greedy break-at-last-space algorithm.
    function _wrapString(text, height, width) {
        const out = [];
        let lineStart = 0;
        let searchFrom = 0;
        while (true) {
            const m = /\s+/.exec(text.slice(searchFrom));
            let s, e;
            if (!m) {
                s = text.length;
                e = text.length;
            } else {
                s = searchFrom + m.index;
                e = s + m[0].length;
            }
            if (s >= text.length) {
                out.push(text.slice(lineStart));
                break;
            }
            const lastBreak = s;
            searchFrom = e;
            if (textMetrics.width(height, "VAR", text.slice(lineStart, s)) > width) {
                out.push(text.slice(lineStart, lastBreak));
                lineStart = e;
            }
        }
        return out;
    }

    function addLine(size, text, font) {
        if (!text) return;
        const f = font || "VAR";
        const raw = String(text).split("\n");
        const next = lines.slice();
        for (const line of raw) {
            if (maxWidth > 0) {
                for (const wrapped of _wrapString(line, size, maxWidth - hPad))
                    next.push({ size: size, text: wrapped, font: f, center: center });
            } else {
                next.push({ size: size, text: line, font: f, center: center });
            }
        }
        lines = next;
    }

    function addSeparator(size) {
        const sz = size || 10;
        const last = lines.length > 0 ? lines[lines.length - 1] : null;
        if (last && last.isSeparator) return; // no back-to-back separators
        const next = lines.slice();
        next.push({ isSeparator: true, size: sz });
        lines = next;
    }

    // Param-memoized rebuild gate: pass the values this tooltip's content
    // depends on (e.g. [item.name, item.rarity, outputRevision]) as an array.
    // Returns true (and clears) when any value changed since the last call —
    // the caller should rebuild (addLine/addSeparator...) only in that case.
    function checkForUpdate(params) {
        let changed = false;
        if (!_updateParams || _updateParams.length !== params.length) {
            changed = true;
        } else {
            for (let i = 0; i < params.length; i++) {
                if (_updateParams[i] !== params[i]) { changed = true; break; }
            }
        }
        if (changed) {
            _updateParams = params.slice();
            clear();
        }
        return changed;
    }

    // --- Layout ---------------------------------------------------------

    function getSize() {
        let w = 0, h = 0;
        for (const d of lines) {
            h += (d.size || 10) + 2;
            if (d.text) {
                const lw = textMetrics.width(d.size, d.font || "VAR", d.text);
                if (lw > w) w = lw;
            }
        }
        return { width: w + hPad, height: h + vPad };
    }

    // Position + show as a hover tooltip next to a hovered control at
    // (hx,hy) sized (hw,hh), flipping to the left/above when it would
    // overflow `viewport` ({x,y,width,height}) — ported from Tooltip:Draw.
    function showAt(hx, hy, hw, hh, viewport) {
        const sz = getSize();
        let ttX = hx, ttY = hy;
        if (hw !== undefined && hh !== undefined && hw !== null && hh !== null) {
            ttX = ttX + hw + 5;
            if (ttX + sz.width > viewport.x + viewport.width) {
                ttX = Math.max(viewport.x, hx - 5 - sz.width);
                if (ttX + sz.width > hx) ttY = ttY + hh;
            }
            if (ttY + sz.height > viewport.y + viewport.height) {
                ttY = Math.max(viewport.y, hy + hh - sz.height);
            }
        }
        root.x = ttX;
        root.y = ttY;
        root.width = sz.width;
        root.height = sz.height;
        root.visible = lines.length > 0;
    }

    function hide() {
        root.visible = false;
    }

    // --- Rendering --------------------------------------------------------

    Column {
        x: root.hPad / 2
        y: root.vPad / 2
        width: root.width - root.hPad
        spacing: 2

        Repeater {
            model: root.lines
            delegate: Item {
                width: parent ? parent.width : 0
                height: modelData.isSeparator ? (modelData.size || 10) : lineText.implicitHeight

                Rectangle {
                    visible: !!modelData.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: theme.border
                }
                ColorText {
                    id: lineText
                    visible: !modelData.isSeparator
                    sourceText: modelData.text || ""
                    defaultColor: theme.text
                    font.pixelSize: modelData.size || theme.fontSize
                    width: parent.width
                    horizontalAlignment: modelData.center ? Text.AlignHCenter : Text.AlignLeft
                }
            }
        }
    }
}
