#include "SaveLoadModel.h"
#include "LuaEngine.h"
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QTextStream>

SaveLoadModel::SaveLoadModel(LuaEngine* engine, QObject* parent)
    : QObject(parent), m_engine(engine) {}

bool SaveLoadModel::saveBuild(const QString& path) {
    if (!m_engine) {
        m_lastError = "engine unavailable";
        emit lastErrorChanged();
        return false;
    }
    const bool ok = m_engine->saveBuild(path);
    m_lastError = ok ? QString() : ("failed to save build to " + path);
    emit lastErrorChanged();
    return ok;
}

bool SaveLoadModel::loadBuildFile(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = "cannot open " + path;
        emit lastErrorChanged();
        return false;
    }
    QTextStream in(&f);
    const QString xml = in.readAll();
    f.close();
    if (xml.isEmpty()) {
        m_lastError = "empty file " + path;
        emit lastErrorChanged();
        return false;
    }
    return loadBuildXML(xml);
}

QString SaveLoadModel::defaultSavePath() const {
    return QDir::tempPath() + "/pob_save_test.xml";
}

bool SaveLoadModel::loadBuildXML(const QString& xml) {
    if (!m_engine) {
        m_lastError = "engine unavailable";
        emit lastErrorChanged();
        return false;
    }
    const bool ok = m_engine->loadBuildXML(xml);
    if (ok) {
        m_lastError.clear();
        emit lastErrorChanged();
        emit buildLoaded();
        return true;
    }
    m_lastError = "failed to load build from XML";
    emit lastErrorChanged();
    return false;
}

QString SaveLoadModel::getBuildXML() {
    if (!m_engine) {
        m_lastError = "engine unavailable";
        emit lastErrorChanged();
        return QString();
    }
    const QString xml = m_engine->getBuildXML();
    m_buildXML = xml;
    emit buildXMLChanged();
    m_lastError = xml.isEmpty() ? QString("getBuildXML returned empty") : QString();
    emit lastErrorChanged();
    return xml;
}

void SaveLoadModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // main.modes.BUILD.unsaved is the engine's "has unsaved changes" flag.
    const bool dirty = engine->getPath("main.modes.BUILD.unsaved").toBool();
    if (dirty != m_isDirty) {
        m_isDirty = dirty;
        emit dirtyChanged();
    }
}
