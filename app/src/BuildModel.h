#pragma once
#include <QObject>
#include <QString>

class LuaEngine;

// Phase 2a: typed, signal-driven mirror of the engine's build-mode metadata.
//
// Exposes the scalar build-state fields that the top bar / future tabs need
// (build name, character level, class / ascendancy names, target version, and
// the socket-group count). Each property is backed by a cached value and a
// single `dataChanged` NOTIFY signal. refresh(LuaEngine*) re-reads the relevant
// fields from Lua via LuaEngine::getPath(...) and only emits when a value
// actually differs, so QML bindings update exactly once per real change.
//
// All Lua reads are defensive: if a field is absent (e.g. the engine is in LIST
// mode and buildMode.spec is nil) getPath() returns an empty QVariant and the
// property simply keeps its default. No Lua error is surfaced to the caller.
class BuildModel : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString buildName READ buildName NOTIFY dataChanged)
    Q_PROPERTY(int characterLevel READ characterLevel NOTIFY dataChanged)
    Q_PROPERTY(QString className READ className NOTIFY dataChanged)
    Q_PROPERTY(QString ascendClassName READ ascendClassName NOTIFY dataChanged)
    Q_PROPERTY(QString targetVersion READ targetVersion NOTIFY dataChanged)
    Q_PROPERTY(int socketGroupCount READ socketGroupCount NOTIFY dataChanged)

public:
    explicit BuildModel(QObject* parent = nullptr);

    // Pull the current build metadata from the engine. Safe to call repeatedly
    // (e.g. every frame); emits dataChanged() only when something changed.
    void refresh(LuaEngine* engine);

    QString buildName() const { return m_buildName; }
    int characterLevel() const { return m_characterLevel; }
    QString className() const { return m_className; }
    QString ascendClassName() const { return m_ascendClassName; }
    QString targetVersion() const { return m_targetVersion; }
    int socketGroupCount() const { return m_socketGroupCount; }

signals:
    void dataChanged();

private:
    QString m_buildName;
    int m_characterLevel = 0;
    QString m_className;
    QString m_ascendClassName;
    QString m_targetVersion;
    int m_socketGroupCount = 0;
};
