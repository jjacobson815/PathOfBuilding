#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QDebug>
#include "LuaEngine.h"
#include "selftest_checks.h"

#ifndef POB_LUA_DIR
#define POB_LUA_DIR "."
#endif

// Headless verification of the LuaJIT bridge: load the calc engine, confirm the
// BUILD mode initialised, read the data-driven sidebar registry, and confirm a
// calculation produced output. Run inside the dev sandbox:
//   pob-selftest <srcDir> <runtimeDir>
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);

    QString srcDir, runtimeDir, hostFile;
    if (argc > 1) srcDir = argv[1];
    if (argc > 2) runtimeDir = argv[2];
    if (argc > 3) hostFile = argv[3];

    // Resolve src/runtime/lua relative to the executable so a deployed (e.g.
    // cross-compiled) binary finds its own files next to it. The build-host
    // POB_LUA_DIR is only a fallback for running from the build tree. This
    // mirrors main.cpp so pob-selftest behaves identically to pob-qt.
    auto resolveDir = [&](const QString& cliVal, const QString& subdir) -> QString {
        if (!cliVal.isEmpty()) return cliVal;
        QString exeDir = QCoreApplication::applicationDirPath();
        if (QDir(exeDir + "/" + subdir).exists()) return exeDir + "/" + subdir;
        QDir d(POB_LUA_DIR);
        d.cdUp(); d.cdUp(); // app/lua -> repo root
        return d.absolutePath() + "/" + subdir;
    };
    auto resolveHost = [&](const QString& cliVal) -> QString {
        if (!cliVal.isEmpty()) return cliVal;
        QString exeDir = QCoreApplication::applicationDirPath();
        QString candidate = exeDir + "/lua/pob_host.lua";
        if (QFile::exists(candidate)) return candidate;
        return QString(POB_LUA_DIR) + "/pob_host.lua";
    };

    srcDir = resolveDir(srcDir, "src");
    runtimeDir = resolveDir(runtimeDir, "runtime");
    hostFile = resolveHost(hostFile);
    QDir::setCurrent(srcDir); // engine opens TreeData/ + manifest.xml relative to cwd
    qDebug() << "srcDir    =" << srcDir;
    qDebug() << "runtimeDir=" << runtimeDir;
    qDebug() << "hostFile  =" << hostFile;

    LuaEngine engine;
    QObject::connect(&engine, &LuaEngine::logMessage,
                     [](const QString& m) { qDebug().noquote() << "[lua]" << m; });
    if (!engine.init(srcDir, runtimeDir, hostFile)) {
        qCritical() << "INIT FAILED";
        return 1;
    }
    qDebug() << "engine init OK";

    return pob_run_all_selftests(engine) ? 0 : 1;
}
