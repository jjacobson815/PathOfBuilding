import QtQuick
import QtQuick.Controls
import PathOfBuilding 1.0

// Phase 4 Part 4.1: Embeddable, parameterized Passive Tree Viewer.
// Reusable component for the main Tree tab, Items tab jewel socket viewer,
// Timeless Jewel finder, and Calcs tab breakdown viewer.
Item {
    id: treeViewerRoot

    property var controller: treeViewController
    property bool interactive: true
    property bool readOnly: false
    property bool showSearch: true
    property bool showCrosshair: false
    property int targetNodeId: -1
    property bool useSceneGraph: true

    function centerOnNodeId(nodeId) {
        if (!controller || !nodeModel) return
        var node = null
        for (var i = 0; i < nodeModel.count; ++i) {
            var n = nodeModel.get(i)
            if (n && n.id === nodeId) {
                node = n
                break
            }
        }
        if (node) {
            var bsize = controller.boundsSize
            var scale = controller.zoom * (Math.min(treeViewerRoot.width, treeViewerRoot.height) / (bsize > 0 ? bsize : 1))
            controller.setZoomX(-node.x * scale)
            controller.setZoomY(-node.y * scale)
        }
    }

    Item {
        id: viewContainer
        anchors.fill: parent
        clip: true

        Component.onCompleted: {
            if (controller) {
                controller.setViewport(viewContainer.width, viewContainer.height)
            }
        }
        onWidthChanged: {
            if (controller) controller.setViewport(viewContainer.width, viewContainer.height)
        }
        onHeightChanged: {
            if (controller) controller.setViewport(viewContainer.width, viewContainer.height)
        }

        // Scene-Graph GPU Renderer
        TreeScene {
            id: sceneGraph
            anchors.fill: parent
            controller: treeViewerRoot.controller
            showSearch: treeViewerRoot.showSearch
            showCrosshair: treeViewerRoot.showCrosshair
            targetNodeId: treeViewerRoot.targetNodeId
            visible: treeViewerRoot.useSceneGraph
        }

        // Interaction MouseArea
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
                if (controller) {
                    controller.zoomBy(wheel.angleDelta.y > 0 ? 1 : -1)
                    wheel.accepted = true
                }
            }

            onPressed: function(mouse) {
                lastPos = Qt.point(mouse.x, mouse.y)
                dragMoved = false
            }

            onPositionChanged: function(mouse) {
                if (!controller) return
                if (pressed) {
                    var dx = mouse.x - lastPos.x
                    var dy = mouse.y - lastPos.y
                    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) dragMoved = true
                    controller.panBy(dx, dy)
                    lastPos = Qt.point(mouse.x, mouse.y)
                } else {
                    var hid = controller.hitTest(mouse.x, mouse.y, viewContainer.width, viewContainer.height)
                    if (hid >= 0) {
                        sceneGraph.hoverNodeId = hid
                        var tip = luaEngine.getNodeTooltip(hid)
                        if (tip) {
                            nodeTooltip.node = tip
                            nodeTooltip.x = Math.min(mouse.x + 14, treeViewerRoot.width - nodeTooltip.width - 8)
                            nodeTooltip.y = Math.min(mouse.y + 14, treeViewerRoot.height - nodeTooltip.height - 8)
                            nodeTooltip.visible = true
                        } else {
                            nodeTooltip.visible = false
                        }
                    } else {
                        sceneGraph.hoverNodeId = -1
                        nodeTooltip.visible = false
                    }
                }
            }

            onExited: {
                sceneGraph.hoverNodeId = -1
                nodeTooltip.visible = false
            }

            onClicked: function(mouse) {
                if (dragMoved) { dragMoved = false; return }
                if (!treeViewerRoot.readOnly && mouse.button === Qt.LeftButton && controller) {
                    var id = controller.hitTest(mouse.x, mouse.y, viewContainer.width, viewContainer.height)
                    if (id >= 0) controller.toggleNode(id)
                }
            }
        }

        // Search Field Overlay
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
