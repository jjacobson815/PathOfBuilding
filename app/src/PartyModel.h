#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5e: PartyTab (PARTY view) model. The engine's PartyTab stores imported
// party buffs in self.actor (Aura/Curse/Warcry/Link) rather than a live network
// roster, so we expose the buff categories that ARE present as rows
// (name/level/class/count). refresh() pulls the data from the Lua bridge
// (pob_getPartyMembers) and rebuilds only when the engine's build output
// revision changes (throttled by build.outputRevision) so the per-frame call
// from the frame loop is cheap. Linked ONLY into pob-qt (never pob-selftest)
// like CalcModel/ItemModel/SkillModel.
class PartyModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit PartyModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_members.size(); }

    // Pull the party buff categories from the engine via
    // LuaEngine::getPartyMembers(); throttled by the engine's build.outputRevision
    // so we only rebuild when the build actually recalculates.
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        NameRole = Qt::UserRole + 1,
        LevelRole,
        ClassRole,
        CountRole,
    };

    QList<QVariantMap> m_members;
    int m_lastRev = -1;
    bool m_loaded = false;
};
