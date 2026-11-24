import QtQuick
import QtQuick.Controls as QC

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

    // Optional item tooltip chrome (Phase 6 Part 6.4): rarity header art,
    // left/right influence badges, rarity border colour, and Shift-held
    // granted-skill child tooltips. Reset on clear() so plain tooltips stay plain.
    property string headerRarity: ""
    property bool showHeaderArt: false
    property string headerLeft: ""
    property string headerMiddle: ""
    property string headerRight: ""
    property int headerHeight: 0
    property int headerSideWidth: 0
    property string influenceIcon1: ""
    property string influenceIcon2: ""
    property string borderColorOverride: ""
    property var childTooltips: []

    function _fileUrl(p) {
        return p ? (p.charAt(0) === "/" ? "file://" : "file:///") + p : ""
    }

    function setItemMeta(t) {
        if (!t) return
        headerRarity = t.header || ""
        showHeaderArt = t.showHeaderArt === true
        headerLeft = t.headerLeft || ""
        headerMiddle = t.headerMiddle || ""
        headerRight = t.headerRight || ""
        headerHeight = t.headerHeight || 0
        headerSideWidth = t.headerSideWidth || 0
        influenceIcon1 = t.influenceIcon1 || ""
        influenceIcon2 = t.influenceIcon2 || ""
        borderColorOverride = t.color || ""
        childTooltips = (t.children && t.children.length !== undefined) ? t.children : []
    }

    // Legacy draws tooltips on the top layer, never clipped. showAt() moves
    // this item into the window's popup overlay (above views AND popups) and
    // maps the caller's local coordinates from the item it was declared in
    // (`_home`), so no ancestor `clip: true` can cut it off. Set false to
    // keep it where it is declared.
    property bool floating: true
    property Item _home: null
    property bool _moving: false
    readonly property Item _overlay: QC.Overlay.overlay
    onParentChanged: if (!_moving && parent !== _overlay) _home = parent
    Component.onCompleted: if (!_home) _home = parent
    // Item.visible reads the EFFECTIVE visibility, so this also fires when an
    // ancestor of the home item (e.g. the whole view) is hidden.
    readonly property bool _homeShown: _home ? _home.visible : true
    on_HomeShownChanged: if (!_homeShown) visible = false

    visible: false
    z: 100
    color: Qt.rgba(0, 0, 0, 0.85)
    border.width: 1
    border.color: borderColorOverride !== "" ? borderColorOverride : theme.borderStrong
    radius: theme.radiusControl

    // --- Programmatic content API (mirrors Tooltip.lua) --------------------

    // Mirrors Tooltip:Clear — also resets the per-tooltip config (maxWidth/
    // center), not just the content, since the typical call pattern is
    // checkForUpdate() -> clear() -> reconfigure -> addLine(...).
    function clear() {
        lines = [];
        maxWidth = 0;
        center = false;
        headerRarity = "";
        showHeaderArt = false;
        headerLeft = "";
        headerMiddle = "";
        headerRight = "";
        headerHeight = 0;
        headerSideWidth = 0;
        influenceIcon1 = "";
        influenceIcon2 = "";
        borderColorOverride = "";
        childTooltips = [];
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

    function addLine(size, text, font, lineCenter) {
        if (!text) return;
        const f = font || "VAR";
        const ctr = (lineCenter !== undefined && lineCenter !== null) ? !!lineCenter : center;
        const raw = String(text).split("\n");
        const next = lines.slice();
        for (const line of raw) {
            if (maxWidth > 0) {
                for (const wrapped of _wrapString(line, size, maxWidth - hPad))
                    next.push({ size: size, text: wrapped, font: f, center: ctr });
            } else {
                next.push({ size: size, text: line, font: f, center: ctr });
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
        // The .tgf metrics above reproduce legacy's layout, but Qt paints with
        // the TTF (invariant #8): take the real laid-out extent when larger, so
        // a tall or wide tooltip never overflows its own box.
        // (Summed here rather than read from the Column, which only lays
        // out at the next polish -- after this call has already sized us.)
        let laid = 0;
        for (let i = 0; i < lineRepeater.count; i++) {
            const it = lineRepeater.itemAt(i);
            if (!it) continue;
            if (it.textW > w) w = it.textW;
            laid += it.height + lineColumn.spacing;
        }
        h = Math.max(h, laid);
        // Reserve width for rarity header side caps + influence badges (Tooltip.lua:427-433).
        if (showHeaderArt && headerLeft !== "" && lines.length > 0 && lines[0].text) {
            const titleW = textMetrics.width(lines[0].size || theme.fontSize, lines[0].font || "VAR", lines[0].text);
            const pad = influenceIcon1 !== "" ? 64 : 50;
            if (titleW + pad > w) w = titleW + pad;
            if (headerHeight > h) h = headerHeight;
        }
        return { width: w + hPad, height: h + vPad };
    }

    // Position + show as a hover tooltip next to a hovered control at
    // (hx,hy) sized (hw,hh), flipping to the left/above when it would
    // overflow `viewport` ({x,y,width,height}) — ported from Tooltip:Draw.
    function showAt(hx, hy, hw, hh, viewport) {
        if (floating && _home && _overlay) {
            const p = _home.mapToItem(_overlay, hx, hy);
            if (viewport)
                viewport = Qt.rect(viewport.x + p.x - hx, viewport.y + p.y - hy, viewport.width, viewport.height);
            hx = p.x;
            hy = p.y;
            if (parent !== _overlay) {
                _moving = true;
                parent = _overlay;
                _moving = false;
            }
            z = 1000;
        }
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

    // Rarity header art + influence icons behind title lines (Tooltip.lua:486-561).
    Item {
        visible: root.showHeaderArt && root.headerLeft !== "" && root.headerHeight > 0 && root.lines.length > 0
        x: 1; y: 1
        width: Math.max(0, root.width - 2)
        height: root.headerHeight
        clip: true
        Image {
            x: 0; y: 0
            width: root.headerSideWidth; height: parent.height
            source: parent.visible ? root._fileUrl(root.headerLeft) : ""
        }
        Image {
            x: root.headerSideWidth; y: 0
            width: Math.max(0, parent.width - 2 * root.headerSideWidth)
            height: parent.height
            fillMode: Image.TileHorizontally
            source: parent.visible ? root._fileUrl(root.headerMiddle) : ""
        }
        Image {
            x: Math.max(0, parent.width - root.headerSideWidth); y: 0
            width: root.headerSideWidth; height: parent.height
            source: parent.visible ? root._fileUrl(root.headerRight) : ""
        }
        Image {
            visible: root.influenceIcon1 !== ""
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: parent.height / 2; height: parent.height / 2
            source: visible ? root._fileUrl(root.influenceIcon1) : ""
        }
        Image {
            visible: root.influenceIcon2 !== ""
            x: Math.max(0, parent.width - width - 4); anchors.verticalCenter: parent.verticalCenter
            width: parent.height / 2; height: parent.height / 2
            source: visible ? root._fileUrl(root.influenceIcon2) : ""
        }
    }

    Column {
        id: lineColumn
        x: root.hPad / 2
        y: root.vPad / 2
        width: root.width - root.hPad
        spacing: 2

        Repeater {
            id: lineRepeater
            model: root.lines
            delegate: Item {
                readonly property real textW: modelData.isSeparator ? 0 : lineText.implicitWidth
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

    // Granted-skill child tooltips when Shift is held (Tooltip.lua:662-685).
    Column {
        id: childCol
        visible: root.visible && root.childTooltips && root.childTooltips.length > 0
        x: (root.parent && root.x + root.width + 4 + width > root.parent.width)
            ? -width - 4 : root.width + 4
        y: 0
        spacing: 6
        Repeater {
            model: (root.childTooltips && root.childTooltips.length !== undefined) ? root.childTooltips.length : 0
            delegate: Rectangle {
                readonly property var childRec: root.childTooltips[index] || ({})
                readonly property var childLines: (childRec.lines && childRec.lines.length !== undefined) ? childRec.lines : []
                width: childLineCol.width + root.hPad
                height: childLineCol.height + root.vPad
                color: Qt.rgba(0, 0, 0, 0.90)
                border.width: 1
                border.color: (childRec.color && childRec.color !== "") ? childRec.color : theme.borderStrong
                radius: theme.radiusControl
                Column {
                    id: childLineCol
                    x: root.hPad / 2
                    y: root.vPad / 2
                    spacing: 2
                    Repeater {
                        model: childLines.length
                        delegate: Item {
                            readonly property var ln: childLines[index] || ({})
                            width: Math.max(childTxt.implicitWidth, 240)
                            height: ln.sep ? (ln.size || 10) : childTxt.implicitHeight
                            Rectangle {
                                visible: !!ln.sep
                                anchors.verticalCenter: parent.verticalCenter
                                width: childLineCol.width; height: 1
                                color: theme.border
                            }
                            ColorText {
                                id: childTxt
                                visible: !ln.sep
                                width: childLineCol.width
                                sourceText: ln.sep ? "" : (ln.text && ln.text.length > 0 ? ln.text : " ")
                                defaultColor: theme.text
                                font.pixelSize: ln.size || theme.fontSize
                                horizontalAlignment: ln.center ? Text.AlignHCenter : Text.AlignLeft
                            }
                        }
                    }
                }
            }
        }
    }
}
