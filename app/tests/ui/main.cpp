#include <QtQuickTest/quicktest.h>
#include <QCoreApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>

#include "AppBootstrap.h"
#include "LuaEngine.h"
#include "UiTestHelper.h"

#ifndef POB_UI_TEST_SOURCE_DIR
#define POB_UI_TEST_SOURCE_DIR "."
#endif

class UiTestSetup : public QObject {
    Q_OBJECT
public:
    UiTestSetup() = default;

public slots:
    void applicationAvailable() {
        m_bootstrap = new AppBootstrap(this);
        AppBootstrap::Options opts;
        opts.launchArgs << QCoreApplication::applicationFilePath();
        opts.connectLogToDebug = false;
        if (!m_bootstrap->init(opts)) {
            qFatal("pob-ui-test: failed to initialise LuaEngine");
        }

        m_uiTest = new UiTestHelper(m_bootstrap->engine(), this);
    }

    void qmlEngineAvailable(QQmlEngine* qmlEngine) {
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml"));
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml/components"));
        qmlEngine->addImportPath(QStringLiteral("qrc:/qml/views"));

        m_bootstrap->attachToQmlEngine(qmlEngine, m_uiTest->captureMode());
        m_uiTest->attachEngine(qmlEngine);
        m_uiTest->resetWarnings();

        qmlEngine->rootContext()->setContextProperty(QStringLiteral("uiTest"), m_uiTest);
    }

    void cleanupTestCase() {
        if (m_uiTest) {
            m_uiTest->restoreLuaMocks();
            m_uiTest->resetWarnings();
            m_uiTest->setCaptureMode(true);
        }
    }

private:
    AppBootstrap* m_bootstrap = nullptr;
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
