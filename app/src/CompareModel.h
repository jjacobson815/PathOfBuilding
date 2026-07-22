#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5e: CompareTab (COMPARE view) model. One row per comparison build entry
// (compareTab.compareEntries), each carrying name/buildName/level/class. refresh()
// pulls the data from the Lua bridge (pob_getCompareEntries) and rebuilds only
// when the engine's build output revision changes (throttled by
// build.outputRevision) so the per-frame call from the frame loop is cheap.
// Linked ONLY into pob-qt (never pob-selftest) like CalcModel/ItemModel/SkillModel.
class CompareModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit CompareModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_entries.size(); }

    // Pull the comparison entries from the engine via LuaEngine::getCompareEntries();
    // throttled by the engine's build.outputRevision so we only rebuild when the
    // build actually recalculates.
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        NameRole = Qt::UserRole + 1,
        BuildNameRole,
        LevelRole,
        ClassRole,
    };

    QList<QVariantMap> m_entries;
    int m_lastRev = -1;
    bool m_loaded = false;
};
