#include "ConfigModel.h"
#include "LuaEngine.h"

#include <QHash>
#include <QDebug>

ConfigModel::ConfigModel(QObject* parent) : QAbstractListModel(parent) {}

int ConfigModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_options.size();
}

QHash<int, QByteArray> ConfigModel::roleNames() const {
    return {
        { NameRole, "name" },
        { LabelRole, "label" },
        { TypeRole, "type" },
        { ValueRole, "value" },
        { OptionsRole, "options" },
        { SectionRole, "section" },
        { TooltipRole, "tooltip" },
    };
}

QVariant ConfigModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_options.size())
        return QVariant();
    const QVariantMap& m = m_options.at(index.row());
    switch (role) {
        case NameRole: return m.value("name");
        case LabelRole: return m.value("label");
        case TypeRole: return m.value("type");
        case ValueRole: return m.value("value");
        case OptionsRole: return m.value("options");
        case SectionRole: return m.value("section");
        case TooltipRole: return m.value("tooltip");
        default: return QVariant();
    }
}

QVariant ConfigModel::get(int row) const {
    if (row < 0 || row >= m_options.size())
        return QVariant();
    return m_options.at(row);
}

void ConfigModel::refresh(LuaEngine* engine) {
    if (!engine)
        return;
    // Throttle by the engine's build output revision so we only rebuild when the
    // build actually recalculates (config value changes flag a rebuild via
    // buildFlag, which bumps outputRevision).
    int rev = engine->getPath("main.modes.BUILD.outputRevision").toInt();
    if (m_loaded && rev == m_lastRev)
        return;
    m_lastRev = rev;
    QVariant out = engine->getConfigOptions();
    if (out.typeId() != QMetaType::QVariantList) {
        qDebug().noquote() << "[ConfigModel] refresh -> no options";
        return;
    }
    QVariantList opts = out.toList();
    // Only rebuild (which resets the model and forces the QML Repeater to
    // recreate all of its delegates) when the actual option data changed.
    // A bare outputRevision bump with identical options must NOT reset the
    // model, otherwise the ~570-delegate configView Repeater is rebuilt every
    // frame and the GUI thread freezes.
    if (m_loaded && opts == m_lastOpts)
        return;
    m_loaded = true;
    m_lastOpts = opts;
    beginResetModel();
    m_options.clear();
    m_options.reserve(opts.size());
    for (const QVariant& v : opts)
        m_options.append(v.toMap());
    endResetModel();
    emit countChanged();
    qDebug().noquote() << "[ConfigModel] refresh -> options=" << m_options.size();
}
