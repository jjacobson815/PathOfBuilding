#pragma once
#include <QQuickItem>
#include <QSGNode>
#include <QSGTransformNode>
#include <QSGGeometryNode>
#include <QSGTextureMaterial>
#include <QSGOpaqueTextureMaterial>
#include <QSGFlatColorMaterial>
#include <QSGTexture>
#include <QImage>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QPointer>
#include "TreeViewController.h"
#include "TreeViewport.h"

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
class TreeScene : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(TreeViewController* controller READ controller WRITE setController NOTIFY controllerChanged)
    Q_PROPERTY(double zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY transformChanged)
    Q_PROPERTY(double zoom READ zoom NOTIFY transformChanged)
    Q_PROPERTY(double zoomX READ zoomX WRITE setZoomX NOTIFY transformChanged)
    Q_PROPERTY(double zoomY READ zoomY WRITE setZoomY NOTIFY transformChanged)
    Q_PROPERTY(double baseScale READ baseScale NOTIFY transformChanged)
    Q_PROPERTY(int hoverNodeId READ hoverNodeId WRITE setHoverNodeId NOTIFY hoverNodeIdChanged)
    // -1 = free view. Otherwise the view stays centred on this node through
    // resizes and tree refreshes (legacy recomputes zoomX/zoomY every frame).
    Q_PROPERTY(int focusNodeId READ focusNodeId WRITE setFocusNodeId NOTIFY focusChanged)
    // Raw zoom factor while focused; <= 0 keeps the current zoom level.
    Q_PROPERTY(double focusZoom READ focusZoom WRITE setFocusZoom NOTIFY focusChanged)
    Q_PROPERTY(bool showSearch READ showSearch WRITE setShowSearch NOTIFY showSearchChanged)

public:
    struct QuadBatch {
        QString atlasPath;
        QVector<float> vertices; // 4 * (x, y, tx, ty) per quad
        // A single atlas batch can contain the whole tree. Keep indices 32-bit:
        // search rings alone can exceed the 65,535-vertex ceiling of uint16.
        QVector<quint32> indices; // 6 indices per quad
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

    int focusNodeId() const { return m_focusNodeId; }
    void setFocusNodeId(int id);
    double focusZoom() const { return m_focusZoom; }
    void setFocusZoom(double z);

    bool showSearch() const { return m_showSearch; }
    void setShowSearch(bool show);

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

    // Texture cache helper (shared per QQuickWindow)
    static QSGTexture* getTexture(QQuickWindow* window, const QString& path, bool repeat = false);
    static QImage getImage(const QString& cleanPath);

signals:
    void controllerChanged();
    void transformChanged();
    void hoverNodeIdChanged();
    void focusChanged();
    void showSearchChanged();
    void searchChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* updateData) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private:
    void onControllerViewChanged();
    void onControllerSearchChanged();
    // Push the controller's tree extent + our size into m_view and re-apply a
    // sticky focus. Emits transformChanged when the view moved.
    void syncViewport();
    bool applyFocus();
    void viewMoved();

    void buildGeometryBatches();

    QPointer<TreeViewController> m_controller;
    TreeViewport m_view;
    int m_hoverNodeId = -1;
    int m_focusNodeId = -1;
    double m_focusZoom = 0.0;
    bool m_showSearch = true;

    bool m_dirtyGeometry = true;
    bool m_dirtyOverlay = true;
    bool m_dirtyTransform = true;
    QString m_builtRevision;
    QString m_backgroundPath;

    // Batched geometry structures ready for GPU upload
    QVector<QuadBatch> m_groupBatches;
    QVector<QuadBatch> m_connectorBatches;
    QVector<QuadBatch> m_nodeIconBatches;
    QVector<QuadBatch> m_nodeFrameBatches;
    QVector<QuadBatch> m_overlayBatches;
};
