#include "SocketGroupModel.h"
#include "LuaEngine.h"
#include <QDebug>

SocketGroupModel::SocketGroupModel(QObject* parent) : QAbstractListModel(parent) {}

int SocketGroupModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_groups.size();
}

QHash<int, QByteArray> SocketGroupModel::roleNames() const {
    return {
        { TitleRole, "title" },
        { SlotRole, "slot" },
        { EnabledRole, "enabled" },
        { SkillSummaryRole, "skillSummary" },
        { GemsRole, "gems" },
        { MainActiveSkillRole, "mainActiveSkill" },
    };
}

QVariant SocketGroupModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_groups.size())
        return QVariant();
    const SocketGroupData& g = m_groups.at(index.row());
    switch (role) {
        case TitleRole: return g.title;
        case SlotRole: return g.slot;
        case EnabledRole: return g.enabled;
        case SkillSummaryRole: return g.skillSummary;
        case GemsRole: return g.gems;
        case MainActiveSkillRole: return g.mainActiveSkill;
        default: return QVariant();
    }
}

void SocketGroupModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;

    // Defensive: an absent skillsTab (LIST mode) yields an empty list.
    const QVariantList raw =
        engine->getPath("main.modes.BUILD.skillsTab.socketGroupList").toList();

    QList<SocketGroupData> groups;
    groups.reserve(raw.size());
    for (const QVariant& v : raw) {
        const QVariantMap m = v.toMap();
        SocketGroupData g;
        g.title = m.value("label").toString();
        g.slot = m.value("slot").toString();          // nil slot -> "" (QVariant->toString)
        g.enabled = m.value("enabled", true).toBool(); // default enabled when absent
        g.mainActiveSkill = m.value("mainActiveSkill", 1).toInt();
        const QVariantList gems = m.value("gemList").toList();
        QVariantList gemRows;
        gemRows.reserve(gems.size());
        QStringList names;
        names.reserve(gems.size());
        for (const QVariant& gv : gems) {
            const QVariantMap gm = gv.toMap();
            const QString n = gm.value("nameSpec").toString();
            QVariantMap row;
            row.insert("name", n);
            row.insert("level", gm.value("level", 1).toInt());
            row.insert("quality", gm.value("quality", 0).toInt());
            row.insert("enabled", gm.value("enabled", true).toBool());
            gemRows.append(row);
            if (!n.isEmpty())
                names.append(n);
        }
        g.gems = gemRows;
        g.skillSummary = names.join(", ");
        groups.append(g);
    }

    if (groups.size() != m_groups.size()) {
        beginResetModel();
        m_groups = groups;
        endResetModel();
        emit countChanged();
        qDebug().noquote() << "[SocketGroupModel] refresh -> count=" << m_groups.size();
        return;
    }

    // Same size: detect in-place content changes and emit dataChanged if any.
    bool changed = false;
    for (int i = 0; i < groups.size(); ++i) {
        if (groups.at(i).title != m_groups.at(i).title ||
            groups.at(i).slot != m_groups.at(i).slot ||
            groups.at(i).enabled != m_groups.at(i).enabled ||
            groups.at(i).skillSummary != m_groups.at(i).skillSummary ||
            groups.at(i).mainActiveSkill != m_groups.at(i).mainActiveSkill ||
            groups.at(i).gems != m_groups.at(i).gems) {
            changed = true;
            break;
        }
    }
    if (changed) {
        m_groups = groups;
        emit dataChanged(index(0, 0), index(m_groups.size() - 1, 0), {});
        qDebug().noquote() << "[SocketGroupModel] refresh -> content changed, count="
                           << m_groups.size();
    }
}
