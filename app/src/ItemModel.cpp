#include "ItemModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

ItemModel::ItemModel(QObject* parent) : QAbstractListModel(parent) {}

int ItemModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_items.size();
}

QHash<int, QByteArray> ItemModel::roleNames() const {
    return {
        { IdRole, "id" },
        { NameRole, "name" },
        { BaseNameRole, "baseName" },
        { TypeRole, "type" },
        { RarityRole, "rarity" },
        { QualityRole, "quality" },
        { LevelRole, "level" },
        { ModLinesRole, "modLines" },
        { IsEquippedRole, "isEquipped" },
        { SlotNameRole, "slotName" },
        { SocketCountRole, "socketCount" },
    };
}

QVariant ItemModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return QVariant();
    const QVariantMap& m = m_items.at(index.row());
    switch (role) {
        case IdRole: return m.value("id");
        case NameRole: return m.value("name");
        case BaseNameRole: return m.value("baseName");
        case TypeRole: return m.value("type");
        case RarityRole: return m.value("rarity");
        case QualityRole: return m.value("quality");
        case LevelRole: return m.value("level");
        case ModLinesRole: return m.value("modLines");
        case IsEquippedRole: return m.value("isEquipped");
        case SlotNameRole: return m.value("slotName");
        case SocketCountRole: return m.value("socketCount");
        default: return QVariant();
    }
}

QVariant ItemModel::get(int row) const {
    if (row < 0 || row >= m_items.size())
        return QVariant();
    return m_items.at(row);
}

void ItemModel::setItems(const QVariantList& items) {
    beginResetModel();
    m_items.clear();
    m_items.reserve(items.size());
    for (const QVariant& v : items)
        m_items.append(v.toMap());
    endResetModel();
    emit countChanged();
}

void ItemModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    QVariantList items = engine->getItems();
    // Throttle: only rebuild when the item set actually changes. Signature
    // combines count, each id, equip flag, name/rarity hash and mod count so
    // add/delete/equip and (most) mod edits are detected without a full
    // rebuild every frame.
    int sig = items.size();
    int equipped = 0;
    for (const QVariant& v : items) {
        const QVariantMap m = v.toMap();
        sig = sig * 31 + m.value("id").toInt();
        if (m.value("isEquipped").toBool())
            equipped++;
        sig = sig * 31 + int(qHash(m.value("name").toString()));
        sig = sig * 31 + int(qHash(m.value("rarity").toString()));
        sig = sig * 31 + m.value("modLines").toList().size();
    }
    sig = sig * 31 + equipped;
    if (m_loaded && sig == m_lastSig)
        return;
    m_lastSig = sig;
    m_loaded = true;
    setItems(items);
    qDebug().noquote() << "[ItemModel] refresh -> items=" << m_items.size();
}
