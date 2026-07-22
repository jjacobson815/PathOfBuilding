#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5a: equipped item-slot model for the ITEMS view. One row per
// equipped slot in main.modes.BUILD.itemsTab.orderedSlots (slots whose
// selItemId ~= 0). Each row carries slotName / selItemId / itemName.
// refresh() pulls from the Lua bridge (pob_getItemSlots) and rebuilds
// only when the equipped set changes (throttled by a signature).
class ItemSlotModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit ItemSlotModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_rows.size(); }

    void setRows(const QVariantList& rows);
    void refresh(LuaEngine* engine);
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        SlotNameRole = Qt::UserRole + 1,
        SelItemIdRole,
        ItemNameRole
    };

    QList<QVariantMap> m_rows;
    int m_lastSig = -1;
    bool m_loaded = false;
};
