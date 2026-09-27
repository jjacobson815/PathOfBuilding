#include "TreeScene.h"
#include "TreeViewController.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"
#include "LuaEngine.h"
#include "TintedTextureMaterial.h"

#include <QQuickWindow>
#include <QImageReader>
#include <QPainter>
#include <cmath>
#include <algorithm>
#include <cstring>
#include <QColor>

namespace {
// Thread-safe image memoization cache across all tree instances.
static QHash<QString, QImage> s_imageCache;
// Per-window texture cache.
static QHash<QPair<QQuickWindow*, QString>, QSGTexture*> s_textureCache;

QString cleanPath(const QString& path) {
    if (path.isEmpty())
        return QString();
    QString p = path;
    if (p.startsWith("file:///"))
        p = p.mid(8);
    else if (p.startsWith("file://"))
        p = p.mid(7);
    p.replace('\\', '/');
    return p;
}
}

TreeScene::TreeScene(QQuickItem* parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
    // No accepted mouse buttons: input is handled by the TreeViewer MouseArea
    // on top. Accepting here would swallow clicks meant for whatever sits
    // under a non-interactive embedded viewer.
}

TreeScene::~TreeScene() = default;

void TreeScene::setController(TreeViewController* ctrl) {
    if (m_controller == ctrl)
        return;
    if (m_controller)
        m_controller->disconnect(this);
    m_controller = ctrl;
    if (m_controller) {
        connect(m_controller, &TreeViewController::viewChanged, this, &TreeScene::onControllerViewChanged);
        connect(m_controller, &TreeViewController::searchChanged, this, &TreeScene::onControllerSearchChanged);
        connect(m_controller, &TreeViewController::overlaysChanged, this, &TreeScene::onControllerOverlaysChanged);
    }
    m_dirtyGeometry = true;
    m_dirtyTransform = true;
    syncViewport();
    emit controllerChanged();
    update();
}

double TreeScene::baseScale() const {
    const double bs = m_view.baseScale();
    return (std::isfinite(bs) && bs > 0) ? bs : 1.0;
}

void TreeScene::viewMoved() {
    m_dirtyTransform = true;
    emit transformChanged();
    update();
}

void TreeScene::syncViewport() {
    if (m_controller)
        m_view.setTreeExtent(m_controller->boundsSize(), m_controller->extentX(), m_controller->extentY());
    m_view.setViewport(width(), height());
    applyFocus();
    // Size/extent changes move nodes on screen even when the pan offset is
    // unchanged, so always notify overlays that track screen positions.
    viewMoved();
}

bool TreeScene::applyFocus() {
    if (m_focusNodeId < 0 || !m_controller || !m_view.valid())
        return false;
    double x = 0, y = 0;
    if (!m_controller->nodePosition(m_focusNodeId, x, y))
        return false;
    const double oldX = m_view.zoomX(), oldY = m_view.zoomY(), oldZoom = m_view.zoom();
    m_view.focus(x, y, m_focusZoom);
    return m_view.zoomX() != oldX || m_view.zoomY() != oldY || m_view.zoom() != oldZoom;
}

void TreeScene::setZoomLevel(double level) {
    if (m_view.setZoomLevel(level))
        viewMoved();
}

void TreeScene::setZoomX(double v) {
    if (m_view.setZoomX(v))
        viewMoved();
}

void TreeScene::setZoomY(double v) {
    if (m_view.setZoomY(v))
        viewMoved();
}

void TreeScene::zoomBy(double delta, double cursorX, double cursorY) {
    if (cursorX < 0 || cursorY < 0) {
        cursorX = width() / 2.0;
        cursorY = height() / 2.0;
    }
    if (m_view.zoomAt(delta, cursorX, cursorY))
        viewMoved();
}

void TreeScene::panBy(double dx, double dy) {
    if (m_view.panBy(dx, dy))
        viewMoved();
}

void TreeScene::resetView() {
    m_view.reset();
    syncViewport();
}

int TreeScene::hitTest(double x, double y) const {
    double tx = 0, ty = 0;
    if (!m_controller || !m_view.valid() || !m_view.screenToTree(x, y, tx, ty))
        return -1;
    return m_controller->hitTestTree(tx, ty);
}

QVariant TreeScene::nodeScreenPos(int id) const {
    double tx = 0, ty = 0;
    if (!m_controller || !m_view.valid() || !m_controller->nodePosition(id, tx, ty))
        return QVariant();
    double sx = 0, sy = 0;
    m_view.treeToScreen(tx, ty, sx, sy);
    return QPointF(sx, sy);
}

bool TreeScene::centerOnNode(int id, double zoomFactor) {
    double x = 0, y = 0;
    if (!m_controller || !m_view.valid() || !m_controller->nodePosition(id, x, y))
        return false;
    m_view.focus(x, y, zoomFactor);
    viewMoved();
    return true;
}

void TreeScene::setHoverNodeId(int id) {
    if (m_hoverNodeId == id)
        return;
    m_hoverNodeId = id;
    // The hovered node draws its "alloc" frame (PassiveTreeView.lua:789).
    m_dirtyTint = true;
    emit hoverNodeIdChanged();
    update();
}

void TreeScene::setHoverInfo(const QVariantMap& info) {
    m_hoverInfo = info;
    m_hoverPath.clear();
    m_hoverDeps.clear();
    m_radiusColors.clear();
    for (const QVariant& v : info.value("path").toList())
        m_hoverPath.insert(v.toInt());
    for (const QVariant& v : info.value("depends").toList())
        m_hoverDeps.insert(v.toInt());
    const QVariantMap radius = info.value("radius").toMap();
    for (const QVariant& v : radius.value("nodes").toList()) {
        const QVariantMap n = v.toMap();
        const QColor c(n.value("color").toString());
        m_radiusColors.insert(n.value("id").toInt(),
                              (quint32(c.red()) << 24) | (quint32(c.green()) << 16) | (quint32(c.blue()) << 8) | 0xffu);
    }
    m_dirtyTint = true;
    m_dirtyOverlay = true;
    emit hoverInfoChanged();
    update();
}

void TreeScene::setFocusNodeId(int id) {
    if (m_focusNodeId == id)
        return;
    m_focusNodeId = id;
    emit focusChanged();
    if (applyFocus())
        viewMoved();
}

void TreeScene::setFocusZoom(double z) {
    if (m_focusZoom == z)
        return;
    m_focusZoom = z;
    emit focusChanged();
    if (applyFocus())
        viewMoved();
}

void TreeScene::setShowSearch(bool show) {
    if (m_showSearch == show)
        return;
    m_showSearch = show;
    m_dirtyOverlay = true;
    emit showSearchChanged();
    update();
}

void TreeScene::setEdgeSearchHighlight(bool on) {
    if (m_edgeSearch == on)
        return;
    m_edgeSearch = on;
    emit showSearchChanged();
    update();
}

QVariantList TreeScene::searchCircleRects() const {
    QVariantList out;
    for (const QRectF& r : m_searchCircles)
        out << QVariant(r);
    return out;
}

void TreeScene::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        syncViewport();
}

void TreeScene::onControllerViewChanged() {
    m_dirtyGeometry = true;
    // A refresh can change the tree version (bounds) or drop the focus node.
    syncViewport();
}

void TreeScene::onControllerSearchChanged() {
    m_dirtyOverlay = true;
    emit searchChanged();
    update();
}

void TreeScene::onControllerOverlaysChanged() {
    m_dirtyTint = true;
    update();
}

QImage TreeScene::getImage(const QString& rawPath) {
    const QString p = cleanPath(rawPath);
    if (p.isEmpty())
        return QImage();
    auto it = s_imageCache.constFind(p);
    if (it != s_imageCache.constEnd())
        return it.value();
    QImage img(p);
    s_imageCache.insert(p, img);
    return img;
}

QSGTexture* TreeScene::getTexture(QQuickWindow* window, const QString& rawPath, bool repeat) {
    if (!window)
        return nullptr;
    const QString p = cleanPath(rawPath);
    if (p.isEmpty())
        return nullptr;
    const auto key = qMakePair(window, p + (repeat ? ":repeat" : ""));
    auto it = s_textureCache.constFind(key);
    if (it != s_textureCache.constEnd())
        return it.value();
    const QImage img = getImage(p);
    if (img.isNull())
        return nullptr;
    QSGTexture* tex = window->createTextureFromImage(img);
    if (tex) {
        tex->setFiltering(QSGTexture::Linear);
        tex->setMipmapFiltering(QSGTexture::Linear);
        if (repeat) {
            tex->setHorizontalWrapMode(QSGTexture::Repeat);
            tex->setVerticalWrapMode(QSGTexture::Repeat);
        }
        s_textureCache.insert(key, tex);
        connect(window, &QObject::destroyed, [window]() {
            auto keys = s_textureCache.keys();
            for (const auto& k : keys) {
                if (k.first == window) {
                    delete s_textureCache.take(k);
                }
            }
        });
    }
    return tex;
}

namespace {
constexpr quint32 kWhite = 0xffffffffu;
constexpr quint32 kRed = 0xff0000ffu;
constexpr quint32 kGreen = 0x00ff00ffu;
constexpr quint32 kBlue = 0x0000ffffu;
// Legacy draws every tree sprite at 2.66x its atlas pixel size (tree units).
constexpr float kSpriteScale = 2.66f;

void readFloats(const QVariant& v, float* out, int n, bool& ok) {
    const QVariantList l = v.toList();
    ok = l.size() >= n;
    for (int i = 0; i < n; ++i)
        out[i] = i < l.size() ? l[i].toFloat() : 0.0f;
}

int batchFor(QVector<TreeScene::QuadBatch>& batches, QHash<QString, int>& index, const QString& atlas) {
    int i = index.value(atlas, -1);
    if (i < 0) {
        i = batches.size();
        index.insert(atlas, i);
        TreeScene::QuadBatch b;
        b.atlasPath = atlas;
        batches.append(b);
    }
    return i;
}

void pushQuad(TreeScene::QuadBatch& b, const float* xy, const float* uv, quint32 rgba) {
    const quint32 base = static_cast<quint32>(b.vertices.size());
    for (int k = 0; k < 4; ++k) {
        TintedVertex v;
        v.set(xy[k * 2], xy[k * 2 + 1], uv[k * 2], uv[k * 2 + 1], rgba);
        b.vertices.append(v);
    }
    b.indices << base << (base + 1) << (base + 2) << base << (base + 2) << (base + 3);
}

void pushRect(TreeScene::QuadBatch& b, float x0, float y0, float x1, float y1,
              float u0, float v0, float u1, float v1, quint32 rgba) {
    const float xy[8] = { x0, y0, x1, y0, x1, y1, x0, y1 };
    const float uv[8] = { u0, v0, u1, v0, u1, v1, u0, v1 };
    pushQuad(b, xy, uv, rgba);
}

quint32 colorFromString(const QString& s) {
    const QColor c(s);
    if (!c.isValid())
        return kWhite;
    return (quint32(c.red()) << 24) | (quint32(c.green()) << 16) | (quint32(c.blue()) << 8) | 0xffu;
}
}

// Parse the controller's QVariant payload into plain structs, once per tree
// revision. Every later rebuild (hover, heat map, compare) reads these.
void TreeScene::parseTreeData() {
    m_nodeRecs.clear();
    m_nodeIndex.clear();
    m_connRecs.clear();
    if (!m_controller)
        return;
    auto sprite = [](const QVariant& v) {
        Sprite sp;
        const QVariantMap m = v.toMap();
        sp.atlas = m.value("atlas").toString();
        sp.sx = m.value("sx").toFloat();
        sp.sy = m.value("sy").toFloat();
        sp.sw = m.value("sw").toFloat();
        sp.sh = m.value("sh").toFloat();
        return sp;
    };
    if (auto* nodeModel = m_controller->nodesModel()) {
        const auto& nodes = nodeModel->nodes();
        m_nodeRecs.reserve(nodes.size());
        for (const QVariantMap& node : nodes) {
            NodeRec r;
            r.id = node.value("id").toInt();
            r.x = node.value("x").toFloat();
            r.y = node.value("y").toFloat();
            r.alloc = node.value("allocated").toBool();
            r.icon = sprite(node.value("iconSprite"));
            r.frame = sprite(node.value("frameSprite"));
            r.framePath = sprite(node.value("framePathSprite"));
            r.frameAlloc = sprite(node.value("frameAllocSprite"));
            m_nodeIndex.insert(r.id, m_nodeRecs.size());
            m_nodeRecs.append(r);
        }
    }
    if (auto* connModel = m_controller->connectorsModel()) {
        const auto& connectors = connModel->connectors();
        m_connRecs.reserve(connectors.size());
        for (const QVariantMap& conn : connectors) {
            ConnRec c;
            c.n1 = conn.value("nodeId1").toInt();
            c.n2 = conn.value("nodeId2").toInt();
            c.atlas = conn.value("atlas").toString();
            bool okV = false, okU = false;
            readFloats(conn.value("vert"), c.vert, 8, okV);
            readFloats(conn.value("uv"), c.uv, 8, okU);
            if (c.atlas.isEmpty() || !okV || !okU)
                continue;
            bool ok = false;
            c.atlasIntermediate = conn.value("atlasIntermediate").toString();
            readFloats(conn.value("vertIntermediate"), c.vertIntermediate, 8, ok);
            c.hasIntermediate = ok && !c.atlasIntermediate.isEmpty();
            c.atlasActive = conn.value("atlasActive").toString();
            readFloats(conn.value("vertActive"), c.vertActive, 8, ok);
            c.hasActive = ok && !c.atlasActive.isEmpty();
            m_connRecs.append(c);
        }
    }
}

void TreeScene::addSpriteQuad(QVector<QuadBatch>& batches, QHash<QString, int>& index,
                              const Sprite& sp, float cx, float cy, quint32 rgba) {
    if (!sp.valid())
        return;
    const QImage atlasImg = getImage(sp.atlas);
    if (atlasImg.isNull() || atlasImg.width() <= 0 || atlasImg.height() <= 0)
        return;
    const float aw = atlasImg.width();
    const float ah = atlasImg.height();
    const float dw = sp.sw * kSpriteScale;
    const float dh = sp.sh * kSpriteScale;
    QuadBatch& b = batches[batchFor(batches, index, sp.atlas)];
    pushRect(b, cx - dw / 2.0f, cy - dh / 2.0f, cx + dw / 2.0f, cy + dh / 2.0f,
             sp.sx / aw, sp.sy / ah, (sp.sx + sp.sw) / aw, (sp.sy + sp.sh) / ah, rgba);
}

void TreeScene::buildGroupBatches() {
    m_groupBatches.clear();
    if (!m_controller)
        return;
    auto* groupModel = m_controller->groupsModel();
    if (!groupModel)
        return;
    QHash<QString, int> batchMap;
    for (const QVariantMap& grp : groupModel->groups()) {
        const QVariantMap sp = grp.value("sprite").toMap();
        const QString atlas = sp.value("atlas").toString();
        if (atlas.isEmpty())
            continue;
        const float sw = sp.value("sw").toFloat();
        const float sh = sp.value("sh").toFloat();
        const float sx = sp.value("sx").toFloat();
        const float sy = sp.value("sy").toFloat();
        if (sw <= 0 || sh <= 0)
            continue;
        const QImage atlasImg = getImage(atlas);
        if (atlasImg.isNull() || atlasImg.width() <= 0 || atlasImg.height() <= 0)
            continue;
        const float aw = atlasImg.width();
        const float ah = atlasImg.height();
        QuadBatch& batch = m_groupBatches[batchFor(m_groupBatches, batchMap, atlas)];
        const float gx = grp.value("x").toFloat();
        const float gy = grp.value("y").toFloat();
        const float gdw = sw * kSpriteScale;
        const float gdh = sh * kSpriteScale;
        const float u0 = sx / aw, v0 = sy / ah, u1 = (sx + sw) / aw, v1 = (sy + sh) / ah;
        if (sp.value("isHalf").toBool()) {
            // Top half, then the bottom half mirrored vertically about gy.
            pushRect(batch, gx - gdw / 2.0f, gy - gdh, gx + gdw / 2.0f, gy, u0, v0, u1, v1, kWhite);
            pushRect(batch, gx - gdw / 2.0f, gy, gx + gdw / 2.0f, gy + gdh, u0, v1, u1, v0, kWhite);
        } else {
            pushRect(batch, gx - gdw / 2.0f, gy - gdh / 2.0f, gx + gdw / 2.0f, gy + gdh / 2.0f,
                     u0, v0, u1, v1, kWhite);
        }
    }
}

// Connectors, node icons and frames with legacy's per-state art and tints
// (PassiveTreeView.lua:636-688 connectors, 765-957 nodes).
void TreeScene::buildTintedBatches() {
    m_connectorBatches.clear();
    m_nodeIconBatches.clear();
    m_nodeFrameBatches.clear();
    if (!m_controller)
        return;
    const bool heatOn = m_controller->heatMapOn();
    const bool compareOn = m_controller->compareActive();
    const int hover = m_hoverNodeId;
    const bool hasPath = !m_hoverPath.isEmpty();

    auto allocOf = [this](int id) {
        const auto it = m_nodeIndex.constFind(id);
        return it != m_nodeIndex.constEnd() && m_nodeRecs.at(it.value()).alloc;
    };
    // Legacy GetCompareNodeColor: green = only the compared tree has it, red =
    // only this tree, blue = both, with a different mastery effect.
    auto compareTint = [&](const NodeRec& n) -> quint32 {
        if (!compareOn)
            return kWhite;
        const bool c = m_controller->compareAlloc(n.id);
        if (c && !n.alloc) return kGreen;
        if (!c && n.alloc) return kRed;
        if (c && n.alloc && m_controller->compareBlue(n.id)) return kBlue;
        return kWhite;
    };

    QHash<QString, int> connIdx;
    for (const ConnRec& c : m_connRecs) {
        const bool a1 = allocOf(c.n1), a2 = allocOf(c.n2);
        const float* vert = c.vert;
        QString atlas = c.atlas;
        quint32 tint = kWhite;
        if (!(a1 && a2) && hasPath && c.hasIntermediate
            && (a1 || c.n1 == hover || m_hoverPath.contains(c.n1))
            && (a2 || c.n2 == hover || m_hoverPath.contains(c.n2))) {
            vert = c.vertIntermediate;
            atlas = c.atlasIntermediate;
        }
        if (compareOn) {
            const bool cBoth = m_controller->compareAlloc(c.n1) && m_controller->compareAlloc(c.n2);
            if (cBoth && !(a1 && a2)) {
                if (c.hasActive) { vert = c.vertActive; atlas = c.atlasActive; }
                tint = kGreen;
            } else if ((a1 && a2) && !cBoth) {
                tint = kRed;
            }
        }
        if (m_hoverDeps.contains(c.n1) && m_hoverDeps.contains(c.n2))
            tint = kRed;
        QuadBatch& b = m_connectorBatches[batchFor(m_connectorBatches, connIdx, atlas)];
        pushQuad(b, vert, c.uv, tint);
    }

    QHash<QString, int> iconIdx, frameIdx;
    for (const NodeRec& n : m_nodeRecs) {
        quint32 base = compareTint(n);
        const bool compareShowsAlloc = compareOn && m_controller->compareAlloc(n.id);
        if (heatOn && !n.alloc) {
            const quint32 h = m_controller->heatColor(n.id);
            if (h != 0)
                base = h;
        }
        addSpriteQuad(m_nodeIconBatches, iconIdx, n.icon, n.x, n.y, base);

        // Frame state (PassiveTreeView.lua:788-797).
        const Sprite* frame = &n.frame;
        if (!n.alloc) {
            if ((heatOn || n.id == hover || compareShowsAlloc) && n.frameAlloc.valid())
                frame = &n.frameAlloc;
            else if (m_hoverPath.contains(n.id) && n.framePath.valid())
                frame = &n.framePath;
        }
        quint32 frameTint = base;
        if (hover >= 0 && m_hoverDeps.contains(n.id))
            frameTint = kRed;
        else if (m_radiusColors.contains(n.id))
            frameTint = m_radiusColors.value(n.id);
        addSpriteQuad(m_nodeFrameBatches, frameIdx, *frame, n.x, n.y, frameTint);
    }
}

// Tree-space overlay: the hovered socket's jewel-radius rings
// (PassiveTreeView.lua:1122-1152, Assets/ring.png).
void TreeScene::buildOverlayBatches() {
    m_overlayBatches.clear();
    const QVariantMap radius = m_hoverInfo.value("radius").toMap();
    const QVariantList rings = radius.value("rings").toList();
    if (rings.isEmpty())
        return;
    const float x = radius.value("x").toFloat();
    const float y = radius.value("y").toFloat();
    QHash<QString, int> idx;
    const QString ring = QStringLiteral("Assets/ring.png");
    QuadBatch& b = m_overlayBatches[batchFor(m_overlayBatches, idx, ring)];
    for (const QVariant& v : rings) {
        const QVariantMap r = v.toMap();
        const quint32 col = colorFromString(r.value("color").toString());
        const float outer = r.value("outer").toFloat();
        const float inner = r.value("inner").toFloat();
        pushRect(b, x - outer, y - outer, x + outer, y + outer, 0, 0, 1, 1, col);
        if (inner > 0)
            pushRect(b, x - inner, y - inner, x + inner, y + inner, 0, 0, 1, 1, col);
    }
}

// Screen-space overlay: search-match circles (PassiveTreeView.lua:975-1001,
// Assets/small_ring.png, red, size 175*scale/zoom^0.4), clamped to the
// viewport edge at 2/3 size when main.edgeSearchHighlight is on.
void TreeScene::buildScreenBatches() {
    m_screenBatches.clear();
    m_searchCircles.clear();
    if (!m_controller || !m_showSearch || !m_view.valid())
        return;
    const QVariantList results = m_controller->searchResults();
    if (results.isEmpty())
        return;
    const double vpW = width(), vpH = height();
    const double baseSize = 175.0 * m_view.scale() / std::pow(m_view.zoom(), 0.4);
    constexpr double peek = 1.15;
    constexpr double scaledDown = 0.6667;
    QHash<QString, int> idx;
    const QString ringPath = QStringLiteral("Assets/small_ring.png");
    QuadBatch& b = m_screenBatches[batchFor(m_screenBatches, idx, ringPath)];
    for (const QVariant& v : results) {
        double tx = 0, ty = 0;
        if (!m_controller->nodePosition(v.toInt(), tx, ty))
            continue;
        double sx = 0, sy = 0;
        m_view.treeToScreen(tx, ty, sx, sy);
        double size = baseSize;
        double nx = sx - size, ny = sy - size;
        const double cx = std::clamp(nx, -size / peek, vpW - size * peek);
        const double cy = std::clamp(ny, -size / peek, vpH - size * peek);
        if (cx != nx || cy != ny) {
            if (!m_edgeSearch)
                continue;
            size *= scaledDown;
            nx = cx + size / 2.0;
            ny = cy + size / 2.0;
        }
        m_searchCircles.append(QRectF(nx, ny, size * 2.0, size * 2.0));
        pushRect(b, float(nx), float(ny), float(nx + size * 2.0), float(ny + size * 2.0), 0, 0, 1, 1, kRed);
    }
}

namespace {
void clearContainer(QSGNode* c) {
    while (c->childCount() > 0) {
        QSGNode* child = c->childAtIndex(0);
        c->removeChildNode(child);
        delete child;
    }
}

void populateTinted(QSGNode* container, const QVector<TreeScene::QuadBatch>& batches, QQuickWindow* window) {
    for (const auto& batch : batches) {
        if (batch.vertices.isEmpty() || batch.indices.isEmpty())
            continue;
        QSGTexture* tex = TreeScene::getTexture(window, batch.atlasPath);
        if (!tex)
            continue;
        auto* geomNode = new QSGGeometryNode;
        auto* geom = new QSGGeometry(tintedTextureAttributes(), batch.vertices.size(),
                                     batch.indices.size(), QSGGeometry::UnsignedIntType);
        geom->setDrawingMode(QSGGeometry::DrawTriangles);
        std::memcpy(geom->vertexData(), batch.vertices.constData(), batch.vertices.size() * sizeof(TintedVertex));
        std::memcpy(geom->indexDataAsUInt(), batch.indices.constData(), batch.indices.size() * sizeof(quint32));
        geomNode->setGeometry(geom);
        geomNode->setFlag(QSGNode::OwnsGeometry, true);
        auto* mat = new TintedTextureMaterial;
        mat->setTexture(tex);
        geomNode->setMaterial(mat);
        geomNode->setFlag(QSGNode::OwnsMaterial, true);
        container->appendChildNode(geomNode);
    }
}
}

QSGNode* TreeScene::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) {
    if (width() <= 0 || height() <= 0) {
        delete oldNode;
        return nullptr;
    }

    // Node tree: root -> [background, transform -> [groups, connectors, icons,
    // frames, overlay], screen overlay].
    QSGNode* rootNode = oldNode;
    QSGNode* bgContainer = nullptr;
    QSGTransformNode* transformNode = nullptr;
    QSGNode* groupContainer = nullptr;
    QSGNode* connContainer = nullptr;
    QSGNode* iconContainer = nullptr;
    QSGNode* frameContainer = nullptr;
    QSGNode* overlayContainer = nullptr;
    QSGNode* screenContainer = nullptr;

    if (!rootNode) {
        rootNode = new QSGNode;
        bgContainer = new QSGNode;
        rootNode->appendChildNode(bgContainer);
        transformNode = new QSGTransformNode;
        rootNode->appendChildNode(transformNode);
        groupContainer = new QSGNode;
        transformNode->appendChildNode(groupContainer);
        connContainer = new QSGNode;
        transformNode->appendChildNode(connContainer);
        iconContainer = new QSGNode;
        transformNode->appendChildNode(iconContainer);
        frameContainer = new QSGNode;
        transformNode->appendChildNode(frameContainer);
        overlayContainer = new QSGNode;
        transformNode->appendChildNode(overlayContainer);
        screenContainer = new QSGNode;
        rootNode->appendChildNode(screenContainer);
        m_dirtyGeometry = true;
        m_dirtyTransform = true;
    } else {
        bgContainer = rootNode->childAtIndex(0);
        transformNode = static_cast<QSGTransformNode*>(rootNode->childAtIndex(1));
        groupContainer = transformNode->childAtIndex(0);
        connContainer = transformNode->childAtIndex(1);
        iconContainer = transformNode->childAtIndex(2);
        frameContainer = transformNode->childAtIndex(3);
        overlayContainer = transformNode->childAtIndex(4);
        screenContainer = rootNode->childAtIndex(2);
    }

    if (!m_controller || !m_view.valid())
        return rootNode;

    const double scale = m_view.scale();
    const double zx = zoomX();
    const double zy = zoomY();
    const float w = static_cast<float>(width());
    const float h = static_cast<float>(height());

    // 1. Tiled Background Node Update. The background texture belongs to the
    // selected tree version, so a spec/version switch must replace an existing
    // material instead of silently retaining the old atlas.
    const QString bgUrl = m_controller ? m_controller->backgroundUrl() : QString();
    if (m_backgroundPath != bgUrl) {
        clearContainer(bgContainer);
        m_backgroundPath = bgUrl;
    }
    if (!bgUrl.isEmpty()) {
        QSGTexture* bgTex = getTexture(window(), bgUrl, true);
        if (bgTex) {
            QSGGeometryNode* bgGeomNode = nullptr;
            if (bgContainer->childCount() == 0) {
                bgGeomNode = new QSGGeometryNode;
                auto* bgGeom = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 4, 6, QSGGeometry::UnsignedShortType);
                bgGeom->setDrawingMode(QSGGeometry::DrawTriangles);
                bgGeomNode->setGeometry(bgGeom);
                bgGeomNode->setFlag(QSGNode::OwnsGeometry, true);
                auto* mat = new QSGTextureMaterial;
                mat->setTexture(bgTex);
                mat->setFiltering(QSGTexture::Linear);
                bgGeomNode->setMaterial(mat);
                bgGeomNode->setFlag(QSGNode::OwnsMaterial, true);
                auto* iData = bgGeom->indexDataAsUShort();
                iData[0] = 0; iData[1] = 1; iData[2] = 2;
                iData[3] = 0; iData[4] = 2; iData[5] = 3;
                bgContainer->appendChildNode(bgGeomNode);
            } else {
                bgGeomNode = static_cast<QSGGeometryNode*>(bgContainer->childAtIndex(0));
            }
            if (bgGeomNode && bgGeomNode->geometry()) {
                const float bgSize = bgTex->textureSize().width() * scale * 1.33f * 2.5f;
                const float u0 = (zx + w / 2.0f) / -bgSize;
                const float v0 = (zy + h / 2.0f) / -bgSize;
                const float u1 = (w / 2.0f - zx) / bgSize;
                const float v1 = (h / 2.0f - zy) / bgSize;
                auto* vData = bgGeomNode->geometry()->vertexDataAsTexturedPoint2D();
                vData[0].set(0, 0, u0, v0);
                vData[1].set(w, 0, u1, v0);
                vData[2].set(w, h, u1, v1);
                vData[3].set(0, h, u0, v1);
                bgGeomNode->markDirty(QSGNode::DirtyGeometry);
            }
        }
    }

    // 2. Transform Node Update (Zero CPU: matrix write only)
    QMatrix4x4 mat;
    mat.translate(w / 2.0f + static_cast<float>(zx), h / 2.0f + static_cast<float>(zy), 0.0f);
    mat.scale(static_cast<float>(scale), static_cast<float>(scale), 1.0f);
    transformNode->setMatrix(mat);

    // 3. Tree data: re-parse only when the tree revision changes.
    const QString currentRev = m_controller ? m_controller->lastRevision() : QString();
    if (m_dirtyGeometry || m_builtRevision.isEmpty() || m_builtRevision != currentRev) {
        m_dirtyGeometry = false;
        m_builtRevision = currentRev;
        parseTreeData();
        buildGroupBatches();
        clearContainer(groupContainer);
        populateTinted(groupContainer, m_groupBatches, window());
        m_dirtyTint = true;
        m_dirtyOverlay = true;
    }

    // 4. Art state + tints (hover preview, heat map, compare).
    if (m_dirtyTint) {
        m_dirtyTint = false;
        buildTintedBatches();
        clearContainer(connContainer);
        populateTinted(connContainer, m_connectorBatches, window());
        clearContainer(iconContainer);
        populateTinted(iconContainer, m_nodeIconBatches, window());
        clearContainer(frameContainer);
        populateTinted(frameContainer, m_nodeFrameBatches, window());
    }

    // 5. Tree-space overlay (radius rings).
    if (m_dirtyOverlay) {
        buildOverlayBatches();
        clearContainer(overlayContainer);
        populateTinted(overlayContainer, m_overlayBatches, window());
    }

    // 6. Screen-space overlay (search circles): moves with every pan/zoom.
    if (m_dirtyOverlay || m_dirtyTransform) {
        buildScreenBatches();
        clearContainer(screenContainer);
        populateTinted(screenContainer, m_screenBatches, window());
    }
    m_dirtyOverlay = false;
    m_dirtyTransform = false;

    return rootNode;
}
