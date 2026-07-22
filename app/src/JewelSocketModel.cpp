#include "JewelSocketModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

JewelSocketModel::JewelSocketModel(QObject* parent) : QAbstractListModel(parent) {}

int JewelSocketModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QHash<int, QByteArray> JewelSocketModel::roleNames() const {
    return {
        { NodeIdRole, "nodeId" },
        { SelItemIdRole, "selItemId" },
        { ItemNameRole, "itemName" },
    };
}

QVariant JewelSocketModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return QVariant();
    const QVariantMap& m = m_rows.at(index.row());
    switch (role) {
        case NodeIdRole: return m.value("nodeId");
        case SelItemIdRole: return m.value("selItemId");
        case ItemNameRole: return m.value("itemName");
        default: return QVariant();
    }
}

QVariant JewelSocketModel::get(int row) const {
    if (row < 0 || row >= m_rows.size())
        return QVariant();
    return m_rows.at(row);
}

void JewelSocketModel::setRows(const QVariantList& rows) {
    beginResetModel();
    m_rows.clear();
    m_rows.reserve(rows.size());
    for (const QVariant& v : rows)
        m_rows.append(v.toMap());
    endResetModel();
    emit countChanged();
}

void JewelSocketModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    QVariantList rows = engine->getJewelSockets();
    int sig = rows.size();
    for (const QVariant& v : rows) {
        const QVariantMap m = v.toMap();
        sig = sig * 31 + m.value("nodeId").toInt();
        sig = sig * 31 + m.value("selItemId").toInt();
    }
    if (m_loaded && sig == m_lastSig)
        return;
    m_lastSig = sig;
    m_loaded = true;
    setRows(rows);
    qDebug().noquote() << "[JewelSocketModel] refresh -> sockets=" << m_rows.size();
}
