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
// `searchable: true` ports legacy's type-to-filter while the list is dropped
// (SearchHost word-order caseless matching, color codes ignored): typed
// characters build a filter, Backspace edits it, Escape clears it and then
// closes; only matching rows are listed, with the matched text highlighted.
// A filtered pick still emits `selected(originalIndex)`. With the default
// `searchable: false` the plain type-ahead below is unchanged.
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
    property bool searchable: false      // opt-in type-to-filter (see header)

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

    // --- searchable filter -------------------------------------------------
    property string _filter: ""
    // Original model indices currently listed (identity when not filtering).
    property var _viewIdx: []
    readonly property int viewCount: (_viewIdx && _viewIdx.length !== undefined) ? _viewIdx.length : 0
    readonly property int _headerH: (searchable && _filter.length > 0) ? _rowHeight : 0

    function _plain(item) {
        return root.labelOf(item).replace(/\^x[0-9a-fA-F]{6}|\^[0-9]/g, "")
    }
    SearchHost {
        id: sh
        valueAccessor: root._plain
        listAccessor: function () {
            var a = []
            for (var i = 0; i < root.count; i++) a.push(root.model[i])
            return a
        }
    }
    function _rebuildView() {
        var out = []
        if (root.searchable && root._filter.length > 0) {
            sh.searchTerm = root._filter
            sh.updateSearch()
            for (var i = 0; i < root.count; i++) {
                var info = sh.searchInfos[i]
                if (info && info.matches) out.push(i)
            }
        } else {
            sh.resetSearch()
            for (var j = 0; j < root.count; j++) out.push(j)
        }
        root._viewIdx = out
    }
    on_FilterChanged: _rebuildView()
    onModelChanged: _rebuildView()
    onSearchableChanged: _rebuildView()
    Component.onCompleted: _rebuildView()

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
        implicitHeight: Math.min(Math.max(root.viewCount, root.searchable ? 1 : 0),
                                 root.maxVisibleItems) * root._rowHeight
                        + root._headerH + 2 * theme.space1
        padding: theme.space1

        closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside

        background: Rectangle {
            color: theme.titleBar
            border.width: 1
            border.color: theme.borderStrong
            radius: theme.radiusControl
        }

        onOpened: {
            var at = root._viewIdx.indexOf(root.currentIndex)
            list.currentIndex = at
            list.positionViewAtIndex(Math.max(0, at), ListView.Contain)
            list.forceActiveFocus()
        }
        // One row tooltip for the whole list, OUTSIDE the clipped ListView
        // (a tooltip inside a delegate was clipped to the list and never
        // showed beside it).
        onClosed: { root._typeBuffer = ""; root._filter = ""; rowTip.hide() }

        contentItem: Item {
            Tooltip { id: rowTip; z: 100; property int ownerRow: -1 }
            ColorText {
                visible: root._headerH > 0
                anchors.left: parent.left
                anchors.leftMargin: 4
                y: (root._headerH - height) / 2
                sourceText: "^7Search: " + sh.searchTermPretty()
                defaultColor: theme.text
                font.pixelSize: root.size
            }
            ListView {
                id: list
                anchors.fill: parent
                anchors.topMargin: root._headerH
                anchors.rightMargin: sb.visible ? sb.width + 2 : 0
                clip: true
                // Scrolling is driven by our own ScrollBar (below) so the list
                // matches every other scrollable surface in the app.
                interactive: false
                contentY: sb.offset
                model: root._viewIdx
                highlightMoveDuration: 0

                delegate: Rectangle {
                    id: row
                    width: list.width
                    height: root._rowHeight
                    // `modelData` is the ORIGINAL model index of this row.
                    readonly property int orig: modelData
                    readonly property var item: root.model[orig]
                    readonly property bool rowEnabled:
                        root.itemEnabled ? root.itemEnabled(item, orig) : true
                    color: orig === root.currentIndex ? theme.active
                         : rowMa.containsMouse ? theme.hover
                         : "transparent"

                    // Matched search text (ranges index the colour-stripped label).
                    Repeater {
                        model: (root.searchable && root._filter.length > 0
                                && sh.searchInfos[row.orig]) ? sh.searchInfos[row.orig].ranges : []
                        delegate: Rectangle {
                            readonly property string plain: root._plain(row.item)
                            x: 4 + textMetrics.width(root.size, "VAR", plain.slice(0, modelData.from))
                            width: textMetrics.width(root.size, "VAR", plain.slice(modelData.from, modelData.to))
                            anchors.verticalCenter: parent.verticalCenter
                            height: root.size + 2
                            color: Qt.rgba(0.9, 0.75, 0.2, 0.35)
                        }
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        label: root.labelOf(row.item)
                        size: root.size
                        defaultColor: row.rowEnabled ? theme.text : theme.muted
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!row.rowEnabled) return
                            root._pick(row.orig)
                            listPopup.close()
                        }
                        onContainsMouseChanged: {
                            if (!root.tooltipForItem) return
                            // Shared tooltip: the old row's exit can arrive after the
                            // new row's enter, so only the owning row may hide it.
                            if (!containsMouse) { if (rowTip.ownerRow === index) rowTip.hide(); return }
                            rowTip.ownerRow = index
                            rowTip.clear()
                            root.tooltipForItem(row.item, rowTip)
                            if (rowTip.lines.length === 0) { rowTip.hide(); return }
                            var host = rowTip.parent
                            var p = row.mapToItem(host, 0, 0)
                            var win = Window.window
                            var origin = win ? host.mapToItem(win.contentItem, 0, 0)
                                             : Qt.point(0, 0)
                            var viewport = win
                                ? Qt.rect(-origin.x, -origin.y, win.width, win.height)
                                : Qt.rect(0, 0, host.width, host.height)
                            rowTip.showAt(p.x, p.y, row.width, row.height, viewport)
                        }
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (list.currentIndex >= 0 && list.currentIndex < root.viewCount) {
                            root._pick(root._viewIdx[list.currentIndex])
                            listPopup.close()
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        if (root.searchable && root._filter.length > 0) root._filter = ""
                        else listPopup.close()
                        event.accepted = true
                    } else if (root.searchable && event.key === Qt.Key_Backspace) {
                        root._filter = root._filter.slice(0, -1)
                        list.currentIndex = root.viewCount > 0 ? 0 : -1
                        event.accepted = true
                    } else if (event.text && event.text.length === 1
                               && event.text >= " ") {
                        if (root.searchable) {
                            if (event.text === " " && (root._filter === "" || root._filter.slice(-1) === " ")) {
                                event.accepted = true
                                return
                            }
                            root._filter = root._filter + event.text
                            list.currentIndex = root.viewCount > 0 ? 0 : -1
                        } else {
                            root._typeAhead(event.text)
                        }
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
                contentDim: root.viewCount * root._rowHeight
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
        var need = Math.min(Math.max(viewCount, searchable ? 1 : 0), maxVisibleItems) * _rowHeight
                   + _headerH + 2 * theme.space1
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
