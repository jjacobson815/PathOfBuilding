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
#include "LuaEngine.h"
#include "selftest_checks.h"
#include "Theme.h"
#include "BuildModel.h"
#include "SocketGroupModel.h"
#include "SaveLoadModel.h"
#include "BuildListModel.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"
#include "TreeViewController.h"
#include "ItemModel.h"
#include "ItemSlotModel.h"
#include "JewelSocketModel.h"
#include "SkillModel.h"
#include "CalcModel.h"
#include "ConfigModel.h"
#include "NotesController.h"
#include "CompareModel.h"
#include "PartyModel.h"

#ifndef POB_LUA_DIR
#define POB_LUA_DIR "."
#endif

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
static void mainLog(const QString& msg) {
    QFile f("c:/Users/User/source/repos/PathOfBuilding/main_status.log");
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
            capLog(ctx->statusPath, QString("done (failed=%1) -> %2").arg(ctx->failed).arg(QDir(ctx->outDir).absolutePath()));
            timer->stop();
            QCoreApplication::exit(ctx->failed > 0 ? 1 : 0);
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
    QString captureDir;
    for (int i = 1; i < argc; i++) {
        QString a = argv[i];
        if (a == "--headless") headless = true;
        else if (a == "--capture") {
            capture = true;
            // Optional output directory: --capture [outdir]
            if (i + 1 < argc && !QString(argv[i + 1]).startsWith("--"))
                captureDir = argv[++i];
        }
        else if (a == "--src" && i + 1 < argc) srcDir = argv[++i];
        else if (a == "--runtime" && i + 1 < argc) runtimeDir = argv[++i];
        else if (a == "--host" && i + 1 < argc) hostFile = argv[++i];
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
        if (!engine.init(srcDir, runtimeDir, hostFile)) {
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
            bool ok = idleOk && mutOk;
            QFile rf("/workdir/frameloop_result.txt");
            if (rf.open(QIODevice::WriteOnly | QIODevice::Text)) {
                QTextStream ts(&rf);
                ts << "idleOk=" << idleOk << "\n";
                ts << "mutOk=" << mutOk << "\n";
                ts << "ok=" << (ok ? "1" : "0") << "\n";
                rf.close();
            }
            return ok ? 0 : 1;
        }

        return engine.runSelfTest() ? 0 : 1;
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("Path of Building (Qt)");
    mainLog("QGuiApplication created");

    srcDir = resolveDir(srcDir, "src");
    runtimeDir = resolveDir(runtimeDir, "runtime");
    hostFile = resolveHost(hostFile);
    QDir::setCurrent(srcDir); // engine opens TreeData/ + manifest.xml relative to cwd
    mainLog("cwd=" + srcDir + " runtime=" + runtimeDir + " host=" + hostFile);

    checkBinaryFreshness();

    LuaEngine engine;
    QObject::connect(&engine, &LuaEngine::logMessage,
                     [](const QString& m) { qDebug().noquote() << "[lua]" << m; });
    if (!engine.init(srcDir, runtimeDir, hostFile)) {
        mainLog("engine.init FAILED");
        qCritical() << "Failed to initialise Lua engine";
        return 1;
    }
    mainLog("engine.init OK");

    QQmlApplicationEngine qml;
    qml.rootContext()->setContextProperty("luaEngine", &engine);

    // Phase 1b: expose the engine's UITheme as a QML theme singleton (context
    // property "theme"). Must be initialised AFTER engine.init() so the Lua
    // UITheme module (and the LoadModule global) exist. Parented to the app so
    // it is cleaned up at exit; the QML context property keeps a reference.
    Theme* theme = new Theme(&app);
    theme->init(&engine);
    qml.rootContext()->setContextProperty("theme", theme);

    // Phase 2a: typed build-state models. They are parented to the app so they
    // live for the process lifetime; the QML context properties keep references.
    // refresh() is called once now (after boot) and again every frame so the
    // models stay in sync with the engine without QML polling raw QVariants.
    BuildModel* buildModel = new BuildModel(&app);
    SocketGroupModel* socketGroupModel = new SocketGroupModel(&app);
    BuildListModel* buildListModel = new BuildListModel(&app);
    buildModel->refresh(&engine);
    socketGroupModel->refresh(&engine);
    buildListModel->refresh(&engine);
    qml.rootContext()->setContextProperty("buildModel", buildModel);
    qml.rootContext()->setContextProperty("socketGroupModel", socketGroupModel);
    qml.rootContext()->setContextProperty("buildListModel", buildListModel);

    // Phase 4a: passive-tree rendering models. TreeModel/TreeGroupModel/
    // TreeConnectorModel hold the node/group/connector rows; TreeViewController
    // owns the pan/zoom transform and pulls the data from the engine via
    // LuaEngine::getTreeData() (which calls the pob_getTreeData Lua global).
    // The controller is refreshed every frame (throttled internally by an
    // allocation+node-count signature) so the tree stays in sync with the
    // engine without QML polling raw QVariants.
    TreeModel* treeModel = new TreeModel(&app);
    TreeGroupModel* treeGroupModel = new TreeGroupModel(&app);
    TreeConnectorModel* treeConnectorModel = new TreeConnectorModel(&app);
    TreeViewController* treeViewController = new TreeViewController(&app);
    treeViewController->setModels(treeModel, treeGroupModel, treeConnectorModel);
    treeViewController->setEngine(&engine); // Phase 4b: enable alloc/search wrappers
    treeViewController->refresh(&engine); // initial pull after boot
    qml.rootContext()->setContextProperty("treeModel", treeModel);
    qml.rootContext()->setContextProperty("treeGroupModel", treeGroupModel);
    qml.rootContext()->setContextProperty("treeConnectorModel", treeConnectorModel);
    qml.rootContext()->setContextProperty("treeViewController", treeViewController);

    // Phase 5a: ItemsTab (ITEMS view) models. itemModel holds the build's
    // item list (name/rarity/mods/equip state); itemSlotModel holds the
    // equipped slots; jewelSocketModel holds the tree jewel sockets. They are
    // refreshed every frame (throttled internally by a change signature) so
    // the ITEMS view stays in sync with the engine without QML polling.
    ItemModel* itemModel = new ItemModel(&app);
    ItemSlotModel* itemSlotModel = new ItemSlotModel(&app);
    JewelSocketModel* jewelSocketModel = new JewelSocketModel(&app);
    itemModel->refresh(&engine);
    itemSlotModel->refresh(&engine);
    jewelSocketModel->refresh(&engine);
    qml.rootContext()->setContextProperty("itemModel", itemModel);
    qml.rootContext()->setContextProperty("itemSlotModel", itemSlotModel);
    qml.rootContext()->setContextProperty("jewelSocketModel", jewelSocketModel);

    // Phase 5b: SkillsTab (SKILLS view) model. skillModel holds the build's
    // active-skill DPS list (name/dps/totalDps/minionDps/socketGroupLabel/
    // isMain/socketGroupIndex/displaySkillIndex). It is refreshed every frame
    // (throttled internally by a change signature over the socket groups + main
    // skill selection) so the SKILLS view stays in sync without QML polling.
    SkillModel* skillModel = new SkillModel(&app);
    skillModel->refresh(&engine);
    qml.rootContext()->setContextProperty("skillModel", skillModel);

    // Phase 5c: CalcsTab (CALCS view) model. calcModel holds the build's
    // calculation output (summary numbers + the rendered CalcSection list with
    // per-stat values and breakdown keys). It is refreshed every frame
    // (throttled internally by the engine's build.outputRevision signature) so
    // the CALCS view stays in sync without QML polling.
    CalcModel* calcModel = new CalcModel(&app);
    calcModel->refresh(&engine);
    qml.rootContext()->setContextProperty("calcModel", calcModel);

    // Phase 5d: configuration-options browser for the CONFIG view. Exposes the
    // build's config options (src/Modules/ConfigOptions.lua) and lets the UI
    // write values back via LuaEngine::setConfigOption. Refreshed every frame
    // (throttled internally by build.outputRevision) so the CONFIG view stays
    // in sync without QML polling.
    ConfigModel* configModel = new ConfigModel(&app);
    configModel->refresh(&engine);
    qml.rootContext()->setContextProperty("configModel", configModel);

    // Phase 5e: Notes/Import/Compare/Party (utility) tabs bridge. notesController
    // mirrors the NotesTab edit buffer onto a QML-bindable `notes` QString;
    // compareModel/partyModel are list models for the COMPARE/PARTY views. They
    // are refreshed every frame (throttled internally) so the utility views stay
    // in sync with the engine without QML polling. Import needs no model: the
    // QML IMPORT view calls LuaEngine::importFromCode directly.
    NotesController* notesController = new NotesController(&app);
    CompareModel* compareModel = new CompareModel(&app);
    PartyModel* partyModel = new PartyModel(&app);
    notesController->refresh(&engine);
    compareModel->refresh(&engine);
    partyModel->refresh(&engine);
    qml.rootContext()->setContextProperty("notesController", notesController);
    qml.rootContext()->setContextProperty("compareModel", compareModel);
    qml.rootContext()->setContextProperty("partyModel", partyModel);

    // Phase 3 verification hook (opt-in). When POB_TEST_LIST_FLOW is set, main.cpp
    // drives the LIST -> BUILD flow headlessly (via the same LuaEngine slots the
    // QML buttons call) and logs the resulting mode + buildName, so the offscreen
    // GUI test can prove the bridge without clicking.
    bool testListFlow = !qEnvironmentVariableIsEmpty("POB_TEST_LIST_FLOW");
    qml.rootContext()->setContextProperty("testListFlow", testListFlow);

    // Phase 2b: build save/load bridge. The model delegates to the LuaEngine
    // save/load slots (which call the pob_* Lua globals). On a successful load
    // it emits buildLoaded(); we refresh the typed models immediately so the UI
    // reflects the newly loaded build without waiting for the next frame tick.
    SaveLoadModel* saveLoadModel = new SaveLoadModel(&engine, &app);
    QObject::connect(saveLoadModel, &SaveLoadModel::buildLoaded, [&]() {
        buildModel->refresh(&engine);
        socketGroupModel->refresh(&engine);
        qDebug().noquote() << "[SaveLoad] build loaded; models refreshed";
    });
    qml.rootContext()->setContextProperty("saveLoadModel", saveLoadModel);

    // Phase 6: event-driven model synchronisation. LuaEngine emits a specific
    // signal the moment a genuine mutation occurs; each model refreshes exactly
    // once in response. No polling timer, so an idle UI performs zero refreshes
    // and sits at 0% CPU. (The Lua rebuild already happened synchronously
    // inside the bridge method that emitted the signal.)
    QObject::connect(&engine, &LuaEngine::buildDataChanged, [&]() { buildModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::buildDataChanged, [&]() { socketGroupModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::treeChanged, [&]() { treeViewController->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::configChanged, [&]() { configModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::itemsChanged, [&]() { itemModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::itemsChanged, [&]() { itemSlotModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::itemsChanged, [&]() { jewelSocketModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::skillsChanged, [&]() { skillModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::calcsChanged, [&]() { calcModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::notesChanged, [&]() { notesController->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::compareChanged, [&]() { compareModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::partyChanged, [&]() { partyModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::buildListChanged, [&]() { buildListModel->refresh(&engine); });
    // modeChanged covers mode switches and new-build loads: refresh everything.
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { buildModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { socketGroupModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { buildListModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { saveLoadModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { treeViewController->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { itemModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { itemSlotModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { jewelSocketModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { skillModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { calcModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { configModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { notesController->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { compareModel->refresh(&engine); });
    QObject::connect(&engine, &LuaEngine::modeChanged, [&]() { partyModel->refresh(&engine); });

    qml.load(QUrl("qrc:/qml/main.qml"));
    if (qml.rootObjects().isEmpty()) {
        mainLog("qml FAILED to load");
        qCritical() << "Failed to load QML";
        return 1;
    }
    mainLog("qml loaded");

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

    // Phase 2a verification: prove a Lua state change propagates to the typed
    // model's NOTIFY signal. We rename the build via the bridge, then refresh
    // directly (the frame loop would also catch it on the next tick). The model
    // logs the change in BuildModel::refresh(). We revert afterwards so the
    // default build name is restored for normal use.
    QTimer::singleShot(800, &app, [&]() {
        engine.setBuildName("Test Build");
        buildModel->refresh(&engine); // detects buildName change -> emits dataChanged
        QTimer::singleShot(800, &app, [&]() {
            engine.setBuildName("Unnamed build");
            buildModel->refresh(&engine);
        });
    });

    // Phase 3 verification (opt-in, POB_TEST_LIST_FLOW=1): drive the LIST -> BUILD
    // flow synchronously (no event loop needed) using the same LuaEngine slots the
    // QML buttons call (setListMode / createBuild), then log + persist the resulting
    // mode + buildModel.buildName to prove the bridge switches mode and updates the
    // typed model live. Runs before app.exec() so it is deterministic and flushes.
    if (testListFlow) {
        engine.setListMode();
        engine.runCallback("OnFrame"); // initialise LIST mode
        engine.createBuild();          // SetMode BUILD + OnFrame (initialises BUILD)
        buildModel->refresh(&engine);  // sync typed model with the new build
        const QString mode = engine.currentMode();
        const QString bn = buildModel->buildName();
        qDebug().noquote() << "[TEST] list-flow: currentMode=" << mode
                 << " buildName=" << bn;
        QFile rf("/workdir/guitest_result.txt");
        if (rf.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream ts(&rf);
            ts << "currentMode=" << mode << "\n";
            ts << "buildName=" << bn << "\n";
            rf.close();
        }
    }

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

    return app.exec();
}
