import QtQuick

// DropTarget — Tier 0 shared drop target, pairs with DragSource. Wraps
// arbitrary content (default property) around a DropArea; `canReceiveDrag`/
// `receiveDrag` are JS function properties the consumer supplies, mirroring
// legacy's `CanReceiveDrag(type, value)` / `ReceiveDrag(type, value,
// source)` control methods. `highlighted` mirrors legacy's green
// drag-target tint (ListControl.lua Draw: SetDrawColor(0.2, 0.6, 0.2) while
// a compatible drag hovers) — bind a Rectangle's color to it, e.g.
// `color: dropTarget.highlighted ? theme.success : "transparent"`.
//
// Deferred (no real consumer yet to validate against): the reorder
// insertion-caret (legacy `selDragIndex`, a row-index computed from cursor Y
// inside a specific list) is list-layout-specific and belongs with the
// future ListControl (Tier 3), not this generic primitive.
Item {
    id: root

    // (type: string, value: var) -> bool
    property var canReceiveDrag: function (type, value) { return false; }
    // (type: string, value: var, source: Item) -> void
    property var receiveDrag: function (type, value, source) {};

    readonly property bool highlighted: area.containsDrag

    default property alias content: contentItem.data

    Item {
        id: contentItem
        anchors.fill: parent
    }

    DropArea {
        id: area
        anchors.fill: parent
        onEntered: (drag) => {
            const src = drag.source;
            drag.accepted = !!src && root.canReceiveDrag(src.dragType, src.dragValue);
        }
        onDropped: (drop) => {
            const src = drop.source;
            if (src) root.receiveDrag(src.dragType, src.dragValue, src);
        }
    }
}
