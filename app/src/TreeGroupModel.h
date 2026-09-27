#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class TreeGroupModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit TreeGroupModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_groups.size(); }

    void setGroups(const QVariantList& groups);
    Q_INVOKABLE QVariant get(int row) const;
    const QList<QVariantMap>& groups() const { return m_groups; }

signals:
    void countChanged();

private:
    enum Roles : int {
        IdRole = Qt::UserRole + 1,
        XRole,
        YRole,
        OoRole,
        AscendancyNameRole,
        IsAscendancyStartRole,
        SpriteRole
    };

    QList<QVariantMap> m_groups;
};
