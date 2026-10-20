import QtQuick
import QtQuick.Controls as QC

// DragGhost — the moving label of a cross-control drag (legacy ListControl's
// drag: the row text follows the cursor and any control in `dragTargetList`
// that CanReceiveDrag lights up). It lives in the window overlay, so drop
// targets anywhere in the window (other lists, slot rows, the sidebar, open
// popups) see it, and the source row never moves.
//
// Payload for DropArea consumers: `drag.source.dragType` (the DropArea `keys`
// string, e.g. "Item") and `drag.source.dragValue` (any JS value, e.g.
// { kind, key, shift }). Drive it from the source's MouseArea:
//   ghost.start(sourceItem, mouse.x, mouse.y, "Item", payload, rowText)
//   ghost.moveTo(sourceItem, mouse.x, mouse.y)      // onPositionChanged
//   ghost.finish()                                  // onReleased -> drop
Rectangle {
    id: root

    property string dragType: ""
    property var dragValue: null
    property string text: ""
    readonly property bool active: Drag.active

    parent: QC.Overlay.overlay
    visible: Drag.active
    z: 1000
    width: lbl.implicitWidth + 8
    height: 18
    color: theme.background
    border.width: 1
    border.color: theme.text
    opacity: 0.85

    Drag.keys: [dragType]
    Drag.source: root
    Drag.hotSpot.x: 0
    Drag.hotSpot.y: 0

    Label {
        id: lbl
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        label: root.text
        size: 14
    }

    function moveTo(from, x, y) {
        if (!parent) return
        const p = from.mapToItem(parent, x, y)
        root.x = p.x
        root.y = p.y
    }

    function start(from, x, y, type, value, label) {
        dragType = type
        dragValue = value
        text = label
        moveTo(from, x, y)
        Drag.active = true
    }

    // Deliver the drop to the DropArea under the cursor (if it accepted).
    function finish() {
        if (!Drag.active) return
        Drag.drop()
        Drag.active = false
    }

    function cancel() { Drag.active = false }
}
