#pragma once
#include <QAbstractListModel>
#include <QString>
#include <QVariantList>

class LuaEngine;

// One entry in the LIST-mode build library. Mirrors the shape produced by
// BuildListHelpers.ScanFolder and stored in main.modes.LIST.list: a build
// (.xml file) or a folder. Build entries carry buildName/fileName/fullFileName/
// subPath/level/className/ascendClassName; folder entries carry folderName.
struct BuildListEntry {
    QString displayName;   // buildName for builds, folderName for folders
    bool isFolder = false;
    QString fileName;      // "MyBuild.xml" (build only)
    QString fullFileName;  // absolute path
    QString buildName;     // display name without extension (build only)
    QString folderName;    // folder name (folder only)
    QString className;     // parsed class (build only)
    QString ascendClassName;
    int level = 0;
    QString subPath;
};

// Phase 3: QAbstractListModel mirror of main.modes.LIST.list (the scanned build
// library). Preferred over a raw QVariantList so QML ListView can bind directly
// and benefit from incremental change signals. refresh(LuaEngine*) re-reads the
// list from Lua (only while the engine is in LIST mode) and, when the set of
// entries changes size, does a full resetModel() + countChanged(); when only
// contents change it emits dataChanged() for the affected rows. All reads are
// defensive (an absent LIST.list yields an empty list).
class BuildListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit BuildListModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_entries.size(); }

    // Re-read the build library from the engine. Safe to call every frame; only
    // acts when the engine is in LIST mode (main.modes.LIST.list is populated).
    void refresh(LuaEngine* engine);

signals:
    void countChanged();

private:
    enum Roles : int {
        DisplayNameRole = Qt::UserRole + 1,
        IsFolderRole,
        FileNameRole,
        FullFileNameRole,
        BuildNameRole,
        FolderNameRole,
        ClassNameRole,
        AscendClassNameRole,
        LevelRole,
        SubPathRole
    };

    QList<BuildListEntry> m_entries;
};
