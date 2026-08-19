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

// Phase 4 Part 4.1: High-performance scene-graph passive tree renderer (TreeScene).
// Replaces the Canvas-2D JS repaint loop with native GPU scene-graph nodes.
// All tree geometry (~3k nodes, ~3k connectors, ~700 groups) lives in a QSGTransformNode,
// so panning and zooming updates only a 4x4 matrix without re-uploading geometry.
// Textures are cached per QQuickWindow and shared across all TreeScene instances.
class TreeScene : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(TreeViewController* controller READ controller WRITE setController NOTIFY controllerChanged)
    Q_PROPERTY(double zoom READ zoom NOTIFY transformChanged)
    Q_PROPERTY(double zoomX READ zoomX NOTIFY transformChanged)
    Q_PROPERTY(double zoomY READ zoomY NOTIFY transformChanged)
    Q_PROPERTY(double baseScale READ baseScale NOTIFY transformChanged)
    Q_PROPERTY(int hoverNodeId READ hoverNodeId WRITE setHoverNodeId NOTIFY hoverNodeIdChanged)
    Q_PROPERTY(int targetNodeId READ targetNodeId WRITE setTargetNodeId NOTIFY targetNodeIdChanged)
    Q_PROPERTY(bool showCrosshair READ showCrosshair WRITE setShowCrosshair NOTIFY showCrosshairChanged)
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

    double zoom() const;
    double zoomX() const;
    double zoomY() const;
    double baseScale() const;

    int hoverNodeId() const { return m_hoverNodeId; }
    void setHoverNodeId(int id);

    int targetNodeId() const { return m_targetNodeId; }
    void setTargetNodeId(int id);

    bool showCrosshair() const { return m_showCrosshair; }
    void setShowCrosshair(bool show);

    bool showSearch() const { return m_showSearch; }
    void setShowSearch(bool show);

    // Texture cache helper (shared per QQuickWindow)
    static QSGTexture* getTexture(QQuickWindow* window, const QString& path, bool repeat = false);
    static QImage getImage(const QString& cleanPath);

signals:
    void controllerChanged();
    void transformChanged();
    void hoverNodeIdChanged();
    void targetNodeIdChanged();
    void showCrosshairChanged();
    void showSearchChanged();
    void searchChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* updateData) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private:
    void onControllerViewChanged();
    void onControllerTransformChanged();
    void onControllerSearchChanged();

    void buildGeometryBatches();

    QPointer<TreeViewController> m_controller;
    int m_hoverNodeId = -1;
    int m_targetNodeId = -1;
    bool m_showCrosshair = false;
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
