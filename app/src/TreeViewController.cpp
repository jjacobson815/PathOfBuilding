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

double TreeViewController::extentX() const {
    return std::max(std::abs(m_bounds.value("min_x").toDouble()),
                    std::abs(m_bounds.value("max_x").toDouble()));
}

double TreeViewController::extentY() const {
    return std::max(std::abs(m_bounds.value("min_y").toDouble()),
                    std::abs(m_bounds.value("max_y").toDouble()));
}

bool TreeViewController::nodePosition(int id, double& x, double& y) const {
    const auto it = m_nodePos.constFind(id);
    if (it == m_nodePos.constEnd())
        return false;
    x = it->first;
    y = it->second;
    return true;
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
    m_nodePos.clear();
    m_hitNodes.reserve(nodes.size());
    m_nodePos.reserve(nodes.size());

    for (const QVariant& row : nodes) {
        const QVariantMap node = row.toMap();
        m_nodePos.insert(node.value("id").toInt(),
                         qMakePair(node.value("x").toDouble(), node.value("y").toDouble()));
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

// Pick the closest node whose LEGACY hit circle (`node.rsq`) contains the
// tree-space point. The screen->tree inversion is per view (TreeViewport); the
// spatial grid built at refresh time means a mouse move no longer deep-copies
// and scans every QVariantMap in TreeModel.
int TreeViewController::hitTestTree(double treeX, double treeY) const {
    if (!m_loaded || m_hitNodes.isEmpty())
        return -1;
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

