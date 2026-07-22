#include "TreeModel.h"

TreeModel::TreeModel(QObject* parent) : QAbstractListModel(parent) {}

int TreeModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_nodes.size();
}

QHash<int, QByteArray> TreeModel::roleNames() const {
    return {
        { IdRole, "id" },
        { XRole, "x" },
        { YRole, "y" },
        { TypeRole, "type" },
        { AllocatedRole, "allocated" },
        { GroupRole, "group" },
        { AscendancyNameRole, "ascendancyName" },
        { NameRole, "name" },
        { IsJewelSocketRole, "isJewelSocket" },
        { IsMasteryRole, "isMastery" },
        { IconSpriteRole, "iconSprite" },
        { SdRole, "sd" },
    };
}

QVariant TreeModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_nodes.size())
        return QVariant();
    const QVariantMap& m = m_nodes.at(index.row());
    switch (role) {
        case IdRole: return m.value("id");
        case XRole: return m.value("x");
        case YRole: return m.value("y");
        case TypeRole: return m.value("type");
        case AllocatedRole: return m.value("allocated");
        case GroupRole: return m.value("group");
        case AscendancyNameRole: return m.value("ascendancyName");
        case NameRole: return m.value("name");
        case IsJewelSocketRole: return m.value("isJewelSocket");
        case IsMasteryRole: return m.value("isMastery");
        case IconSpriteRole: return m.value("iconSprite");
        case SdRole: return m.value("sd");
        default: return QVariant();
    }
}

QVariant TreeModel::get(int row) const {
    if (row < 0 || row >= m_nodes.size())
        return QVariant();
    return m_nodes.at(row);
}

void TreeModel::setNodes(const QVariantList& nodes) {
    beginResetModel();
    m_nodes.clear();
    m_nodes.reserve(nodes.size());
    for (const QVariant& v : nodes)
        m_nodes.append(v.toMap());
    endResetModel();
    emit countChanged();
}
