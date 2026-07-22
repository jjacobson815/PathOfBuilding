#include "SkillModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

SkillModel::SkillModel(QObject* parent) : QAbstractListModel(parent) {}

int SkillModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_skills.size();
}

QHash<int, QByteArray> SkillModel::roleNames() const {
    return {
        { NameRole, "name" },
        { DpsRole, "dps" },
        { TotalDpsRole, "totalDps" },
        { MinionDpsRole, "minionDps" },
        { SocketGroupLabelRole, "socketGroupLabel" },
        { IsMainRole, "isMain" },
        { SocketGroupIndexRole, "socketGroupIndex" },
        { DisplaySkillIndexRole, "displaySkillIndex" },
    };
}

QVariant SkillModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_skills.size())
        return QVariant();
    const QVariantMap& m = m_skills.at(index.row());
    switch (role) {
        case NameRole: return m.value("name");
        case DpsRole: return m.value("dps");
        case TotalDpsRole: return m.value("totalDps");
        case MinionDpsRole: return m.value("minionDps");
        case SocketGroupLabelRole: return m.value("socketGroupLabel");
        case IsMainRole: return m.value("isMain");
        case SocketGroupIndexRole: return m.value("socketGroupIndex");
        case DisplaySkillIndexRole: return m.value("displaySkillIndex");
        default: return QVariant();
    }
}

QVariant SkillModel::get(int row) const {
    if (row < 0 || row >= m_skills.size())
        return QVariant();
    return m_skills.at(row);
}

void SkillModel::setSkills(const QVariantList& skills) {
    beginResetModel();
    m_skills.clear();
    m_skills.reserve(skills.size());
    for (const QVariant& v : skills)
        m_skills.append(v.toMap());
    endResetModel();
    emit countChanged();
}

void SkillModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // Cheap signature from the socket groups (no recalc) plus the main-skill
    // selection. This avoids running the (expensive) per-skill recalc in
    // pob_getActiveSkills on every frame; we only recompute when the skill set
    // or the active skill actually changes.
    QVariantList groups = engine->getSocketGroups();
    int sig = groups.size();
    for (const QVariant& v : groups) {
        const QVariantMap m = v.toMap();
        sig = sig * 31 + qHash(m.value("label").toString());
        sig = sig * 31 + (m.value("enabled").toBool() ? 1 : 0);
        sig = sig * 31 + m.value("mainActiveSkill").toInt();
        const QVariantList gems = m.value("gems").toList();
        sig = sig * 31 + gems.size();
        for (const QVariant& gv : gems) {
            const QVariantMap gm = gv.toMap();
            sig = sig * 31 + qHash(gm.value("name").toString());
            sig = sig * 31 + gm.value("level").toInt();
            sig = sig * 31 + gm.value("quality").toInt();
            sig = sig * 31 + (gm.value("enabled").toBool() ? 1 : 0);
        }
    }
    QVariant ms = engine->getPath("main.modes.BUILD.mainSocketGroup");
    sig = sig * 31 + ms.toInt();
    if (m_loaded && sig == m_lastSig)
        return;
    m_lastSig = sig;
    m_loaded = true;
    QVariantList skills = engine->getActiveSkills();
    setSkills(skills);
    qDebug().noquote() << "[SkillModel] refresh -> skills=" << m_skills.size();
}
