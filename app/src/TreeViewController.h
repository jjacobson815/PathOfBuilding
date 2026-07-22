
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QString>

class LuaEngine;
class TreeModel;
class TreeGroupModel;
class TreeConnectorModel;

// Phase 4a/4b: owns the passive-tree view state (zoom/pan) and the three tree
// data models, and repopulates them from the Lua bridge (pob_getTreeData) on
// demand. refresh() is throttled: it only rebuilds the models when the allocation
// signature changes (or on first load), so calling it every frame is cheap.
// Phase 4b adds hit-testing (screen->node id), allocation toggles that flow
// through the Lua bridge and repaint the canvas, and a search-match id list.
class TreeViewController : public QObject {
    Q_OBJECT
    // zoom/pan transform properties notify transformChanged (NOT viewChanged) so the
    // QML Scale/Translate bindings update without forcing a full canvas repaint.
    Q_PROPERTY(double zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY transformChanged)
    Q_PROPERTY(double zoom READ zoom NOTIFY transformChanged)
    Q_PROPERTY(double zoomX READ zoomX WRITE setZoomX NOTIFY transformChanged)
    Q_PROPERTY(double zoomY READ zoomY WRITE setZoomY NOTIFY transformChanged)
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

    double zoomLevel() const { return m_zoomLevel; }
    double zoom() const;
    double zoomX() const { return m_zoomX; }
    double zoomY() const { return m_zoomY; }
    QVariantMap bounds() const { return m_bounds; }
    double boundsSize() const { return m_bounds.value("size").toDouble(); }
    QVariantMap treeAssets() const { return m_assets; }
    QString assetBasePath() const { return m_assetBasePath; }
    QString backgroundUrl() const { return m_backgroundUrl; }
    QVariantList searchResults() const { return m_searchResults; }
    bool boundsValid() const { return m_boundsValid; }

    void setZoomLevel(double v);
    void setZoomX(double v);
    void setZoomY(double v);

    Q_INVOKABLE void zoomBy(double delta);
    Q_INVOKABLE void panBy(double dx, double dy);
    Q_INVOKABLE void resetView();
    Q_INVOKABLE void refresh(LuaEngine* engine);

    // The tree view reports its pixel size here (on load + resize). It is needed
    // to clamp panning so the tree can't be dragged off into empty canvas, and
    // must be kept current for the clamp bounds to track the viewport.
    Q_INVOKABLE void setViewport(qreal w, qreal h);


    // Phase 4b: invert the treeToScreen transform to find the nearest node id
    // under a screen point (screenX/screenY in the viewport's local pixels;
    // vpW/vpH are the viewport size). Returns the node id, or -1 if none within
    // the pixel hit threshold.
    Q_INVOKABLE int hitTest(qreal screenX, qreal screenY, qreal vpW, qreal vpH);

    // Phase 4b: allocation toggles. Each calls the Lua bridge, refreshes the
    // models (so the canvas reflects the new alloc state) and repaints.
    Q_INVOKABLE void allocNode(int id);
    Q_INVOKABLE void deallocNode(int id);
    Q_INVOKABLE void toggleNode(int id);

    // Phase 4b: set the tree search string; stores the matching id list and
    // emits searchChanged() so the canvas can highlight matches.
    Q_INVOKABLE void setTreeSearch(const QString& str);

private:
    // Clamp m_zoomX/m_zoomY so the tree can't be panned into empty canvas,
    // mirroring legacy (PassiveTreeView.lua): the allowed pan offset is
    // +/- viewport * zoom * 2/3 on each axis, which grows with zoom (a larger
    // tree needs more travel to reach its edges) and keeps the outer nodes
    // reachable without exposing void beyond the radial border. No-op until the
    // viewport size is known. Returns true if either value changed.
    bool clampPan();

public:

signals:
    void viewChanged();       // data/allocation changed -> canvas must repaint
    void transformChanged();  // zoom/pan changed -> only the Scale/Translate updates
    void searchChanged();
    void boundsValidChanged();   // bounds + assets became valid (fires once)
    void assetsInitialized();     // asset metadata ready (fires once)

private:
    TreeModel* m_nodes = nullptr;
    TreeGroupModel* m_groups = nullptr;
    TreeConnectorModel* m_connectors = nullptr;
    LuaEngine* m_engine = nullptr;
    // Default view opens zoomed in near the tree centre (class start), matching
    // legacy PoB, rather than fit-whole-tree. zoom = 1.2^level, so 8 ≈ 4.3x.
    double m_zoomLevel = 8.0;
    double m_zoomX = 0.0;
    double m_zoomY = 0.0;
    // Tree-view pixel size (from setViewport); 0 until first reported. Used only
    // for the pan clamp (see clampPan).
    double m_vpW = 0.0;
    double m_vpH = 0.0;
    QVariantMap m_bounds;
    QVariantMap m_assets;
    QString m_assetBasePath;
    QString m_backgroundUrl;
    QVariantList m_searchResults;
    int m_lastSig = -1;
    bool m_loaded = false;
    bool m_boundsValid = false;        // guards boundsValidChanged single emission
    bool m_assetsInitialized = false;  // guards assetsInitialized single emission
};
