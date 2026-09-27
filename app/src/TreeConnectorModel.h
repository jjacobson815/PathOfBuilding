#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class TreeConnectorModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit TreeConnectorModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_connectors.size(); }

    void setConnectors(const QVariantList& connectors);
    Q_INVOKABLE QVariant get(int row) const;
    const QList<QVariantMap>& connectors() const { return m_connectors; }

signals:
    void countChanged();

private:
    enum Roles : int {
        NodeId1Role = Qt::UserRole + 1,
        NodeId2Role,
        TypeRole,
        AscendancyNameRole,
        StateRole,
        X1Role,
        Y1Role,
        X2Role,
        Y2Role,
        VertRole,
        UvRole,
        AtlasRole,
        IsArcRole,
    };

    QList<QVariantMap> m_connectors;
};
