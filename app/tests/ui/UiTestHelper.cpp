#include "UiTestHelper.h"
#include "LuaEngine.h"

#include <QColor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontMetrics>
#include <QHash>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPen>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSet>
#include <QTest>
#include <QtGlobal>
#include <algorithm>
#include <cmath>
#include <lua.hpp>

#ifndef POB_LUA_DIR
#define POB_LUA_DIR "."
#endif

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
    restoreLuaMocks();
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

void UiTestHelper::attachEngine(QQmlEngine* qmlEngine) {
    m_qmlEngine = qmlEngine;
    if (!qmlEngine) return;
    connect(qmlEngine, &QQmlEngine::warnings, this, [this](const QList<QQmlError>& errs) {
        for (const QQmlError& e : errs) {
            recordWarning(e.toString());
        }
    });
}

void UiTestHelper::setCaptureMode(bool enabled) {
    m_captureMode = enabled;
    if (m_qmlEngine) {
        m_qmlEngine->rootContext()->setContextProperty(QStringLiteral("pobCaptureMode"), enabled);
    }
}

int UiTestHelper::stepDelayMs() const {
    bool ok = false;
    const int val = qEnvironmentVariableIntValue("POB_UI_TEST_STEP_MS", &ok);
    return (ok && val > 0) ? val : 0;
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
    Q_UNUSED(ctx)
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

QString repoRootDir() {
    QDir d(QStringLiteral(POB_LUA_DIR));
    d.cdUp();
    d.cdUp(); // app/lua -> repo root
    return d.absolutePath();
}

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

bool isScrollContainer(const QQuickItem* item) {
    if (!item) return false;
    return item->inherits("QQuickFlickable")
        || item->inherits("QQuickScrollView")
        || item->inherits("QQuickListView")
        || item->inherits("QQuickGridView")
        || item->inherits("QQuickTableView");
}

bool isInsideScrollableFlickable(QQuickItem* item) {
    QQuickItem* cur = item ? item->parentItem() : nullptr;
    while (cur) {
        if (cur->inherits("QQuickFlickable")) {
            const double cw = cur->property("contentWidth").toDouble();
            const double ch = cur->property("contentHeight").toDouble();
            if (cw > cur->width() + 1.0 || ch > cur->height() + 1.0) return true;
        }
        cur = cur->parentItem();
    }
    return false;
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

bool isInsideVertScrollableFlickable(QQuickItem* item) {
    QQuickItem* cur = item ? item->parentItem() : nullptr;
    while (cur) {
        if (cur->inherits("QQuickFlickable")) {
            const double ch = cur->property("contentHeight").toDouble();
            if (ch > cur->height() + 1.0) return true;
        }
        cur = cur->parentItem();
    }
    return false;
}

bool isAllowlisted(const QString& objName, const QStringList& allowlist) {
    if (objName.isEmpty() || allowlist.isEmpty()) return false;
    for (const QString& entry : allowlist) {
        if (entry.isEmpty()) continue;
        if (objName == entry || objName.startsWith(entry) || objName.contains(entry)) {
            return true;
        }
    }
    return false;
}

QQuickItem* resolveRootItem(QObject* rootObj) {
    if (auto* item = qobject_cast<QQuickItem*>(rootObj)) return item;
    if (auto* win = qobject_cast<QQuickWindow*>(rootObj)) return win->contentItem();
    return nullptr;
}

QRectF mapToRootRect(QQuickItem* item, QQuickItem* rootItem) {
    if (!item) return QRectF();
    const QRectF localRect(0.0, 0.0, item->width(), item->height());
    if (!rootItem || item == rootItem) return localRect;
    return item->mapRectToItem(rootItem, localRect);
}

QVariantMap makeViolation(const QString& kind,
                          const QString& objectName,
                          const QString& message,
                          const QRectF& rect) {
    QVariantMap v;
    v.insert(QStringLiteral("kind"), kind);
    v.insert(QStringLiteral("objectName"), objectName);
    v.insert(QStringLiteral("message"), message);
    v.insert(QStringLiteral("x"), rect.x());
    v.insert(QStringLiteral("y"), rect.y());
    v.insert(QStringLiteral("width"), rect.width());
    v.insert(QStringLiteral("height"), rect.height());
    return v;
}

bool isInteractiveCandidate(QQuickItem* item) {
    if (!item || !item->isVisible() || item->opacity() <= 0.0) return false;
    if (item->width() <= 0.0 || item->height() <= 0.0) return false;
    if (item->inherits("QQuickRepeater") || item->inherits("QQuickScrollBar")) return false;
    if (item->objectName().startsWith(QLatin1String("pob."))) return true;
    if (item->inherits("QQuickAbstractButton")
        || item->inherits("QQuickTextInput")
        || item->inherits("QQuickTextEdit")
        || item->inherits("QQuickComboBox")
        || item->inherits("QQuickSlider")
        || item->inherits("QQuickSpinBox")) {
        return true;
    }
    return item->property("controlEnabled").isValid();
}

QJsonObject dumpItemTree(QQuickItem* item, int depth) {
    QJsonObject obj;
    if (!item || depth > 24) return obj;
    obj.insert(QStringLiteral("className"), QString::fromLatin1(item->metaObject()->className()));
    if (!item->objectName().isEmpty()) {
        obj.insert(QStringLiteral("objectName"), item->objectName());
    }
    obj.insert(QStringLiteral("x"), item->x());
    obj.insert(QStringLiteral("y"), item->y());
    obj.insert(QStringLiteral("width"), item->width());
    obj.insert(QStringLiteral("height"), item->height());
    const QPointF scenePos = item->mapToScene(QPointF(0.0, 0.0));
    obj.insert(QStringLiteral("sceneX"), scenePos.x());
    obj.insert(QStringLiteral("sceneY"), scenePos.y());
    obj.insert(QStringLiteral("clip"), item->clip());
    obj.insert(QStringLiteral("visible"), item->isVisible());
    obj.insert(QStringLiteral("opacity"), item->opacity());
    if (item->inherits("QQuickText")) {
        obj.insert(QStringLiteral("text"), item->property("text").toString().left(120));
        obj.insert(QStringLiteral("paintedWidth"), item->property("paintedWidth").toDouble());
        obj.insert(QStringLiteral("paintedHeight"), item->property("paintedHeight").toDouble());
    }
    QJsonArray childrenArr;
    for (QQuickItem* child : item->childItems()) {
        if (child && child->isVisible() && child->opacity() > 0.0) {
            childrenArr.append(dumpItemTree(child, depth + 1));
        }
    }
    if (!childrenArr.isEmpty()) {
        obj.insert(QStringLiteral("children"), childrenArr);
    }
    return obj;
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

QVariantMap UiTestHelper::checkLayoutOracle(QObject* rootObj,
                                            int viewportW,
                                            int viewportH,
                                            const QVariantMap& options) const {
    QVariantMap result;
    QStringList issues;
    QVariantList violations;
    int checkedItems = 0;
    int checkedTexts = 0;

    if (!rootObj) {
        const QString msg = QStringLiteral("checkLayoutOracle called with null root");
        issues.append(msg);
        violations.append(makeViolation(QStringLiteral("null-root"), QString(), msg, QRectF()));
        result.insert(QStringLiteral("ok"), false);
        result.insert(QStringLiteral("issues"), issues);
        result.insert(QStringLiteral("violations"), violations);
        result.insert(QStringLiteral("checkedItems"), 0);
        result.insert(QStringLiteral("checkedTexts"), 0);
        return result;
    }

    const bool strict = options.value(QStringLiteral("strict"), false).toBool();
    const bool checkViewport = options.value(QStringLiteral("checkViewportBounds"), strict).toBool();
    const bool checkClip = options.value(QStringLiteral("checkClipOverflow"), strict).toBool();
    const bool checkVertText = options.value(QStringLiteral("checkVerticalTextOverflow"), strict).toBool();
    const bool checkOverlap = options.value(QStringLiteral("checkSiblingOverlap"), strict).toBool();

    QStringList allowlist;
    const QVariant allowVar = options.value(QStringLiteral("allowlist"));
    if (allowVar.canConvert<QStringList>()) {
        allowlist = allowVar.toStringList();
    } else if (allowVar.canConvert<QVariantList>()) {
        for (const QVariant& v : allowVar.toList()) {
            allowlist.append(v.toString());
        }
    }

    QQuickItem* rootItem = resolveRootItem(rootObj);
    const int effViewportW = (viewportW > 0) ? viewportW : (rootItem ? qRound(rootItem->width()) : 0);
    const int effViewportH = (viewportH > 0) ? viewportH : (rootItem ? qRound(rootItem->height()) : 0);

    QList<QObject*> queue;
    QSet<QObject*> visited;
    queue.append(rootObj);
    visited.insert(rootObj);

    QHash<QQuickItem*, QList<QQuickItem*>> siblingGroups;

    int idx = 0;
    while (idx < queue.size()) {
        QObject* cur = queue[idx++];
        auto* item = qobject_cast<QQuickItem*>(cur);
        const QString curName = item ? item->objectName() : QString();
        const bool curAllowlisted = isAllowlisted(curName, allowlist);
        if (curAllowlisted && curName == QLatin1String("pob.tooltip.root")) {
            continue;
        }
        collectChildren(cur, queue, visited);

        if (!item || !isEffectivelyVisible(item)) continue;

        const QString objName = curName;
        const bool allowlisted = curAllowlisted;
        const bool isPobControl = objName.startsWith(QLatin1String("pob.")) && !item->inherits("QQuickRepeater");

        if (isPobControl) {
            ++checkedItems;
            if (!allowlisted && (item->width() <= 0.0 || item->height() <= 0.0)) {
                const QString msg = QStringLiteral("Zero-size control '%1' (%2x%3)")
                                        .arg(objName)
                                        .arg(item->width())
                                        .arg(item->height());
                issues.append(msg);
                violations.append(makeViolation(QStringLiteral("zero-size"),
                                                objName,
                                                msg,
                                                mapToRootRect(item, rootItem)));
            }

            if (!allowlisted && checkViewport && effViewportW > 0 && effViewportH > 0
                && item != rootItem && !isInsideScrollableFlickable(item)) {
                const QRectF r = mapToRootRect(item, rootItem);
                if (r.left() < -1.0 || r.top() < -1.0
                    || r.right() > effViewportW + 1.0 || r.bottom() > effViewportH + 1.0) {
                    const QString msg = QStringLiteral("Viewport bounds overflow on '%1': rect=(%2,%3 %4x%5) > viewport=(%6x%7)")
                                            .arg(objName)
                                            .arg(r.x(), 0, 'f', 1)
                                            .arg(r.y(), 0, 'f', 1)
                                            .arg(r.width(), 0, 'f', 1)
                                            .arg(r.height(), 0, 'f', 1)
                                            .arg(effViewportW)
                                            .arg(effViewportH);
                    issues.append(msg);
                    violations.append(makeViolation(QStringLiteral("viewport-bounds"), objName, msg, r));
                }
            }
        }

        if (checkClip && !allowlisted && item != rootItem && item->width() > 0.0 && item->height() > 0.0
            && (isPobControl || item->inherits("QQuickText"))) {
            QQuickItem* anc = item->parentItem();
            while (anc) {
                if (isScrollContainer(anc)) {
                    anc = nullptr;
                    break;
                }
                if (anc->clip() && anc->width() > 0.0 && anc->height() > 0.0) {
                    const QRectF inAnc = item->mapRectToItem(anc, QRectF(0.0, 0.0, item->width(), item->height()));
                    if (inAnc.left() < -1.0 || inAnc.top() < -1.0
                        || inAnc.right() > anc->width() + 1.0 || inAnc.bottom() > anc->height() + 1.0) {
                        const QString tag = objName.isEmpty()
                            ? (item->parentItem() ? item->parentItem()->objectName() : QStringLiteral("<unnamed>"))
                            : objName;
                        const QString msg = QStringLiteral("Ancestor clip overflow on '%1' inside '%2': (%3,%4 %5x%6) vs (%7x%8)")
                                                .arg(tag, anc->objectName().isEmpty() ? QStringLiteral("<clip>") : anc->objectName())
                                                .arg(inAnc.x(), 0, 'f', 1)
                                                .arg(inAnc.y(), 0, 'f', 1)
                                                .arg(inAnc.width(), 0, 'f', 1)
                                                .arg(inAnc.height(), 0, 'f', 1)
                                                .arg(anc->width(), 0, 'f', 1)
                                                .arg(anc->height(), 0, 'f', 1);
                        issues.append(msg);
                        violations.append(makeViolation(QStringLiteral("clip-overflow"),
                                                        tag,
                                                        msg,
                                                        mapToRootRect(item, rootItem)));
                    }
                    break;
                }
                if (anc == rootItem) break;
                anc = anc->parentItem();
            }
        }

        if (item->inherits("QQuickText")) {
            const QString txt = item->property("text").toString();
            if (!txt.trimmed().isEmpty() && item->width() > 0.0 && item->height() > 0.0) {
                ++checkedTexts;
                const int elide = item->property("elide").toInt();
                const int wrapMode = item->property("wrapMode").toInt();
                const double paintedW = item->property("paintedWidth").toDouble();
                const double paintedH = item->property("paintedHeight").toDouble();
                const QString tag = objName.isEmpty()
                    ? (item->parentItem() ? item->parentItem()->objectName() : QStringLiteral("<unnamed>"))
                    : objName;

                if (!allowlisted && elide == 0 && wrapMode == 0 && paintedW > item->width() + 2.0) {
                    if (!isInsideHorizScrollableFlickable(item)) {
                        const QString msg = QStringLiteral("Text overflow on '%1' text='%2': paintedWidth=%3 > width=%4")
                                                .arg(tag, txt.left(40))
                                                .arg(paintedW)
                                                .arg(item->width());
                        issues.append(msg);
                        violations.append(makeViolation(QStringLiteral("text-overflow-x"),
                                                        tag,
                                                        msg,
                                                        mapToRootRect(item, rootItem)));
                    }
                }

                if (checkVertText && !allowlisted && wrapMode == 0 && paintedH > item->height() + 1.0) {
                    if (!isInsideVertScrollableFlickable(item)) {
                        const QString msg = QStringLiteral("Vertical text overflow on '%1' text='%2': paintedHeight=%3 > height=%4")
                                                .arg(tag, txt.left(40))
                                                .arg(paintedH)
                                                .arg(item->height());
                        issues.append(msg);
                        violations.append(makeViolation(QStringLiteral("text-overflow-y"),
                                                        tag,
                                                        msg,
                                                        mapToRootRect(item, rootItem)));
                    }
                }
            }
        }

        if (checkOverlap && !allowlisted && item->parentItem() && isInteractiveCandidate(item)) {
            siblingGroups[item->parentItem()].append(item);
        }
    }

    if (checkOverlap) {
        for (auto it = siblingGroups.constBegin(); it != siblingGroups.constEnd(); ++it) {
            const QList<QQuickItem*>& sibs = it.value();
            for (int i = 0; i < sibs.size(); ++i) {
                QQuickItem* a = sibs[i];
                const QRectF ra(a->x(), a->y(), a->width(), a->height());
                for (int j = i + 1; j < sibs.size(); ++j) {
                    QQuickItem* b = sibs[j];
                    if (std::abs(a->z() - b->z()) > 0.01) continue;
                    const QRectF rb(b->x(), b->y(), b->width(), b->height());
                    const QRectF inter = ra.intersected(rb);
                    if (inter.width() > 2.0 && inter.height() > 2.0) {
                        const QString nameA = a->objectName().isEmpty()
                            ? QString::fromLatin1(a->metaObject()->className()) : a->objectName();
                        const QString nameB = b->objectName().isEmpty()
                            ? QString::fromLatin1(b->metaObject()->className()) : b->objectName();
                        const QString msg = QStringLiteral("Sibling hitbox overlap between '%1' and '%2' (%3x%4)")
                                                .arg(nameA, nameB)
                                                .arg(inter.width(), 0, 'f', 1)
                                                .arg(inter.height(), 0, 'f', 1);
                        const QRectF mapped = rootItem
                            ? it.key()->mapRectToItem(rootItem, inter)
                            : inter;
                        issues.append(msg);
                        violations.append(makeViolation(QStringLiteral("sibling-overlap"),
                                                        nameA + QStringLiteral(" & ") + nameB,
                                                        msg,
                                                        mapped));
                    }
                }
            }
        }
    }

    result.insert(QStringLiteral("ok"), issues.isEmpty());
    result.insert(QStringLiteral("issues"), issues);
    result.insert(QStringLiteral("violations"), violations);
    result.insert(QStringLiteral("checkedItems"), checkedItems);
    result.insert(QStringLiteral("checkedTexts"), checkedTexts);
    return result;
}

QString UiTestHelper::captureAnnotatedFailure(QObject* windowOrItem,
                                              const QVariantList& issues,
                                              const QString& outPath) const {
    QQuickWindow* win = qobject_cast<QQuickWindow*>(windowOrItem);
    if (!win) {
        if (auto* item = qobject_cast<QQuickItem*>(windowOrItem)) {
            win = item->window();
        }
    }

    QString finalPath = outPath;
    if (finalPath.isEmpty()) {
        const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_hhmmss_zzz"));
        finalPath = repoRootDir()
            + QStringLiteral("/build-win/ui-test-artifacts/failure_")
            + stamp
            + QStringLiteral(".png");
    }

    QFileInfo fi(finalPath);
    QDir().mkpath(fi.absolutePath());

    QImage img;
    if (win) {
        img = win->grabWindow();
    }
    if (img.isNull()) {
        const int w = win ? std::max(1, win->width()) : 800;
        const int h = win ? std::max(1, win->height()) : 600;
        img = QImage(w, h, QImage::Format_ARGB32);
        img.fill(QColor(24, 24, 28));
    } else if (img.format() != QImage::Format_ARGB32 && img.format() != QImage::Format_ARGB32_Premultiplied) {
        img = img.convertToFormat(QImage::Format_ARGB32);
    }

    const qreal dpr = img.devicePixelRatio() > 0.0 ? img.devicePixelRatio() : 1.0;

    QPainter painter(&img);
    painter.setRenderHint(QPainter::Antialiasing, true);
    QFont labelFont(QStringLiteral("Liberation Sans"), 9);
    painter.setFont(labelFont);
    QFontMetrics fm(labelFont);

    QJsonArray jsonIssues;
    int bannerRow = 0;
    for (const QVariant& entry : issues) {
        if (entry.typeId() == QMetaType::QVariantMap) {
            const QVariantMap m = entry.toMap();
            const qreal x = m.value(QStringLiteral("x")).toDouble() * dpr;
            const qreal y = m.value(QStringLiteral("y")).toDouble() * dpr;
            const qreal w = m.value(QStringLiteral("width")).toDouble() * dpr;
            const qreal h = m.value(QStringLiteral("height")).toDouble() * dpr;
            const QString kind = m.value(QStringLiteral("kind")).toString();
            const QString objName = m.value(QStringLiteral("objectName")).toString();
            const QString msg = m.value(QStringLiteral("message")).toString();

            QJsonObject jo = QJsonObject::fromVariantMap(m);
            jsonIssues.append(jo);

            if (w > 0.0 && h > 0.0) {
                const QRectF box(x, y, w, h);
                painter.fillRect(box, QColor(255, 48, 48, 36));
                painter.setPen(QPen(QColor(255, 48, 48), 2));
                painter.drawRect(box);

                const QString tag = kind.isEmpty() ? objName : (kind + QStringLiteral(": ") + objName);
                const QString label = tag.left(64);
                const QSize textSz = fm.size(Qt::TextSingleLine, label);
                const qreal lx = std::clamp(x, 2.0, std::max(2.0, qreal(img.width() - textSz.width() - 10)));
                const qreal ly = (y >= textSz.height() + 8.0) ? (y - textSz.height() - 6.0) : (y + 2.0);
                const QRectF pill(lx, ly, textSz.width() + 8, textSz.height() + 4);
                painter.fillRect(pill, QColor(180, 20, 20, 230));
                painter.setPen(Qt::white);
                painter.drawText(pill.adjusted(4, 2, -4, -2), Qt::AlignLeft | Qt::AlignVCenter, label);
            } else if (!msg.isEmpty()) {
                const QRectF pill(8.0, 8.0 + bannerRow * (fm.height() + 8), img.width() - 16.0, fm.height() + 6);
                painter.fillRect(pill, QColor(160, 20, 20, 220));
                painter.setPen(Qt::white);
                painter.drawText(pill.adjusted(6, 2, -6, -2), Qt::AlignLeft | Qt::AlignVCenter, msg.left(120));
                ++bannerRow;
            }
        } else {
            const QString msg = entry.toString();
            jsonIssues.append(msg);
            if (!msg.isEmpty()) {
                const QRectF pill(8.0, 8.0 + bannerRow * (fm.height() + 8), img.width() - 16.0, fm.height() + 6);
                painter.fillRect(pill, QColor(160, 20, 20, 220));
                painter.setPen(Qt::white);
                painter.drawText(pill.adjusted(6, 2, -6, -2), Qt::AlignLeft | Qt::AlignVCenter, msg.left(120));
                ++bannerRow;
            }
        }
    }
    painter.end();

    img.save(finalPath);

    QJsonObject rootJson;
    QJsonObject vpObj;
    vpObj.insert(QStringLiteral("width"), win ? win->width() : img.width());
    vpObj.insert(QStringLiteral("height"), win ? win->height() : img.height());
    rootJson.insert(QStringLiteral("viewport"), vpObj);
    rootJson.insert(QStringLiteral("issues"), jsonIssues);
    if (win && win->contentItem()) {
        rootJson.insert(QStringLiteral("sceneTree"), dumpItemTree(win->contentItem(), 0));
    }

    QFile treeFile(finalPath + QStringLiteral(".tree.json"));
    if (treeFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        treeFile.write(QJsonDocument(rootJson).toJson(QJsonDocument::Indented));
    }

    return finalPath;
}

bool UiTestHelper::loadTestBuild(const QString& relPath) {
    if (!m_engine || relPath.isEmpty()) return false;

    QString resolved;
    const QFileInfo direct(relPath);
    if (direct.exists() && direct.isFile()) {
        resolved = direct.absoluteFilePath();
    } else {
        const QString fromRepo = QDir(repoRootDir()).filePath(relPath);
        if (QFileInfo::exists(fromRepo)) {
            resolved = QFileInfo(fromRepo).absoluteFilePath();
        }
    }
    if (resolved.isEmpty()) return false;

    QFile f(resolved);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return false;
    const QString xml = QString::fromUtf8(f.readAll());
    if (xml.trimmed().isEmpty()) return false;

    const bool ok = m_engine->loadBuildXML(xml);
    if (!ok) return false;

    m_engine->recalculate();
    emit m_engine->modeChanged();
    emit m_engine->viewChanged();
    emit m_engine->currentModeChanged();
    emit m_engine->currentViewChanged();
    return true;
}

bool UiTestHelper::mockLuaGlobal(const QString& fnName, const QString& luaBody) {
    if (!m_engine || fnName.isEmpty()) return false;
    lua_State* L = m_engine->state();
    if (!L) return false;

    const QByteArray nameUtf8 = fnName.toUtf8();
    if (!m_mockBackupRefs.contains(fnName)) {
        lua_getglobal(L, nameUtf8.constData());
        const int ref = luaL_ref(L, LUA_REGISTRYINDEX);
        m_mockBackupRefs.insert(fnName, ref);
    }

    const QByteArray exprChunk = (QStringLiteral("return ") + luaBody).toUtf8();
    int rc = luaL_loadbuffer(L, exprChunk.constData(), exprChunk.size(), nameUtf8.constData());
    if (rc != 0) {
        lua_pop(L, 1);
        const QByteArray fnChunk =
            (QStringLiteral("return function(...)\n") + luaBody + QStringLiteral("\nend")).toUtf8();
        rc = luaL_loadbuffer(L, fnChunk.constData(), fnChunk.size(), nameUtf8.constData());
        if (rc != 0) {
            recordWarning(QStringLiteral("mockLuaGlobal(%1) compile error: %2")
                              .arg(fnName, QString::fromUtf8(lua_tostring(L, -1))));
            lua_pop(L, 1);
            return false;
        }
    }

    if (lua_pcall(L, 0, 1, 0) != 0) {
        recordWarning(QStringLiteral("mockLuaGlobal(%1) eval error: %2")
                          .arg(fnName, QString::fromUtf8(lua_tostring(L, -1))));
        lua_pop(L, 1);
        return false;
    }

    lua_setglobal(L, nameUtf8.constData());
    return true;
}

void UiTestHelper::restoreLuaMocks() {
    if (!m_engine || m_mockBackupRefs.isEmpty()) {
        m_mockBackupRefs.clear();
        return;
    }
    lua_State* L = m_engine->state();
    if (!L) {
        m_mockBackupRefs.clear();
        return;
    }

    for (auto it = m_mockBackupRefs.constBegin(); it != m_mockBackupRefs.constEnd(); ++it) {
        const QByteArray nameUtf8 = it.key().toUtf8();
        const int ref = it.value();
        if (ref == LUA_REFNIL || ref == LUA_NOREF) {
            lua_pushnil(L);
        } else {
            lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
            luaL_unref(L, LUA_REGISTRYINDEX, ref);
        }
        lua_setglobal(L, nameUtf8.constData());
    }
    m_mockBackupRefs.clear();
}

void UiTestHelper::sendKeyClick(QObject* targetWindow, int key, int modifiers) const {
    QQuickWindow* win = qobject_cast<QQuickWindow*>(targetWindow);
    if (!win) {
        if (auto* item = qobject_cast<QQuickItem*>(targetWindow)) {
            win = item->window();
        }
    }
    if (!win) return;
    QTest::keyClick(win, static_cast<Qt::Key>(key), static_cast<Qt::KeyboardModifiers>(modifiers));
}

void UiTestHelper::resetEngineForTest() {
    restoreLuaMocks();
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
