import QtQuick
import QtQuick.Window
// Namespaced: an unqualified QtQuick.Controls import would make the bare type
// name `Button` ambiguous against this directory's own Button.qml (implicit
// same-directory resolution), which is a hard QML-load error, not a warning.
import QtQuick.Controls as QC

// DropDownControl — Tier 3, ported from legacy DropDownControl.lua.
//
// Legacy draws its own drop list, hit-tests rows by coordinate, scrolls with a
// child ScrollBarControl, and supports per-row tooltips plus type-ahead
// selection. All of that is reproduced here, but the list is hosted in a
// `QtQuick.Controls.Popup` so it renders in the window overlay: a hand-rolled
// child Item would be clipped by any ancestor with `clip: true` (every list
// row and scroll view in this app), which is the one thing an immediate-mode
// renderer never has to worry about and a retained-mode one always does.
//
// `model` accepts either plain strings or objects. For objects the label is
// read from `labelFor` when set, else `.label`, else `.text`, else String(x).
// Per-row rich tooltips come from `tooltipForItem(item, tooltip)`, matching the
// `tooltipFunc(tooltip)` contract used by Button/CheckBox/EditControl.
//
// Selection semantics mirror legacy: `selected(index)` fires ONLY on a real
// user pick (click / ENTER / type-ahead commit), never when `currentIndex` is
// assigned programmatically by a model refresh. Callers can therefore drive
// currentIndex from engine state without re-entering their own handler.
Item {
    id: root

    property var model: []
    property int currentIndex: -1
    property string placeholder: ""
    property bool controlEnabled: true
    property int size: theme.fontSize
    property int maxVisibleItems: 12
    property int popupMinWidth: 0        // 0 = at least the control's width

    // function(item) -> string
    property var labelFor: null
    // function(item, tooltip) -> void ; called with this component's Tooltip
    property var tooltipForItem: null
    // function(item, index) -> bool ; false renders the row greyed + unpickable
    property var itemEnabled: null

    // Tooltip for the CONTROL itself (not a row), same contract as Button.
    property string tooltipText: ""
    property var tooltipFunc: null
    property bool noTooltip: false

    readonly property bool hovered: hoverMa.containsMouse
    readonly property bool open: listPopup.visible
    // An EMPTY Lua table marshals across the bridge as a QVariantMap, not a
    // QVariantList, so `model.length` is undefined rather than 0 and the int
    // binding fails with "Unable to assign [undefined] to int". Guard on the
    // property existing, not just on the model being truthy.
    readonly property int count: (model && model.length !== undefined) ? model.length : 0
    readonly property var currentItem:
        (currentIndex >= 0 && currentIndex < count) ? model[currentIndex] : undefined
    readonly property string currentLabel:
        currentItem !== undefined ? root.labelOf(currentItem) : ""

    signal selected(int index)

    implicitWidth: 160
    implicitHeight: theme.controlSize

    // Type-ahead buffer (legacy DropDownControl:OnChar), reset after a pause.
    property string _typeBuffer: ""
    Timer {
        id: typeReset
        interval: 900
        onTriggered: root._typeBuffer = ""
    }

    Chrome {
        anchors.fill: parent
        hovered: root.hovered
        locked: root.open
        controlEnabled: root.controlEnabled
    }

    Label {
        id: valueLabel
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.right: arrow.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        label: root.currentLabel.length > 0 ? root.currentLabel : root.placeholder
        size: root.size
        defaultColor: !root.controlEnabled ? theme.muted
                    : root.currentLabel.length > 0 ? theme.text
                    : theme.mutedDark
    }

    Arrow {
        id: arrow
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        width: 9
        height: 5
        direction: root.open ? "up" : "down"
        glyphColor: root.controlEnabled ? theme.text : theme.muted
    }

    MouseArea {
        id: hoverMa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (!root.controlEnabled) return
            if (root.open) listPopup.close()
            else root.openList()
        }
        onWheel: (wheel) => {
            // Legacy steps the selection with the wheel while the list is shut.
            if (!root.controlEnabled || root.open || root.count === 0) return
            var next = root.currentIndex + (wheel.angleDelta.y > 0 ? -1 : 1)
            next = Math.max(0, Math.min(root.count - 1, next))
            if (next !== root.currentIndex) root._pick(next)
        }
    }

    Keys.onPressed: (event) => {
        if (!root.controlEnabled) return
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            if (!root.open) { root.openList(); event.accepted = true; return }
        }
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter) {
            if (!root.open) { root.openList(); event.accepted = true }
        }
    }

    QC.Popup {
        id: listPopup

        // Positioned in root's local space; Popup itself renders in the window
        // overlay, so no ancestor `clip: true` can cut the list off.
        x: 0
        y: root._flipUp ? -implicitHeight : root.height
        width: Math.max(root.width, root.popupMinWidth)
        implicitHeight: Math.min(root.count, root.maxVisibleItems) * root._rowHeight
                        + 2 * theme.space1
        padding: theme.space1

        closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside

        background: Rectangle {
            color: theme.titleBar
            border.width: 1
            border.color: theme.borderStrong
            radius: theme.radiusControl
        }

        onOpened: {
            list.currentIndex = root.currentIndex
            list.positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Contain)
            list.forceActiveFocus()
        }
        // NOTE: row tooltips are owned by their delegate instance, so they
        // cannot be reached (or hidden) from here — a delegate's ids are not
        // in scope outside it. They hide themselves via the row's own
        // onContainsMouseChanged when the list goes away and hover is lost.
        onClosed: root._typeBuffer = ""

        contentItem: Item {
            ListView {
                id: list
                anchors.fill: parent
                anchors.rightMargin: sb.visible ? sb.width + 2 : 0
                clip: true
                // Scrolling is driven by our own ScrollBar (below) so the list
                // matches every other scrollable surface in the app.
                interactive: false
                contentY: sb.offset
                model: root.model
                highlightMoveDuration: 0

                delegate: Rectangle {
                    id: row
                    width: list.width
                    height: root._rowHeight
                    readonly property bool rowEnabled:
                        root.itemEnabled ? root.itemEnabled(modelData, index) : true
                    color: index === root.currentIndex ? theme.active
                         : rowMa.containsMouse ? theme.hover
                         : "transparent"

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        label: root.labelOf(modelData)
                        size: root.size
                        defaultColor: row.rowEnabled ? theme.text : theme.muted
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!row.rowEnabled) return
                            root._pick(index)
                            listPopup.close()
                        }
                        onContainsMouseChanged: {
                            if (!root.tooltipForItem) return
                            if (!containsMouse) { rowTip.hide(); return }
                            rowTip.clear()
                            root.tooltipForItem(modelData, rowTip)
                            if (rowTip.lines.length === 0) { rowTip.hide(); return }
                            var win = Window.window
                            var origin = win ? row.mapToItem(win.contentItem, 0, 0)
                                             : Qt.point(0, 0)
                            var viewport = win
                                ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                                : Qt.rect(0, 0, row.width, row.height)
                            rowTip.showAt(0, 0, row.width, row.height, viewport)
                        }
                    }

                    // The row tooltip lives on the row so its coordinate space
                    // is the row's own, matching Button's local-space contract.
                    Tooltip { id: rowTip }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (list.currentIndex >= 0) {
                            root._pick(list.currentIndex)
                            listPopup.close()
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        listPopup.close()
                        event.accepted = true
                    } else if (event.text && event.text.length === 1
                               && event.text >= " ") {
                        root._typeAhead(event.text)
                        event.accepted = true
                    }
                }
                onCurrentIndexChanged: sb.scrollIndexIntoView(currentIndex)
            }

            ScrollBar {
                id: sb
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 12
                autoHide: true
                visible: contentDim > viewDim
                step: root._rowHeight
                contentDim: root.count * root._rowHeight
                viewDim: list.height

                function scrollIndexIntoView(i) {
                    if (i < 0) return
                    var top = i * root._rowHeight
                    var bottom = top + root._rowHeight
                    if (top < offset) offset = top
                    else if (bottom > offset + viewDim) offset = bottom - viewDim
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    var d = event.angleDelta.y > 0 ? -root._rowHeight : root._rowHeight
                    sb.offset = Math.max(0, Math.min(sb.offsetMax, sb.offset + d))
                }
            }
        }
    }

    Tooltip { id: tt }

    readonly property int _rowHeight: root.size + 8
    // Flip the list above the control when there isn't room below it, matching
    // Tooltip.qml's viewport-flip behaviour.
    readonly property bool _flipUp: {
        var win = Window.window
        if (!win) return false
        var origin = root.mapToItem(win.contentItem, 0, 0)
        var need = Math.min(count, maxVisibleItems) * _rowHeight + 2 * theme.space1
        return (origin.y + root.height + need > win.height) && (origin.y - need >= 0)
    }

    // --- API ---------------------------------------------------------------
    function openList() {
        if (root.count === 0) return
        listPopup.open()
    }

    function closeList() { listPopup.close() }

    function labelOf(item) {
        if (item === undefined || item === null) return ""
        if (root.labelFor) return root.labelFor(item)
        if (typeof item === "string") return item
        if (item.label !== undefined) return String(item.label)
        if (item.text !== undefined) return String(item.text)
        return String(item)
    }

    // Select by label, returning true when a match was found. Useful for
    // driving the control from an engine value rather than an index.
    function selectByLabel(text) {
        for (var i = 0; i < root.count; i++) {
            if (root.labelOf(root.model[i]) === text) { root.currentIndex = i; return true }
        }
        return false
    }

    // --- internals ---------------------------------------------------------
    function _pick(i) {
        root.currentIndex = i
        root.selected(i)
    }

    function _typeAhead(ch) {
        root._typeBuffer += ch.toLowerCase()
        typeReset.restart()
        for (var i = 0; i < root.count; i++) {
            if (root.labelOf(root.model[i]).toLowerCase().indexOf(root._typeBuffer) === 0) {
                list.currentIndex = i
                return
            }
        }
        // No prefix match for the accumulated buffer — fall back to matching
        // just the newest character, so a mistyped run doesn't dead-end.
        root._typeBuffer = ch.toLowerCase()
        for (var j = 0; j < root.count; j++) {
            if (root.labelOf(root.model[j]).toLowerCase().indexOf(root._typeBuffer) === 0) {
                list.currentIndex = j
                return
            }
        }
    }

    function _showTooltip() {
        if (!root.hovered || root.noTooltip || root.open) { tt.hide(); return }
        tt.clear()
        if (root.tooltipFunc) root.tooltipFunc(tt)
        else if (root.tooltipText) tt.addLine(14, root.tooltipText)
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

    onHoveredChanged: _showTooltip()
    onTooltipTextChanged: _showTooltip()
    onNoTooltipChanged: _showTooltip()
}
