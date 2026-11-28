#pragma once

#include <QMap>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

class QQmlEngine;
class QQmlError;
class LuaEngine;

class UiTestHelper : public QObject {
    Q_OBJECT
public:
    explicit UiTestHelper(LuaEngine* engine, QObject* parent = nullptr);
    ~UiTestHelper() override;

    void attachEngine(QQmlEngine* qmlEngine);

    Q_INVOKABLE void resetWarnings();
    Q_INVOKABLE QStringList warnings() const;
    Q_INVOKABLE int warningCount() const;

    // Test toggle for pobCaptureMode so startup / UpdateBanner flows stay testable.
    Q_INVOKABLE void setCaptureMode(bool enabled);
    Q_INVOKABLE bool captureMode() const { return m_captureMode; }

    // Slow-mo step delay read from env var POB_UI_TEST_STEP_MS (default 0).
    Q_INVOKABLE int stepDelayMs() const;

    // Simulates Qt6 QVariantList / QVariantMap bridge values returned by LuaEngine.
    Q_INVOKABLE QVariant toVariantList(const QVariantList& items) const;
    Q_INVOKABLE QVariant toVariantMap(const QVariantMap& map) const;

    Q_INVOKABLE QObject* findObject(QObject* root, const QString& objectName) const;
    Q_INVOKABLE QVariantList findObjectsByPrefix(QObject* root, const QString& prefix) const;

    Q_INVOKABLE QVariantMap checkLayoutOracle(QObject* rootObj,
                                              int viewportW = 0,
                                              int viewportH = 0,
                                              const QVariantMap& options = QVariantMap()) const;
    Q_INVOKABLE QString captureAnnotatedFailure(QObject* windowOrItem,
                                                const QVariantList& issues,
                                                const QString& outPath = QString()) const;

    Q_INVOKABLE bool loadTestBuild(const QString& relPath);
    Q_INVOKABLE bool mockLuaGlobal(const QString& fnName, const QString& luaBody);
    Q_INVOKABLE void restoreLuaMocks();
    Q_INVOKABLE void sendKeyClick(QObject* targetWindow, int key, int modifiers = 0) const;

    Q_INVOKABLE void resetEngineForTest();
    Q_INVOKABLE bool isWindows() const;

    void recordWarning(const QString& msg);

private:
    static void messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg);
    static bool isBenignPlatformWarning(const QString& msg);

    LuaEngine* m_engine = nullptr;
    QPointer<QQmlEngine> m_qmlEngine;
    bool m_captureMode = true;
    QStringList m_warnings;
    QMap<QString, int> m_mockBackupRefs;
    static UiTestHelper* s_instance;
    static QtMessageHandler s_prevHandler;
};
