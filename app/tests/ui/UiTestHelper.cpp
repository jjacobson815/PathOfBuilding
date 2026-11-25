#include "UiTestHelper.h"
#include "LuaEngine.h"

#include <QDir>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSet>
#include <QtGlobal>

UiTestHelper* UiTestHelper::s_instance = nullptr;
QtMessageHandler UiTestHelper::s_prevHandler = nullptr;

UiTestHelper::UiTestHelper(LuaEngine* engine, QObject* parent)
    : QObject(parent), m_engine(engine) {
    s_instance = this;
    if (!s_prevHandler) {
        s_prevHandler = qInstallMessageHandler(&UiTestHelper::messageHandler);
    }
}

UiTestHelper::~UiTestHelper() {
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

void UiTestHelper::attachEngine(QQmlEngine* qmlEngine) {
    if (!qmlEngine) return;
    connect(qmlEngine, &QQmlEngine::warnings, this, [this](const QList<QQmlError>& errs) {
        for (const QQmlError& e : errs) {
            recordWarning(e.toString());
        }
    });
}

bool UiTestHelper::isBenignPlatformWarning(const QString& msg) {
    if (msg.contains(QLatin1String("QWindowsWindow::setGeometry"))) return true;
    return false;
}

void UiTestHelper::recordWarning(const QString& msg) {
    if (isBenignPlatformWarning(msg)) return;
    if (!m_warnings.contains(msg)) {
        m_warnings.append(msg);
    }
}

void UiTestHelper::messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg) {
    if ((type == QtWarningMsg || type == QtCriticalMsg) && s_instance) {
        s_instance->recordWarning(msg);
    }
    if (s_prevHandler) {
        s_prevHandler(type, ctx, msg);
    }
}

void UiTestHelper::resetWarnings() {
    m_warnings.clear();
}

QStringList UiTestHelper::warnings() const {
    return m_warnings;
}

int UiTestHelper::warningCount() const {
    return m_warnings.size();
}

QVariant UiTestHelper::toVariantList(const QVariantList& items) const {
    return QVariant::fromValue(items);
}

QVariant UiTestHelper::toVariantMap(const QVariantMap& map) const {
    return QVariant::fromValue(map);
}

namespace {

void collectChildren(QObject* obj, QList<QObject*>& out, QSet<QObject*>& visited) {
    if (!obj) return;
    auto pushUnique = [&](QObject* child) {
        if (child && !visited.contains(child)) {
            visited.insert(child);
            out.append(child);
        }
    };

    if (auto* win = qobject_cast<QQuickWindow*>(obj)) {
        pushUnique(win->contentItem());
    }
    if (auto* item = qobject_cast<QQuickItem*>(obj)) {
        for (QQuickItem* child : item->childItems()) {
            pushUnique(child);
        }
    }
    const QVariant contentProp = obj->property("contentItem");
    if (contentProp.isValid()) {
        if (QObject* contentObj = contentProp.value<QObject*>()) {
            pushUnique(contentObj);
        }
    }
    for (QObject* child : obj->children()) {
        pushUnique(child);
    }
}

bool isEffectivelyVisible(QQuickItem* item) {
    if (!item || !item->isVisible() || item->opacity() <= 0.0) return false;
    QQuickItem* cur = item->parentItem();
    while (cur) {
        if (!cur->isVisible() || cur->opacity() <= 0.0) return false;
        if (cur->clip() && (cur->width() <= 0.0 || cur->height() <= 0.0)) return false;
        cur = cur->parentItem();
    }
    return true;
}

bool isInsideHorizScrollableFlickable(QQuickItem* item) {
    QQuickItem* cur = item ? item->parentItem() : nullptr;
    while (cur) {
        if (cur->inherits("QQuickFlickable")) {
            const double cw = cur->property("contentWidth").toDouble();
            if (cw > cur->width() + 1.0) return true;
        }
        cur = cur->parentItem();
    }
    return false;
}

} // namespace

QObject* UiTestHelper::findObject(QObject* root, const QString& objectName) const {
    if (!root || objectName.isEmpty()) return nullptr;
    QList<QObject*> queue;
    QSet<QObject*> visited;
    queue.append(root);
    visited.insert(root);

    int idx = 0;
    while (idx < queue.size()) {
        QObject* cur = queue[idx++];
        if (cur->objectName() == objectName) {
            return cur;
        }
        collectChildren(cur, queue, visited);
    }
    return nullptr;
}

QVariantList UiTestHelper::findObjectsByPrefix(QObject* root, const QString& prefix) const {
    QVariantList result;
    if (!root) return result;
    QList<QObject*> queue;
    QSet<QObject*> visited;
    queue.append(root);
    visited.insert(root);

    int idx = 0;
    while (idx < queue.size()) {
        QObject* cur = queue[idx++];
        if (cur->objectName().startsWith(prefix)) {
            result.append(QVariant::fromValue(cur));
        }
        collectChildren(cur, queue, visited);
    }
    return result;
}

QVariantMap UiTestHelper::checkLayoutOracle(QObject* rootObj, int viewportW, int viewportH) const {
    Q_UNUSED(viewportW)
    Q_UNUSED(viewportH)

    QVariantMap result;
    QStringList issues;
    int checkedItems = 0;
    int checkedTexts = 0;

    if (!rootObj) {
        issues.append(QStringLiteral("checkLayoutOracle called with null root"));
        result.insert(QStringLiteral("ok"), false);
        result.insert(QStringLiteral("issues"), issues);
        result.insert(QStringLiteral("checkedItems"), 0);
        result.insert(QStringLiteral("checkedTexts"), 0);
        return result;
    }

    QList<QObject*> queue;
    QSet<QObject*> visited;
    queue.append(rootObj);
    visited.insert(rootObj);

    int idx = 0;
    while (idx < queue.size()) {
        QObject* cur = queue[idx++];
        collectChildren(cur, queue, visited);

        auto* item = qobject_cast<QQuickItem*>(cur);
        if (!item || !isEffectivelyVisible(item)) continue;

        const QString objName = item->objectName();
        if (objName.startsWith(QLatin1String("pob.")) && !item->inherits("QQuickRepeater")) {
            ++checkedItems;
            if (item->width() <= 0.0 || item->height() <= 0.0) {
                issues.append(QStringLiteral("Zero-size control '%1' (%2x%3)")
                                  .arg(objName)
                                  .arg(item->width())
                                  .arg(item->height()));
            }
        }

        if (item->inherits("QQuickText")) {
            const QString txt = item->property("text").toString();
            if (!txt.trimmed().isEmpty() && item->width() > 0.0 && item->height() > 0.0) {
                ++checkedTexts;
                const int elide = item->property("elide").toInt();
                const int wrapMode = item->property("wrapMode").toInt();
                const double paintedW = item->property("paintedWidth").toDouble();
                if (elide == 0 && wrapMode == 0 && paintedW > item->width() + 2.0) {
                    if (!isInsideHorizScrollableFlickable(item)) {
                        const QString tag = objName.isEmpty()
                            ? (item->parentItem() ? item->parentItem()->objectName() : QStringLiteral("<unnamed>"))
                            : objName;
                        issues.append(QStringLiteral("Text overflow on '%1' text='%2': paintedWidth=%3 > width=%4")
                                          .arg(tag, txt.left(40))
                                          .arg(paintedW)
                                          .arg(item->width()));
                    }
                }
            }
        }
    }

    result.insert(QStringLiteral("ok"), issues.isEmpty());
    result.insert(QStringLiteral("issues"), issues);
    result.insert(QStringLiteral("checkedItems"), checkedItems);
    result.insert(QStringLiteral("checkedTexts"), checkedTexts);
    return result;
}

void UiTestHelper::resetEngineForTest() {
    if (!m_engine) return;
    if (m_engine->currentMode() != QLatin1String("BUILD")) {
        m_engine->setMode(QStringLiteral("BUILD"));
    }
    if (m_engine->currentView() != QLatin1String("TREE")) {
        m_engine->setActiveView(QStringLiteral("TREE"));
    }
}

bool UiTestHelper::isWindows() const {
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}
