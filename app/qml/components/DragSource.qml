import QtQuick

// DragSource — Tier 0 shared drag-and-drop source, ported from legacy's
// typed-payload drag protocol (ListControl.lua's selDragging/selDragActive
// state machine). Wraps arbitrary content (default property); once the
// mouse moves past a 10px threshold (matching legacy's
// `(dx*dx+dy*dy) > 100`) the item follows the cursor and becomes a live
// `Drag` source carrying `dragType`/`dragValue` as the typed payload —
// readable by a paired DropTarget's `receiveDrag` via `drop.source.dragType`
// / `drop.source.dragValue`. Built on Qt Quick's own Drag/DropArea rather
// than hand-rolled hit-testing (legacy has no OS-level drag either — this
// is the equivalent in-process mechanism).
//
// CAVEAT (documented, not yet exercised by a real consumer — no ListControl/
// ItemSlotControl exists yet to integrate this into): this moves the SOURCE
// item itself via MouseArea.drag.target, snapping back to its original
// position on release. That's correct for anchor/x-y positioned items (item
// slots, tree nodes) but fights a Row/Column/Layout parent's own
// positioning — a future ListControl (Tier 3) row should reparent the
// dragged visual to a window-covering overlay instead of using this as-is
// inside a Layout.
Item {
    id: root

    property string dragType: ""
    property var dragValue: null
    readonly property bool dragging: ma.drag.active

    default property alias content: contentItem.data

    Item {
        id: contentItem
        anchors.fill: parent
    }

    Drag.active: ma.drag.active
    Drag.source: root
    Drag.keys: [dragType]
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    opacity: dragging ? 0.5 : 1.0
    z: dragging ? 200 : 0

    MouseArea {
        id: ma
        anchors.fill: parent
        drag.target: root
        drag.threshold: 10
        drag.axis: Drag.XAndYAxis

        property real startX
        property real startY

        onPressed: {
            startX = root.x;
            startY = root.y;
        }
        onReleased: {
            root.Drag.drop();
            root.x = startX;
            root.y = startY;
        }
    }
}
