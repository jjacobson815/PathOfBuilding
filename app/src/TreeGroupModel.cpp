#include "TreeGroupModel.h"

TreeGroupModel::TreeGroupModel(QObject* parent) : QAbstractListModel(parent) {}

int TreeGroupModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_groups.size();
}

QHash<int, QByteArray> TreeGroupModel::roleNames() const {
    return {
        { IdRole, "id" },
        { XRole, "x" },
        { YRole, "y" },
        { OoRole, "oo" },
        { AscendancyNameRole, "ascendancyName" },
        { IsAscendancyStartRole, "isAscendancyStart" },
        { SpriteRole, "sprite" },
    };
}

QVariant TreeGroupModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_groups.size())
        return QVariant();
    const QVariantMap& m = m_groups.at(index.row());
    switch (role) {
        case IdRole: return m.value("id");
        case XRole: return m.value("x");
        case YRole: return m.value("y");
        case OoRole: return m.value("oo");
        case AscendancyNameRole: return m.value("ascendancyName");
        case IsAscendancyStartRole: return m.value("isAscendancyStart");
        case SpriteRole: return m.value("sprite");
        default: return QVariant();
    }
}

QVariant TreeGroupModel::get(int row) const {
    if (row < 0 || row >= m_groups.size())
        return QVariant();
    return m_groups.at(row);
}

void TreeGroupModel::setGroups(const QVariantList& groups) {
    beginResetModel();
    m_groups.clear();
    m_groups.reserve(groups.size());
    for (const QVariant& v : groups)
        m_groups.append(v.toMap());
    endResetModel();
    emit countChanged();
}
