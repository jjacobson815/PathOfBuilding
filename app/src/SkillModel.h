#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5b: active-skill DPS browser model for the SKILLS view. One row per
// display skill across all socket groups, in engine order. Each row carries
// the skill name, its computed DPS / total DPS / minion DPS (read from the
// calc output after selecting it as the main skill), the owning socket group's
// label, whether it is the current main skill, and the (socketGroupIndex,
// displaySkillIndex) pair used to select it via LuaEngine::setActiveSkill.
// refresh() pulls the data from the Lua bridge (pob_getActiveSkills) and
// rebuilds only when the underlying skill set actually changes (throttled by a
// signature over the socket groups + main-skill selection) so the per-frame
// call from the frame loop is cheap and the ListView selection is not reset on
// every tick.
class SkillModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit SkillModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_skills.size(); }

    // Replace the skill list (each entry is a QVariantMap with the role keys).
    void setSkills(const QVariantList& skills);
    // Pull skills from the engine via LuaEngine::getActiveSkills(); throttled.
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        NameRole = Qt::UserRole + 1,
        DpsRole,
        TotalDpsRole,
        MinionDpsRole,
        SocketGroupLabelRole,
        IsMainRole,
        SocketGroupIndexRole,
        DisplaySkillIndexRole
    };

    QList<QVariantMap> m_skills;
    int m_lastSig = -1;
    bool m_loaded = false;
};
