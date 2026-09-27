#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class TreeModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit TreeModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_nodes.size(); }

    // Replace the node list (each entry is a QVariantMap with the role keys).
    void setNodes(const QVariantList& nodes);
    // QML/Canvas helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;
    const QList<QVariantMap>& nodes() const { return m_nodes; }

signals:
    void countChanged();

private:
    enum Roles : int {
        IdRole = Qt::UserRole + 1,
        XRole,
        YRole,
        TypeRole,
        AllocatedRole,
        GroupRole,
        AscendancyNameRole,
        NameRole,
        IsJewelSocketRole,
        IsMasteryRole,
        IconSpriteRole,
        SdRole
    };

    QList<QVariantMap> m_nodes;
};
