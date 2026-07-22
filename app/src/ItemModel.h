#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5a: item browser model for the ITEMS view. One row per item in
// main.modes.BUILD.itemsTab, in display order (itemOrderList). Each row
// carries the item's identity, base/type, rarity, quality, level, the list
// of built mod-line strings, whether it is currently equipped (and in which
// slot), and its socket count. refresh() pulls the data from the Lua bridge
// (pob_getItems) and rebuilds only when the item set actually changes
// (throttled by an id+equip+name+rarity+modcount signature) so the
// per-frame call from the frame loop is cheap and the ListView selection is
// not reset on every tick.
class ItemModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit ItemModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_items.size(); }

    // Replace the item list (each entry is a QVariantMap with the role keys).
    void setItems(const QVariantList& items);
    // Pull items from the engine via LuaEngine::getItems(); throttled.
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        IdRole = Qt::UserRole + 1,
        NameRole,
        BaseNameRole,
        TypeRole,
        RarityRole,
        QualityRole,
        LevelRole,
        ModLinesRole,
        IsEquippedRole,
        SlotNameRole,
        SocketCountRole
    };

    QList<QVariantMap> m_items;
    int m_lastSig = -1;
    bool m_loaded = false;
};
