#include "TreeConnectorModel.h"

TreeConnectorModel::TreeConnectorModel(QObject* parent) : QAbstractListModel(parent) {}

int TreeConnectorModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_connectors.size();
}

QHash<int, QByteArray> TreeConnectorModel::roleNames() const {
    return {
        { NodeId1Role, "nodeId1" },
        { NodeId2Role, "nodeId2" },
        { TypeRole, "type" },
        { AscendancyNameRole, "ascendancyName" },
        { StateRole, "state" },
        { X1Role, "x1" },
        { Y1Role, "y1" },
        { X2Role, "x2" },
        { Y2Role, "y2" },
    };
}

QVariant TreeConnectorModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_connectors.size())
        return QVariant();
    const QVariantMap& m = m_connectors.at(index.row());
    switch (role) {
        case NodeId1Role: return m.value("nodeId1");
        case NodeId2Role: return m.value("nodeId2");
        case TypeRole: return m.value("type");
        case AscendancyNameRole: return m.value("ascendancyName");
        case StateRole: return m.value("state");
        case X1Role: return m.value("x1");
        case Y1Role: return m.value("y1");
        case X2Role: return m.value("x2");
        case Y2Role: return m.value("y2");
        default: return QVariant();
    }
}

QVariant TreeConnectorModel::get(int row) const {
    if (row < 0 || row >= m_connectors.size())
        return QVariant();
    return m_connectors.at(row);
}

void TreeConnectorModel::setConnectors(const QVariantList& connectors) {
    beginResetModel();
    m_connectors.clear();
    m_connectors.reserve(connectors.size());
    for (const QVariant& v : connectors)
        m_connectors.append(v.toMap());
    endResetModel();
    emit countChanged();
}
