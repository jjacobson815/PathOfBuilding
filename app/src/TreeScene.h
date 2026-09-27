#pragma once
#include <QQuickItem>
#include <QSGNode>
#include <QSGTransformNode>
#include <QSGGeometryNode>
#include <QSGTextureMaterial>
#include <QSGTexture>
#include <QImage>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>
#include <QPointer>
#include "TreeViewController.h"
#include "TreeViewport.h"
#include "TintedTextureMaterial.h"

// Phase 4 Part 4.1: High-performance scene-graph passive tree renderer (TreeScene).
// Replaces the Canvas-2D JS repaint loop with native GPU scene-graph nodes.
// All tree geometry (~3k nodes, ~3k connectors, ~700 groups) lives in a QSGTransformNode,
// so panning and zooming updates only a 4x4 matrix without re-uploading geometry.
// Textures are cached per QQuickWindow and shared across all TreeScene instances.
//
// Multi-instance: tree DATA is shared through the controller (one per build),
// but each TreeScene owns its own TreeViewport (zoom/pan/size), mirroring legacy's
// one-PassiveTreeView-per-embed design. Embeds set focusNodeId (+ focusZoom, a raw
// zoom factor as legacy embeds assign `viewer.zoom`) to stay centred on a node.
//
// Phase 4 Part 4.3: node icons, frames and connectors are drawn with a
// per-vertex TINT (TintedTextureMaterial = legacy SetDrawColor). The tree
// payload is parsed ONCE per revision into plain structs; the batches are then
// rebuilt from those structs whenever something that only changes art STATE
// or TINT changes -- the hover preview (per view), the heat map and compare
// overlay (shared, controller) -- which is cheap (no QVariant access).
class TreeScene : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(TreeViewController* controller READ controller WRITE setController NOTIFY controllerChanged)
    Q_PROPERTY(double zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY transformChanged)
    Q_PROPERTY(double zoom READ zoom NOTIFY transformChanged)
    Q_PROPERTY(double zoomX READ zoomX WRITE setZoomX NOTIFY transformChanged)
    Q_PROPERTY(double zoomY READ zoomY WRITE setZoomY NOTIFY transformChanged)
    Q_PROPERTY(double baseScale READ baseScale NOTIFY transformChanged)
    Q_PROPERTY(int hoverNodeId READ hoverNodeId WRITE setHoverNodeId NOTIFY hoverNodeIdChanged)
    // pob_getHoverInfo result for the hovered node: { path:[ids], depends:[ids],
    // radius:{ x, y, rings:[{outer,inner,color}], nodes:[{id,color}] } }.
    Q_PROPERTY(QVariantMap hoverInfo READ hoverInfo WRITE setHoverInfo NOTIFY hoverInfoChanged)
    // -1 = free view. Otherwise the view stays centred on this node through
    // resizes and tree refreshes (legacy recomputes zoomX/zoomY every frame).
    Q_PROPERTY(int focusNodeId READ focusNodeId WRITE setFocusNodeId NOTIFY focusChanged)
    // Raw zoom factor while focused; <= 0 keeps the current zoom level.
    Q_PROPERTY(double focusZoom READ focusZoom WRITE setFocusZoom NOTIFY focusChanged)
    Q_PROPERTY(bool showSearch READ showSearch WRITE setShowSearch NOTIFY showSearchChanged)
    // Legacy main.edgeSearchHighlight: off-screen search matches get a smaller
    // circle clamped to the viewport edge.
    Q_PROPERTY(bool edgeSearchHighlight READ edgeSearchHighlight WRITE setEdgeSearchHighlight NOTIFY showSearchChanged)

public:
    struct QuadBatch {
        QString atlasPath;
        QVector<TintedVertex> vertices;  // 4 per quad
        // A single atlas batch can contain the whole tree. Keep indices 32-bit:
        // search rings alone can exceed the 65,535-vertex ceiling of uint16.
        QVector<quint32> indices;        // 6 per quad
    };

    explicit TreeScene(QQuickItem* parent = nullptr);
    ~TreeScene() override;

    TreeViewController* controller() const { return m_controller; }
    void setController(TreeViewController* ctrl);

    double zoomLevel() const { return m_view.zoomLevel(); }
    void setZoomLevel(double level);
    double zoom() const { return m_view.zoom(); }
    double zoomX() const { return m_view.zoomX(); }
    void setZoomX(double v);
    double zoomY() const { return m_view.zoomY(); }
    void setZoomY(double v);
    double baseScale() const;
    const TreeViewport& viewport() const { return m_view; }

    int hoverNodeId() const { return m_hoverNodeId; }
    void setHoverNodeId(int id);
    QVariantMap hoverInfo() const { return m_hoverInfo; }
    void setHoverInfo(const QVariantMap& info);

    int focusNodeId() const { return m_focusNodeId; }
    void setFocusNodeId(int id);
    double focusZoom() const { return m_focusZoom; }
    void setFocusZoom(double z);

    bool showSearch() const { return m_showSearch; }
    void setShowSearch(bool show);
    bool edgeSearchHighlight() const { return m_edgeSearch; }
    void setEdgeSearchHighlight(bool on);

    // Legacy PassiveTreeView:Zoom — keeps the tree point under (cursorX, cursorY)
    // fixed. Pass a negative cursor to zoom about the viewport centre.
    Q_INVOKABLE void zoomBy(double delta, double cursorX = -1, double cursorY = -1);
    Q_INVOKABLE void panBy(double dx, double dy);
    Q_INVOKABLE void resetView();
    // Screen (item-local px) -> node id under the cursor, or -1.
    Q_INVOKABLE int hitTest(double x, double y) const;
    // Node id -> item-local screen point, or an invalid QVariant if unknown.
    Q_INVOKABLE QVariant nodeScreenPos(int id) const;
    // One-shot centre on a node (legacy PassiveTreeView:Focus); zoomFactor <= 0
    // keeps the current zoom. Unlike focusNodeId this does not stick.
    Q_INVOKABLE bool centerOnNode(int id, double zoomFactor = 0);
    // Screen rects of the search circles last drawn (x, y, w, h), for tests.
    Q_INVOKABLE QVariantList searchCircleRects() const;

    // Texture cache helper (shared per QQuickWindow)
    static QSGTexture* getTexture(QQuickWindow* window, const QString& path, bool repeat = false);
    static QImage getImage(const QString& cleanPath);

signals:
    void controllerChanged();
    void transformChanged();
    void hoverNodeIdChanged();
    void hoverInfoChanged();
    void focusChanged();
    void showSearchChanged();
    void searchChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* updateData) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private:
    struct Sprite {
        QString atlas;
        float sx = 0, sy = 0, sw = 0, sh = 0;
        bool valid() const { return !atlas.isEmpty() && sw > 0 && sh > 0; }
    };
    struct NodeRec {
        int id = -1;
        float x = 0, y = 0;
        bool alloc = false;
        Sprite icon, frame, framePath, frameAlloc;
    };
    struct ConnRec {
        int n1 = -1, n2 = -1;
        QString atlas, atlasIntermediate, atlasActive;
        float vert[8] = {};
        float vertIntermediate[8] = {};
        float vertActive[8] = {};
        float uv[8] = {};
        bool hasIntermediate = false, hasActive = false;
    };

    void onControllerViewChanged();
    void onControllerSearchChanged();
    void onControllerOverlaysChanged();
    // Push the controller's tree extent + our size into m_view and re-apply a
    // sticky focus. Emits transformChanged when the view moved.
    void syncViewport();
    bool applyFocus();
    void viewMoved();

    void parseTreeData();
    void buildGroupBatches();
    void buildTintedBatches();
    void buildOverlayBatches();
    void buildScreenBatches();
    void addSpriteQuad(QVector<QuadBatch>& batches, QHash<QString, int>& index,
                       const Sprite& sp, float cx, float cy, quint32 rgba);

    QPointer<TreeViewController> m_controller;
    TreeViewport m_view;
    int m_hoverNodeId = -1;
    QVariantMap m_hoverInfo;
    QSet<int> m_hoverPath;
    QSet<int> m_hoverDeps;
    QHash<int, quint32> m_radiusColors;
    int m_focusNodeId = -1;
    double m_focusZoom = 0.0;
    bool m_showSearch = true;
    bool m_edgeSearch = true;

    bool m_dirtyGeometry = true;   // tree data changed: re-parse + rebuild all
    bool m_dirtyTint = true;       // hover / overlays changed: rebuild tinted batches
    bool m_dirtyOverlay = true;    // search / radius / zoom changed: rebuild overlay
    bool m_dirtyTransform = true;
    QString m_builtRevision;
    QString m_backgroundPath;

    QVector<NodeRec> m_nodeRecs;
    QHash<int, int> m_nodeIndex;
    QVector<ConnRec> m_connRecs;

    // Batched geometry structures ready for GPU upload
    QVector<QuadBatch> m_groupBatches;
    QVector<QuadBatch> m_connectorBatches;
    QVector<QuadBatch> m_nodeIconBatches;
    QVector<QuadBatch> m_nodeFrameBatches;
    QVector<QuadBatch> m_overlayBatches;
    QVector<QuadBatch> m_screenBatches;
    QVector<QRectF> m_searchCircles;
};
