#include <QtQuickTest/quicktest.h>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>

#include "LuaEngine.h"
#include "Theme.h"
#include "TextMetrics.h"
#include "ColorText.h"
#include "BuildModel.h"
#include "SocketGroupModel.h"
#include "SaveLoadModel.h"
#include "BuildListModel.h"
#include "TreeModel.h"
#include "TreeGroupModel.h"
#include "TreeConnectorModel.h"
#include "TreeViewController.h"
#include "TreeScene.h"
#include "ItemSlotModel.h"
#include "JewelSocketModel.h"
#include "CalcModel.h"
#include "ConfigModel.h"
#include "NotesController.h"
#include "CompareModel.h"
#include "PartyModel.h"
#include "UiTestHelper.h"

#ifndef POB_LUA_DIR
#define POB_LUA_DIR "."
#endif

#ifndef POB_UI_TEST_SOURCE_DIR
#define POB_UI_TEST_SOURCE_DIR "."
#endif

class UiTestSetup : public QObject {
    Q_OBJECT
public:
    UiTestSetup() = default;

public slots:
    void applicationAvailable() {
        auto resolveDir = [](const QString& subdir) -> QString {
            QString exeDir = QCoreApplication::applicationDirPath();
            if (QDir(exeDir + "/" + subdir).exists()) return exeDir + "/" + subdir;
            QDir d(POB_LUA_DIR);
            d.cdUp();
            d.cdUp(); // app/lua -> repo root
            return d.absolutePath() + "/" + subdir;
        };
        auto resolveHost = []() -> QString {
            QString exeDir = QCoreApplication::applicationDirPath();
            QString candidate = exeDir + "/lua/pob_host.lua";
            if (QFile::exists(candidate)) return candidate;
            return QString(POB_LUA_DIR) + "/pob_host.lua";
        };

        const QString srcDir = resolveDir(QStringLiteral("src"));
        const QString runtimeDir = resolveDir(QStringLiteral("runtime"));
        const QString hostFile = resolveHost();
        QDir::setCurrent(srcDir);

        const QString fontDir = runtimeDir + "/SimpleGraphic/Fonts";
        for (const char* f : {"Liberation Sans.ttf", "Liberation Sans Bold.ttf",
                              "Bitstream Vera Sans Mono.ttf"}) {
            QFontDatabase::addApplicationFont(fontDir + "/" + f);
        }

        m_engine = new LuaEngine(this);
        QStringList launchArgs;
        launchArgs << QCoreApplication::applicationFilePath();
        if (!m_engine->init(srcDir, runtimeDir, hostFile, launchArgs, false)) {
            qFatal("pob-ui-test: failed to initialise LuaEngine");
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
        m_compareModel = new CompareModel(this);
        m_partyModel = new PartyModel(this);
        m_notesController->refresh(m_engine);
        m_compareModel->refresh(m_engine);
        m_partyModel->refresh(m_engine);

        m_saveLoadModel = new SaveLoadModel(m_engine, this);
        QObject::connect(m_saveLoadModel, &SaveLoadModel::buildLoaded, this, [this]() {
            m_buildModel->refresh(m_engine);
            m_socketGroupModel->refresh(m_engine);
        });

        QObject::connect(m_engine, &LuaEngine::buildDataChanged, this, [this]() {
            m_buildModel->refresh(m_engine);
            m_socketGroupModel->refresh(m_engine);
        });
        QObject::connect(m_engine, &LuaEngine::treeChanged, this, [this]() { m_treeViewController->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::configChanged, this, [this]() { m_configModel->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::itemsChanged, this, [this]() {
            m_itemSlotModel->refresh(m_engine);
            m_jewelSocketModel->refresh(m_engine);
        });
        QObject::connect(m_engine, &LuaEngine::calcsChanged, this, [this]() { m_calcModel->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::notesChanged, this, [this]() { m_notesController->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::compareChanged, this, [this]() { m_compareModel->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::partyChanged, this, [this]() { m_partyModel->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::buildListChanged, this, [this]() { m_buildListModel->refresh(m_engine); });
        QObject::connect(m_engine, &LuaEngine::modeChanged, this, [this]() {
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
            m_compareModel->refresh(m_engine);
            m_partyModel->refresh(m_engine);
        });

        m_uiTest = new UiTestHelper(m_engine, this);
    }

    void qmlEngineAvailable(QQmlEngine* qmlEngine) {
        qmlRegisterType<TreeScene>("PathOfBuilding", 1, 0, "TreeScene");
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml"));
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml/components"));
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml/views"));

        m_uiTest->attachEngine(qmlEngine);
        m_uiTest->resetWarnings();

        QQmlContext* ctx = qmlEngine->rootContext();
        ctx->setContextProperty(QStringLiteral("luaEngine"), m_engine);
        ctx->setContextProperty(QStringLiteral("pobCaptureMode"), true);
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
        ctx->setContextProperty(QStringLiteral("compareModel"), m_compareModel);
        ctx->setContextProperty(QStringLiteral("partyModel"), m_partyModel);
        ctx->setContextProperty(QStringLiteral("saveLoadModel"), m_saveLoadModel);
        ctx->setContextProperty(QStringLiteral("uiTest"), m_uiTest);
    }

    void cleanupTestCase() {
        if (m_uiTest) {
            m_uiTest->resetWarnings();
        }
    }

private:
    LuaEngine* m_engine = nullptr;
    Theme* m_theme = nullptr;
    ColorText* m_colorText = nullptr;
    BuildModel* m_buildModel = nullptr;
    SocketGroupModel* m_socketGroupModel = nullptr;
    BuildListModel* m_buildListModel = nullptr;
    TreeModel* m_treeModel = nullptr;
    TreeGroupModel* m_treeGroupModel = nullptr;
    TreeConnectorModel* m_treeConnectorModel = nullptr;
    TreeViewController* m_treeViewController = nullptr;
    ItemSlotModel* m_itemSlotModel = nullptr;
    JewelSocketModel* m_jewelSocketModel = nullptr;
    CalcModel* m_calcModel = nullptr;
    ConfigModel* m_configModel = nullptr;
    NotesController* m_notesController = nullptr;
    CompareModel* m_compareModel = nullptr;
    PartyModel* m_partyModel = nullptr;
    SaveLoadModel* m_saveLoadModel = nullptr;
    UiTestHelper* m_uiTest = nullptr;
};

int main(int argc, char** argv) {
    qputenv("QT_QUICK_CONTROLS_STYLE", "Fusion");
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    QTEST_SET_MAIN_SOURCE_PATH
    UiTestSetup setup;
    return quick_test_main_with_setup(argc, argv, "pob-ui-test", POB_UI_TEST_SOURCE_DIR, &setup);
}

#include "main.moc"
