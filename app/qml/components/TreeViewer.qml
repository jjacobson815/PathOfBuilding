import QtQuick
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

    function centerOnNode(nodeId, zoomFactor) {
        return sceneGraph.centerOnNode(nodeId, zoomFactor === undefined ? 0 : zoomFactor)
    }
    function resetView() { sceneGraph.resetView() }

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

            property point lastPos: Qt.point(0, 0)
            property bool dragMoved: false

            onWheel: function(wheel) {
                sceneGraph.zoomBy(wheel.angleDelta.y > 0 ? 1 : -1, wheel.x, wheel.y)
                wheel.accepted = true
            }

            onPressed: function(mouse) {
                lastPos = Qt.point(mouse.x, mouse.y)
                dragMoved = false
            }

            onPositionChanged: function(mouse) {
                if (pressed) {
                    var dx = mouse.x - lastPos.x
                    var dy = mouse.y - lastPos.y
                    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) dragMoved = true
                    sceneGraph.panBy(dx, dy)
                    lastPos = Qt.point(mouse.x, mouse.y)
                    return
                }
                var hid = sceneGraph.hitTest(mouse.x, mouse.y)
                sceneGraph.hoverNodeId = hid
                var tip = (hid >= 0 && treeViewerRoot.showTooltip) ? luaEngine.getNodeTooltip(hid) : null
                if (tip) {
                    nodeTooltip.node = tip
                    nodeTooltip.x = Math.min(mouse.x + 14, treeViewerRoot.width - nodeTooltip.width - 8)
                    nodeTooltip.y = Math.min(mouse.y + 14, treeViewerRoot.height - nodeTooltip.height - 8)
                    nodeTooltip.visible = true
                } else {
                    nodeTooltip.visible = false
                }
            }

            onExited: {
                sceneGraph.hoverNodeId = -1
                nodeTooltip.visible = false
            }

            onClicked: function(mouse) {
                if (dragMoved) { dragMoved = false; return }
                if (!treeViewerRoot.readOnly && mouse.button === Qt.LeftButton && controller) {
                    var id = sceneGraph.hitTest(mouse.x, mouse.y)
                    if (id >= 0) controller.toggleNode(id)
                }
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
            placeholderText: "Search nodes (name / stats)…"
            onTextChanged: {
                if (controller) controller.setTreeSearch(text)
            }
            color: theme.text
            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
        }
    }

    // Hover Tooltip
    Rectangle {
        id: nodeTooltip
        property var node: null
        visible: false
        z: 100
        width: tipCol.implicitWidth + 16
        height: tipCol.implicitHeight + 12
        color: theme.sideBarBg
        border.color: theme.section
        border.width: 1
        radius: theme.radiusControl

        Column {
            id: tipCol
            x: 8; y: 6
            spacing: 2
            Text {
                text: nodeTooltip.node ? nodeTooltip.node.name : ""
                color: theme.text
                font.bold: true
                font.pixelSize: theme.fontSize
            }
            Text {
                text: nodeTooltip.node ? (nodeTooltip.node.type + (nodeTooltip.node.alloc ? "  •  allocated" : "")) : ""
                color: theme.muted
                font.pixelSize: theme.fontSize - 2
            }
            Repeater {
                model: nodeTooltip.node ? nodeTooltip.node.sd : []
                delegate: Text {
                    text: modelData
                    color: theme.text
                    font.pixelSize: theme.fontSize - 1
                    width: 280
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
