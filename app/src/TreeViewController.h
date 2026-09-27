#pragma once
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QString>
#include <QHash>
#include <QVector>

class LuaEngine;
class TreeModel;
class TreeGroupModel;
class TreeConnectorModel;

// Phase 4a/4b: owns the three passive-tree data models (shared by every tree
// view of the current build) and repopulates them from the Lua bridge
// (pob_getTreeData) on demand. View state (zoom/pan) is NOT here: it is per
// view, in TreeScene's TreeViewport (Phase 4.1 embeddable viewer). refresh()
// is throttled: it only rebuilds the models when the engine's tree revision
// changes (or on first load), so calling it every frame is cheap.
// Phase 4b adds tree-space hit-testing, allocation toggles that flow through
// the Lua bridge, and a search-match id list.
class TreeViewController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap bounds READ bounds NOTIFY viewChanged)
    // Robust, typed accessor for the tree bounds "size" (max extent in tree
    // units). Exposed separately from the QVariantMap so QML never has to rely
    // on QVariantMap key access (which can return undefined and yield a NaN
    // baseScale). Returns 0.0 if the bounds are not yet populated.
    Q_PROPERTY(double boundsSize READ boundsSize NOTIFY viewChanged)
    Q_PROPERTY(QVariantMap treeAssets READ treeAssets NOTIFY viewChanged)
    Q_PROPERTY(QString assetBasePath READ assetBasePath NOTIFY viewChanged)
    Q_PROPERTY(QString backgroundUrl READ backgroundUrl NOTIFY viewChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchChanged)
    // boundsValid: true once tree bounds AND asset metadata are present.
    // NOTIFY boundsValidChanged fires exactly once on the false->true transition.
    Q_PROPERTY(bool boundsValid READ boundsValid NOTIFY boundsValidChanged)

public:
    explicit TreeViewController(QObject* parent = nullptr);

    void setModels(TreeModel* nodes, TreeGroupModel* groups, TreeConnectorModel* connectors);
    // Wire the Lua engine so the Q_INVOKABLE interaction wrappers can reach it.
    void setEngine(LuaEngine* engine) { m_engine = engine; }

    TreeModel* nodesModel() const { return m_nodes; }
    TreeGroupModel* groupsModel() const { return m_groups; }
    TreeConnectorModel* connectorsModel() const { return m_connectors; }
    LuaEngine* engine() const { return m_engine; }
    QString lastRevision() const { return m_lastRevision; }

    QVariantMap bounds() const { return m_bounds; }
    double boundsSize() const { return m_bounds.value("size").toDouble(); }
    // Per-axis max |coordinate| of the tree bounds; each TreeScene's pan clamp
    // needs it. 0 until the first refresh.
    double extentX() const;
    double extentY() const;
    QVariantMap treeAssets() const { return m_assets; }
    QString assetBasePath() const { return m_assetBasePath; }
    QString backgroundUrl() const { return m_backgroundUrl; }
    QVariantList searchResults() const { return m_searchResults; }
    bool boundsValid() const { return m_boundsValid; }

    Q_INVOKABLE void refresh(LuaEngine* engine);

    // Nearest node id whose LEGACY hit circle (`node.rsq`) contains the tree-space
    // point, or -1. Zoom/pan are per view (TreeScene owns a TreeViewport and
    // converts screen -> tree before calling this), so one controller serves
    // any number of views.
    int hitTestTree(double treeX, double treeY) const;
    // Tree-space position of any exported node (proxies included). False if
    // the id is not in the current tree.
    bool nodePosition(int id, double& x, double& y) const;

    // Phase 4b: allocation toggles. Each calls the Lua bridge, refreshes the
    // models (so every view reflects the new alloc state) and repaints.
    Q_INVOKABLE void allocNode(int id);
    Q_INVOKABLE void deallocNode(int id);
    Q_INVOKABLE void toggleNode(int id);

    // Phase 4b: set the tree search string; stores the matching id list and
    // emits searchChanged() so views can highlight matches.
    Q_INVOKABLE void setTreeSearch(const QString& str);

signals:
    void viewChanged();       // data/allocation changed -> views must rebuild
    void searchChanged();
    void boundsValidChanged();   // bounds + assets became valid (fires once)
    void assetsInitialized();     // asset metadata ready (fires once)

private:
    // Hit-test rows are kept separately from TreeModel so mouse movement does
    // not repeatedly materialise QVariantMaps for every node. The grid stores
    // each node in every cell its legacy rsq circle reaches; lookup is then one
    // cell plus exact circle tests, rather than a linear scan of the whole tree.
    struct HitNode {
        int id = -1;
        double x = 0.0;
        double y = 0.0;
        double radiusSquared = 0.0;
    };
    void rebuildHitIndex(const QVariantList& nodes);
    static qint64 hitCellKey(int x, int y);

    TreeModel* m_nodes = nullptr;
    TreeGroupModel* m_groups = nullptr;
    TreeConnectorModel* m_connectors = nullptr;
    LuaEngine* m_engine = nullptr;
    QVariantMap m_bounds;
    QVariantMap m_assets;
    QString m_assetBasePath;
    QString m_backgroundUrl;
    QVariantList m_searchResults;
    QVector<HitNode> m_hitNodes;
    QHash<qint64, QVector<int>> m_hitCells;
    QHash<int, QPair<double, double>> m_nodePos;
    QString m_lastRevision;
    bool m_loaded = false;
    bool m_boundsValid = false;        // guards boundsValidChanged single emission
    bool m_assetsInitialized = false;  // guards assetsInitialized single emission
};
