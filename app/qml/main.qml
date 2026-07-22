import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls

// Phase 1c/2a/3 MainWindow. The top bar is always present. The body swaps
// between the BUILD page (collapsible sidebar + typed-model content) and the
// LIST page (build library browser) depending on luaEngine.currentMode.
// All colours/sizes come from the engine theme singleton (context property
// "theme"); nothing is hardcoded. Real tab content is Phase 3+.
Window {
    id: root
    visible: true
    width: 1100
    height: 720
    title: "Path of Building"
    color: theme.background

    // Engine state is event-driven: activeMode/activeView are bound to the
    // luaEngine.currentMode/currentView Q_PROPERTYs, which emit
    // currentModeChanged/currentViewChanged on every genuine mutation. No
    // polling Timer is used, so the UI sits at 0% CPU when idle. Build
    // metadata and socket groups come from the typed models (buildModel /
    // socketGroupModel) which update via NOTIFY signals.
    property string activeMode: luaEngine.currentMode
    property string activeView: luaEngine.currentView
    property bool sideBarCollapsed: false
    // Phase 2b: last save/load status string shown in the content-area toolbar.
    property string saveLoadStatus: "idle"
    // Phase 3: LIST-mode selection state.
    property int listSelectedIndex: -1
    property string listSelectedName: ""
    property string listSelectedFullFileName: ""
    property bool listSelectedIsFolder: false

    // Phase 5a: ITEMS-view selection state. Holds the currently selected
    // item's map (from itemModel) so the details panel can show its mods.
    property var selectedItem: null

    // Phase 5a: map an item rarity string to its theme colour (no hex
    // hardcoded in QML — all colours come from the theme singleton).
    function rarityColor(r) {
        if (r === "NORMAL") return theme.rarityNormal
        if (r === "MAGIC") return theme.rarityMagic
        if (r === "RARE") return theme.rarityRare
        if (r === "UNIQUE") return theme.rarityUnique
        if (r === "RELIC") return theme.rarityRelic
        return theme.text
    }

    // Phase 4a/asset: convert a bare filesystem path (e.g. C:/.../x.png) into a
    // proper file:/// URL so QML Image.source can load it. Paths that already
    // carry a scheme (file://, qrc://, http://) are returned unchanged. The Lua
    // bridge (pob_host.lua) already returns file:/// URLs, but this guards
    // against any bare path reaching an Image.source (defense-in-depth).
    function fileUrl(p) {
        if (!p) return ""
        if (p.indexOf("://") !== -1) return p
        return "file:///" + p.replace(/\\/g, "/")
    }

    // Raw view registry from the engine (main.modes.BUILD.viewList).
    property var allViews: luaEngine.viewList()

    // Group the views by `group` ("primary" first, then "utility") for the
    // sidebar. Each entry is { group: string, items: [ {id,label,key,group,tab}, ... ] }.
    property var groups: (function () {
        var buckets = {}
        for (var i = 0; i < allViews.length; i++) {
            var v = allViews[i]
            if (!buckets[v.group]) buckets[v.group] = []
            buckets[v.group].push(v)
        }
        var order = ["primary", "utility"]
        var out = []
        for (var j = 0; j < order.length; j++) {
            if (buckets[order[j]])
                out.push({ group: order[j], items: buckets[order[j]] })
        }
        return out
    })()

    // Resolve a view id to its human label (for the content-area placeholder).
    function viewLabel(id) {
        for (var i = 0; i < allViews.length; i++)
            if (allViews[i].id === id) return allViews[i].label
        return id
    }

    // Phase 3: open the selected build/folder from the LIST library.
    function openSelected() {
        if (listSelectedIndex < 0) return
        if (listSelectedIsFolder) {
            // Folders are not openable as builds; ignore (UI disables Open).
            return
        }
        luaEngine.openBuild(listSelectedFullFileName)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- Top bar: title + typed build metadata + current mode + collapse toggle ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.topBarHeight
            color: theme.titleBar
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: theme.space2
                anchors.rightMargin: theme.space2
                spacing: theme.space2
                Button {
                    text: sideBarCollapsed ? ">>" : "<<"
                    onClicked: sideBarCollapsed = !sideBarCollapsed
                    ToolTip.text: "Collapse / expand sidebar"
                    ToolTip.visible: hovered
                    ToolTip.delay: 250
                }
                Text {
                    text: "Path of Building"
                    color: theme.text
                    font.bold: true
                    font.pixelSize: theme.fontSize + 2
                }
                // Phase 3: mode-switch bar (toggle LIST / BUILD). Buttons are
                // generated from luaEngine.modeNames() and call setMode(name).
                Repeater {
                    model: luaEngine.modeNames()
                    delegate: Button {
                        text: modelData
                        highlighted: activeMode === modelData
                        onClicked: luaEngine.setMode(modelData)
                    }
                }
                Item { Layout.fillWidth: true }
                // Phase 2a: typed, signal-driven build metadata.
                Text {
                    text: "Build: " + (buildModel.buildName || "—")
                    color: theme.text
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                    Layout.minimumWidth: 60
                }
                Text {
                    text: "Lv " + buildModel.characterLevel
                    color: theme.text
                }
                Text {
                    text: (buildModel.className || "?") +
                          (buildModel.ascendClassName ? " (" + buildModel.ascendClassName + ")" : "")
                    color: theme.text
                }
                Text {
                    text: "Mode: " + activeMode
                    color: theme.accent
                    font.bold: true
                }
            }
        }

        // --- Body: swaps between BUILD page and LIST page by mode ---
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: activeMode === "LIST" ? 1 : 0

            // ===== Page 0: BUILD (sidebar + content) =====
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sidebar (collapsible; width animates between 0 and theme.sideBarWidth).
                Rectangle {
                    id: sideBar
                    Layout.fillHeight: true
                    // NOTE: never put a Behavior directly on a Layout.* attached
                    // property — it corrupts the layout's size-hint bookkeeping and
                    // starves sibling fillWidth items of space (content collapsed to 0).
                    // Animate a plain proxy property and bind the attached prop to it.
                    property real _sideBarW: sideBarCollapsed ? 0 : theme.sideBarWidth
                    Behavior on _sideBarW { NumberAnimation { duration: 150 } }
                    Layout.preferredWidth: _sideBarW
                    color: theme.sideBarBg
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: theme.space2
                        anchors.topMargin: theme.space2
                        anchors.rightMargin: theme.space2
                        spacing: theme.navRowGap

                        Repeater {
                            model: groups
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: theme.navButtonGap
                                Text {
                                    text: modelData.group === "primary" ? "BUILD" : "TOOLS"
                                    color: theme.section
                                    font.family: theme.fontFamily
                                    font.weight: theme.fontWeightBold
                                    font.pixelSize: theme.fontSizeSm
                                }
                                Repeater {
                                    model: modelData.items
                                    delegate: Rectangle {
                                        id: navBtn
                                        Layout.alignment: Qt.AlignLeft
                                        Layout.preferredWidth: modelData.group === "primary"
                                            ? theme.navWidthPrimary : theme.navWidthUtility
                                        Layout.preferredHeight: theme.navButtonHeight
                                        radius: theme.radiusControl
                                        // Hover background is bound to the MouseArea's
                                        // containsMouse property (event-driven, no Timer).
                                        color: navMa.containsMouse ? theme.hover : "transparent"
                                        // Legacy SimpleGraphic draws a 3px accent bar on
                                        // the LEFT EDGE of the active tab (selection state
                                        // bound to the activeView property).
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 3
                                            color: theme.accent
                                            visible: activeView === modelData.id
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width
                                            elide: Text.ElideRight
                                            clip: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.label
                                            color: theme.text
                                            font.family: theme.fontFamily
                                            font.weight: theme.fontWeightNormal
                                            font.pixelSize: theme.fontSize
                                        }
                                        MouseArea {
                                            id: navMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: luaEngine.setActiveView(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Content area: demonstrates the Phase 2a typed models, and (Phase 4a)
                // renders the passive tree for the TREE view.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Always visible: each child view (treeView, generic content,
                    // skillsView, itemsView, calcsView, configView, notesView,
                    // importView, compareView, partyView) toggles itself via its own
                    // `visible: activeView === "X"`. Hiding this parent previously
                    // made the IMPORT/NOTES/COMPARE/PARTY views unreachable.
                    visible: true
                    color: theme.background

                    // Phase 4a: passive-tree view. Replaces the SimpleGraphic
                    // PassiveTreeView rendering for the TREE view. The pan/zoom
                    // transform is owned by treeViewController; the three list
                    // models (groups / connectors / nodes) supply the geometry.
                    // Rendering uses Canvas shapes (circles by node type, lines for
                    // connectors, rounded rects for group backgrounds) so the tree
                    // is always visible even when atlas sprites are unavailable.
                    Item {
                        id: treeView
                        anchors.fill: parent
                        // Explicitly above the generic (non-TREE) content sibling so a blank
                        // tree can never be caused by z-order occlusion. The generic
                        // content ColumnLayout is invisible when activeView==="TREE" anyway.
                        z: 1
                        visible: activeView === "TREE"
                        clip: true

                        // Repaint the canvas as soon as tree bounds become valid.
                        // Tree data may finish loading AFTER the one-shot Timer below
                        // has already fired, which would otherwise leave a blank tree.
                        onBoundsValidChanged: {
                            if (boundsValid) treeView.requestBufferRender()
                        }

                        // Guarantee an initial paint. At QML load the boot refresh()
                        // (main.cpp) may have already populated bounds, so boundsValid
                        // initialises to true and onBoundsValidChanged never fires — the
                        // canvas would stay blank until an unrelated signal repaints it.
                        Component.onCompleted: {
                            treeViewController.setViewport(treeView.width, treeView.height)
                            treeView.requestBufferRender()
                        }
                        // Repaint every time the view is shown. The safety Timer below
                        // only runs while the view is initially visible, so switching
                        // TO the TREE view later would otherwise show a blank canvas.
                        onVisibleChanged: {
                            if (visible) treeView.requestBufferRender()
                        }
                        // Viewport resize changes the buffer size AND the pan-clamp bounds;
                        // report the new size to the controller (which re-clamps pan) and
                        // repaint.
                        onWidthChanged: { treeViewController.setViewport(treeView.width, treeView.height); treeView.requestBufferRender() }
                        onHeightChanged: { treeViewController.setViewport(treeView.width, treeView.height); treeView.requestBufferRender() }

                        property real vpW: treeView.width
                        property real vpH: treeView.height
                        property bool boundsValid: treeViewController.boundsValid
                        // baseScale must never be NaN/Infinity/0. Guard against
                        // zero/undefined bounds.size and a zero viewport so every ctx.drawImage /
                        // lineTo receives finite coordinates (NaN coords silently draw nothing).
                        // Uses the typed C++ boundsSize property instead of fragile QVariantMap
                        // key access (treeViewController.bounds.size) which can yield undefined.
                        property real baseScale: {
                            var bsize = treeViewController.boundsSize
                            var vw = vpW > 0 ? vpW : 0
                            var vh = vpH > 0 ? vpH : 0
                            var bs = (vw > 0 && vh > 0 && bsize > 0) ? Math.min(vw, vh) / bsize : 1
                            return (isFinite(bs) && bs > 0) ? bs : 1
                        }

                        // --- Tree visual tuning ---
                        // Connector (path) stroke width in TREE units, like legacy (its
                        // line-3.png quads live in tree space, so paths thicken as you zoom
                        // in). The draw bakes zoom into `scale`, so on-screen width is
                        // connTreeWidth * scale, clamped so paths never vanish at min zoom
                        // nor turn into ribbons at max zoom.
                        property real connTreeWidth: 24      // tree-unit path width
                        property real connMinWidth: 1.0      // on-screen clamp (px)
                        property real connMaxWidth: 8.0
                        // Legacy path colours. Legacy draws connectors as white-tinted
                        // line-3.png quads, so these approximate that texture's on-screen
                        // colour as flat strokes: unallocated is a warm tan (sampled from
                        // legacy at ~rgb(68,59,36)); allocated is a brighter gold so the
                        // path stands out. (The previous grey inactive / darker-than-inactive
                        // active were both wrong — allocated must read brighter than not.)
                        property string connActiveColor: "#887646"
                        property string connInactiveColor: "#443b24"

                        // --- Repaint entry point (event-driven, 0% idle CPU) ---
                        // A data/alloc/search/asset/view/TRANSFORM change calls
                        // requestBufferRender(), which repaints the visible treeCanvas once.
                        // The tree is drawn at the LIVE zoom/pan (native resolution — sprites
                        // are sampled from the sheets at their on-screen size, never GPU-
                        // upscaled, so zooming stays crisp like legacy). Repaints are purely
                        // event-driven (requestPaint coalesces to at most one per frame) and
                        // viewport culling below skips off-screen work, so an idle UI still
                        // performs zero repaints and sits at 0% CPU.
                        function requestBufferRender() {
                            treeCanvas.requestPaint()
                        }

                        // Tree-drawing routine used by the visible treeCanvas. Draws
                        // background -> group backgrounds -> connectors -> nodes in screen
                        // space for the given (w,h) surface and (zoomX,zoomY,scale) transform.
                        // zoom/pan ARE baked in here (scale = baseScale * zoom): the canvas
                        // repaints on every transform change at native resolution. Each layer
                        // culls to the viewport, so zoomed-in repaints touch only the ~5% of
                        // primitives actually visible.
                        function drawTree(ctx, w, h, zoomX, zoomY, scale) {
                            ctx.imageSmoothingEnabled = true
                            ctx.imageSmoothingQuality = "medium"
                            ctx.shadowBlur = 0
                            var bsize = treeViewController.boundsSize
                            // [FIX] Gate on GEOMETRY validity (bounds.size > 0), NOT on the
                            // stricter boundsValid (which also requires asset metadata). The
                            // draw routine has per-asset fallbacks (themed circles/lines), so a
                            // missing atlas must NOT blank the whole tree. This is the most
                            // likely root cause: hitTest() works (it only needs m_loaded +
                            // size>0) while drawTree bailed on !boundsValid when assets were
                            // absent, leaving the canvas transparent (dark parent shows through).
                            if (!(bsize > 0)) {
                                return
                            }
                            // Geometry is valid; per-asset fallbacks (themed circles/lines) handle
                            // missing atlas metadata so a missing sprite must not blank the tree.
                            ctx.clearRect(0, 0, w, h)
                            try {
                                var ox = w / 2 + zoomX
                                var oy = h / 2 + zoomY
                                function sx(x) { return ox + scale * x }
                                function sy(y) { return oy + scale * y }
                                // Legacy background: repeating tiled pattern across the whole
                                // canvas, drawn first so paths/nodes composite on top.
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
                                // viewport: the largest group art is ~283 tree units wide drawn
                                // at 2.66x, so anything whose centre is further than that half-
                                // extent off-screen cannot intersect the canvas.
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
                                                            // Legacy DrawAsset(..., isHalf): the sheet stores the
                                                            // TOP half only; draw it above the centre, then again
                                                            // mirrored vertically below (full backdrop = art + mirror).
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
                                // Connectors (under nodes). Width is in tree units (legacy
                                // parity: paths thicken with zoom since zoom is baked into
                                // `scale`). Segments whose bounding box misses the viewport are
                                // culled before any stroke work.
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
                                // Nodes: sprite frames where available, themed fallback circle otherwise.
                                // Sprite destination size is sheetRect * scale * 2.66 with zoom baked
                                // into `scale`, so sprites are sampled at native on-screen resolution.
                                // Culled to the viewport (largest node art ~85px * 2.66 half-extent).
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
                                            // icon atlas is still decoding. Frame rects are larger than the
                                            // icon (e.g. 39 vs 26 for normals) so the ring encircles it.
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

                        // NOTE: the previous offscreen `treeBuffer` Canvas (opacity:0) that
                        // treeCanvas blitted via drawImage() has been REMOVED. Cross-Canvas
                        // drawImage of an invisible buffer could silently copy an empty
                        // backing store (no exception thrown), leaving the canvas blank while
                        // the direct-draw fallback was never reached.

                        // Viewport-sized canvas drawn at NATIVE zoom: drawTree bakes the live
                        // zoom/pan into the draw (scale = baseScale * zoom), repainting on
                        // every transform change. The previous scene-graph Scale transform
                        // (draw once at baseScale, GPU-upscale for zoom) is GONE — it made
                        // zoomed-in sprites blurry by construction (a 4.3x-stretched raster).
                        // Screen mapping (must stay in lockstep with TreeViewController::
                        // hitTest): screen = vp/2 + pan + baseScale*zoom*treeXY — identical
                        // before and after this change, so hit-testing is unaffected.
                        // We still do NOT size the canvas to the full ~26000x21000px tree
                        // bounds - a Canvas that large exceeds Qt's renderable limit and
                        // silently fails to composite, leaving the tree blank.
                        Canvas {
                            id: treeCanvas
                            anchors.fill: parent
                            // Canvas sits above the sibling background; MouseArea below is z:2 so
                            // interaction still works; treeSearch is z:50.
                            z: 1
                            visible: true
                            // Cache loaded atlas images keyed by absolute path so we
                            // only decode each sprite sheet once.
                            property var _atlases: ({})
                            function getAtlas(path) {
                                if (!path) return null
                                if (treeCanvas._atlases[path]) return treeCanvas._atlases[path]
                                var img = Qt.createQmlObject(
                                    'import QtQuick; Image { source: "' + fileUrl(path) + '"; asynchronous: true; visible: false }',
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
                                // drawTree() clears the canvas and paints the legacy tiled
                                // background first, then paths, then nodes — at the LIVE
                                // zoom/pan so sprites render at native resolution.
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
                            // Data/alloc/search changed -> re-render the offscreen buffer.
                            function onViewChanged() { treeView.requestBufferRender() }
                            function onSearchChanged() { treeView.requestBufferRender() }
                            // Asset metadata ready (fires once) -> pre-warm sprite atlases
                            // so the first paint shows sprites immediately (no blank flash).
                            function onAssetsInitialized() {
                                var a = treeViewController.treeAssets
                                for (var k in a) { if (a[k] && a[k].atlas) treeCanvas.getAtlas(a[k].atlas) }
                            }
                            // zoom/pan emit transformChanged (NOT viewChanged). The canvas
                            // draws at native zoom (no scene-graph transform), so every
                            // transform change needs a repaint. requestPaint() coalesces to
                            // at most one paint per frame, and drawTree culls to the
                            // viewport, so wheel/drag stay responsive and idle CPU stays 0%.
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
                        // NOTE: the previous one-shot repaint Timer (running while
                        // !boundsValid) has been REMOVED. Repaint is now fully
                        // signal-driven: Component.onCompleted / onVisibleChanged /
                        // onBoundsValidChanged / onViewChanged / onAssetsInitialized /
                        // atlas statusChanged all call requestBufferRender(). This keeps
                        // idle CPU at 0% (no polling, no OnFrame pump).
                    }
                    } // end treeView Item — Part 0.2: un-nest the tooltip + non-TREE
                      // views below so they are siblings under contentArea, not children
                      // of treeView (whose visible: activeView==="TREE" hid them all).

                    // Phase 4b: hover tooltip bound to the node under the cursor.
                    // Sibling of treeView (not a child) so treeView's clip doesn't
                    // hide it; positioned in the content-area's coordinate space.
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

                    // Phase 2a/2b: generic build content for non-TREE views.
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2
                        visible: activeView !== "TREE" && activeView !== "ITEMS" && activeView !== "SKILLS" && activeView !== "CALCS" && activeView !== "CONFIG" && activeView !== "NOTES" && activeView !== "IMPORT" && activeView !== "COMPARE" && activeView !== "PARTY"

                        // Phase 2b: minimal save/load toolbar.
                        RowLayout {
                            spacing: theme.space2
                            Button {
                                text: "Save"
                                onClicked: {
                                    saveLoadModel.saveBuild(saveLoadModel.defaultSavePath())
                                    saveLoadStatus = (saveLoadModel.lastError === "")
                                        ? ("Saved → " + saveLoadModel.defaultSavePath())
                                        : ("Save error: " + saveLoadModel.lastError)
                                }
                            }
                            Button {
                                text: "Load"
                                onClicked: {
                                    saveLoadModel.loadBuildFile(saveLoadModel.defaultSavePath())
                                    saveLoadStatus = (saveLoadModel.lastError === "")
                                        ? "Loaded OK"
                                        : ("Load error: " + saveLoadModel.lastError)
                                }
                            }
                            Text {
                                text: "Status: " + saveLoadStatus
                                color: theme.muted
                                font.pixelSize: theme.fontSize
                            }
                        }

                        Text {
                            text: "Active view: " + activeView + "  (" + viewLabel(activeView) + ")"
                            color: theme.text
                            font.pixelSize: theme.fontSize + 4
                        }
                        Text {
                            text: "Socket groups: " + socketGroupModel.count
                            color: theme.accent
                            font.bold: true
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: socketGroupModel
                            clip: true
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 26
                                color: index % 2 ? theme.sideBarBg : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: theme.space1
                                    spacing: theme.space2
                                    Text {
                                        text: (model.enabled ? "✔" : "✖") + "  " + (model.title || "(untitled)")
                                        color: theme.text
                                        font.pixelSize: theme.fontSize
                                        Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    clip: true
                                    }
                                    Text {
                                        text: model.slot ? ("[" + model.slot + "]") : ""
                                        color: theme.muted
                                        font.pixelSize: theme.fontSize - 1
                                    elide: Text.ElideRight
                                    clip: true
                                    }
                                    Text {
                                        text: model.skillSummary
                                        color: theme.muted
                                        font.pixelSize: theme.fontSize - 1
                                        elide: Text.ElideRight
                                        Layout.preferredWidth: 320
                                    }
                                }
                            }
                        }
                    }

                    // ===== Phase 5b: SKILLS view (socket groups + active-skill DPS) =====
                    // Bound to socketGroupModel (groups + nested gems) and skillModel
                    // (active-skill DPS list). Selecting an active skill calls
                    // luaEngine.setActiveSkill(socketGroupIndex, displaySkillIndex).
                    // A themed "Add group + gem" control calls
                    // luaEngine.addSocketGroupWithGem(label, gemName). All colours
                    // come from the theme singleton (no hardcoded hex).
                    Item {
                        id: skillsView
                        anchors.fill: parent
                        visible: activeView === "SKILLS"
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: theme.space3
                            spacing: theme.space2

                            Text {
                                text: "Skills"
                                color: theme.text
                                font.bold: true
                                font.pixelSize: theme.fontSize + 4
                            }

                            // --- Add group + gem control ---
                            RowLayout {
                                spacing: theme.space1
                                TextField {
                                    id: skillGroupLabel
                                    Layout.fillWidth: true
                                    placeholderText: "Group label"
                                    color: theme.text
                                    background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                                }
                                TextField {
                                    id: skillGemName
                                    Layout.fillWidth: true
                                    placeholderText: "Gem name (e.g. Fireball)"
                                    color: theme.text
                                    background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                                }
                                Button {
                                    text: "Add"
                                    onClicked: {
                                        if (skillGemName.text.trim() !== "") {
                                            luaEngine.addSocketGroupWithGem(
                                                skillGroupLabel.text.trim() || "New Group",
                                                skillGemName.text.trim())
                                            skillGroupLabel.text = ""
                                            skillGemName.text = ""
                                        }
                                    }
                                }
                            }

                            // --- Socket groups (with nested gems) ---
                            Text {
                                text: "Socket groups: " + socketGroupModel.count
                                color: theme.accent
                                font.bold: true
                            }
                            ListView {
                                id: socketGroupListView
                                Layout.fillWidth: true
                                Layout.preferredHeight: parent.height * 0.4
                                model: socketGroupModel
                                clip: true
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: gemRow.height + 8
                                    color: index % 2 ? theme.sideBarBg : "transparent"
                                    Column {
                                        id: gemRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: theme.space1
                                        spacing: 2
                                        RowLayout {
                                            width: parent.width
                                            spacing: theme.space2
                                            Text {
                                                text: (model.enabled ? "✔" : "✖") + "  " + (model.title || "(untitled)")
                                                color: model.enabled ? theme.text : theme.muted
                                                font.pixelSize: theme.fontSize
                                                Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            clip: true
                                            }
                                            Text {
                                                text: model.slot ? ("[" + model.slot + "]") : ""
                                                color: theme.muted
                                                font.pixelSize: theme.fontSize - 1
                                            }
                                            Text {
                                                text: "main #" + model.mainActiveSkill
                                                color: theme.muted
                                                font.pixelSize: theme.fontSize - 1
                                            }
                                        }
                                        // Nested gem list for this group.
                                        ListView {
                                            width: parent.width
                                            height: Math.max(1, (model.gems ? model.gems.length : 0) * 20)
                                            model: model.gems
                                            clip: true
                                            interactive: false
                                            delegate: Text {
                                                text: "   • " + (modelData.name || "?")
                                                      + "  " + (modelData.level || 1) + "/" + (modelData.quality || 0)
                                                      + (modelData.enabled ? "" : "  (disabled)")
                                                color: theme.muted
                                                font.pixelSize: theme.fontSize - 1
                                            elide: Text.ElideRight
                                            clip: true
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Active-skill DPS list ---
                            Text {
                                text: "Active skills (DPS):"
                                color: theme.accent
                                font.bold: true
                            }
                            ListView {
                                id: activeSkillListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: skillModel
                                clip: true
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 24
                                    color: model.isMain ? theme.accent : (index % 2 ? theme.sideBarBg : "transparent")
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: theme.space1
                                        spacing: theme.space2
                                        Text {
                                            text: (model.isMain ? "★ " : "  ") + (model.name || "?")
                                            color: model.isMain ? theme.background : theme.text
                                            font.pixelSize: theme.fontSize
                                            Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        clip: true
                                        }
                                        Text {
                                            text: "DPS " + Math.round(model.totalDps || 0).toLocaleString()
                                            color: model.isMain ? theme.background : theme.accent
                                            font.pixelSize: theme.fontSize - 1
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            luaEngine.setActiveSkill(
                                                model.socketGroupIndex,
                                                model.displaySkillIndex)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ===== Phase 5a: ITEMS view (item browser) =====
                    // Bound to itemModel (the build's item list). Selecting an item
                    // shows its details (mods) in a side panel. A themed
                    // "Add from text" TextArea + button calls
                    // luaEngine.addItemFromRaw(text). All colours come from the
                    // theme singleton (rarity colours via theme.rarity*).
                    Item {
                        id: itemsView
                        anchors.fill: parent
                        visible: activeView === "ITEMS"
                        clip: true

                        // "Add from text" panel (top)
                        ColumnLayout {
                            id: itemsAddPanel
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: theme.space2
                            spacing: theme.space1
                            Text {
                                text: "Add item from text"
                                color: theme.text
                                font.bold: true
                                font.pixelSize: theme.fontSize
                            }
                            RowLayout {
                                spacing: theme.space1
                                TextArea {
                                    id: itemRawInput
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 60
                                    color: theme.text
                                    background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                                    placeholderText: "Paste item text (Rarity: ...)"
                                    font.pixelSize: theme.fontSize - 1
                                    wrapMode: Text.WordWrap
                                }
                                Button {
                                    text: "Add"
                                    onClicked: {
                                        if (itemRawInput.text.trim() !== "") {
                                            luaEngine.addItemFromRaw(itemRawInput.text)
                                            itemRawInput.text = ""
                                        }
                                    }
                                }
                            }
                        }

                        // Body: item list (left) + details (right)
                        RowLayout {
                            anchors.top: itemsAddPanel.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: theme.space2
                            spacing: theme.space2

                            // Item list
                            ListView {
                                id: itemListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: parent.width * 0.45
                                model: itemModel
                                clip: true
                                highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
                                focus: true
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 30
                                    color: (ListView.isCurrentItem ? theme.accent
                                           : (index % 2 ? theme.sideBarBg : "transparent"))
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: theme.space1
                                        spacing: theme.space1
                                        Text {
                                            text: (model.isEquipped ? "● " : "") + (model.name || "?")
                                            color: ListView.isCurrentItem ? theme.background : rarityColor(model.rarity)
                                            font.pixelSize: theme.fontSize
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        clip: true
                                        }
                                        Text {
                                            text: model.baseName || model.type || ""
                                            color: ListView.isCurrentItem ? theme.background : theme.muted
                                            font.pixelSize: theme.fontSize - 2
                                            elide: Text.ElideRight
                                            Layout.preferredWidth: 120
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            itemListView.currentIndex = index
                                            selectedItem = itemModel.get(index)
                                        }
                                    }
                                }
                            }

                            // Details panel
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: parent.width * 0.55
                                color: theme.sideBarBg
                                border.color: theme.section
                                radius: theme.radiusControl
                                clip: true
                                ScrollView {
                                    anchors.fill: parent
                                    anchors.margins: theme.space2
                                    contentWidth: width
                                    ColumnLayout {
                                        spacing: theme.space1
                                        width: parent.width
                                        Text {
                                            text: selectedItem ? selectedItem.name : "Select an item"
                                            color: selectedItem ? rarityColor(selectedItem.rarity) : theme.muted
                                            font.bold: true
                                            font.pixelSize: theme.fontSize + 2
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            visible: selectedItem
                                            text: (selectedItem ? (selectedItem.baseName || selectedItem.type || "") : "")
                                                  + (selectedItem && selectedItem.quality ? ("  (Quality: " + selectedItem.quality + ")") : "")
                                                  + (selectedItem && selectedItem.level ? ("  (ilvl " + selectedItem.level + ")") : "")
                                            color: theme.muted
                                            font.pixelSize: theme.fontSize - 1
                                            Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        clip: true
                                        }
                                        Text {
                                            visible: selectedItem && selectedItem.isEquipped
                                            text: "Equipped in: " + (selectedItem ? selectedItem.slotName : "")
                                            color: theme.accent
                                            font.pixelSize: theme.fontSize - 1
                                            Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        clip: true
                                        }
                                        Repeater {
                                            model: selectedItem ? selectedItem.modLines : []
                                            delegate: Text {
                                                text: modelData
                                                color: theme.text
                                                font.pixelSize: theme.fontSize - 1
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                // ===== Phase 5c: CALCS view (calculation output browser) =====
                // Bound to calcModel (sections + summary). Summary cards show
                // Life/Mana/ES/TotalDPS from calcModel.summary (coloured via
                // theme). Each section lists its stat lines (label + value,
                // coloured by statType via theme). Clicking a stat with
                // hasBreakdown opens a themed popup showing the breakdown lines
                // from luaEngine.getCalcBreakdown(section, stat.breakdown). All
                // colours come from the theme singleton (no hardcoded hex).
                Item {
                    id: calcsView
                    anchors.fill: parent
                    visible: activeView === "CALCS"
                    clip: true

                    // Breakdown popup state.
                    property var breakdownLines: []
                    property string breakdownTitle: ""

                    function openBreakdown(sectionLabel, stat) {
                        if (!stat || !stat.hasBreakdown) return
                        var lines = luaEngine.getCalcBreakdown(sectionLabel, stat.breakdown)
                        calcsView.breakdownLines = lines || []
                        calcsView.breakdownTitle = (stat.label || "Stat") + " breakdown"
                        breakdownPopup.open()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: 10

                        Text {
                            text: "Calculations"
                            color: theme.text
                            font.bold: true
                            font.pixelSize: theme.fontSize + 4
                        }

                        // --- Summary cards ---
                        RowLayout {
                            spacing: theme.space2
                            Repeater {
                                model: [
                                    { key: "life", label: "Life", val: calcModel.summary.life },
                                    { key: "mana", label: "Mana", val: calcModel.summary.mana },
                                    { key: "es", label: "Energy Shield", val: calcModel.summary.es },
                                    { key: "totalDps", label: "Total DPS", val: calcModel.summary.totalDps },
                                ]
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 56
                                    color: theme.sideBarBg
                                    border.color: theme.section
                                    radius: theme.radiusControl
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            text: modelData.label
                                            color: theme.muted
                                            font.pixelSize: theme.fontSize - 2
                                            horizontalAlignment: Text.AlignHCenter
                                            width: parent.width
                                        }
                                        Text {
                                            text: (modelData.val !== undefined && modelData.val !== null)
                                                  ? String(Math.round(Number(modelData.val))) : "—"
                                            color: theme.accent
                                            font.bold: true
                                            font.pixelSize: theme.fontSize + 2
                                            horizontalAlignment: Text.AlignHCenter
                                            width: parent.width
                                        }
                                    }
                                }
                            }
                        }

                        // --- Sections ---
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            clip: true
                            ColumnLayout {
                                spacing: 10
                                width: parent.width
                                Repeater {
                                    model: calcModel
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        color: theme.background
                                        border.color: theme.section
                                        radius: theme.radiusControl
                                        property string secLabel: model && model.label ? model.label : ""
                                        property var sectionStats: model ? model.stats : []
                                        Column {
                                            id: secCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.margins: theme.space2
                                            spacing: 2
                                            Text {
                                                text: model.label
                                                color: theme.section
                                                font.bold: true
                                                font.pixelSize: theme.fontSize
                                                width: parent.width
                                            elide: Text.ElideRight
                                            clip: true
                                            }
                                            Repeater {
                                                model: sectionStats
                                                delegate: Rectangle {
                                                    width: secCol.width
                                                    height: 22
                                                    color: index % 2 ? theme.sideBarBg : "transparent"
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: theme.space1
                                                        spacing: theme.space2
                                                        Text {
                                                            text: modelData.label ? (modelData.label + ":") : ""
                                                            color: theme.text
                                                            font.pixelSize: theme.fontSize - 1
                                                            Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        clip: true
                                                        }
                                                        Text {
                                                            text: modelData.value !== undefined ? String(modelData.value) : ""
                                                            color: modelData.statType === "offence" ? theme.accent
                                                                 : (modelData.statType === "defence" ? theme.section : theme.text)
                                                            font.pixelSize: theme.fontSize - 1
                                                        elide: Text.ElideRight
                                                        clip: true
                                                        }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: modelData.hasBreakdown
                                                        cursorShape: modelData.hasBreakdown ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: {
                                                            if (modelData.hasBreakdown)
                                                                calcsView.openBreakdown(secLabel, modelData)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- Breakdown popup (CalcBreakdownControl equivalent) ---
                    Popup {
                        id: breakdownPopup
                        modal: true
                        focus: true
                        anchors.centerIn: Overlay.overlay
                        width: Math.min(520, calcsView.width - 40)
                        height: Math.min(420, calcsView.height - 40)
                        background: Rectangle { color: theme.sideBarBg; border.color: theme.accent; radius: theme.radiusCard }
                        contentItem: ColumnLayout {
                            spacing: theme.space1
                            Text {
                                text: calcsView.breakdownTitle
                                color: theme.accent
                                font.bold: true
                                font.pixelSize: theme.fontSize + 1
                            }
                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                Column {
                                    spacing: 2
                                    width: parent.width
                                    Repeater {
                                        model: calcsView.breakdownLines
                                        delegate: Text {
                                            text: modelData
                                            color: theme.text
                                            font.pixelSize: theme.fontSize - 1
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                }
                            }
                            Button {
                                text: "Close"
                                Layout.alignment: Qt.AlignRight
                                onClicked: breakdownPopup.close()
                            }
                        }
                    }
                }

                // ===== Phase 5d: CONFIG (ConfigTab) view =====
                // Configuration-options browser. Renders the build's config
                // options (src/Modules/ConfigOptions.lua) grouped by section,
                // with the appropriate control per option type (boolean ->
                // CheckBox, number -> TextField, list -> ComboBox, string ->
                // TextField). Changing a control writes back via
                // luaEngine.setConfigOption(name, value), which flags a rebuild.
                // All colours come from the theme singleton (no hardcoded hex).
                // Uses a Repeater (no delegate reuse) so each model refresh
                // recreates the controls and their initial state is always
                // correct. Section headers are emitted when the section changes
                // from the previous option (configModel.get(index-1).section).
                Item {
                    id: configView
                    anchors.fill: parent
                    visible: activeView === "CONFIG"
                    clip: true

                    // Control components (defined once; receive the option via
                    // the Loader's `cfg` property). Initial state is set in
                    // Component.onCompleted because the Repeater recreates the
                    // delegates on every model refresh.
                    Component {
                        id: cfgBoolComp
                        CheckBox {
                            Component.onCompleted: checked = (cfg.value === true)
                            onClicked: luaEngine.setConfigOption(cfg.name, checked)
                        }
                    }
                    Component {
                        id: cfgNumComp
                        TextField {
                            Component.onCompleted: text = (cfg.value !== undefined && cfg.value !== null) ? String(cfg.value) : "0"
                            color: theme.text
                            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                            implicitWidth: 90
                            onEditingFinished: {
                                var n = Number(text)
                                if (!isNaN(n)) luaEngine.setConfigOption(cfg.name, n)
                            }
                        }
                    }
                    Component {
                        id: cfgListComp
                        ComboBox {
                            model: cfg.options || []
                            textRole: "label"
                            Component.onCompleted: {
                                var idx = -1
                                var opts = cfg.options || []
                                for (var i = 0; i < opts.length; i++) {
                                    if (opts[i].val === cfg.value) { idx = i; break }
                                }
                                currentIndex = idx
                            }
                            onActivated: {
                                if (index >= 0 && cfg.options && cfg.options[index])
                                    luaEngine.setConfigOption(cfg.name, cfg.options[index].val)
                            }
                        }
                    }
                    Component {
                        id: cfgStrComp
                        TextField {
                            Component.onCompleted: text = (cfg.value !== undefined && cfg.value !== null) ? String(cfg.value) : ""
                            color: theme.text
                            background: Rectangle { color: theme.sideBarBg; border.color: theme.section; radius: theme.radiusControl }
                            implicitWidth: 240
                            onEditingFinished: luaEngine.setConfigOption(cfg.name, text)
                        }
                    }
                    Component {
                        id: sectionHeaderComp
                        Rectangle {
                            width: parent.width
                            height: 28
                            color: theme.section
                            Text {
                                text: secText
                                color: theme.text
                                font.bold: true
                                font.pixelSize: theme.fontSize + 1
                                anchors.left: parent.left
                                anchors.leftMargin: theme.space2
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        contentWidth: width
                        clip: true
                        background: Rectangle { color: theme.background }

                        ColumnLayout {
                            spacing: theme.space1
                            width: parent.width

                            Repeater {
                                model: configModel
                                delegate: ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: theme.space1

                                    // Section header: shown for the first option
                                    // of each section (when the previous option's
                                    // section differs, or this is index 0).
                                    Loader {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: active ? 28 : 0
                                        active: index === 0 || (configModel.get(index - 1) ? configModel.get(index - 1).section !== model.section : true)
                                        sourceComponent: sectionHeaderComp
                                        property string secText: model.section
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        MouseArea {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: labelText.height
                                            hoverEnabled: true
                                            ToolTip.text: model.tooltip ? model.tooltip : ""
                                            ToolTip.visible: model.tooltip ? containsMouse : false
                                            Text {
                                                id: labelText
                                                text: model.label || model.name
                                                color: theme.text
                                                font.pixelSize: theme.fontSize
                                                width: parent.width
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                        Loader {
                                            property var cfg: model
                                            sourceComponent: {
                                                if (model.type === "boolean") return cfgBoolComp
                                                if (model.type === "number") return cfgNumComp
                                                if (model.type === "list") return cfgListComp
                                                return cfgStrComp
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Phase 5e: Notes/Import/Compare/Party (utility) tabs.
                // These four views are bound to the engine tabs via the
                // notesController / compareModel / partyModel context properties
                // and the LuaEngine::importFromCode slot. All colours/sizes come
                // from the theme singleton (no hardcoded hex). They live INSIDE
                // the content-area Rectangle (an Item) — like configView — so
                // anchors.fill: parent is valid and does not trigger the
                // "managed by a layout" warning.

                // NOTES: a notes editor bound to notesController.notes.
                Item {
                    id: notesView
                    anchors.fill: parent
                    visible: activeView === "NOTES"
                    clip: true
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        contentHeight: notesEdit.height
                        clip: true
                        TextArea {
                            id: notesEdit
                            width: parent.width
                            text: notesController.notes
                            color: theme.text
                            font.pixelSize: theme.fontSize
                            wrapMode: Text.WordWrap
                            background: Rectangle { color: theme.background; radius: theme.radiusControl }
                            onTextChanged: notesController.setNotes(text)
                        }
                    }
                }

                // IMPORT: paste a build share code and load it via the engine.
                Item {
                    id: importView
                    anchors.fill: parent
                    visible: activeView === "IMPORT"
                    clip: true
                    property string importStatus: ""
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space2
                        TextField {
                            id: importCode
                            Layout.fillWidth: true
                            placeholderText: "Paste build share code..."
                            color: theme.text
                            font.pixelSize: theme.fontSize
                            background: Rectangle { color: theme.background; radius: theme.radiusControl }
                        }
                        Button {
                            text: "Import Build"
                            onClicked: {
                                var ok = luaEngine.importFromCode(importCode.text)
                                importView.importStatus = ok ? "Imported OK" : "Import failed"
                            }
                        }
                        Text {
                            text: importView.importStatus
                            color: theme.muted
                            font.pixelSize: theme.fontSize
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // COMPARE: list of comparison build entries.
                Item {
                    id: compareView
                    anchors.fill: parent
                    visible: activeView === "COMPARE"
                    clip: true
                    ListView {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space1
                        model: compareModel
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 28
                            color: theme.background
                            radius: theme.radiusControl
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: theme.space1
                                spacing: theme.space2
                                Text { text: name; color: theme.text; font.pixelSize: theme.fontSize; elide: Text.ElideRight; clip: true }
                                Text { text: buildName; color: theme.muted; font.pixelSize: theme.fontSize; elide: Text.ElideRight; clip: true }
                                Text { text: "Lv " + level; color: theme.muted; font.pixelSize: theme.fontSize }
                                Text { text: className; color: theme.muted; font.pixelSize: theme.fontSize; elide: Text.ElideRight; clip: true }
                            }
                        }
                    }
                }

                // PARTY: list of present party buff categories.
                Item {
                    id: partyView
                    anchors.fill: parent
                    visible: activeView === "PARTY"
                    clip: true
                    ListView {
                        anchors.fill: parent
                        anchors.margins: theme.space3
                        spacing: theme.space1
                        model: partyModel
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 28
                            color: theme.background
                            radius: theme.radiusControl
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: theme.space1
                                spacing: theme.space2
                                Text { text: name; color: theme.text; font.pixelSize: theme.fontSize; elide: Text.ElideRight; clip: true }
                                Text { text: "x" + count; color: theme.muted; font.pixelSize: theme.fontSize }
                            }
                        }
                    }
                }

            }
            }

            // ===== Page 1: LIST (build library browser) =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: theme.space2
                // StackLayout sets child geometry directly and IGNORES `anchors`,
                // so the 12px inset must be expressed via Layout margins (which
                // StackLayout honours) — otherwise content touches the window
                // edges (right columns off-screen; left text clipped).
                Layout.leftMargin: theme.space3
                Layout.rightMargin: theme.space3
                Layout.topMargin: theme.space3
                Layout.bottomMargin: theme.space3

                Text {
                    text: "Build Library"
                    color: theme.text
                    font.bold: true
                    font.pixelSize: theme.fontSize + 6
                }

                // Toolbar: create / import / delete / rename controls.
                RowLayout {
                    spacing: theme.space1
                    Button {
                        text: "New Build"
                        onClicked: luaEngine.createBuild()
                    }
                    Button {
                        text: "Open"
                        enabled: listSelectedIndex >= 0 && !listSelectedIsFolder
                        onClicked: openSelected()
                    }
                    Button {
                        text: "Delete"
                        enabled: listSelectedIndex >= 0
                        onClicked: {
                            if (listSelectedIsFolder)
                                luaEngine.deleteFolder(listSelectedName)
                            else
                                luaEngine.deleteBuild(listSelectedFullFileName)
                            listSelectedIndex = -1
                        }
                    }
                    Item { Layout.fillWidth: true }
                    TextField {
                        id: folderNameField
                        placeholderText: "New folder name"
                        Layout.preferredWidth: 160
                        font.pixelSize: theme.fontSize
                    }
                    Button {
                        text: "New Folder"
                        enabled: folderNameField.text !== ""
                        onClicked: {
                            luaEngine.createFolder(folderNameField.text)
                            folderNameField.text = ""
                        }
                    }
                }

                RowLayout {
                    spacing: theme.space1
                    TextField {
                        id: importUrlField
                        placeholderText: "Paste build share URL"
                        Layout.fillWidth: true
                        font.pixelSize: theme.fontSize
                    }
                    Button {
                        text: "Import URL"
                        enabled: importUrlField.text !== ""
                        onClicked: {
                            luaEngine.importBuildFromURL(importUrlField.text)
                            importUrlField.text = ""
                        }
                    }
                }

                // The build/folder list, bound to the BuildListModel.
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: buildListModel
                    clip: true
                    highlight: Rectangle { color: theme.accent; radius: theme.radiusControl }
                    focus: true
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 28
                        color: (ListView.isCurrentItem ? theme.accent : (index % 2 ? theme.sideBarBg : "transparent"))
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: theme.space2
                            spacing: theme.space2
                            Text {
                                text: model.isFolder ? ("📁 " + model.displayName) : (model.displayName || model.fileName)
                                color: ListView.isCurrentItem ? theme.background : theme.text
                                font.pixelSize: theme.fontSize
                                font.bold: model.isFolder
                                Layout.fillWidth: true
                            elide: Text.ElideRight
                            clip: true
                            }
                            Text {
                                text: model.isFolder ? "folder"
                                     : ((model.className ? model.className : "") +
                                        (model.level ? ("  Lv" + model.level) : ""))
                                color: ListView.isCurrentItem ? theme.background : theme.muted
                                font.pixelSize: theme.fontSize - 1
                            elide: Text.ElideRight
                            clip: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                listSelectedIndex = index
                                listSelectedName = model.isFolder ? model.folderName : model.buildName
                                listSelectedFullFileName = model.fullFileName
                                listSelectedIsFolder = model.isFolder
                                ListView.view.currentIndex = index
                            }
                            onDoubleClicked: openSelected()
                        }
                    }
                }

                Text {
                    text: "Builds/folders: " + buildListModel.count
                    color: theme.muted
                    font.pixelSize: theme.fontSize
                }
            }
    }
}
}
