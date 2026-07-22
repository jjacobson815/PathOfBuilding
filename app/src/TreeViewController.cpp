#include "TreeViewController.h"
#include "LuaEngine.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"

#include <cmath>
#include <QDebug>
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QImage>
#include <QMap>

TreeViewController::TreeViewController(QObject* parent) : QObject(parent) {}

void TreeViewController::setModels(TreeModel* nodes, TreeGroupModel* groups,
                                   TreeConnectorModel* connectors) {
    m_nodes = nodes;
    m_groups = groups;
    m_connectors = connectors;
}

double TreeViewController::zoom() const {
    return std::pow(1.2, m_zoomLevel);
}

// Clamp pan so the tree can't be dragged into empty canvas past its border,
// while never cropping the outermost nodes (legacy PassiveTreeView.lua limits
// pan the same way; its literal `viewport * zoom * 2/3` formula is calibrated to
// legacy's own tree->screen scale and does NOT transfer to ours, so this derives
// the bound from our actual geometry instead).
//
// Screen mapping (must match drawTree / hitTest):
//     screen = vp/2 + zoomOffset + scale * treeCoord,  scale = baseScale * zoom,
//     baseScale = min(vpW,vpH) / bounds.size
// The farthest node on an axis sits at distance `extent` tree-units from the
// tree origin, i.e. `extent * scale` screen-px from the origin point. Allowing
// |zoomOffset| up to `extent*scale - vp/2` lets that node travel exactly to the
// viewport edge (fully reachable, never cropped) and no further (beyond it would
// be void). When the whole tree fits in the viewport the bound is 0 -> locked.
bool TreeViewController::clampPan() {
    if (m_vpW <= 0.0 || m_vpH <= 0.0)
        return false;
    const double size = m_bounds.value("size").toDouble();
    if (size <= 0.0)
        return false;
    const double scale = (std::min(m_vpW, m_vpH) / size) * zoom();
    const double minx = m_bounds.value("min_x").toDouble();
    const double maxx = m_bounds.value("max_x").toDouble();
    const double miny = m_bounds.value("min_y").toDouble();
    const double maxy = m_bounds.value("max_y").toDouble();
    const double extentX = std::max(std::abs(minx), std::abs(maxx));
    const double extentY = std::max(std::abs(miny), std::abs(maxy));
    // Margin so the outermost node sits fully inside the border rather than
    // half-clipped by it. Without it the edge node's CENTRE lands on the
    // viewport edge (its outer half off-screen). Sized to a node's on-screen
    // half-extent (largest overlay ~85 sheet-units * scale * 2.66 / 2), so it
    // tracks zoom; the resulting sliver of canvas beyond the node is negligible
    // versus the unbounded void this clamp removes.
    const double nodeMargin = 85.0 * scale * 2.66 / 2.0;
    const double maxX = std::max(0.0, extentX * scale - m_vpW / 2.0 + nodeMargin);
    const double maxY = std::max(0.0, extentY * scale - m_vpH / 2.0 + nodeMargin);
    const double cx = std::min(std::max(m_zoomX, -maxX), maxX);
    const double cy = std::min(std::max(m_zoomY, -maxY), maxY);
    if (cx != m_zoomX || cy != m_zoomY) {
        m_zoomX = cx;
        m_zoomY = cy;
        return true;
    }
    return false;
}

void TreeViewController::setViewport(qreal w, qreal h) {
    if (m_vpW == w && m_vpH == h)
        return;
    m_vpW = w;
    m_vpH = h;
    // A shrunk viewport (or first report) may put an existing pan out of bounds.
    if (clampPan())
        emit transformChanged();
}

void TreeViewController::setZoomLevel(double v) {
    if (v < 0.0) v = 0.0;
    if (v > 12.0) v = 12.0;
    if (m_zoomLevel != v) {
        m_zoomLevel = v;
        // Zooming out shrinks the allowed pan range, so re-clamp.
        clampPan();
        emit transformChanged();
    }
}

void TreeViewController::setZoomX(double v) {
    const double old = m_zoomX;
    m_zoomX = v;
    clampPan();
    if (m_zoomX != old)
        emit transformChanged();
}

void TreeViewController::setZoomY(double v) {
    const double old = m_zoomY;
    m_zoomY = v;
    clampPan();
    if (m_zoomY != old)
        emit transformChanged();
}

void TreeViewController::zoomBy(double delta) {
    setZoomLevel(m_zoomLevel + delta);
}

void TreeViewController::panBy(double dx, double dy) {
    const double oldX = m_zoomX, oldY = m_zoomY;
    m_zoomX += dx;
    m_zoomY += dy;
    clampPan();
    if (m_zoomX != oldX || m_zoomY != oldY)
        emit transformChanged();
}

void TreeViewController::resetView() {
    m_zoomLevel = 8.0;
    m_zoomX = 0.0;
    m_zoomY = 0.0;
    emit transformChanged();
}

void TreeViewController::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    m_engine = engine;
    QVariant data = engine->getTreeData();
    if (data.typeId() != QMetaType::QVariantMap) {
        // Tree not ready yet. Do NOT poll: LuaEngine::treeChanged / modeChanged
        // will re-invoke refresh() when the build/tree becomes available.
        return;
    }
    const QVariantMap d = data.toMap();

    // Throttle: only rebuild when the allocation signature changes (or first load).
    const int nodeCount = d.value("nodeCount").toInt();
    const int allocCount = d.value("allocCount").toInt();
    const int sig = allocCount * 1000003 + nodeCount;
    if (m_loaded && sig == m_lastSig) {
        return;
    }
    m_lastSig = sig;
    m_loaded = true;

    if (m_nodes)
        m_nodes->setNodes(d.value("nodes").toList());
    if (m_groups)
        m_groups->setGroups(d.value("groups").toList());
    if (m_connectors)
        m_connectors->setConnectors(d.value("connectors").toList());

    m_bounds = d.value("bounds").toMap();
    m_assets = d.value("assets").toMap();
    m_assetBasePath = d.value("assetBasePath").toString();
    m_backgroundUrl = d.value("backgroundUrl").toString();

    // --- Bounds-valid + asset-init signals (event-driven, fire once) ---
    const bool valid = (m_bounds.value("size").toDouble() > 0)
                       && !m_assets.isEmpty()
                       && !m_assetBasePath.isEmpty();
    if (valid && !m_boundsValid) {
        m_boundsValid = true;
        emit boundsValidChanged();
    }
    if (valid && !m_assetsInitialized) {
        m_assetsInitialized = true;
        emit assetsInitialized();
    }

    const int nNodes = d.value("nodes").toList().size();
    const int nGroups = d.value("groups").toList().size();
    const int nConn = d.value("connectors").toList().size();

    emit viewChanged();
    qDebug().noquote() << "[TreeViewController] refresh -> nodes="
             << d.value("nodes").toList().size()
             << " groups=" << d.value("groups").toList().size()
             << " connectors=" << d.value("connectors").toList().size();
}

// Phase 4b: invert the treeToScreen transform to find the nearest node id.
// Screen = vpW/2 + zoomX + scale * treeX  (and likewise for y), where
// scale = min(vpW,vpH)/bounds.size * zoom. We solve for treeX/treeY and pick the
// closest node within a ~25px hit radius (in tree units: 25/scale).
int TreeViewController::hitTest(qreal screenX, qreal screenY, qreal vpW, qreal vpH) {
    if (!m_loaded || !m_nodes)
        return -1;
    const double size = m_bounds.value("size").toDouble();
    if (size <= 0 || vpW <= 0 || vpH <= 0)
        return -1;
    const double baseScale = std::min(vpW, vpH) / size;
    const double scale = baseScale * zoom();
    if (scale <= 0)
        return -1;
    const double offsetX = m_zoomX + vpW / 2.0;
    const double offsetY = m_zoomY + vpH / 2.0;
    const double treeX = (screenX - offsetX) / scale;
    const double treeY = (screenY - offsetY) / scale;
    const double threshold = 25.0 / scale; // ~25px hit radius
    double bestDist = threshold * threshold;
    int bestId = -1;
    const int n = m_nodes->count();
    for (int i = 0; i < n; i++) {
        const QVariantMap m = m_nodes->get(i).toMap();
        const double nx = m.value("x").toDouble();
        const double ny = m.value("y").toDouble();
        const double dx = nx - treeX;
        const double dy = ny - treeY;
        const double d2 = dx * dx + dy * dy;
        if (d2 <= bestDist) {
            bestDist = d2;
            bestId = m.value("id").toInt();
        }
    }
    return bestId;
}

// Phase 4b: allocation toggles. Call the Lua bridge, then refresh the models so
// the canvas reflects the new alloc state, and repaint via viewChanged().
void TreeViewController::allocNode(int id) {
    if (!m_engine)
        return;
    m_engine->allocNode(id);
    refresh(m_engine);
    emit viewChanged();
}

void TreeViewController::deallocNode(int id) {
    if (!m_engine)
        return;
    m_engine->deallocNode(id);
    refresh(m_engine);
    emit viewChanged();
}

void TreeViewController::toggleNode(int id) {
    if (!m_engine)
        return;
    m_engine->toggleNode(id);
    refresh(m_engine);
    emit viewChanged();
}

// Phase 4b: set the tree search string; store the matching id list and notify.
void TreeViewController::setTreeSearch(const QString& str) {
    if (!m_engine) {
        m_searchResults.clear();
        emit searchChanged();
        return;
    }
    m_searchResults = m_engine->setTreeSearch(str);
    emit searchChanged();
}

