#include "TreeViewController.h"
#include "LuaEngine.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"

#include <cmath>
#include <limits>
#include <QDebug>
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QImage>
#include <QMap>

namespace {
// Tree-space units. Most node hit circles span only one or two cells; storing
// circles in all touched cells keeps lookup O(candidates at cursor), including
// at any zoom level because the test is performed in tree coordinates.
constexpr double kHitCellSize = 96.0;
}

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

qint64 TreeViewController::hitCellKey(int x, int y) {
    // Do not shift a negative signed integer (undefined behaviour). The high
    // and low halves remain a one-to-one pair for practical tree-grid indices.
    return static_cast<qint64>(x) * 0x100000000LL
           + static_cast<quint32>(y);
}

void TreeViewController::rebuildHitIndex(const QVariantList& nodes) {
    m_hitNodes.clear();
    m_hitCells.clear();
    m_hitNodes.reserve(nodes.size());

    for (const QVariant& row : nodes) {
        const QVariantMap node = row.toMap();
        // Legacy PassiveTreeView only considers nodes that have artwork sized
        // by rsq, belong to a non-proxy group, and are not proxy nodes. The
        // bridge filters proxies too; retaining these checks here makes a
        // malformed/future payload safely non-interactive rather than clickable.
        const double rsq = node.value("rsq").toDouble();
        if (node.value("isProxy").toBool() || !node.value("hasGroup").toBool()
            || node.value("groupIsProxy").toBool() || rsq <= 0.0) {
            continue;
        }

        HitNode hit;
        hit.id = node.value("id").toInt();
        hit.x = node.value("x").toDouble();
        hit.y = node.value("y").toDouble();
        hit.radiusSquared = rsq;
        const int index = m_hitNodes.size();
        m_hitNodes.append(hit);

        const double radius = std::sqrt(rsq);
        const int minX = static_cast<int>(std::floor((hit.x - radius) / kHitCellSize));
        const int maxX = static_cast<int>(std::floor((hit.x + radius) / kHitCellSize));
        const int minY = static_cast<int>(std::floor((hit.y - radius) / kHitCellSize));
        const int maxY = static_cast<int>(std::floor((hit.y + radius) / kHitCellSize));
        for (int cellX = minX; cellX <= maxX; ++cellX) {
            for (int cellY = minY; cellY <= maxY; ++cellY)
                m_hitCells[hitCellKey(cellX, cellY)].append(index);
        }
    }
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

    // Throttle: only rebuild when the engine's tree revision changes (or first load).
    // This was `allocCount * 1000003 + nodeCount`, which was blind to two real cases:
    // an allocation SWAP (dealloc one node, alloc another -> identical counts, so the
    // canvas kept the stale allocation) and any change to the search highlight, which
    // the signature did not sample at all. pob_getTreeData now folds the tree version,
    // both counts, an order-independent checksum of the allocated ids and a search
    // serial into one opaque string. Empty means the host predates the field: fall
    // through and rebuild rather than throttle on a value we cannot trust.
    const QString revision = d.value("revision").toString();
    if (m_loaded && !revision.isEmpty() && revision == m_lastRevision) {
        return;
    }
    m_lastRevision = revision;
    m_loaded = true;

    const QVariantList nodeRows = d.value("nodes").toList();
    if (m_nodes)
        m_nodes->setNodes(nodeRows);
    rebuildHitIndex(nodeRows);
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

    emit viewChanged();
    qDebug().noquote() << "[TreeViewController] refresh -> nodes="
             << nodeRows.size()
             << " groups=" << d.value("groups").toList().size()
             << " connectors=" << d.value("connectors").toList().size();
}

// Phase 4b: invert the treeToScreen transform to find the nearest node id.
// Screen = vpW/2 + zoomX + scale * treeX  (and likewise for y), where
// scale = min(vpW,vpH)/bounds.size * zoom. We solve for treeX/treeY and pick the
// closest node inside its LEGACY hit circle (`node.rsq`). The bridge builds a
// spatial grid at refresh time, so a mouse move no longer deep-copies and scans
// every QVariantMap in TreeModel.
int TreeViewController::hitTest(qreal screenX, qreal screenY, qreal vpW, qreal vpH) {
    if (!m_loaded || m_hitNodes.isEmpty())
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
    const int cellX = static_cast<int>(std::floor(treeX / kHitCellSize));
    const int cellY = static_cast<int>(std::floor(treeY / kHitCellSize));
    const auto candidates = m_hitCells.constFind(hitCellKey(cellX, cellY));
    if (candidates == m_hitCells.constEnd())
        return -1;
    double bestDist = std::numeric_limits<double>::infinity();
    int bestId = -1;
    for (const int index : candidates.value()) {
        const HitNode& node = m_hitNodes.at(index);
        const double dx = node.x - treeX;
        const double dy = node.y - treeY;
        const double d2 = dx * dx + dy * dy;
        if (d2 <= node.radiusSquared && d2 < bestDist) {
            bestDist = d2;
            bestId = node.id;
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

