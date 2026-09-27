import QtQuick
import QtQuick.Window
import QtQuick.Controls
import PathOfBuilding 1.0

// Phase 4 Part 4.1: embeddable, multi-instance passive tree viewer.
//
// Tree DATA is shared through `controller` (one per build); zoom/pan are owned
// by each instance's TreeScene, so any number of viewers can show the same
// tree at independent framings — legacy creates one PassiveTreeView per embed:
//   Tree tab          free pan/zoom, alloc on click, search, tooltips
//   Items jewel socket  interactive:false, focusNodeId + focusZoom 17 + crosshair
//                       (ItemSlotHelper.DrawViewer)
//   Calcs breakdown     interactive:false, focusNodeId + focusZoom 5 + focus ring
//                       (CalcBreakdownControl node view)
//   Timeless finder     socket preview (TreeTab:FindTimelessJewel socketViewer)
//
// Phase 4 Part 4.3: legacy PassiveTreeView input (PassiveTreeView.lua:172-519):
//   * hover preview — the path to an unallocated node is drawn in the
//     "intermediate" art, an allocated node's dependents in red, a jewel
//     socket's radius rings + in-radius node colours (pob_getHoverInfo);
//   * Shift = trace mode: the path follows the cursor through linked nodes
//     and a click on its end allocates along it (the alternate path);
//   * click on RELEASE, drag past 5px pans; Ctrl+click zooms (+2 / right -2);
//     wheel zooms ±1 (Shift ±3);
//   * the tooltip is the engine's own PassiveTreeView:AddNodeTooltip output
//     (stat diffs, path/gold lines, tips); Ctrl hides it, Shift hides it on
//     a jewel socket so the rings stay visible.
// Clicks go through pob_clickNode / pob_rightClickNode; results that need UI
// (mastery popup, class-change confirm, tattoo popup, Items tab) are raised
// as signals for the host view to handle.
Item {
    id: treeViewerRoot

    property var controller: treeViewController
    // Pan/zoom + hover (tooltips). Legacy embeds pass no input events at all.
    property bool interactive: true
    // Block allocation clicks even while interactive.
    property bool readOnly: false
    property bool showSearch: true
    property bool showTooltip: interactive
    // Two 2px 20%-white lines through the centre (ItemSlotHelper.DrawViewer).
    property bool showCrosshair: false
    // Keep the view centred on this node (-1 = free view). focusZoom is a raw
    // zoom factor (legacy `viewer.zoom`); <= 0 keeps the current zoom level.
    property int focusNodeId: -1
    property real focusZoom: 0
    // Red ring on the focus node (CalcBreakdownControl's highlightRing).
    property bool showFocusRing: false

    readonly property alias scene: sceneGraph
    readonly property int hoverNodeId: sceneGraph.hoverNodeId
    // Shift trace path (node ids, start -> end); empty outside trace mode.
    property var tracePath: []

    // Raised on any mouse press on the tree (hosts use it to take key focus).
    signal activated()
    // Results of pob_clickNode / pob_rightClickNode that need host UI.
    signal nodeAction(var result)

    function centerOnNode(nodeId, zoomFactor) {
        return sceneGraph.centerOnNode(nodeId, zoomFactor === undefined ? 0 : zoomFactor)
    }
    function resetView() { sceneGraph.resetView() }
    function focusSearch() { treeSearch.forceActiveFocus(); treeSearch.selectAll() }
    // PgUp/PgDn (legacy :195-198): zoom about the centre.
    function zoomStep(delta) { sceneGraph.zoomBy(delta, -1, -1) }

    // Re-evaluate the hover preview + tooltip for the node under the cursor.
    function _updateHover(x, y, modifiers) {
        const shift = (modifiers & Qt.ShiftModifier) !== 0
        const ctrl = (modifiers & Qt.ControlModifier) !== 0
        if (!shift && tracePath.length > 0) tracePath = []
        let hid = sceneGraph.hitTest(x, y)
        let info = null
        if (hid >= 0) {
            info = luaEngine.invoke("pob_getHoverInfo", [hid, tracePath, shift])
            if (info) {
                if (shift) tracePath = info.trace || []
                if (info.id === -1) hid = -1
            }
        }
        sceneGraph.hoverNodeId = hid
        sceneGraph.hoverInfo = (hid >= 0 && info) ? info : ({})
        _updateTooltip(hid, x, y, shift, ctrl)
    }

    property int _tipNode: -1
    property var _tipTrace: []
    function _updateTooltip(hid, x, y, shift, ctrl) {
        if (hid < 0 || !showTooltip || ctrl) { nodeTooltip.hide(); _tipNode = -1; return }
        if (hid !== _tipNode || JSON.stringify(tracePath) !== JSON.stringify(_tipTrace)) {
            _tipNode = hid
            _tipTrace = tracePath.slice()
            const t = luaEngine.invoke("pob_getNodeTooltipLines", [hid, tracePath])
            nodeTooltip.clear()
            nodeTooltip.maxWidth = 800
            nodeTooltip.isSocket = !!(t && t.isSocket)
            if (t && t.show && t.lines) {
                for (let i = 0; i < t.lines.length; i++) {
                    const l = t.lines[i]
                    if (l.sep) { nodeTooltip.addSeparator(l.size); continue }
                    nodeTooltip.center = !!l.center
                    nodeTooltip.addLine(l.size, l.text.length > 0 ? l.text : " ")
                }
            }
        }
        if (nodeTooltip.isSocket && shift) { nodeTooltip.hide(); return }
        nodeTooltip.showAt(x + 12, y + 12, 0, 0, Qt.rect(0, 0, treeViewerRoot.width, treeViewerRoot.height))
    }
    function refreshHover() {
        _tipNode = -1
        if (mouseArea.containsMouse) _updateHover(mouseArea.mouseX, mouseArea.mouseY, mouseArea._mods)
    }

    Item {
        id: viewContainer
        anchors.fill: parent
        clip: true

        TreeScene {
            id: sceneGraph
            anchors.fill: parent
            controller: treeViewerRoot.controller
            showSearch: treeViewerRoot.showSearch
            focusNodeId: treeViewerRoot.focusNodeId
            focusZoom: treeViewerRoot.focusZoom
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            z: 2
            enabled: treeViewerRoot.interactive
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            property point pressPos: Qt.point(0, 0)
            property point lastPos: Qt.point(0, 0)
            property bool dragging: false
            property int _mods: 0

            onWheel: function(wheel) {
                const step = (wheel.modifiers & Qt.ShiftModifier) ? 3 : 1
                sceneGraph.zoomBy(wheel.angleDelta.y > 0 ? step : -step, wheel.x, wheel.y)
                wheel.accepted = true
                treeViewerRoot._updateHover(wheel.x, wheel.y, wheel.modifiers)
            }

            onPressed: function(mouse) {
                pressPos = Qt.point(mouse.x, mouse.y)
                lastPos = pressPos
                dragging = false
                treeViewerRoot.activated()
            }

            onPositionChanged: function(mouse) {
                _mods = mouse.modifiers
                if (pressed && (mouse.buttons & Qt.LeftButton)) {
                    // Legacy starts a drag past 5px (PassiveTreeView.lua:224-242).
                    if (!dragging && (Math.abs(mouse.x - pressPos.x) > 5 || Math.abs(mouse.y - pressPos.y) > 5))
                        dragging = true
                    if (dragging) {
                        sceneGraph.panBy(mouse.x - lastPos.x, mouse.y - lastPos.y)
                        lastPos = Qt.point(mouse.x, mouse.y)
                        nodeTooltip.hide()
                        return
                    }
                }
                treeViewerRoot._updateHover(mouse.x, mouse.y, mouse.modifiers)
            }

            onExited: {
                sceneGraph.hoverNodeId = -1
                sceneGraph.hoverInfo = ({})
                nodeTooltip.hide()
                treeViewerRoot._tipNode = -1
            }

            onReleased: function(mouse) {
                if (dragging) { dragging = false; return }
                // Ctrl+click zooms instead of clicking (legacy :245-248).
                if (mouse.modifiers & Qt.ControlModifier) {
                    sceneGraph.zoomBy(mouse.button === Qt.RightButton ? -2 : 2, mouse.x, mouse.y)
                    return
                }
                if (treeViewerRoot.readOnly) return
                const id = sceneGraph.hoverNodeId
                if (id < 0) return
                let r = null
                if (mouse.button === Qt.LeftButton)
                    r = luaEngine.invoke("pob_clickNode", [id, treeViewerRoot.tracePath])
                else if (mouse.button === Qt.RightButton)
                    r = luaEngine.invoke("pob_rightClickNode", [id])
                if (r && r.action && r.action !== "none") treeViewerRoot.nodeAction(r)
                treeViewerRoot.refreshHover()
            }
        }

        // Crosshair (ItemSlotHelper.DrawViewer: SetDrawColor(1,1,1,0.2), 2px).
        Rectangle {
            visible: treeViewerRoot.showCrosshair
            z: 3
            x: Math.floor(parent.width / 2) - 1
            width: 2
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.2)
        }
        Rectangle {
            visible: treeViewerRoot.showCrosshair
            z: 3
            y: Math.floor(parent.height / 2) - 1
            width: parent.width
            height: 2
            color: Qt.rgba(1, 1, 1, 0.2)
        }

        // Focus ring (CalcBreakdownControl: red highlightRing, 30x30 px).
        Rectangle {
            id: focusRing
            property var pos: null
            function reposition() {
                pos = (treeViewerRoot.showFocusRing && treeViewerRoot.focusNodeId >= 0)
                    ? sceneGraph.nodeScreenPos(treeViewerRoot.focusNodeId) : null
            }
            visible: pos !== null && pos !== undefined
            z: 3
            width: 30; height: 30; radius: 15
            x: visible ? pos.x - 15 : 0
            y: visible ? pos.y - 15 : 0
            color: "transparent"
            border.color: Qt.rgba(1, 0, 0, 1)
            border.width: 2
            Connections {
                target: sceneGraph
                function onTransformChanged() { focusRing.reposition() }
                function onFocusChanged() { focusRing.reposition() }
            }
            Connections {
                target: treeViewerRoot
                function onShowFocusRingChanged() { focusRing.reposition() }
            }
            Component.onCompleted: reposition()
        }

        TextField {
            id: treeSearch
            visible: treeViewerRoot.showSearch
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: theme.space1
            z: 50
            placeholderText: "Search nodes (Lua patterns, \"quoted phrase\", (a|b), oil: prefix)…"
            onTextChanged: {
                if (controller) controller.setTreeSearch(text)
            }
            Keys.onEscapePressed: { text = ""; treeViewerRoot.activated() }
            color: theme.text
            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
        }
    }

    // Node tooltip: legacy AddNodeTooltip lines (colour codes, separators).
    Tooltip {
        id: nodeTooltip
        property bool isSocket: false
        z: 100
    }

    Connections {
        target: luaEngine
        // Stat diffs and dependents change after any edit: rebuild the tooltip.
        function onCalcsChanged() { treeViewerRoot.refreshHover() }
    }
}
