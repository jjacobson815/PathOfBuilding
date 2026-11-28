#include <QGuiApplication>
#include <QCoreApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QUrl>
#include <QDebug>
#include <QTimer>
#include <QQuickStyle>
#include <QFile>
#include <QTextStream>
#include <QQuickWindow>
#include <QImage>
#include <QEventLoop>
#include <QThread>
#include <QDateTime>
#include <QFontDatabase>
#include "AppBootstrap.h"
#include "LuaEngine.h"
#include "SubScriptManager.h"
#include "selftest_checks.h"
#include <QFileInfo>

// Phase 2: warn if the running binary is stale vs the latest build artifact.
// The recurring "theme/tree changes not applied" bug was caused by launching
// dist/pob-qt.exe without re-running cmake --install after ninja. This catches it.
static void checkBinaryFreshness() {
    QString exe = QCoreApplication::applicationFilePath();
    QFileInfo running(exe);
    QDir repoRoot(running.absoluteDir());
    if (!repoRoot.cdUp()) return; // dist -> repo root
    QFileInfo built(repoRoot.absoluteFilePath("build-win/pob-qt.exe"));
    if (!built.exists()) return; // no build tree present; skip
    if (running.lastModified() < built.lastModified() || running.size() != built.size()) {
        qWarning().noquote() << "[deploy] STALE BINARY: running" << exe
            << "is older/different than" << built.absoluteFilePath()
            << "- run: ninja && cmake --install build-win --prefix" << repoRoot.absolutePath();
    } else {
        qDebug().noquote() << "[deploy] binary fresh:" << exe;
    }
}

// Phase 8: offscreen screenshot capture of every view. Loads main.qml with
// QT_QPA_PLATFORM=offscreen, iterates the engine's BUILD view registry (plus
// LIST mode), switches each view via LuaEngine::setActiveView, and grabs the
// window with QQuickWindow::grabWindow(), writing <outDir>/<id>.png. This lets
// tools/verify_style.py run headlessly (no display required).
//
// The capture is driven FROM the Qt event loop (via a QTimer), NOT called
// synchronously before app.exec(). QQuickWindow::grabWindow() forces a render
// that depends on the render thread, which is only serviced while the event
// loop runs — calling it from a blocked main thread deadlocks. So runCapture
// just arms a timer and returns 0; main() then calls app.exec() and the timer
// sequences the view switches + grabs, quitting at the end.
//
// NOTE: pob-qt is a GUI-subsystem binary, so qDebug/qCritical go to the
// debugger (OutputDebugString), not stdout. We therefore log progress to a
// file (_status.log in outDir) so the harness is diagnosable headlessly.
static void capLog(const QString& path, const QString& msg) {
    QFile f(path);
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream ts(&f);
        ts << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << " " << msg << "\n";
    }
}

// File-based milestone log for main() (GUI-subsystem binary: qDebug is invisible).
// Writes to the OS temp dir; the old path hardcoded a wrong absolute repo root
// (a different checkout), so the log silently went nowhere.
static void mainLog(const QString& msg) {
    QFile f(QDir::tempPath() + "/pob-qt-main.log");
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream ts(&f);
        ts << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << " " << msg << "\n";
    }
}

static int runCapture(LuaEngine& engine, QQmlApplicationEngine& qml, const QString& outDir) {
    QDir().mkpath(outDir);
    QString statusPath = outDir + "/_status.log";
    capLog(statusPath, "start");

    QObject* root = qml.rootObjects().value(0, nullptr);
    if (!root) { capLog(statusPath, "ERROR no root object"); return 1; }
    auto* win = qobject_cast<QQuickWindow*>(root);
    if (!win) { capLog(statusPath, "ERROR root is not a QQuickWindow"); return 1; }
    win->setWidth(1100);
    win->setHeight(720);
    win->show();
    capLog(statusPath, "window shown");

    // BUILD-mode views from the engine registry (main.modes.BUILD.viewList),
    // followed by LIST mode (captured last, separate from the registry).
    QStringList ids;
    for (const QVariant& v : engine.viewList().toList()) {
        QString id = v.toMap().value("id").toString();
        if (!id.isEmpty()) ids << id;
    }
    capLog(statusPath, QString("viewList count=%1").arg(ids.size()));
    if (ids.isEmpty()) { capLog(statusPath, "ERROR viewList empty; nothing to capture"); return 1; }
    ids << "LIST";

    // Heap state shared across timer ticks (leaked on purpose: one-shot tool).
    struct Ctx { int idx = 0; int failed = 0; QStringList ids; LuaEngine* engine; QQuickWindow* win; QString outDir; QString statusPath; };
    auto* ctx = new Ctx{0, 0, ids, &engine, win, outDir, statusPath};

    auto* timer = new QTimer(win);
    timer->setInterval(500);
    QObject::connect(timer, &QTimer::timeout, [ctx, timer]() {
        if (ctx->idx >= ctx->ids.size()) {
            timer->stop();
            // Wait for the LAST item's grab singleShot (scheduled at +300ms below)
            // to run before exiting. QCoreApplication::exit() cancels pending
            // singleShots, so exiting immediately dropped the final view's PNG
            // (e.g. LIST) whenever the closing tick raced ahead of its grab.
            QTimer::singleShot(400, [ctx]() {
                capLog(ctx->statusPath, QString("done (failed=%1) -> %2").arg(ctx->failed).arg(QDir(ctx->outDir).absolutePath()));
                QCoreApplication::exit(ctx->failed > 0 ? 1 : 0);
            });
            return;
        }
        QString id = ctx->ids[ctx->idx++];
        if (id == "LIST") { ctx->engine->setListMode(); ctx->engine->runCallback("OnFrame"); }
        else ctx->engine->setActiveView(id);
        capLog(ctx->statusPath, "switch -> " + id);
        // Grab on the next tick so the QML binding (activeView) re-evaluates and
        // the view becomes visible + renders before we snapshot it.
        QTimer::singleShot(300, [ctx, id]() {
            QImage img = ctx->win->grabWindow();
            if (img.isNull()) {
                ctx->failed++;
                capLog(ctx->statusPath, "grab NULL for " + id);
                return;
            }
            QString path = ctx->outDir + "/" + id.toLower() + ".png";
            img.save(path);
            capLog(ctx->statusPath, QString("grab %1 -> %2 %3x%4").arg(id, path).arg(img.width()).arg(img.height()));
        });
    });
    // Initial delay lets the scene graph + tree atlas initialise before the
    // first grab.
    QTimer::singleShot(600, [timer]() { timer->start(); });
    return 0;
}

int main(int argc, char** argv) {
    // Force a non-native Qt Quick Controls 2 style via the environment variable
    // BEFORE QGuiApplication is constructed. Qt resolves the Quick Controls 2
    // style from QT_QUICK_CONTROLS_STYLE at QGuiApplication init time; setting it
    // only via QQuickStyle::setStyle() (below) is too late because the style is
    // already locked to the platform default (native Windows) by then — which is
    // why the UI previously rendered as unstyled raw system widgets.
    qputenv("QT_QUICK_CONTROLS_STYLE", "Fusion");

    // Force a non-native Qt Quick Controls 2 style. The build-mode UI
    // customises `background` on TextField/TextArea/ScrollView (see main.qml)
    // to render the dark theme sourced from the UITheme module. The native
    // Windows style rejects that customisation, emitting a QML warning and
    // leaking a detached zero-size rectangle on every control (re)creation —
    // which, inside the CONFIG view's Repeater refresh loop, floods the console
    // and spirals into a UI lockup on real Windows (Wine silently no-ops it).
    // Fusion honours the customisation so the themed UI works as designed.
    // Override with the QT_QUICK_CONTROLS_STYLE env var if a different style
    // is ever desired (e.g. "Material", "Basic").
    QQuickStyle::setStyle(qEnvironmentVariable("QT_QUICK_CONTROLS_STYLE", "Fusion"));

    // Parse CLI flags up front so --headless can select the right Q*Application
    // and so path resolution can honour --src/--runtime/--host overrides.
    QString srcDir, runtimeDir, hostFile;
    bool headless = false;
    bool capture = false;
    bool devMode = false;
    QString captureDir;
    // Positional (non-harness) CLI args passed through to the engine as `arg`
    // (arg[0]=program, arg[1..]=params). The engine reads arg[1] as an
    // open-on-launch build file / import URL (fully realized in Phase 11). Our
    // own harness flags (--headless/--capture/--dev/--src/--runtime/--host) are
    // consumed here and NOT forwarded, so they can't be mistaken for a build/URL.
    QStringList launchArgs;
    launchArgs << QString::fromLocal8Bit(argv[0]);
    for (int i = 1; i < argc; i++) {
        QString a = argv[i];
        if (a == "--headless") headless = true;
        else if (a == "--dev") devMode = true;
        else if (a == "--capture") {
            capture = true;
            // Optional output directory: --capture [outdir]
            if (i + 1 < argc && !QString(argv[i + 1]).startsWith("--"))
                captureDir = argv[++i];
        }
        else if (a == "--src" && i + 1 < argc) srcDir = argv[++i];
        else if (a == "--runtime" && i + 1 < argc) runtimeDir = argv[++i];
        else if (a == "--host" && i + 1 < argc) hostFile = argv[++i];
        else launchArgs << a;
    }

    // Phase 8: offscreen capture harness. By default we use the system's native
    // platform (windows) so a real, grabable window exists on a desktop. The
    // offscreen platform is opt-in (POB_CAPTURE_OFFSCREEN=1) for true headless
    // CI; this build's offscreen plugin crashes (STATUS_STACK_BUFFER_OVERRUN),
    // so we must not force it on a normal desktop.
    if (capture && qEnvironmentVariableIsSet("POB_CAPTURE_OFFSCREEN")
            && qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");

    // Resolve a directory for the deployed app. Prefer an explicit CLI override;
    // otherwise look next to the executable (so an installed copy finds its own
    // src/runtime/lua); fall back to the compile-time POB_LUA_DIR (build tree).
    auto resolveDir = [](const QString& cliVal, const QString& subdir) -> QString {
        return AppBootstrap::resolveDir(cliVal, subdir);
    };
    auto resolveHost = [](const QString& cliVal) -> QString {
        return AppBootstrap::resolveHost(cliVal);
    };

    // Phase 6b: headless mode. No window / display required — run the full
    // self-test suite (identical to pob-selftest) and exit. This makes the GUI
    // binary itself a CI smoke test and proves the engine is fully headless
    // (no SimpleGraphic / display dependency).
    if (headless) {
        QCoreApplication app(argc, argv);
        app.setApplicationName("Path of Building (Qt) [headless]");
        srcDir = resolveDir(srcDir, "src");
        runtimeDir = resolveDir(runtimeDir, "runtime");
        hostFile = resolveHost(hostFile);
        QDir::setCurrent(srcDir); // engine opens TreeData/ + manifest.xml relative to cwd
        qDebug() << "headless srcDir =" << srcDir << "runtimeDir =" << runtimeDir;
        LuaEngine engine;
        QObject::connect(&engine, &LuaEngine::logMessage,
                         [](const QString& m) { qDebug().noquote() << "[lua]" << m; });
        if (!engine.init(srcDir, runtimeDir, hostFile, launchArgs, devMode)) {
            qCritical() << "Failed to initialise Lua engine";
            return 1;
        }

        // Phase 7: event-driven architecture self-test. Proves the frame loop is
        // gone and that model refreshes are driven ONLY by explicit LuaEngine
        // signals emitted on genuine mutation (never by a polling timer). Signal
        // spies confirm: idle emits nothing; one mutation emits exactly the
        // expected signal(s).
        if (!qEnvironmentVariableIsEmpty("POB_TEST_FRAMELOOP")) {
            long cBuildData = 0, cTree = 0, cConfig = 0, cItems = 0, cSkills = 0,
                 cCalcs = 0, cNotes = 0, cCompare = 0, cParty = 0, cBuildList = 0,
                 cMode = 0, cView = 0;
            QObject::connect(&engine, &LuaEngine::buildDataChanged, [&]() { cBuildData++; });
            QObject::connect(&engine, &LuaEngine::treeChanged, [&]() { cTree++; });
            QObject::connect(&engine, &LuaEngine::configChanged, [&]() { cConfig++; });
            QObject::connect(&engine, &LuaEngine::itemsChanged, [&]() { cItems++; });
            QObject::connect(&engine, &LuaEngine::skillsChanged, [&]() { cSkills++; });
            QObject::connect(&engine, &LuaEngine::calcsChanged, [&]() { cCalcs++; });
            QObject::connect(&engine, &LuaEngine::notesChanged, [&]() { cNotes++; });
            QObject::connect(&engine, &LuaEngine::compareChanged, [&]() { cCompare++; });
            QObject::connect(&engine, &LuaEngine::partyChanged, [&]() { cParty++; });
            QObject::connect(&engine, &LuaEngine::buildListChanged, [&]() { cBuildList++; });
            QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { cMode++; });
            QObject::connect(&engine, &LuaEngine::viewChanged, [&]() { cView++; });

            // 1) Idle: no mutation -> no signals. Pump the event loop briefly.
            QCoreApplication::processEvents();
            bool idleOk = (cBuildData == 0 && cTree == 0 && cConfig == 0 && cItems == 0
                           && cSkills == 0 && cCalcs == 0 && cNotes == 0 && cCompare == 0
                           && cParty == 0 && cBuildList == 0 && cMode == 0 && cView == 0);

            // 2) Genuine mutation: setConfigOption must emit configChanged +
            // calcsChanged and NOTHING else.
            engine.setConfigOption("dummy", QVariant(true));
            bool mutOk = (cConfig == 1 && cCalcs == 1 && cBuildData == 0 && cTree == 0
                         && cItems == 0 && cSkills == 0 && cNotes == 0 && cCompare == 0
                         && cParty == 0 && cBuildList == 0 && cMode == 0 && cView == 0);

            qDebug().noquote() << "[FRAMELOOP TEST] idleOk =" << idleOk
                     << " mutOk =" << mutOk;
            // Result is carried by the process exit code (0 pass / 1 fail); the
            // former /workdir/frameloop_result.txt sidecar file was Docker-path-
            // hardcoded and read by nothing.
            return (idleOk && mutOk) ? 0 : 1;
        }

        return engine.runSelfTest() ? 0 : 1;
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("Path of Building (Qt)");
    mainLog("QGuiApplication created");

    srcDir = resolveDir(srcDir, "src");
    runtimeDir = resolveDir(runtimeDir, "runtime");
    hostFile = resolveHost(hostFile);
    mainLog("cwd=" + srcDir + " runtime=" + runtimeDir + " host=" + hostFile);

    checkBinaryFreshness();
    if (!capture) {
        SubScriptManager::registerUriScheme();
    }

    AppBootstrap bootstrap;
    AppBootstrap::Options bootOpts;
    bootOpts.srcDir = srcDir;
    bootOpts.runtimeDir = runtimeDir;
    bootOpts.hostFile = hostFile;
    bootOpts.launchArgs = launchArgs;
    bootOpts.devMode = devMode;
    bootOpts.connectLogToDebug = true;
    if (!bootstrap.init(bootOpts)) {
        mainLog("engine.init FAILED");
        qCritical() << "Failed to initialise Lua engine";
        return 1;
    }
    LuaEngine& engine = *bootstrap.engine();
    mainLog("engine.init OK");

    // Data-loss fix: run the engine shutdown on quit so main:Shutdown ->
    // SaveSettings persists Settings.xml (and the last-open build) — the Qt host
    // previously never called it, so settings never saved. runCallback dispatches
    // to launch:OnExit; the engine's errorReadingSettings latch is respected
    // (SaveSettings early-returns when it is set, so a cloud-read failure does not
    // clobber the file with defaults).
    QObject::connect(&app, &QGuiApplication::aboutToQuit, &engine, [&engine]() {
        engine.runCallback("OnExit");
    });

    QQmlApplicationEngine qml;
    bootstrap.attachToQmlEngine(&qml, capture);

    // GUI-subsystem binary: QML compile warnings/errors go to the debugger
    // (OutputDebugString), never a visible console. Mirror them into mainLog
    // so a load failure is diagnosable without an attached debugger.
    QObject::connect(&qml, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const QQmlError& w : warnings) mainLog("QML warning: " + w.toString());
    });
    qml.load(QUrl("qrc:/qml/main.qml"));
    if (qml.rootObjects().isEmpty()) {
        mainLog("qml FAILED to load");
        qCritical() << "Failed to load QML";
        return 1;
    }
    mainLog("qml loaded");

    // Wire SetForeground() (engine -> foregroundRequested) to raise/activate the
    // main window. Only reached after a successful OAuth today (Phase 11), but
    // the connection is harmless and keeps the bridge non-nil.
    if (auto* win = qobject_cast<QQuickWindow*>(qml.rootObjects().value(0))) {
        QObject::connect(&engine, &LuaEngine::foregroundRequested, win, [win]() {
            win->raise();
            win->requestActivate();
        });
    }

    // Phase 1a: drive the engine's OnFrame from the Qt event loop. This replaces
    // the old single-shot OnFrame pump in pob_host.lua's boot with a continuous
    // frame loop, exactly like the original SimpleGraphic engine. The boot still
    // runs OnInit + first OnFrame + forced BUILD before this timer starts, which
    // keeps the headless selftest green.
    //
    // Phase 2a: the typed models are refreshed every frame so they stay in sync
    // with the engine without QML polling raw QVariants. We only pump OnFrame
    // while the BUILD mode actually has a live build (self.spec present); calling
    // OnFrame after the build is closed crashes the Lua OnFrame at Build.lua:1207
    // (attempt to index field 'spec' (a nil value)). Guarding here keeps the
    // offscreen run clean without touching any Lua source.
    // Phase 6: event-driven model synchronisation. The old 30 ms frame loop that
    // called refresh() on all 13 typed models every tick is GONE — it choked the
    // Qt event loop by crossing the C++/Lua boundary ~33 times a second and, on
    // an idle screen, recreated the configView Repeater's ~570 delegates and
    // rebuilt the calc output continuously, freezing the GUI.
    //
    // Instead, LuaEngine now emits a specific Qt signal the instant a genuine
    // mutation occurs (a user action or a rebuild routed through a bridge method
    // such as setConfigOption / allocNode / createBuild). Each model subscribes
    // to the relevant signal and refreshes exactly once per real state change.
    // An idle UI therefore performs ZERO model refreshes and sits at 0% CPU.
    // The Lua backend's OnFrame/rebuild is already driven synchronously inside
    // each bridge method (the pob_* helpers set buildFlag and pump OnFrame), so
    // no polling timer is required. The signal->refresh wiring lives just below.

    // Phase 8: offscreen capture harness. Iterate every BUILD view (plus LIST
    // mode) and grab the window to <captureDir>/<id>.png so the style-regression
    // gate (tools/verify_style.py) can run with no display. runCapture arms a
    // QTimer and returns; we must run the event loop so grabWindow()'s render
    // thread is serviced, then it quits with the appropriate exit code.
    if (capture) {
        int rc = runCapture(engine, qml, captureDir.isEmpty() ? "captures" : captureDir);
        if (rc != 0) return rc;
        return app.exec();
    }

    // Phase 10 Part 10.3: if launched with a pob:// URI argument, trigger the
    // async URI import once the event loop is active so signals reach QML.
    const QString startupUri = SubScriptManager::parseStartupUri(launchArgs);
    if (!startupUri.isEmpty()) {
        QTimer::singleShot(0, &engine, [&engine, startupUri]() {
            engine.invoke(QStringLiteral("pob_handleStartupUri"), { startupUri });
        });
    }

    return app.exec();
}
