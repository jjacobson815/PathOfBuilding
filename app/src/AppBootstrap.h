#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QQmlEngine;
class LuaEngine;
class Theme;
class ColorText;
class BuildModel;
class SocketGroupModel;
class BuildListModel;
class TreeModel;
class TreeGroupModel;
class TreeConnectorModel;
class TreeViewController;
class ItemSlotModel;
class JewelSocketModel;
class CalcModel;
class ConfigModel;
class NotesController;
class PartyModel;
class SaveLoadModel;

// Shared Qt/Lua/model bootstrap used by both pob-qt (app/src/main.cpp) and
// pob-ui-test (app/tests/ui/main.cpp) so the two binaries stay in lockstep.
class AppBootstrap : public QObject {
    Q_OBJECT
public:
    struct Options {
        QString srcDir;
        QString runtimeDir;
        QString hostFile;
        QStringList launchArgs;
        bool devMode = false;
        bool connectLogToDebug = true;
    };

    explicit AppBootstrap(QObject* parent = nullptr);
    ~AppBootstrap() override = default;

    static QString resolveDir(const QString& cliVal, const QString& subdir);
    static QString resolveHost(const QString& cliVal);
    static void registerAppFonts(const QString& runtimeDir);

    bool init(const Options& opts);
    void attachToQmlEngine(QQmlEngine* qmlEngine, bool captureMode) const;

    LuaEngine* engine() const { return m_engine; }
    const QString& srcDir() const { return m_srcDir; }
    const QString& runtimeDir() const { return m_runtimeDir; }
    const QString& hostFile() const { return m_hostFile; }

private:
    QString m_srcDir;
    QString m_runtimeDir;
    QString m_hostFile;

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
    PartyModel* m_partyModel = nullptr;
    SaveLoadModel* m_saveLoadModel = nullptr;
};
