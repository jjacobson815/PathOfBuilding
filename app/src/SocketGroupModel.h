#pragma once
#include <QAbstractListModel>
#include <QString>
#include <QVariantList>

class LuaEngine;

// One socket group (a SkillsTab "socketGroupList" entry). Mirrors the fields
// the Skills tab renders: the user title (label), the item slot it is socketed
// in (or ""), whether the group is enabled, a short comma-joined summary of
// its gem names (the "skills" of the group), the full list of gem tables (for
// the nested gem ListView in the SKILLS view), and the index of the active
// skill within the group (mainActiveSkill).
struct SocketGroupData {
    QString title;
    QString slot;
    bool enabled = true;
    QString skillSummary;
    QVariantList gems;       // list of { name, level, quality, enabled }
    int mainActiveSkill = 1;
};

// Phase 2a: QAbstractListModel mirror of buildMode.skillsTab.socketGroupList.
//
// Preferred over a raw QVariantList because QML ListView can bind directly and
// benefit from incremental change signals. refresh(LuaEngine*) re-reads the
// list from Lua and, when the set of groups changes size, does a full
// resetModel() + countChanged(); when only contents change it emits
// dataChanged() for the affected rows. All reads are defensive (an absent
// skillsTab yields an empty list).
class SocketGroupModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit SocketGroupModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_groups.size(); }

    // Re-read the socket-group list from the engine. Safe to call every frame.
    void refresh(LuaEngine* engine);

signals:
    void countChanged();

private:
    enum Roles : int {
        TitleRole = Qt::UserRole + 1,
        SlotRole,
        EnabledRole,
        SkillSummaryRole,
        GemsRole,            // Phase 5b: list of gem tables for the nested view
        MainActiveSkillRole  // Phase 5b: active skill index within the group
    };

    QList<SocketGroupData> m_groups;
};
