#pragma once
#include <QAbstractListModel>
#include <QVariantMap>
#include <QVariantList>

class LuaEngine;

// Phase 5d: configuration-options browser model for the CONFIG view. One row
// per config option (src/Modules/ConfigOptions.lua), each carrying name/label/
// type/value/options/section/tooltip. refresh() pulls the data from the Lua
// bridge (pob_getConfigOptions) and rebuilds only when the engine's build
// output revision changes (throttled by build.outputRevision) so the per-frame
// call from the frame loop is cheap. Linked ONLY into pob-qt (never
// pob-selftest) like CalcModel/ItemModel/SkillModel.
class ConfigModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit ConfigModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_options.size(); }

    // Pull the config options from the engine via LuaEngine::getConfigOptions();
    // throttled by the engine's build.outputRevision so we only rebuild when the
    // build actually recalculates (config value changes flag a rebuild via
    // buildFlag, which bumps outputRevision).
    void refresh(LuaEngine* engine);
    // QML helper: return the row's map by index.
    Q_INVOKABLE QVariant get(int row) const;

signals:
    void countChanged();

private:
    enum Roles : int {
        NameRole = Qt::UserRole + 1,
        LabelRole,
        TypeRole,
        ValueRole,
        OptionsRole,
        SectionRole,
        TooltipRole,
    };

    QList<QVariantMap> m_options;
    QVariantList m_lastOpts;   // last raw options list, for change detection
    int m_lastRev = -1;
    bool m_loaded = false;
};
