#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5c: calculation-output browser model for the CALCS view. One row per
// CalcSection (offence/defence/...), each carrying a `label` and a `stats`
// QVariantList of stat maps { label, value, statType, flag, hasBreakdown,
// breakdown }. A `summary` Q_PROPERTY exposes the headline numbers (life/mana/
// es/totalDps/dps/critChance/attackSpeed). refresh() pulls the data from the Lua
// bridge (pob_getCalcOutput) and rebuilds only when the engine's calc output
// revision changes (throttled by build.outputRevision) so the per-frame call
// from the frame loop is cheap and the ListView selection is not reset on every
// tick. Linked ONLY into pob-qt (never pob-selftest) like ItemModel/SkillModel.
class CalcModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QVariantMap summary READ summary NOTIFY summaryChanged)

public:
    explicit CalcModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_sections.size(); }

    QVariantMap summary() const { return m_summary; }

    // Replace the section list (each entry is a QVariantMap with the role keys).
    void setSections(const QVariantList& sections);
    // Pull the calc output from the engine via LuaEngine::getCalcOutput();
    // throttled by the engine's build.outputRevision so we only rebuild when the
    // build actually recalculates (the formatted output is somewhat expensive).
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();
    void summaryChanged();

private:
    enum Roles : int {
        LabelRole = Qt::UserRole + 1,
        StatsRole,
    };

    QList<QVariantMap> m_sections;
    QVariantMap m_summary;
    int m_lastRev = -1;
    bool m_loaded = false;
};
