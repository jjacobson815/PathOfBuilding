#include "BuildModel.h"
#include "LuaEngine.h"
#include <QDebug>

BuildModel::BuildModel(QObject* parent) : QObject(parent) {}

void BuildModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;

    // All paths are defensive: getPath() returns an empty QVariant if any
    // segment is missing (e.g. engine in LIST mode, spec nil), so the cached
    // value simply stays at its default instead of throwing.
    const QString buildName = engine->getPath("main.modes.BUILD.buildName").toString();
    const int characterLevel = engine->getPath("main.modes.BUILD.characterLevel").toInt();
    const QString className = engine->getPath("main.modes.BUILD.spec.curClassName").toString();
    const QString ascendClassName = engine->getPath("main.modes.BUILD.spec.curAscendClassName").toString();
    const QString targetVersion = engine->getPath("main.modes.BUILD.targetVersion").toString();
    const int socketGroupCount =
        engine->getPath("main.modes.BUILD.skillsTab.socketGroupList").toList().size();

    bool changed = false;
    if (buildName != m_buildName) { m_buildName = buildName; changed = true; }
    if (characterLevel != m_characterLevel) { m_characterLevel = characterLevel; changed = true; }
    if (className != m_className) { m_className = className; changed = true; }
    if (ascendClassName != m_ascendClassName) { m_ascendClassName = ascendClassName; changed = true; }
    if (targetVersion != m_targetVersion) { m_targetVersion = targetVersion; changed = true; }
    if (socketGroupCount != m_socketGroupCount) { m_socketGroupCount = socketGroupCount; changed = true; }

    if (changed) {
        // Phase 2a verification hook: log the populated values so the offscreen
        // run can confirm the model actually read the engine state.
        qDebug().noquote() << "[BuildModel] refresh -> buildName=" << m_buildName
                           << " level=" << m_characterLevel
                           << " class=" << m_className
                           << " ascend=" << m_ascendClassName
                           << " targetVersion=" << m_targetVersion
                           << " socketGroups=" << m_socketGroupCount;
        emit dataChanged();
    }
}
