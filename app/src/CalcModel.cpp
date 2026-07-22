#include "CalcModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

CalcModel::CalcModel(QObject* parent) : QAbstractListModel(parent) {}

int CalcModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_sections.size();
}

QHash<int, QByteArray> CalcModel::roleNames() const {
    return {
        { LabelRole, "label" },
        { StatsRole, "stats" },
    };
}

QVariant CalcModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_sections.size())
        return QVariant();
    const QVariantMap& m = m_sections.at(index.row());
    switch (role) {
        case LabelRole: return m.value("label");
        case StatsRole: return m.value("stats");
        default: return QVariant();
    }
}

QVariant CalcModel::get(int row) const {
    if (row < 0 || row >= m_sections.size())
        return QVariant();
    return m_sections.at(row);
}

void CalcModel::setSections(const QVariantList& sections) {
    beginResetModel();
    m_sections.clear();
    m_sections.reserve(sections.size());
    for (const QVariant& v : sections)
        m_sections.append(v.toMap());
    endResetModel();
    emit countChanged();
}

void CalcModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // Throttle by the engine's calc output revision so we only rebuild the
    // (somewhat expensive) formatted output when the build actually recalculates.
    int rev = engine->getPath("main.modes.BUILD.outputRevision").toInt();
    if (m_loaded && rev == m_lastRev)
        return;
    m_lastRev = rev;
    m_loaded = true;
    QVariant out = engine->getCalcOutput();
    if (out.typeId() != QMetaType::QVariantMap) {
        qDebug().noquote() << "[CalcModel] refresh -> no output";
        return;
    }
    const QVariantMap o = out.toMap();
    QVariantMap summary = o.value("summary").toMap();
    QVariantList sections = o.value("sections").toList();
    m_summary = summary;
    emit summaryChanged();
    setSections(sections);
    qDebug().noquote() << "[CalcModel] refresh -> sections=" << m_sections.size()
             << " summary.life=" << summary.value("life").toInt();
}
