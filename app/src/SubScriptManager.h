#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <memory>

class LuaEngine;

// Phase 10: manages isolated worker-thread LuaJIT sub-scripts launched via
// LaunchSubScript(scriptText, funcList, subList, ...).
// Public API is locked across Wave 1 slices; worker implementations extend
// only the private section / Impl.
class SubScriptManager : public QObject {
    Q_OBJECT
public:
    explicit SubScriptManager(LuaEngine* engine);
    ~SubScriptManager() override;

    int launch(const QString& scriptText,
               const QString& funcListCsv,
               const QString& subListCsv,
               const QVariantList& args);
    void abort(int id);
    bool isRunning(int id);
    void shutdown();

    static bool registerUriScheme();
    static QString parseStartupUri(const QStringList& args);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
    LuaEngine* m_engine = nullptr;
};
