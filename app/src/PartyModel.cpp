#include "PartyModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

PartyModel::PartyModel(QObject* parent) : QAbstractListModel(parent) {}

int PartyModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_members.size();
}

QHash<int, QByteArray> PartyModel::roleNames() const {
    return {
        { NameRole, "name" },
        { LevelRole, "level" },
        // NOTE: the Lua map key is "class" (see pob_getPartyMembers), but
        // "class" is a reserved word in JS/QML, so the QML role is "className".
        { ClassRole, "className" },
        { CountRole, "count" },
    };
}

QVariant PartyModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_members.size())
        return QVariant();
    const QVariantMap& m = m_members.at(index.row());
    switch (role) {
        case NameRole: return m.value("name");
        case LevelRole: return m.value("level");
        case ClassRole: return m.value("class");
        case CountRole: return m.value("count");
        default: return QVariant();
    }
}

QVariant PartyModel::get(int row) const {
    if (row < 0 || row >= m_members.size())
        return QVariant();
    return m_members.at(row);
}

void PartyModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // Throttle by the engine's build output revision so we only rebuild when the
    // build actually recalculates (party buffs change flags a rebuild).
    int rev = engine->getPath("main.modes.BUILD.outputRevision").toInt();
    if (m_loaded && rev == m_lastRev)
        return;
    m_lastRev = rev;
    m_loaded = true;
    QVariant out = engine->getPartyMembers();
    if (out.typeId() != QMetaType::QVariantList) {
        qDebug().noquote() << "[PartyModel] refresh -> no members";
        return;
    }
    QVariantList members = out.toList();
    beginResetModel();
    m_members.clear();
    m_members.reserve(members.size());
    for (const QVariant& v : members)
        m_members.append(v.toMap());
    endResetModel();
    emit countChanged();
    qDebug().noquote() << "[PartyModel] refresh -> members=" << m_members.size();
}
