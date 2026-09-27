#include "TreeScene.h"
#include "TreeViewController.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"
#include "LuaEngine.h"

#include <QQuickWindow>
#include <QImageReader>
#include <QPainter>
#include <cmath>
#include <algorithm>

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
    m_dirtyOverlay = true;
    emit hoverNodeIdChanged();
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

void TreeScene::buildGeometryBatches() {
    m_groupBatches.clear();
    m_connectorBatches.clear();
    m_nodeIconBatches.clear();
    m_nodeFrameBatches.clear();

    if (!m_controller)
        return;

    // 1. Group Backgrounds
    if (auto* groupModel = m_controller->groupsModel()) {
        QHash<QString, int> batchMap;
        const auto& groups = groupModel->groups();
        for (const QVariantMap& grp : groups) {
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
            if (atlasImg.isNull())
                continue;
            const float aw = atlasImg.width();
            const float ah = atlasImg.height();
            if (aw <= 0 || ah <= 0)
                continue;

            int batchIdx = batchMap.value(atlas, -1);
            if (batchIdx < 0) {
                batchIdx = m_groupBatches.size();
                batchMap.insert(atlas, batchIdx);
                QuadBatch b;
                b.atlasPath = atlas;
                m_groupBatches.append(b);
            }
            QuadBatch& batch = m_groupBatches[batchIdx];

            const float gx = grp.value("x").toFloat();
            const float gy = grp.value("y").toFloat();
            const float gdw = sw * 2.66f;
            const float gdh = sh * 2.66f;
            const bool isHalf = sp.value("isHalf").toBool();

            const float u0 = sx / aw;
            const float v0 = sy / ah;
            const float u1 = (sx + sw) / aw;
            const float v1 = (sy + sh) / ah;

            if (isHalf) {
                // Top half
                quint32 baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
                batch.vertices << (gx - gdw / 2.0f) << (gy - gdh) << u0 << v0;
                batch.vertices << (gx + gdw / 2.0f) << (gy - gdh) << u1 << v0;
                batch.vertices << (gx + gdw / 2.0f) << gy << u1 << v1;
                batch.vertices << (gx - gdw / 2.0f) << gy << u0 << v1;
                batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                              << baseIdx << (baseIdx + 2) << (baseIdx + 3);

                // Bottom half (mirrored vertically: v1 at center gy, v0 at bottom gy + gdh)
                baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
                batch.vertices << (gx - gdw / 2.0f) << gy << u0 << v1;
                batch.vertices << (gx + gdw / 2.0f) << gy << u1 << v1;
                batch.vertices << (gx + gdw / 2.0f) << (gy + gdh) << u1 << v0;
                batch.vertices << (gx - gdw / 2.0f) << (gy + gdh) << u0 << v0;
                batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                              << baseIdx << (baseIdx + 2) << (baseIdx + 3);
            } else {
                quint32 baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
                batch.vertices << (gx - gdw / 2.0f) << (gy - gdh / 2.0f) << u0 << v0;
                batch.vertices << (gx + gdw / 2.0f) << (gy - gdh / 2.0f) << u1 << v0;
                batch.vertices << (gx + gdw / 2.0f) << (gy + gdh / 2.0f) << u1 << v1;
                batch.vertices << (gx - gdw / 2.0f) << (gy + gdh / 2.0f) << u0 << v1;
                batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                              << baseIdx << (baseIdx + 2) << (baseIdx + 3);
            }
        }
    }

    // 2. Connectors
    if (auto* connModel = m_controller->connectorsModel()) {
        QHash<QString, int> batchMap;
        const auto& connectors = connModel->connectors();
        for (const QVariantMap& conn : connectors) {
            const QString atlas = conn.value("atlas").toString();
            if (atlas.isEmpty())
                continue;
            const QVariantList vert = conn.value("vert").toList();
            const QVariantList uv = conn.value("uv").toList();
            if (vert.size() < 8 || uv.size() < 8)
                continue;

            int batchIdx = batchMap.value(atlas, -1);
            if (batchIdx < 0) {
                batchIdx = m_connectorBatches.size();
                batchMap.insert(atlas, batchIdx);
                QuadBatch b;
                b.atlasPath = atlas;
                m_connectorBatches.append(b);
            }
            QuadBatch& batch = m_connectorBatches[batchIdx];

            quint32 baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
            batch.vertices << vert[0].toFloat() << vert[1].toFloat() << uv[0].toFloat() << uv[1].toFloat();
            batch.vertices << vert[2].toFloat() << vert[3].toFloat() << uv[2].toFloat() << uv[3].toFloat();
            batch.vertices << vert[4].toFloat() << vert[5].toFloat() << uv[4].toFloat() << uv[5].toFloat();
            batch.vertices << vert[6].toFloat() << vert[7].toFloat() << uv[6].toFloat() << uv[7].toFloat();
            batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                          << baseIdx << (baseIdx + 2) << (baseIdx + 3);
        }
    }

    // 3. Node Icons & Frame Rings
    if (auto* nodeModel = m_controller->nodesModel()) {
        QHash<QString, int> iconBatchMap;
        QHash<QString, int> frameBatchMap;
        const auto& nodes = nodeModel->nodes();
        for (const QVariantMap& node : nodes) {
            const float nx = node.value("x").toFloat();
            const float ny = node.value("y").toFloat();

            // Node Icon
            const QVariantMap sp = node.value("iconSprite").toMap();
            const QString iconAtlas = sp.value("atlas").toString();
            if (!iconAtlas.isEmpty()) {
                const float sw = sp.value("sw").toFloat();
                const float sh = sp.value("sh").toFloat();
                const float sx = sp.value("sx").toFloat();
                const float sy = sp.value("sy").toFloat();
                if (sw > 0 && sh > 0) {
                    const QImage atlasImg = getImage(iconAtlas);
                    if (!atlasImg.isNull() && atlasImg.width() > 0 && atlasImg.height() > 0) {
                        const float aw = atlasImg.width();
                        const float ah = atlasImg.height();
                        int batchIdx = iconBatchMap.value(iconAtlas, -1);
                        if (batchIdx < 0) {
                            batchIdx = m_nodeIconBatches.size();
                            iconBatchMap.insert(iconAtlas, batchIdx);
                            QuadBatch b;
                            b.atlasPath = iconAtlas;
                            m_nodeIconBatches.append(b);
                        }
                        QuadBatch& batch = m_nodeIconBatches[batchIdx];

                        const float dw = sw * 2.66f;
                        const float dh = sh * 2.66f;
                        const float u0 = sx / aw;
                        const float v0 = sy / ah;
                        const float u1 = (sx + sw) / aw;
                        const float v1 = (sy + sh) / ah;

                        quint32 baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
                        batch.vertices << (nx - dw / 2.0f) << (ny - dh / 2.0f) << u0 << v0;
                        batch.vertices << (nx + dw / 2.0f) << (ny - dh / 2.0f) << u1 << v0;
                        batch.vertices << (nx + dw / 2.0f) << (ny + dh / 2.0f) << u1 << v1;
                        batch.vertices << (nx - dw / 2.0f) << (ny + dh / 2.0f) << u0 << v1;
                        batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                                      << baseIdx << (baseIdx + 2) << (baseIdx + 3);
                    }
                }
            }

            // Node Frame Ring
            const QVariantMap fr = node.value("frameSprite").toMap();
            const QString frameAtlas = fr.value("atlas").toString();
            if (!frameAtlas.isEmpty()) {
                const float fsw = fr.value("sw").toFloat();
                const float fsh = fr.value("sh").toFloat();
                const float fsx = fr.value("sx").toFloat();
                const float fsy = fr.value("sy").toFloat();
                if (fsw > 0 && fsh > 0) {
                    const QImage fatlasImg = getImage(frameAtlas);
                    if (!fatlasImg.isNull() && fatlasImg.width() > 0 && fatlasImg.height() > 0) {
                        const float faw = fatlasImg.width();
                        const float fah = fatlasImg.height();
                        int batchIdx = frameBatchMap.value(frameAtlas, -1);
                        if (batchIdx < 0) {
                            batchIdx = m_nodeFrameBatches.size();
                            frameBatchMap.insert(frameAtlas, batchIdx);
                            QuadBatch b;
                            b.atlasPath = frameAtlas;
                            m_nodeFrameBatches.append(b);
                        }
                        QuadBatch& batch = m_nodeFrameBatches[batchIdx];

                        const float fdw = fsw * 2.66f;
                        const float fdh = fsh * 2.66f;
                        const float fu0 = fsx / faw;
                        const float fv0 = fsy / fah;
                        const float fu1 = (fsx + fsw) / faw;
                        const float fv1 = (fsy + fsh) / fah;

                        quint32 baseIdx = static_cast<quint32>(batch.vertices.size() / 4);
                        batch.vertices << (nx - fdw / 2.0f) << (ny - fdh / 2.0f) << fu0 << fv0;
                        batch.vertices << (nx + fdw / 2.0f) << (ny - fdh / 2.0f) << fu1 << fv0;
                        batch.vertices << (nx + fdw / 2.0f) << (ny + fdh / 2.0f) << fu1 << fv1;
                        batch.vertices << (nx - fdw / 2.0f) << (ny + fdh / 2.0f) << fu0 << fv1;
                        batch.indices << baseIdx << (baseIdx + 1) << (baseIdx + 2)
                                      << baseIdx << (baseIdx + 2) << (baseIdx + 3);
                    }
                }
            }
        }
    }
}

namespace {
void populateBatchContainer(QSGNode* container, const QVector<TreeScene::QuadBatch>& batches, QQuickWindow* window) {
    for (const auto& batch : batches) {
        if (batch.vertices.isEmpty() || batch.indices.isEmpty())
            continue;
        QSGTexture* tex = TreeScene::getTexture(window, batch.atlasPath);
        if (!tex)
            continue;
        auto* geomNode = new QSGGeometryNode;
        auto* geom = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(),
                                     batch.vertices.size() / 4,
                                     batch.indices.size(),
                                     QSGGeometry::UnsignedIntType);
        geom->setDrawingMode(QSGGeometry::DrawTriangles);

        auto* vData = geom->vertexDataAsTexturedPoint2D();
        for (int i = 0; i < batch.vertices.size(); i += 4) {
            const int vIdx = i / 4;
            vData[vIdx].set(batch.vertices[i], batch.vertices[i + 1], batch.vertices[i + 2], batch.vertices[i + 3]);
        }

        auto* iData = geom->indexDataAsUInt();
        for (int i = 0; i < batch.indices.size(); ++i) {
            iData[i] = batch.indices[i];
        }

        geomNode->setGeometry(geom);
        geomNode->setFlag(QSGNode::OwnsGeometry, true);

        auto* mat = new QSGTextureMaterial;
        mat->setTexture(tex);
        mat->setMipmapFiltering(QSGTexture::Linear);
        mat->setFiltering(QSGTexture::Linear);
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

    QSGNode* rootNode = oldNode;
    QSGNode* bgContainer = nullptr;
    QSGTransformNode* transformNode = nullptr;
    QSGNode* groupContainer = nullptr;
    QSGNode* connContainer = nullptr;
    QSGNode* iconContainer = nullptr;
    QSGNode* frameContainer = nullptr;
    QSGNode* overlayContainer = nullptr;

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
        while (bgContainer->childCount() > 0) {
            QSGNode* child = bgContainer->childAtIndex(0);
            bgContainer->removeChildNode(child);
            delete child;
        }
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

    // 3. Geometry Batches Rebuild (Only when tree revision changes)
    const QString currentRev = m_controller ? m_controller->lastRevision() : QString();
    if (m_dirtyGeometry || (m_builtRevision.isEmpty() || m_builtRevision != currentRev)) {
        m_dirtyGeometry = false;
        m_builtRevision = currentRev;

        buildGeometryBatches();

        // Clear existing children in containers
        auto clearContainer = [](QSGNode* c) {
            while (c->childCount() > 0) {
                QSGNode* child = c->childAtIndex(0);
                c->removeChildNode(child);
                delete child;
            }
        };

        clearContainer(groupContainer);
        populateBatchContainer(groupContainer, m_groupBatches, window());

        clearContainer(connContainer);
        populateBatchContainer(connContainer, m_connectorBatches, window());

        clearContainer(iconContainer);
        populateBatchContainer(iconContainer, m_nodeIconBatches, window());

        clearContainer(frameContainer);
        populateBatchContainer(frameContainer, m_nodeFrameBatches, window());

        m_dirtyOverlay = true;
    }

    // 4. Search & Overlay Geometry (Highlights)
    if (m_dirtyOverlay) {
        m_dirtyOverlay = false;
        while (overlayContainer->childCount() > 0) {
            QSGNode* child = overlayContainer->childAtIndex(0);
            overlayContainer->removeChildNode(child);
            delete child;
        }

        if (m_showSearch && m_controller) {
            const QVariantList results = m_controller->searchResults();
            if (!results.isEmpty() && m_controller->nodesModel()) {
                QSet<int> matchSet;
                for (const QVariant& v : results)
                    matchSet.insert(v.toInt());

                // Build a combined geometry for all search rings
                const auto& nodes = m_controller->nodesModel()->nodes();
                QVector<float> ringVerts;
                QVector<quint32> ringIndices;

                const int kSegments = 24;
                for (const QVariantMap& node : nodes) {
                    const int id = node.value("id").toInt();
                    if (!matchSet.contains(id))
                        continue;

                    const float nx = node.value("x").toFloat();
                    const float ny = node.value("y").toFloat();
                    const QVariantMap sp = node.value("iconSprite").toMap();
                    float baseR = 30.0f;
                    if (!sp.isEmpty() && sp.value("sw").toFloat() > 0) {
                        baseR = std::max(sp.value("sw").toFloat(), sp.value("sh").toFloat()) * 2.66f / 2.0f + 8.0f;
                    }

                    const float rInner = baseR;
                    const float rOuter = baseR + 6.0f;
                    const quint32 baseIdx = static_cast<quint32>(ringVerts.size() / 2);

                    for (int s = 0; s <= kSegments; ++s) {
                        const float angle = static_cast<float>(s * 2.0 * M_PI / kSegments);
                        const float cosA = std::cos(angle);
                        const float sinA = std::sin(angle);
                        ringVerts << (nx + rInner * cosA) << (ny + rInner * sinA);
                        ringVerts << (nx + rOuter * cosA) << (ny + rOuter * sinA);
                    }
                    for (int s = 0; s < kSegments; ++s) {
                        const quint32 i0 = baseIdx + s * 2;
                        const quint32 i1 = baseIdx + s * 2 + 1;
                        const quint32 i2 = baseIdx + (s + 1) * 2;
                        const quint32 i3 = baseIdx + (s + 1) * 2;
                        ringIndices << i0 << i1 << i2 << i1 << i3 << i2;
                    }
                }

                if (!ringVerts.isEmpty()) {
                    auto* searchNode = new QSGGeometryNode;
                    auto* geom = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(),
                                                 ringVerts.size() / 2,
                                                 ringIndices.size(),
                                                 QSGGeometry::UnsignedIntType);
                    geom->setDrawingMode(QSGGeometry::DrawTriangles);
                    auto* vData = geom->vertexDataAsPoint2D();
                    for (int i = 0; i < ringVerts.size(); i += 2) {
                        vData[i / 2].set(ringVerts[i], ringVerts[i + 1]);
                    }
                    auto* iData = geom->indexDataAsUInt();
                    for (int i = 0; i < ringIndices.size(); ++i) {
                        iData[i] = ringIndices[i];
                    }
                    searchNode->setGeometry(geom);
                    searchNode->setFlag(QSGNode::OwnsGeometry, true);

                    auto* flatMat = new QSGFlatColorMaterial;
                    flatMat->setColor(QColor(0xd4, 0xaf, 0x37, 0xee)); // Gold highlight
                    searchNode->setMaterial(flatMat);
                    searchNode->setFlag(QSGNode::OwnsMaterial, true);

                    overlayContainer->appendChildNode(searchNode);
                }
            }
        }
    }

    return rootNode;
}
