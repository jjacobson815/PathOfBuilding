import QtQuick
import QtQuick.Controls

// TREE view — the passive-tree renderer (Canvas-based) plus its hover tooltip.
// Extracted from main.qml (Part 1.1); render/interaction logic is unchanged.
//
// Structure: a non-clipping root (treeViewRoot) contains the clipping tree Item
// (treeView) and, as a SIBLING, the hover tooltip (nodeTooltip). The tooltip must
// NOT be a child of the clipping treeView (Phase 0.2) or treeView's clip would hide
// it near the viewport edge. Both fill treeViewRoot, so mouse coordinates from the
// canvas MouseArea map directly onto the tooltip's coordinate space.
//
// Visibility is parent-controlled (visible: activeView === "TREE" at the use site);
// treeView.visible tracks the root so the repaint-on-show handlers still fire.
Item {
    id: treeViewRoot
    anchors.fill: parent

    // Convert a bare filesystem path (e.g. C:/.../x.png) into a file:/// URL so
    // QML Image.source can load it. Paths that already carry a scheme are returned
    // unchanged. The Lua bridge already returns file:/// URLs; this is
    // defence-in-depth. Local to this view (only the tree atlas loader uses it).
    function fileUrl(p) {
        if (!p) return ""
        if (p.indexOf("://") !== -1) return p
        return "file:///" + p.replace(/\\/g, "/")
    }

    // Phase 4a: passive-tree view. Replaces the SimpleGraphic PassiveTreeView
    // rendering for the TREE view. The pan/zoom transform is owned by
    // treeViewController; the three list models (groups / connectors / nodes)
    // supply the geometry. Rendering uses Canvas shapes so the tree is always
    // visible even when atlas sprites are unavailable.
    Item {
        id: treeView
        anchors.fill: parent
        // Explicitly above the generic (non-TREE) content sibling so a blank
        // tree can never be caused by z-order occlusion.
        z: 1
        // Track the root's visibility (set by the parent) so the repaint-on-show
        // handlers below still fire on view switches.
        visible: treeViewRoot.visible
        clip: true

        // Repaint the canvas as soon as tree bounds become valid. Tree data may
        // finish loading AFTER the one-shot Timer below has already fired, which
        // would otherwise leave a blank tree.
        onBoundsValidChanged: {
            if (boundsValid) treeView.requestBufferRender()
        }

        // Guarantee an initial paint. At QML load the boot refresh() (main.cpp)
        // may have already populated bounds, so boundsValid initialises to true
        // and onBoundsValidChanged never fires — the canvas would stay blank until
        // an unrelated signal repaints it.
        Component.onCompleted: {
            treeViewController.setViewport(treeView.width, treeView.height)
            treeView.requestBufferRender()
        }
        // Repaint every time the view is shown.
        onVisibleChanged: {
            if (visible) treeView.requestBufferRender()
        }
        // Viewport resize changes the buffer size AND the pan-clamp bounds; report
        // the new size to the controller (which re-clamps pan) and repaint.
        onWidthChanged: { treeViewController.setViewport(treeView.width, treeView.height); treeView.requestBufferRender() }
        onHeightChanged: { treeViewController.setViewport(treeView.width, treeView.height); treeView.requestBufferRender() }

        property real vpW: treeView.width
        property real vpH: treeView.height
        property bool boundsValid: treeViewController.boundsValid
        // baseScale must never be NaN/Infinity/0. Guard against zero/undefined
        // bounds.size and a zero viewport so every ctx.drawImage / lineTo receives
        // finite coordinates (NaN coords silently draw nothing).
        property real baseScale: {
            var bsize = treeViewController.boundsSize
            var vw = vpW > 0 ? vpW : 0
            var vh = vpH > 0 ? vpH : 0
            var bs = (vw > 0 && vh > 0 && bsize > 0) ? Math.min(vw, vh) / bsize : 1
            return (isFinite(bs) && bs > 0) ? bs : 1
        }

        // --- Tree visual tuning ---
        property real connTreeWidth: 24      // tree-unit path width
        property real connMinWidth: 1.0      // on-screen clamp (px)
        property real connMaxWidth: 8.0
        property string connActiveColor: "#887646"
        property string connInactiveColor: "#443b24"

        // --- Repaint entry point (event-driven, 0% idle CPU) ---
        function requestBufferRender() {
            treeCanvas.requestPaint()
        }

        // Tree-drawing routine used by the visible treeCanvas. Draws
        // background -> group backgrounds -> connectors -> nodes in screen space
        // for the given (w,h) surface and (zoomX,zoomY,scale) transform. zoom/pan
        // ARE baked in here (scale = baseScale * zoom): the canvas repaints on every
        // transform change at native resolution. Each layer culls to the viewport.
        function drawTree(ctx, w, h, zoomX, zoomY, scale) {
            ctx.imageSmoothingEnabled = true
            ctx.imageSmoothingQuality = "medium"
            ctx.shadowBlur = 0
            var bsize = treeViewController.boundsSize
            // [FIX] Gate on GEOMETRY validity (bounds.size > 0), NOT on the stricter
            // boundsValid (which also requires asset metadata). The draw routine has
            // per-asset fallbacks (themed circles/lines), so a missing atlas must NOT
            // blank the whole tree.
            if (!(bsize > 0)) {
                return
            }
            ctx.clearRect(0, 0, w, h)
            try {
                var ox = w / 2 + zoomX
                var oy = h / 2 + zoomY
                function sx(x) { return ox + scale * x }
                function sy(y) { return oy + scale * y }
                // Legacy background: repeating tiled pattern across the whole canvas,
                // drawn first so paths/nodes composite on top.
                var bgUrl = treeViewController.backgroundUrl
                if (bgUrl) {
                    var bg = treeCanvas.getAtlas(bgUrl)
                    if (bg && bg.status === Image.Ready) {
                        try {
                            var bgPat = ctx.createPattern(bg, "repeat")
                            if (bgPat) {
                                ctx.save()
                                ctx.fillStyle = bgPat
                                ctx.fillRect(0, 0, w, h)
                                ctx.restore()
                            }
                        } catch (e) { }
                    }
                }
                // Group backgrounds (behind connectors + nodes). Culled to the
                // viewport.
                try {
                    if (treeGroupModel) {
                        var gcull = 400 * scale + 8
                        for (var g = 0; g < treeGroupModel.count; g++) {
                            var grp = treeGroupModel.get(g)
                            if (grp === undefined || grp === null) continue
                            var gsp = grp.sprite
                            if (gsp === undefined || gsp === null) continue
                            if (gsp.atlas) {
                                var gpx = sx(grp.x), gpy = sy(grp.y)
                                if (gpx < -gcull || gpx > w + gcull ||
                                    gpy < -gcull || gpy > h + gcull) continue
                                var gimg = treeCanvas.getAtlas(gsp.atlas)
                                if (gimg && gimg.status === Image.Ready) {
                                    try {
                                        var gdw = gsp.sw * scale * 2.66, gdh = gsp.sh * scale * 2.66
                                        if (gsp.isHalf) {
                                            // Legacy DrawAsset(..., isHalf): the sheet stores
                                            // the TOP half only; draw it above the centre, then
                                            // again mirrored vertically below.
                                            ctx.drawImage(gimg, gsp.sx, gsp.sy, gsp.sw, gsp.sh,
                                                          gpx - gdw / 2, gpy - gdh, gdw, gdh)
                                            ctx.save()
                                            ctx.translate(gpx, gpy)
                                            ctx.scale(1, -1)
                                            ctx.drawImage(gimg, gsp.sx, gsp.sy, gsp.sw, gsp.sh,
                                                          -gdw / 2, -gdh, gdw, gdh)
                                            ctx.restore()
                                        } else {
                                            ctx.drawImage(gimg, gsp.sx, gsp.sy, gsp.sw, gsp.sh,
                                                          gpx - gdw / 2, gpy - gdh / 2, gdw, gdh)
                                        }
                                    } catch (e) { }
                                }
                            }
                        }
                    }
                } catch (e) { }
                // Connectors (under nodes). Width is in tree units (legacy parity:
                // paths thicken with zoom since zoom is baked into `scale`).
                try {
                    ctx.lineWidth = Math.max(treeView.connMinWidth,
                                             Math.min(treeView.connMaxWidth, treeView.connTreeWidth * scale))
                    ctx.lineCap = "round"
                    if (treeConnectorModel) {
                        var ccull = 16
                        for (var c = 0; c < treeConnectorModel.count; c++) {
                            var conn = treeConnectorModel.get(c)
                            if (conn === undefined || conn === null) continue
                            if (conn.x1 === undefined || conn.y1 === undefined ||
                                conn.x2 === undefined || conn.y2 === undefined) continue
                            var cx1 = sx(conn.x1), cy1 = sy(conn.y1)
                            var cx2 = sx(conn.x2), cy2 = sy(conn.y2)
                            if (Math.max(cx1, cx2) < -ccull || Math.min(cx1, cx2) > w + ccull ||
                                Math.max(cy1, cy2) < -ccull || Math.min(cy1, cy2) > h + ccull) continue
                            ctx.strokeStyle = (conn.state === "Active")
                                ? treeView.connActiveColor
                                : treeView.connInactiveColor
                            ctx.beginPath()
                            ctx.moveTo(cx1, cy1)
                            ctx.lineTo(cx2, cy2)
                            ctx.stroke()
                        }
                    }
                } catch (e) { }
                // Nodes: sprite frames where available, themed fallback circle
                // otherwise. Culled to the viewport.
                try {
                    if (treeModel) {
                        var searchIds = treeViewController.searchResults
                        var hasSearch = (searchIds !== undefined && searchIds !== null)
                        var ncull = 150 * scale + 8
                        for (var i = 0; i < treeModel.count; i++) {
                            var n = treeModel.get(i)
                            if (n === undefined || n === null) continue
                            var nid = (n.id !== undefined && n.id !== null) ? n.id : null
                            var px = sx(n.x), py = sy(n.y)
                            if (px < -ncull || px > w + ncull ||
                                py < -ncull || py > h + ncull) continue
                            var sp = n.iconSprite
                            var drewSprite = false
                            if (sp !== undefined && sp !== null && sp.atlas) {
                                var img = treeCanvas.getAtlas(sp.atlas)
                                if (img && img.status === Image.Ready) {
                                    try {
                                        var dw = sp.sw * scale * 2.66
                                        var dh = sp.sh * scale * 2.66
                                        ctx.drawImage(img, sp.sx, sp.sy, sp.sw, sp.sh,
                                                      px - dw / 2, py - dh / 2, dw, dh)
                                        if (hasSearch && nid !== null && searchIds.indexOf(nid) >= 0) {
                                            ctx.strokeStyle = treeView.connActiveColor
                                            ctx.lineWidth = 2   // screen px; zoom is baked into scale
                                            ctx.beginPath()
                                            ctx.arc(px, py, Math.max(dw, dh) / 2 + 3, 0, 2 * Math.PI)
                                            ctx.stroke()
                                        }
                                        drewSprite = true
                                    } catch (e) {
                                        drewSprite = false
                                    }
                                }
                            }
                            // Frame ring overlay (legacy node.overlay layer): the bronze
                            // frame that rings the skill icon, keyed by alloc state and
                            // node type. Drawn OVER the icon (frames have a transparent
                            // centre) and independent of the icon so it shows even if the
                            // icon atlas is still decoding.
                            var fr = n.frameSprite
                            if (fr !== undefined && fr !== null && fr.atlas) {
                                var fimg = treeCanvas.getAtlas(fr.atlas)
                                if (fimg && fimg.status === Image.Ready) {
                                    try {
                                        var fdw = fr.sw * scale * 2.66
                                        var fdh = fr.sh * scale * 2.66
                                        ctx.drawImage(fimg, fr.sx, fr.sy, fr.sw, fr.sh,
                                                      px - fdw / 2, py - fdh / 2, fdw, fdh)
                                    } catch (e) { }
                                }
                            }
                            if (drewSprite) continue
                            var baseR = 9
                            if (n.type === "Notable") baseR = 13
                            else if (n.type === "Keystone") baseR = 17
                            else if (n.isJewelSocket) baseR = 11
                            else if (n.isMastery) baseR = 13
                            var r = Math.max(6, baseR * scale)
                            var isMatch = hasSearch && nid !== null && searchIds.indexOf(nid) >= 0
                            ctx.fillStyle = n.allocated ? String(theme.accent) : String(theme.muted)
                            ctx.beginPath(); ctx.arc(px, py, r, 0, 2 * Math.PI); ctx.fill()
                            ctx.strokeStyle = isMatch ? String(theme.accent) : String(theme.section)
                            ctx.lineWidth = isMatch ? 2 : 1.5   // screen px; zoom baked into scale
                            ctx.stroke()
                        }
                    }
                } catch (e) { }
            } catch (e) { }
        }

        // Viewport-sized canvas drawn at NATIVE zoom: drawTree bakes the live
        // zoom/pan into the draw (scale = baseScale * zoom), repainting on every
        // transform change. We do NOT size the canvas to the full ~26000x21000px
        // tree bounds - a Canvas that large exceeds Qt's renderable limit and
        // silently fails to composite, leaving the tree blank.
        Canvas {
            id: treeCanvas
            anchors.fill: parent
            z: 1
            visible: true
            // Cache loaded atlas images keyed by absolute path so we only decode
            // each sprite sheet once.
            property var _atlases: ({})
            function getAtlas(path) {
                if (!path) return null
                if (treeCanvas._atlases[path]) return treeCanvas._atlases[path]
                var img = Qt.createQmlObject(
                    'import QtQuick; Image { source: "' + treeViewRoot.fileUrl(path) + '"; asynchronous: true; visible: false }',
                    treeCanvas)
                treeCanvas._atlases[path] = img
                img.statusChanged.connect(function() {
                    if (img.status === Image.Ready) treeView.requestBufferRender()
                })
                if (img.status === Image.Ready) treeView.requestBufferRender()
                return img
            }
            onPaint: {
                var ctx = getContext("2d", { antialias: true })
                treeView.drawTree(ctx, width, height,
                                  treeViewController.zoomX || 0,
                                  treeViewController.zoomY || 0,
                                  treeView.baseScale * (treeViewController.zoom || 1))
            }

        // Phase 4a/4b: wheel-zoom + drag-pan, click-to-allocate, hover tooltip.
        MouseArea {
            anchors.fill: parent
            z: 2
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onWheel: function(wheel) {
                treeViewController.zoomBy(wheel.angleDelta.y > 0 ? 1 : -1)
                wheel.accepted = true
            }
            property point lastPos: Qt.point(0, 0)
            property bool dragMoved: false
            onPressed: function(mouse) {
                lastPos = Qt.point(mouse.x, mouse.y)
                dragMoved = false
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    var dx = mouse.x - lastPos.x
                    var dy = mouse.y - lastPos.y
                    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) dragMoved = true
                    treeViewController.panBy(dx, dy)
                    lastPos = Qt.point(mouse.x, mouse.y)
                } else {
                    // Hover: show tooltip for the node under the cursor.
                    var hid = treeViewController.hitTest(mouse.x, mouse.y, treeView.vpW, treeView.vpH)
                    if (hid >= 0) {
                        var tip = luaEngine.getNodeTooltip(hid)
                        if (tip) {
                            nodeTooltip.node = tip
                            nodeTooltip.x = mouse.x + 14
                            nodeTooltip.y = mouse.y + 14
                            nodeTooltip.visible = true
                        } else {
                            nodeTooltip.visible = false
                        }
                    } else {
                        nodeTooltip.visible = false
                    }
                }
            }
            onExited: nodeTooltip.visible = false
            onClicked: function(mouse) {
                if (dragMoved) { dragMoved = false; return }
                if (mouse.button === Qt.LeftButton) {
                    var id = treeViewController.hitTest(mouse.x, mouse.y, treeView.vpW, treeView.vpH)
                    if (id >= 0) treeViewController.toggleNode(id)
                }
            }
        }

        // Phase 4b: search field — highlights matching nodes in the canvas.
        TextField {
            id: treeSearch
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: theme.space1
            z: 50
            placeholderText: "Search nodes (name / stats)…"
            onTextChanged: treeViewController.setTreeSearch(text)
            color: theme.text
            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
        }

        // Repaint the canvas whenever the tree data or transform changes.
        Connections {
            target: treeViewController
            function onViewChanged() { treeView.requestBufferRender() }
            function onSearchChanged() { treeView.requestBufferRender() }
            // Asset metadata ready (fires once) -> pre-warm sprite atlases so the
            // first paint shows sprites immediately (no blank flash).
            function onAssetsInitialized() {
                var a = treeViewController.treeAssets
                for (var k in a) { if (a[k] && a[k].atlas) treeCanvas.getAtlas(a[k].atlas) }
            }
            // zoom/pan emit transformChanged (NOT viewChanged). The canvas draws at
            // native zoom, so every transform change needs a repaint.
            function onTransformChanged() { treeView.requestBufferRender() }
        }
        Connections {
            target: treeModel
            function onCountChanged() { treeView.requestBufferRender() }
        }
        Connections {
            target: treeGroupModel
            function onCountChanged() { treeView.requestBufferRender() }
        }
        Connections {
            target: treeConnectorModel
            function onCountChanged() { treeView.requestBufferRender() }
        }
        }
    }

    // Phase 4b: hover tooltip bound to the node under the cursor. Sibling of
    // treeView (not a child) so treeView's clip doesn't hide it; positioned in the
    // tree view's coordinate space (treeView fills treeViewRoot, so mouse coords
    // from the canvas MouseArea map here directly).
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
