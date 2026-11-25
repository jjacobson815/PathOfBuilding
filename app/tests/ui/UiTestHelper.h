#pragma once

#include <QObject>
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

    // Simulates Qt6 QVariantList / QVariantMap bridge values returned by LuaEngine.
    Q_INVOKABLE QVariant toVariantList(const QVariantList& items) const;
    Q_INVOKABLE QVariant toVariantMap(const QVariantMap& map) const;

    Q_INVOKABLE QObject* findObject(QObject* root, const QString& objectName) const;
    Q_INVOKABLE QVariantList findObjectsByPrefix(QObject* root, const QString& prefix) const;

    Q_INVOKABLE QVariantMap checkLayoutOracle(QObject* rootObj, int viewportW = 0, int viewportH = 0) const;

    Q_INVOKABLE void resetEngineForTest();
    Q_INVOKABLE bool isWindows() const;

    void recordWarning(const QString& msg);

private:
    static void messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg);
    static bool isBenignPlatformWarning(const QString& msg);

    LuaEngine* m_engine = nullptr;
    QStringList m_warnings;
    static UiTestHelper* s_instance;
    static QtMessageHandler s_prevHandler;
};
