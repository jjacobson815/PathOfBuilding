import QtQuick

// TextListControl — Tier 2, ported from legacy TextListControl.lua: a
// read-only, multi-column rich-text scroll block (sidebar stat list,
// changelog viewer). `list` is an array of row objects shaped like the
// legacy `lineInfo` table — `{ 1: "col0 text", 2: "col1 text", height,
// x?, align?, font? }` (1-based column-text keys, matching legacy's
// `lineInfo[colIndex]`); `columns` is `[{x, align}]` per-column defaults a
// row can override. `sectionHeights` (ascending cumulative Y offsets, e.g.
// changelog date-header positions) enables SHIFT+wheel jumps between
// sections — ported from OnKeyUp's SHIFT branch.
//
// Simplification (documented, no real consumer yet to validate pixel
// fidelity against): column `align` only affects text-box-relative
// alignment (Text.AlignLeft/HCenter/Right), not legacy's anchor-POINT
// semantics (where e.g. RIGHT_X's x is the text's right edge, not a box's).
// Exact-enough for left-aligned stat lists; revisit if a real consumer
// needs right/center anchor-point precision.
Item {
    id: root

    property var columns: [{ x: 0, align: "LEFT" }]
    property var list: []                // [{1:"...", 2:"...", height, x?, align?, font?}, ...]
    property var sectionHeights: null    // ascending [Y, Y, ...] or null

    readonly property var rowOffsets: (function () {
        var offs = [];
        var acc = 0;
        for (var i = 0; i < root.list.length; i++) { offs.push(acc); acc += root.list[i].height; }
        return offs;
    })()
    readonly property real contentHeight: (function () {
        var h = 0;
        for (var i = 0; i < root.list.length; i++) h += root.list[i].height;
        return h;
    })()

    implicitWidth: 300
    implicitHeight: 200

    Chrome { anchors.fill: parent }

    Item {
        id: viewportItem
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: scrollBar.left
        anchors.margins: 2
        clip: true

        Item {
            id: content
            width: viewportItem.width
            y: -scrollBar.offset
            height: root.contentHeight

            Repeater {
                model: root.list
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index
                    y: root.rowOffsets[index] || 0
                    width: content.width
                    height: modelData.height

                    readonly property var fontInfo: theme.fontFor(modelData.font || "VAR")

                    Repeater {
                        model: root.columns
                        delegate: ColorText {
                            id: colText
                            required property var modelData
                            required property int index
                            readonly property var cell: rowItem.modelData[index + 1]

                            visible: !!cell
                            sourceText: cell || ""
                            defaultColor: theme.text
                            font.family: rowItem.fontInfo.family
                            font.bold: !!rowItem.fontInfo.bold
                            font.italic: !!rowItem.fontInfo.italic
                            font.pixelSize: rowItem.modelData.height
                            x: rowItem.modelData.x !== undefined ? rowItem.modelData.x : modelData.x
                            width: rowItem.width - x
                            horizontalAlignment: {
                                var al = rowItem.modelData.align || modelData.align;
                                return al === "RIGHT_X" || al === "RIGHT" ? Text.AlignRight
                                     : al === "CENTER_X" ? Text.AlignHCenter
                                     : Text.AlignLeft;
                            }
                        }
                    }
                }
            }
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
        contentDim: root.contentHeight
        viewDim: viewportItem.height
    }

    MouseArea {
        anchors.fill: viewportItem
        onWheel: (wheel) => {
            if ((wheel.modifiers & Qt.ShiftModifier) && root.sectionHeights && root.sectionHeights.length > 0) {
                root._sectionJump(wheel.angleDelta.y < 0);
            } else {
                scrollBar.handleWheel(wheel.angleDelta.y);
            }
        }
    }

    // Mirrors OnKeyUp's SHIFT+WHEELUP/WHEELDOWN section-jump branch.
    function _sectionJump(down) {
        var sh = root.sectionHeights;
        for (var i = 0; i < sh.length; i++) {
            if (sh[i] >= scrollBar.offset) {
                if (down) scrollBar.setOffset(i === sh.length - 1 ? sh[i] : sh[i + 1]);
                else scrollBar.setOffset(i === 0 ? sh[i] : sh[i - 1]);
                return;
            }
        }
        scrollBar.setOffset(scrollBar.offsetMax);
    }
}
