#include "BuildListModel.h"
#include "LuaEngine.h"
#include <QDebug>

BuildListModel::BuildListModel(QObject* parent) : QAbstractListModel(parent) {}

int BuildListModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QHash<int, QByteArray> BuildListModel::roleNames() const {
    return {
        { DisplayNameRole, "displayName" },
        { IsFolderRole, "isFolder" },
        { FileNameRole, "fileName" },
        { FullFileNameRole, "fullFileName" },
        { BuildNameRole, "buildName" },
        { FolderNameRole, "folderName" },
        { ClassNameRole, "className" },
        { AscendClassNameRole, "ascendClassName" },
        { LevelRole, "level" },
        { SubPathRole, "subPath" },
    };
}

QVariant BuildListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const BuildListEntry& e = m_entries.at(index.row());
    switch (role) {
        case DisplayNameRole: return e.displayName;
        case IsFolderRole: return e.isFolder;
        case FileNameRole: return e.fileName;
        case FullFileNameRole: return e.fullFileName;
        case BuildNameRole: return e.buildName;
        case FolderNameRole: return e.folderName;
        case ClassNameRole: return e.className;
        case AscendClassNameRole: return e.ascendClassName;
        case LevelRole: return e.level;
        case SubPathRole: return e.subPath;
        default: return QVariant();
    }
}

void BuildListModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;

    // Only the LIST mode populates main.modes.LIST.list. In BUILD mode the list
    // is stale/empty, so we clear the model and skip the (expensive) re-read.
    const QString mode = engine->getPath("main.mode").toString();
    if (mode != "LIST") {
        if (!m_entries.isEmpty()) {
            beginResetModel();
            m_entries.clear();
            endResetModel();
            emit countChanged();
            qDebug().noquote() << "[BuildListModel] cleared (mode=" << mode << ")";
        }
        return;
    }

    // Defensive: an uninitialised LIST mode yields an empty list.
    const QVariantList raw =
        engine->getPath("main.modes.LIST.list").toList();

    QList<BuildListEntry> entries;
    entries.reserve(raw.size());
    for (const QVariant& v : raw) {
        const QVariantMap m = v.toMap();
        BuildListEntry e;
        e.folderName = m.value("folderName").toString();
        e.isFolder = !e.folderName.isEmpty();
        e.fileName = m.value("fileName").toString();
        e.fullFileName = m.value("fullFileName").toString();
        e.subPath = m.value("subPath").toString();
        e.buildName = m.value("buildName").toString();
        e.displayName = e.isFolder ? e.folderName : e.buildName;
        e.className = m.value("className").toString();
        e.ascendClassName = m.value("ascendClassName").toString();
        e.level = m.value("level").toInt();
        entries.append(e);
    }

    if (entries.size() != m_entries.size()) {
        beginResetModel();
        m_entries = entries;
        endResetModel();
        emit countChanged();
        qDebug().noquote() << "[BuildListModel] refresh -> count=" << m_entries.size();
        return;
    }

    // Same size: detect in-place content changes and emit dataChanged if any.
    bool changed = false;
    for (int i = 0; i < entries.size(); ++i) {
        const BuildListEntry& a = entries.at(i);
        const BuildListEntry& b = m_entries.at(i);
        if (a.displayName != b.displayName || a.isFolder != b.isFolder ||
            a.fileName != b.fileName || a.fullFileName != b.fullFileName ||
            a.buildName != b.buildName || a.folderName != b.folderName ||
            a.className != b.className || a.ascendClassName != b.ascendClassName ||
            a.level != b.level || a.subPath != b.subPath) {
            changed = true;
            break;
        }
    }
    if (changed) {
        m_entries = entries;
        emit dataChanged(index(0, 0), index(m_entries.size() - 1, 0), {});
        qDebug().noquote() << "[BuildListModel] refresh -> content changed, count="
                           << m_entries.size();
    }
}
