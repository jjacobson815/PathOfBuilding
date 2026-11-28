#include "AppBootstrap.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QQmlContext>
#include <QQmlEngine>

#include "BuildListModel.h"
#include "BuildModel.h"
#include "CalcModel.h"
#include "ColorText.h"
#include "ConfigModel.h"
#include "ItemSlotModel.h"
#include "JewelSocketModel.h"
#include "LuaEngine.h"
#include "NotesController.h"
#include "PartyModel.h"
#include "SaveLoadModel.h"
#include "SocketGroupModel.h"
#include "TextMetrics.h"
#include "Theme.h"
#include "TreeConnectorModel.h"
#include "TreeGroupModel.h"
#include "TreeModel.h"
#include "TreeScene.h"
#include "TreeViewController.h"

#ifndef POB_LUA_DIR
#define POB_LUA_DIR "."
#endif

AppBootstrap::AppBootstrap(QObject* parent)
    : QObject(parent) {}

QString AppBootstrap::resolveDir(const QString& cliVal, const QString& subdir) {
    if (!cliVal.isEmpty()) return cliVal;
    const QString exeDir = QCoreApplication::applicationDirPath();
    if (QDir(exeDir + "/" + subdir).exists()) return exeDir + "/" + subdir;
    QDir d(QStringLiteral(POB_LUA_DIR));
    d.cdUp();
    d.cdUp(); // app/lua -> repo root
    return d.absolutePath() + "/" + subdir;
}

QString AppBootstrap::resolveHost(const QString& cliVal) {
    if (!cliVal.isEmpty()) return cliVal;
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QString candidate = exeDir + "/lua/pob_host.lua";
    if (QFile::exists(candidate)) return candidate;
    return QStringLiteral(POB_LUA_DIR) + "/pob_host.lua";
}

void AppBootstrap::registerAppFonts(const QString& runtimeDir) {
    const QString fontDir = runtimeDir + "/SimpleGraphic/Fonts";
    for (const char* f : {"Liberation Sans.ttf", "Liberation Sans Bold.ttf",
                          "Bitstream Vera Sans Mono.ttf"}) {
        const QString path = fontDir + "/" + f;
        if (QFontDatabase::addApplicationFont(path) < 0) {
            qWarning().noquote() << "[fonts] failed to register" << path;
        }
    }
}

bool AppBootstrap::init(const Options& opts) {
    m_srcDir = resolveDir(opts.srcDir, QStringLiteral("src"));
    m_runtimeDir = resolveDir(opts.runtimeDir, QStringLiteral("runtime"));
    m_hostFile = resolveHost(opts.hostFile);

    QDir::setCurrent(m_srcDir); // engine opens TreeData/ + manifest.xml relative to cwd
    registerAppFonts(m_runtimeDir);

    m_engine = new LuaEngine(this);
    if (opts.connectLogToDebug) {
        connect(m_engine, &LuaEngine::logMessage, this,
                [](const QString& m) { qDebug().noquote() << "[lua]" << m; });
    }

    QStringList args = opts.launchArgs;
    if (args.isEmpty()) {
        args << QCoreApplication::applicationFilePath();
    }
    if (!m_engine->init(m_srcDir, m_runtimeDir, m_hostFile, args, opts.devMode)) {
        return false;
    }

    m_theme = new Theme(this);
    m_theme->init(m_engine);
    m_colorText = new ColorText(this);

    m_buildModel = new BuildModel(this);
    m_socketGroupModel = new SocketGroupModel(this);
    m_buildListModel = new BuildListModel(this);
    m_buildModel->refresh(m_engine);
    m_socketGroupModel->refresh(m_engine);
    m_buildListModel->refresh(m_engine);

    m_treeModel = new TreeModel(this);
    m_treeGroupModel = new TreeGroupModel(this);
    m_treeConnectorModel = new TreeConnectorModel(this);
    m_treeViewController = new TreeViewController(this);
    m_treeViewController->setModels(m_treeModel, m_treeGroupModel, m_treeConnectorModel);
    m_treeViewController->setEngine(m_engine);
    m_treeViewController->refresh(m_engine);

    m_itemSlotModel = new ItemSlotModel(this);
    m_jewelSocketModel = new JewelSocketModel(this);
    m_itemSlotModel->refresh(m_engine);
    m_jewelSocketModel->refresh(m_engine);

    m_calcModel = new CalcModel(this);
    m_calcModel->refresh(m_engine);

    m_configModel = new ConfigModel(this);
    m_configModel->refresh(m_engine);

    m_notesController = new NotesController(this);
    m_partyModel = new PartyModel(this);
    m_notesController->refresh(m_engine);
    m_partyModel->refresh(m_engine);

    m_saveLoadModel = new SaveLoadModel(m_engine, this);
    connect(m_saveLoadModel, &SaveLoadModel::buildLoaded, this, [this]() {
        m_buildModel->refresh(m_engine);
        m_socketGroupModel->refresh(m_engine);
        qDebug().noquote() << "[SaveLoad] build loaded; models refreshed";
    });

    connect(m_engine, &LuaEngine::buildDataChanged, this, [this]() {
        m_buildModel->refresh(m_engine);
        m_socketGroupModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::treeChanged, this, [this]() {
        m_treeViewController->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::configChanged, this, [this]() {
        m_configModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::itemsChanged, this, [this]() {
        m_itemSlotModel->refresh(m_engine);
        m_jewelSocketModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::calcsChanged, this, [this]() {
        m_calcModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::notesChanged, this, [this]() {
        m_notesController->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::partyChanged, this, [this]() {
        m_partyModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::buildListChanged, this, [this]() {
        m_buildListModel->refresh(m_engine);
    });
    connect(m_engine, &LuaEngine::modeChanged, this, [this]() {
        m_buildModel->refresh(m_engine);
        m_socketGroupModel->refresh(m_engine);
        m_buildListModel->refresh(m_engine);
        m_saveLoadModel->refresh(m_engine);
        m_treeViewController->refresh(m_engine);
        m_itemSlotModel->refresh(m_engine);
        m_jewelSocketModel->refresh(m_engine);
        m_calcModel->refresh(m_engine);
        m_configModel->refresh(m_engine);
        m_notesController->refresh(m_engine);
        m_partyModel->refresh(m_engine);
    });

    return true;
}

void AppBootstrap::attachToQmlEngine(QQmlEngine* qmlEngine, bool captureMode) const {
    if (!qmlEngine || !m_engine) return;
    qmlRegisterType<TreeScene>("PathOfBuilding", 1, 0, "TreeScene");

    QQmlContext* ctx = qmlEngine->rootContext();
    ctx->setContextProperty(QStringLiteral("luaEngine"), m_engine);
    ctx->setContextProperty(QStringLiteral("pobCaptureMode"), captureMode);
    ctx->setContextProperty(QStringLiteral("theme"), m_theme);
    ctx->setContextProperty(QStringLiteral("textMetrics"), m_engine->textMetrics());
    ctx->setContextProperty(QStringLiteral("colorText"), m_colorText);
    ctx->setContextProperty(QStringLiteral("buildModel"), m_buildModel);
    ctx->setContextProperty(QStringLiteral("socketGroupModel"), m_socketGroupModel);
    ctx->setContextProperty(QStringLiteral("buildListModel"), m_buildListModel);
    ctx->setContextProperty(QStringLiteral("treeModel"), m_treeModel);
    ctx->setContextProperty(QStringLiteral("treeGroupModel"), m_treeGroupModel);
    ctx->setContextProperty(QStringLiteral("treeConnectorModel"), m_treeConnectorModel);
    ctx->setContextProperty(QStringLiteral("treeViewController"), m_treeViewController);
    ctx->setContextProperty(QStringLiteral("itemSlotModel"), m_itemSlotModel);
    ctx->setContextProperty(QStringLiteral("jewelSocketModel"), m_jewelSocketModel);
    ctx->setContextProperty(QStringLiteral("calcModel"), m_calcModel);
    ctx->setContextProperty(QStringLiteral("configModel"), m_configModel);
    ctx->setContextProperty(QStringLiteral("notesController"), m_notesController);
    ctx->setContextProperty(QStringLiteral("partyModel"), m_partyModel);
    ctx->setContextProperty(QStringLiteral("saveLoadModel"), m_saveLoadModel);
}
