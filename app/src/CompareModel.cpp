#include "CompareModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

CompareModel::CompareModel(QObject* parent) : QAbstractListModel(parent) {}

int CompareModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QHash<int, QByteArray> CompareModel::roleNames() const {
    return {
        { NameRole, "name" },
        { BuildNameRole, "buildName" },
        { LevelRole, "level" },
        // NOTE: the Lua map key is "class" (see pob_getCompareEntries), but
        // "class" is a reserved word in JS/QML, so the QML role is "className".
        { ClassRole, "className" },
    };
}

QVariant CompareModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const QVariantMap& m = m_entries.at(index.row());
    switch (role) {
        case NameRole: return m.value("name");
        case BuildNameRole: return m.value("buildName");
        case LevelRole: return m.value("level");
        case ClassRole: return m.value("class");
        default: return QVariant();
    }
}

QVariant CompareModel::get(int row) const {
    if (row < 0 || row >= m_entries.size())
        return QVariant();
    return m_entries.at(row);
}

void CompareModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // Throttle by the engine's build output revision so we only rebuild when the
    // build actually recalculates (compare entries change flags a rebuild).
    int rev = engine->getPath("main.modes.BUILD.outputRevision").toInt();
    if (m_loaded && rev == m_lastRev)
        return;
    m_lastRev = rev;
    m_loaded = true;
    QVariant out = engine->getCompareEntries();
    if (out.typeId() != QMetaType::QVariantList) {
        qDebug().noquote() << "[CompareModel] refresh -> no entries";
        return;
    }
    QVariantList entries = out.toList();
    beginResetModel();
    m_entries.clear();
    m_entries.reserve(entries.size());
    for (const QVariant& v : entries)
        m_entries.append(v.toMap());
    endResetModel();
    emit countChanged();
    qDebug().noquote() << "[CompareModel] refresh -> entries=" << m_entries.size();
}
