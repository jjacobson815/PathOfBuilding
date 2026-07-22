#include "ItemSlotModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

ItemSlotModel::ItemSlotModel(QObject* parent) : QAbstractListModel(parent) {}

int ItemSlotModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QHash<int, QByteArray> ItemSlotModel::roleNames() const {
    return {
        { SlotNameRole, "slotName" },
        { SelItemIdRole, "selItemId" },
        { ItemNameRole, "itemName" },
    };
}

QVariant ItemSlotModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return QVariant();
    const QVariantMap& m = m_rows.at(index.row());
    switch (role) {
        case SlotNameRole: return m.value("slotName");
        case SelItemIdRole: return m.value("selItemId");
        case ItemNameRole: return m.value("itemName");
        default: return QVariant();
    }
}

QVariant ItemSlotModel::get(int row) const {
    if (row < 0 || row >= m_rows.size())
        return QVariant();
    return m_rows.at(row);
}

void ItemSlotModel::setRows(const QVariantList& rows) {
    beginResetModel();
    m_rows.clear();
    m_rows.reserve(rows.size());
    for (const QVariant& v : rows)
        m_rows.append(v.toMap());
    endResetModel();
    emit countChanged();
}

void ItemSlotModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    QVariantList rows = engine->getItemSlots();
    int sig = rows.size();
    for (const QVariant& v : rows) {
        const QVariantMap m = v.toMap();
        sig = sig * 31 + m.value("selItemId").toInt();
        sig = sig * 31 + int(qHash(m.value("slotName").toString()));
    }
    if (m_loaded && sig == m_lastSig)
        return;
    m_lastSig = sig;
    m_loaded = true;
    setRows(rows);
    qDebug().noquote() << "[ItemSlotModel] refresh -> slots=" << m_rows.size();
}
