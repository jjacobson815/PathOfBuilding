#pragma once
#include <QObject>
#include <QString>

class LuaEngine;

// Phase 2b: typed, signal-driven wrapper around the build save/load bridge.
//
// Exposes the save/load operations to QML as Q_INVOKABLE slots that delegate to
// the LuaEngine bridge (which in turn calls the top-level Lua globals
// pob_saveBuild / pob_loadBuildXML / pob_getBuildXML defined in
// app/lua/pob_host.lua). Those globals wrap the engine's Build:SaveDB /
// Build:LoadDB seam, so the exact same xml.lua serialiser the real app uses is
// exercised and .xml / Settings.xml compatibility is preserved.
//
// Properties:
//   buildXML  — the most recently serialised build XML (set by getBuildXML()).
//   lastError — the last error string (empty when the last op succeeded).
//   isDirty   — mirrors the engine's unsaved flag (main.modes.BUILD.unsaved),
//               refreshed from the engine via refresh(LuaEngine*).
//
// After a successful loadBuildXML(), the buildLoaded() signal fires so the host
// (main.cpp) can immediately refresh the other typed models (BuildModel /
// SocketGroupModel) instead of waiting for the next frame tick.
class SaveLoadModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString buildXML READ buildXML NOTIFY buildXMLChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool isDirty READ isDirty NOTIFY dirtyChanged)

public:
    explicit SaveLoadModel(LuaEngine* engine, QObject* parent = nullptr);

    // Serialise the current build to `path` (a file). Returns success.
    Q_INVOKABLE bool saveBuild(const QString& path);
    // Re-initialise the build from an XML string. Returns success and emits
    // buildLoaded() on success so dependent models can refresh immediately.
    Q_INVOKABLE bool loadBuildXML(const QString& xml);
    // Read `path` (a build .xml file) and re-initialise the build from it.
    Q_INVOKABLE bool loadBuildFile(const QString& path);
    // Serialise the current build to an XML string and cache it in buildXML.
    Q_INVOKABLE QString getBuildXML();
    // A cross-platform default temp save path for the GUI "Save" button.
    Q_INVOKABLE QString defaultSavePath() const;

    QString buildXML() const { return m_buildXML; }
    QString lastError() const { return m_lastError; }
    bool isDirty() const { return m_isDirty; }

    // Pull the engine's unsaved flag into isDirty. Safe to call every frame.
    void refresh(LuaEngine* engine);

signals:
    void buildXMLChanged();
    void lastErrorChanged();
    void dirtyChanged();
    // Emitted after a successful loadBuildXML() so the host can refresh models.
    void buildLoaded();

private:
    LuaEngine* m_engine = nullptr;
    QString m_buildXML;
    QString m_lastError;
    bool m_isDirty = false;
};
