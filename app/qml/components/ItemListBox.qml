import QtQuick
import QtQuick.Window

// ItemListBox — a legacy ListControl for item rows (Phase 6 Part 6.2): the
// all-items list (ItemListControl), the Uniques / Rare Templates lists
// (ItemDBControl) and the shared item list (SharedItemListControl). Rows are
// 16px, header label at the top left, buttons above the right edge.
//
// Rows come from the bridge: [{ key, label }] (label = legacy GetRowValue,
// colour codes included). The list never calls the bridge itself; every
// action is a signal the view maps to its pob_items* call:
//   click selects; Ctrl+click -> ctrlClicked(i, shift); double-click ->
//   doubleClicked(i); Ctrl+C -> copyRequested(i); Delete -> deleteRequested(i).
// Hover shows `tooltipFn(i, tooltip, shift)`.
//
// Drag (ListControl: past 10px): the row leaves as a DragGhost carrying
// { kind: dragKind, key, shift, src: this list }. Drops come in through the
// DropArea: from this list -> moved(from, to) when `reorderable` (0-based,
// ListControl's t_remove / t_insert order); from a list whose kind is in
// `acceptKinds` -> droppedIn(payload, at) with `at` the 0-based insertion gap.
FocusScope {
    id: root

    property var rows: []
    property string title: ""                 // "" = no header row
    property string defaultText: ""
    property string dragKind: ""              // payload kind; "" = rows cannot be dragged
    property var acceptKinds: []
    property bool reorderable: false
    property var tooltipFn: null
    property int selIndex: -1
    readonly property int count: rows && rows.length !== undefined ? rows.length : 0
    readonly property bool hasSel: selIndex >= 0 && selIndex < count
    readonly property int rowHeight: 16
    // Header buttons (Delete, Sort, ...) are placed by the view over this row.
    property int headerHeight: title !== "" ? 20 : 0

    signal ctrlClicked(int index, bool shift)
    signal doubleClicked(int index)
    signal copyRequested(int index)
    signal deleteRequested(int index)
    signal moved(int from, int to)
    signal droppedIn(var payload, int at)

    z: tip.visible || ghost.active ? 50 : 0

    function select(i) {
        if (i < 0 || i >= count) return
        selIndex = i
        list.positionViewAtIndex(i, ListView.Contain)
    }

    onRowsChanged: {
        if (selIndex >= count) selIndex = -1
        if (ma.hoverIndex >= 0) Qt.callLater(_showTip)
    }

    Keys.onPressed: function (event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        if (event.key === Qt.Key_Up && count > 0) {
            select(hasSel ? Math.max(0, selIndex - 1) : count - 1)
        } else if (event.key === Qt.Key_Down && count > 0) {
            select(hasSel ? Math.min(count - 1, selIndex + 1) : 0)
        } else if (event.key === Qt.Key_Home && count > 0) {
            select(0)
        } else if (event.key === Qt.Key_End && count > 0) {
            select(count - 1)
        } else if (ctrl && event.key === Qt.Key_C && hasSel) {
            copyRequested(selIndex)
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && hasSel) {
            deleteRequested(selIndex)
        } else {
            return
        }
        event.accepted = true
    }

    Label {
        x: 0
        y: 2
        visible: root.title !== ""
        label: root.title
        size: 16
    }

    Rectangle {
        id: box
        y: root.headerHeight
        width: root.width
        height: root.height - root.headerHeight
        color: theme.background
        border.width: 1
        // ListControl tints a compatible drag target green.
        border.color: drop.containsDrag ? theme.success
                    : root.activeFocus ? theme.text : theme.border
        clip: true

        Column {
            visible: root.count === 0 && root.defaultText !== ""
            x: 6; y: 4
            // Label is one line; legacy defaultText has "\n"s. A later line
            // inherits no colour, so repeat the first line's leading code.
            Repeater {
                model: root.defaultText.split("\n")
                delegate: Label {
                    readonly property string lead: (root.defaultText.match(/^\^(x[0-9A-Fa-f]{6}|[0-9])/) || [""])[0]
                    label: (index > 0 ? lead : "") + modelData
                    size: 14
                }
            }
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 2
            anchors.rightMargin: sb.visible ? 18 : 2
            model: root.count
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                width: list.width
                height: root.rowHeight
                color: index === root.selIndex ? theme.active
                     : index === ma.hoverIndex ? theme.hover : "transparent"
                Label {
                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    label: root.rows[index] ? root.rows[index].label : ""
                    size: 14
                }
            }
            onContentYChanged: sb.setOffset(contentY)
        }

        // Insertion marker while a drag hovers (ListControl draws the gap line).
        Rectangle {
            visible: drop.containsDrag
            x: 2
            width: list.width
            height: 2
            y: 2 + drop.dropIndex * root.rowHeight - list.contentY - 1
            color: theme.text
        }

        ScrollBar {
            id: sb
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 16
            visible: active
            dir: "VERTICAL"
            contentDim: root.count * root.rowHeight
            viewDim: list.height
            onOffsetChanged: list.contentY = offset
        }

        MouseArea {
            id: ma
            anchors.fill: list
            hoverEnabled: true
            property int hoverIndex: -1
            property int pressIndex: -1
            property real pressX: 0
            property real pressY: 0
            property bool shiftHeld: false

            function rowAt(y) {
                const i = Math.floor((y + list.contentY) / root.rowHeight)
                return i >= 0 && i < root.count ? i : -1
            }
            onPositionChanged: function (mouse) {
                shiftHeld = (mouse.modifiers & Qt.ShiftModifier) !== 0
                if (ghost.active) {
                    ghost.moveTo(ma, mouse.x, mouse.y)
                    return
                }
                hoverIndex = rowAt(mouse.y)
                const dx = mouse.x - pressX, dy = mouse.y - pressY
                if (pressed && pressIndex >= 0 && root.dragKind !== "" && (mouse.buttons & Qt.LeftButton)
                        && !(mouse.modifiers & Qt.ControlModifier) && dx * dx + dy * dy > 100) {
                    tip.hide()
                    ghost.start(ma, mouse.x, mouse.y, "Item",
                                { kind: root.dragKind, key: root.rows[pressIndex].key, from: pressIndex,
                                  shift: shiftHeld, src: root },
                                root.rows[pressIndex].label)
                }
            }
            onExited: hoverIndex = -1
            onHoverIndexChanged: root._showTip()
            onPressed: function (mouse) {
                root.forceActiveFocus()
                pressIndex = rowAt(mouse.y)
                pressX = mouse.x
                pressY = mouse.y
            }
            onReleased: function (mouse) {
                const i = pressIndex
                pressIndex = -1
                if (ghost.active) {
                    ghost.dragValue.shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
                    ghost.finish()
                    return
                }
                if (i < 0 || rowAt(mouse.y) !== i) return
                root.select(i)
                if (mouse.modifiers & Qt.ControlModifier)
                    root.ctrlClicked(i, (mouse.modifiers & Qt.ShiftModifier) !== 0)
            }
            onDoubleClicked: function (mouse) {
                const i = rowAt(mouse.y)
                if (i >= 0 && !(mouse.modifiers & Qt.ControlModifier)) root.doubleClicked(i)
            }
            onWheel: function (wheel) { sb.handleWheel(wheel.angleDelta.y) }
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["Item"]
            property int dropIndex: 0
            function gapAt(y) {
                return Math.max(0, Math.min(root.count, Math.round((y - 2 + list.contentY) / root.rowHeight)))
            }
            onEntered: function (drag) {
                const p = drag.source ? drag.source.dragValue : null
                const self = !!p && p.src === root
                drag.accepted = !!p && (self ? root.reorderable : root.acceptKinds.indexOf(p.kind) >= 0)
                dropIndex = gapAt(drag.y)
            }
            onPositionChanged: function (drag) { dropIndex = gapAt(drag.y) }
            onDropped: function (dropEv) {
                const p = dropEv.source ? dropEv.source.dragValue : null
                if (!p) return
                if (p.src === root) {
                    // ListControl: t_remove(sel); if the gap is below it, one less.
                    const to = dropIndex > p.from ? dropIndex - 1 : dropIndex
                    if (to !== p.from) root.moved(p.from, to)
                } else {
                    root.droppedIn(p, dropIndex)
                }
            }
        }
    }

    DragGhost { id: ghost }

    function _showTip() {
        const i = ma.hoverIndex
        if (i < 0 || ghost.active || !tooltipFn) { tip.hide(); return }
        tip.clear()
        tooltipFn(i, tip, ma.shiftHeld)
        if (!tip.lines || !tip.lines.length) { tip.hide(); return }
        const win = Window.window
        const o = win ? root.mapToItem(win.contentItem, 0, 0) : Qt.point(0, 0)
        const rowY = box.y + 2 + i * rowHeight - list.contentY
        tip.showAt(box.x, rowY, box.width, rowHeight,
                   win ? Qt.rect(-o.x, -o.y, win.width, win.height) : Qt.rect(0, 0, width, height))
    }

    Tooltip { id: tip }
}
