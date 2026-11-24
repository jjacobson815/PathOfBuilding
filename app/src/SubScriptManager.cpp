#include "SubScriptManager.h"
#include "LuaEngine.h"

struct SubScriptManager::Impl {};

SubScriptManager::SubScriptManager(LuaEngine* engine)
    : QObject(engine), m_impl(std::make_unique<Impl>()), m_engine(engine) {}

SubScriptManager::~SubScriptManager() {
    shutdown();
}

int SubScriptManager::launch(const QString& /*scriptText*/,
                             const QString& /*funcListCsv*/,
                             const QString& /*subListCsv*/,
                             const QVariantList& /*args*/) {
    return 0;
}

void SubScriptManager::abort(int /*id*/) {}

bool SubScriptManager::isRunning(int /*id*/) {
    return false;
}

void SubScriptManager::shutdown() {}

bool SubScriptManager::registerUriScheme() {
    return false;
}

QString SubScriptManager::parseStartupUri(const QStringList& args) {
    for (int i = 1; i < args.size(); ++i) {
        if (args[i].startsWith(QStringLiteral("pob://"), Qt::CaseInsensitive))
            return args[i];
    }
    return {};
}
