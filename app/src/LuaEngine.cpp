#include "LuaEngine.h"
#include "selftest_checks.h"
#include "luabridge.h"
#include "TextMetrics.h"

#include <QDebug>
#ifndef POB_NO_GUI
#include <QClipboard>
#include <QGuiApplication>
#include <QDesktopServices>
#include <QUrl>
#endif
#include <QDir>
#include <QDateTime>
#include <QFileInfo>
#include <QStandardPaths>
#include <lauxlib.h>

// Part 1.4: Win32 file attributes for OneDrive-dehydration detection
// (l_pob_fileAttributes). NOMINMAX so windows.h's min/max macros don't collide
// with std::min/max used via <algorithm> below.
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#ifndef FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
#define FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS 0x00400000
#endif
#ifndef FILE_ATTRIBUTE_RECALL_ON_OPEN
#define FILE_ATTRIBUTE_RECALL_ON_OPEN 0x00040000
#endif
#endif

#include <zlib.h>
#include <curl/curl.h>

#include <algorithm>
#include <string>
#include <vector>

LuaEngine::LuaEngine(QObject* parent) : QObject(parent) {}

LuaEngine::~LuaEngine() {
    if (m_L) lua_close(m_L);
}

LuaEngine* LuaEngine::selfOf(lua_State* L) {
    lua_getfield(L, LUA_REGISTRYINDEX, "pob_engine");
    LuaEngine* self = static_cast<LuaEngine*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return self;
}

bool LuaEngine::init(const QString& srcDir, const QString& runtimeDir, const QString& hostFile,
                     const QStringList& launchArgs) {
    m_srcDir = srcDir;
    m_runtimeDir = runtimeDir;
    m_launchArgs = launchArgs;
    m_clock.start();   // monotonic clock backing GetTime (ms since init)

    // GetUserPath() must return the Documents dir; the engine appends
    // "/Path of Building/" (Main.lua), so returning Documents/Path of Building
    // would double-append and hide every existing user's build library. The old
    // value (QDir::tempPath()+"/pob-qt") pointed at an OS-wipeable throwaway dir,
    // so existing users saw an empty library + reset settings. Fall back to
    // ~/Documents if the standard location is unavailable.
    m_userDir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (m_userDir.isEmpty())
        m_userDir = QDir::homePath() + "/Documents";
    QDir().mkpath(m_userDir);

    // Phase 1.2a: create the .tgf-backed text-measurement engine before the host
    // bootstrap runs, so DrawStringWidth/DrawStringCursorIndex are real from the
    // first OnInit layout pass. Fonts load lazily on first use. The bitmap-font
    // metrics ship under <runtime>/SimpleGraphic/Fonts.
    m_textMetrics = new TextMetrics(this);
    m_textMetrics->setFontDir(m_runtimeDir + "/SimpleGraphic/Fonts");

    // One-time libcurl global init (idempotent across engine instances).
    static bool curlReady = false;
    if (!curlReady) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
        curlReady = true;
    }

    m_L = luaL_newstate();
    if (!m_L) {
        qCritical() << "luaL_newstate failed";
        return false;
    }
    luaL_openlibs(m_L);

    // Stash `this` so the C callbacks can reach the engine instance.
    lua_pushlightuserdata(m_L, this);
    lua_setfield(m_L, LUA_REGISTRYINDEX, "pob_engine");

    // Register the `pob` bridge table consumed by lua/pob_host.lua.
    static const luaL_Reg pobFuncs[] = {
        { "log",           l_pob_log },
        { "setMainObject", l_pob_setMainObject },
        { "getScriptPath", l_pob_getScriptPath },
        { "getRuntimePath",l_pob_getRuntimePath },
        { "getUserPath",   l_pob_getUserPath },
        { "getTime",       l_pob_getTime },
#ifndef POB_NO_GUI
        { "copy",          l_pob_copy },
        { "paste",         l_pob_paste },
        { "openURL",       l_pob_openURL },
        { "isKeyDown",     l_pob_isKeyDown },
        { "setForeground", l_pob_setForeground },
#endif
        { "makeDir",       l_pob_makeDir },
        { "removeDir",     l_pob_removeDir },
        { "inflate",       l_pob_inflate },
        { "deflate",       l_pob_deflate },
        { "http",          l_pob_http },
        { "listDir",       l_pob_listDir },
        { "stringWidth",       l_pob_stringWidth },
        { "stringCursorIndex", l_pob_stringCursorIndex },
        // Part 1.4: cloud robustness. GUI-independent (registered even headless):
        // fileAttributes backs GetCloudProvider; the two *Popup fns emit Qt
        // signals the QML host turns into real dialogs (no-op with no listener).
        { "fileAttributes",    l_pob_fileAttributes },
        { "cloudErrorPopup",   l_pob_cloudErrorPopup },
        { "pathErrorPopup",    l_pob_pathErrorPopup },
        // Part 1.4 (bullet 5): toast mirror change notification (Lua-initiated
        // push, same pattern as cloudErrorPopup/pathErrorPopup above).
        { "toastsChanged",     l_pob_toastsChanged },
        { nullptr, nullptr }
    };
    lua_newtable(m_L);
    luaL_setfuncs(m_L, pobFuncs, 0);
    lua_setglobal(m_L, "pob");

    // Path globals the host bootstrap prepends to module loads.
    lua_pushstring(m_L, m_srcDir.toUtf8().constData());   lua_setglobal(m_L, "_SRC_DIR");
    lua_pushstring(m_L, m_runtimeDir.toUtf8().constData()); lua_setglobal(m_L, "_RUNTIME_DIR");
    lua_pushstring(m_L, m_userDir.toUtf8().constData());  lua_setglobal(m_L, "_USER_DIR");
    // Directory containing this host bootstrap; used to locate bundled Lua
    // shims (lcurl/safe.lua, lzip.lua) via package.path in pob_host.lua.
    lua_pushstring(m_L, QFileInfo(hostFile).dir().absolutePath().toUtf8().constData());
    lua_setglobal(m_L, "_POB_LUA_DIR");

    // CLI `arg` table (Lua convention: arg[0]=program, arg[1..]=params). Set
    // before the host bootstrap runs OnInit so Main.lua can read arg[1] as an
    // open-on-launch build file / import URL. pob_host.lua keeps this via
    // `arg = arg or {}` instead of clobbering it with an empty table.
    lua_newtable(m_L);
    for (int i = 0; i < m_launchArgs.size(); i++) {
        lua_pushinteger(m_L, i);
        lua_pushstring(m_L, m_launchArgs[i].toUtf8().constData());
        lua_settable(m_L, -3);
    }
    lua_setglobal(m_L, "arg");

    if (luaL_dofile(m_L, hostFile.toUtf8().constData()) != LUA_OK) {
        qCritical() << "Host bootstrap error:" << lua_tostring(m_L, -1);
        lua_pop(m_L, 1);
        return false;
    }
    emit engineReady();
    return true;
}

// --- `pob` C callbacks ------------------------------------------------------

int LuaEngine::l_pob_log(lua_State* L) {
    LuaEngine* self = selfOf(L);
    QString msg = (lua_gettop(L) >= 1) ? QString::fromUtf8(lua_tostring(L, 1)) : QString();
    emit self->logMessage(msg);
    return 0;
}

int LuaEngine::l_pob_setMainObject(lua_State* L) {
    (void)L; // main object is read via the `main` global; nothing to store.
    return 0;
}

int LuaEngine::l_pob_getScriptPath(lua_State* L) {
    lua_pushstring(L, selfOf(L)->m_srcDir.toUtf8().constData());
    return 1;
}

int LuaEngine::l_pob_getRuntimePath(lua_State* L) {
    lua_pushstring(L, selfOf(L)->m_runtimeDir.toUtf8().constData());
    return 1;
}

int LuaEngine::l_pob_getUserPath(lua_State* L) {
    lua_pushstring(L, selfOf(L)->m_userDir.toUtf8().constData());
    return 1;
}

int LuaEngine::l_pob_getTime(lua_State* L) {
    // Legacy GetTime() semantics: monotonic milliseconds since program start,
    // NOT epoch. The engine uses it for frame deltas, timers and unique markers;
    // a monotonic clock avoids wall-clock jumps (NTP/DST) skewing those deltas.
    lua_pushnumber(L, double(selfOf(L)->m_clock.elapsed()));
    return 1;
}

// DrawStringWidth(height, font, text) — real metrics via the .tgf TextMetrics
// engine (replaces the pob_host.lua stub that returned 1). font may be nil → FIXED.
int LuaEngine::l_pob_stringWidth(lua_State* L) {
    LuaEngine* self = selfOf(L);
    const int height = (int)lua_tonumber(L, 1);
    const QString font = lua_isstring(L, 2) ? QString::fromUtf8(lua_tostring(L, 2)) : QString();
    const QString text = lua_isstring(L, 3) ? QString::fromUtf8(lua_tostring(L, 3)) : QString();
    const int w = self->m_textMetrics ? self->m_textMetrics->stringWidth(height, font, text) : 1;
    lua_pushinteger(L, w);
    return 1;
}

// DrawStringCursorIndex(height, font, text, cursorX, cursorY) — caret hit-testing
// (replaces the stub that returned 0). Returns a 0-based char offset.
int LuaEngine::l_pob_stringCursorIndex(lua_State* L) {
    LuaEngine* self = selfOf(L);
    const int height = (int)lua_tonumber(L, 1);
    const QString font = lua_isstring(L, 2) ? QString::fromUtf8(lua_tostring(L, 2)) : QString();
    const QString text = lua_isstring(L, 3) ? QString::fromUtf8(lua_tostring(L, 3)) : QString();
    const int curX = (int)lua_tonumber(L, 4);
    const int curY = (int)lua_tonumber(L, 5);
    const int idx = self->m_textMetrics
        ? self->m_textMetrics->stringCursorIndex(height, font, text, curX, curY) : 0;
    lua_pushinteger(L, idx);
    return 1;
}

// Part 1.4: pob.fileAttributes(path) -> { exists, offline, recallOnDataAccess,
// recallOnOpen, reparsePoint }. Backs the real GetCloudProvider Lua global. On
// Windows the RECALL_ON_* / OFFLINE flags mark a OneDrive "files on demand"
// dehydrated placeholder — the exact state whose transient read failure trips
// the engine's errorReadingSettings path. On non-Windows only `exists` is set.
int LuaEngine::l_pob_fileAttributes(lua_State* L) {
    if (lua_gettop(L) < 1 || !lua_isstring(L, 1)) { lua_pushnil(L); return 1; }
    QString path = QString::fromUtf8(lua_tostring(L, 1));
    lua_newtable(L);
    lua_pushboolean(L, QFileInfo::exists(path) ? 1 : 0);
    lua_setfield(L, -2, "exists");
#ifdef Q_OS_WIN
    const std::wstring wpath = path.toStdWString();
    DWORD attrs = GetFileAttributesW(wpath.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES) {
        lua_pushboolean(L, (attrs & FILE_ATTRIBUTE_OFFLINE) != 0);
        lua_setfield(L, -2, "offline");
        lua_pushboolean(L, (attrs & FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS) != 0);
        lua_setfield(L, -2, "recallOnDataAccess");
        lua_pushboolean(L, (attrs & FILE_ATTRIBUTE_RECALL_ON_OPEN) != 0);
        lua_setfield(L, -2, "recallOnOpen");
        lua_pushboolean(L, (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0);
        lua_setfield(L, -2, "reparsePoint");
    }
#endif
    return 1;
}

// Part 1.4: pob.cloudErrorPopup(path, provider, status) — the engine's
// OpenCloudErrorPopup hands off here; we emit cloudErrorRequested so the QML host
// opens a real MessagePopup. No-op (but harmless) when nothing is connected
// (headless / pob-selftest).
int LuaEngine::l_pob_cloudErrorPopup(lua_State* L) {
    LuaEngine* self = selfOf(L);
    QString path     = lua_isstring(L, 1) ? QString::fromUtf8(lua_tostring(L, 1)) : QString();
    QString provider = lua_isstring(L, 2) ? QString::fromUtf8(lua_tostring(L, 2)) : QString();
    QString status   = lua_isstring(L, 3) ? QString::fromUtf8(lua_tostring(L, 3)) : QString();
    if (self) emit self->cloudErrorRequested(path, provider, status);
    return 0;
}

// Part 1.4: pob.pathErrorPopup(invalidPath, errMsg) — the engine's OpenPathPopup
// hands off here; we emit pathErrorRequested so the QML host opens a real
// MessagePopup.
int LuaEngine::l_pob_pathErrorPopup(lua_State* L) {
    LuaEngine* self = selfOf(L);
    QString invalidPath = lua_isstring(L, 1) ? QString::fromUtf8(lua_tostring(L, 1)) : QString();
    QString errMsg      = lua_isstring(L, 2) ? QString::fromUtf8(lua_tostring(L, 2)) : QString();
    if (self) emit self->pathErrorRequested(invalidPath, errMsg);
    return 0;
}

// Part 1.4 (bullet 5): pob.toastsChanged() -- the pob_host.lua ToastNotification
// wrap calls this after every Add/Update/Remove/Clear; we emit toastsChanged()
// so the QML host re-fetches the current list via getToasts(). No-op (but
// harmless) when nothing is connected (headless / pob-selftest).
int LuaEngine::l_pob_toastsChanged(lua_State* L) {
    LuaEngine* self = selfOf(L);
    if (self) emit self->toastsChanged();
    return 0;
}

int LuaEngine::l_pob_copy(lua_State* L) {
#ifndef POB_NO_GUI
    if (qGuiApp) {
        QString text = (lua_gettop(L) >= 1) ? QString::fromUtf8(lua_tostring(L, 1)) : QString();
        qGuiApp->clipboard()->setText(text);
    }
#endif
    return 0;
}

int LuaEngine::l_pob_paste(lua_State* L) {
    QString text;
#ifndef POB_NO_GUI
    text = (qGuiApp && qGuiApp->clipboard()) ? qGuiApp->clipboard()->text() : QString();
#endif
    lua_pushstring(L, text.toUtf8().constData());
    return 1;
}

int LuaEngine::l_pob_openURL(lua_State* L) {
#ifndef POB_NO_GUI
    if (lua_gettop(L) >= 1)
        QDesktopServices::openUrl(QUrl(QString::fromUtf8(lua_tostring(L, 1))));
#endif
    return 0;
}

// MakeDir(path) -> ok[, errMsg]. The engine's contract (13 sites, incl.
// pob_createFolder and Main.lua folder ops) is (ok, errMsg): the old version
// returned nothing, so `if not res` was always true and every create/rename
// reported false failure. mkpath is idempotent (returns true if the dir
// already exists), matching legacy MakeDir.
int LuaEngine::l_pob_makeDir(lua_State* L) {
    if (lua_gettop(L) < 1 || !lua_isstring(L, 1)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "MakeDir: missing path");
        return 2;
    }
    QString path = QString::fromUtf8(lua_tostring(L, 1));
    if (QDir().mkpath(path)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushboolean(L, 0);
    lua_pushstring(L, "MakeDir: could not create directory");
    return 2;
}

// RemoveDir(path) -> ok[, errMsg]. A path that is already gone counts as
// success (idempotent delete), matching legacy RemoveDir.
int LuaEngine::l_pob_removeDir(lua_State* L) {
    if (lua_gettop(L) < 1 || !lua_isstring(L, 1)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "RemoveDir: missing path");
        return 2;
    }
    QDir dir(QString::fromUtf8(lua_tostring(L, 1)));
    if (!dir.exists() || dir.removeRecursively()) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushboolean(L, 0);
    lua_pushstring(L, "RemoveDir: could not remove directory");
    return 2;
}

// IsKeyDown(name) -> bool. Real modifier state via the platform keyboard
// modifiers (CTRL/SHIFT/ALT — the only names the engine branches on outside
// event handlers). Other key names return false. Headless (POB_NO_GUI): the
// pob.isKeyDown bridge is absent and the Lua wrapper returns false.
int LuaEngine::l_pob_isKeyDown(lua_State* L) {
    bool down = false;
#ifndef POB_NO_GUI
    // Must confirm a real QGuiApplication: the `qGuiApp` macro is a static_cast
    // that stays non-null under a plain QCoreApplication (e.g. `pob-qt --headless`),
    // so calling QGuiApplication::queryKeyboardModifiers() there crashes in
    // Qt6Gui. qobject_cast returns null unless the instance really is GUI. The
    // engine calls IsKeyDown during boot (devMode CTRL/ALT check), so this path
    // IS hit headlessly.
    auto* gui = qobject_cast<QGuiApplication*>(QCoreApplication::instance());
    if (gui && lua_gettop(L) >= 1 && lua_isstring(L, 1)) {
        QString k = QString::fromUtf8(lua_tostring(L, 1)).toUpper();
        Qt::KeyboardModifiers m = QGuiApplication::queryKeyboardModifiers();
        if (k == "CTRL")       down = m.testFlag(Qt::ControlModifier);
        else if (k == "SHIFT") down = m.testFlag(Qt::ShiftModifier);
        else if (k == "ALT")   down = m.testFlag(Qt::AltModifier);
    }
#endif
    lua_pushboolean(L, down ? 1 : 0);
    return 1;
}

// SetForeground() -> raise/activate the app window. Emits a signal wired to the
// QQuickWindow in main.cpp. One engine site (PoEAPI.lua, after OAuth); adding
// it prevents an `attempt to call nil` crash if OAuth ever succeeds.
int LuaEngine::l_pob_setForeground(lua_State* L) {
    emit selfOf(L)->foregroundRequested();
    return 0;
}

// --- zlib helpers (standard zlib stream, NOT raw deflate) -------------------

// Inflate a zlib-compressed buffer into `out`. Returns 0 on success.
static int zlib_inflate(const char* src, size_t srcLen, std::string& out) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (inflateInit(&strm) != Z_OK)
        return -1;
    strm.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(src));
    strm.avail_in = static_cast<uInt>(srcLen);
    out.clear();
    char buf[65536];
    int ret;
    do {
        strm.next_out = reinterpret_cast<Bytef*>(buf);
        strm.avail_out = sizeof(buf);
        ret = inflate(&strm, Z_NO_FLUSH);
        if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR) {
            inflateEnd(&strm);
            return -1;
        }
        out.append(buf, sizeof(buf) - strm.avail_out);
    } while (ret != Z_STREAM_END);
    inflateEnd(&strm);
    return 0;
}

// Deflate a buffer into a zlib-compressed stream in `out`. Returns 0 on success.
static int zlib_deflate(const char* src, size_t srcLen, std::string& out) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (deflateInit(&strm, Z_DEFAULT_COMPRESSION) != Z_OK)
        return -1;
    strm.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(src));
    strm.avail_in = static_cast<uInt>(srcLen);
    out.clear();
    char buf[65536];
    int ret;
    do {
        strm.next_out = reinterpret_cast<Bytef*>(buf);
        strm.avail_out = sizeof(buf);
        ret = deflate(&strm, Z_FINISH);
        if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR) {
            deflateEnd(&strm);
            return -1;
        }
        out.append(buf, sizeof(buf) - strm.avail_out);
    } while (ret != Z_STREAM_END);
    deflateEnd(&strm);
    return 0;
}

// Phase 0d: real zlib inflate/deflate bridging the global Inflate/Deflate.
int LuaEngine::l_pob_inflate(lua_State* L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    std::string out;
    if (zlib_inflate(data, len, out) != 0) {
        lua_pushnil(L); // error contract: nil on failure (engine checks `if not xmlText`)
        return 1;
    }
    lua_pushlstring(L, out.data(), out.size());
    return 1;
}

int LuaEngine::l_pob_deflate(lua_State* L) {
    size_t len = 0;
    const char* data = luaL_checklstring(L, 1, &len);
    std::string out;
    if (zlib_deflate(data, len, out) != 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, out.data(), out.size());
    return 1;
}

// --- Synchronous HTTP via libcurl (lcurl.safe shim backend) -----------------

namespace {
struct HttpBuffers {
    std::string body;
    std::string header;
};
size_t http_write_cb(void* contents, size_t size, size_t nmemb, void* userp) {
    size_t realsize = size * nmemb;
    static_cast<std::string*>(userp)->append(static_cast<char*>(contents), realsize);
    return realsize;
}
size_t http_header_cb(void* contents, size_t size, size_t nmemb, void* userp) {
    size_t realsize = size * nmemb;
    static_cast<std::string*>(userp)->append(static_cast<char*>(contents), realsize);
    return realsize;
}
} // namespace

// pob.http(opts) -> { body, header, code, redirect_url, error }
// opts: url, method("GET"|"POST"), postfields, useragent, accept_encoding,
//       proxy, followlocation, ssl_verifypeer, ssl_verifyhost, ipresolve,
//       httpheader (array of strings).
int LuaEngine::l_pob_http(lua_State* L) {
    if (lua_gettop(L) < 1 || !lua_istable(L, 1)) {
        lua_pushnil(L);
        lua_pushstring(L, "pob.http: expected options table");
        return 2;
    }
    auto getstr = [&](const char* k) -> std::string {
        lua_getfield(L, 1, k);
        std::string v = lua_isstring(L, -1) ? lua_tostring(L, -1) : std::string();
        lua_pop(L, 1);
        return v;
    };
    auto getnum = [&](const char* k, long def) -> long {
        lua_getfield(L, 1, k);
        long v = lua_isnumber(L, -1) ? static_cast<long>(lua_tonumber(L, -1)) : def;
        lua_pop(L, 1);
        return v;
    };

    std::string url = getstr("url");
    std::string method = getstr("method");
    std::string postfields = getstr("postfields");
    std::string useragent = getstr("useragent");
    std::string accept_encoding = getstr("accept_encoding");
    std::string proxy = getstr("proxy");
    std::vector<std::string> headers;
    lua_getfield(L, 1, "httpheader");
    if (lua_istable(L, -1)) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_isstring(L, -1))
                headers.push_back(lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    long followlocation = getnum("followlocation", 0);
    long ssl_verifypeer = getnum("ssl_verifypeer", 1);
    long ssl_verifyhost = getnum("ssl_verifyhost", 1);
    long ipresolve = getnum("ipresolve", 0);

    CURL* curl = curl_easy_init();
    if (!curl) {
        lua_pushnil(L);
        lua_pushstring(L, "curl_easy_init failed");
        return 2;
    }
    HttpBuffers bufs;
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, http_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &bufs.body);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, http_header_cb);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &bufs.header);
    // Empty string enables all encodings libcurl supports (matches engine's
    // setopt(OPT_ACCEPT_ENCODING, "")). Non-empty passes the value through.
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING,
                      accept_encoding.empty() ? "" : accept_encoding.c_str());
    if (!useragent.empty())
        curl_easy_setopt(curl, CURLOPT_USERAGENT, useragent.c_str());
    if (followlocation)
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, ssl_verifypeer ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, ssl_verifyhost ? 2L : 0L);
    if (!proxy.empty())
        curl_easy_setopt(curl, CURLOPT_PROXY, proxy.c_str());
    if (ipresolve == 1)
        curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4);
    else if (ipresolve == 2)
        curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V6);

    struct curl_slist* hlist = nullptr;
    for (const auto& h : headers)
        hlist = curl_slist_append(hlist, h.c_str());
    if (hlist)
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, hlist);

    if (method == "POST" || !postfields.empty()) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postfields.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(postfields.size()));
    }

    CURLcode res = curl_easy_perform(curl);
    long response_code = 0;
    char* redirect_url = nullptr;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &redirect_url);
    if (hlist)
        curl_slist_free_all(hlist);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        lua_pushnil(L);
        lua_pushstring(L, curl_easy_strerror(res));
        return 2;
    }

    lua_newtable(L);
    lua_pushlstring(L, bufs.body.data(), bufs.body.size());
    lua_setfield(L, -2, "body");
    lua_pushlstring(L, bufs.header.data(), bufs.header.size());
    lua_setfield(L, -2, "header");
    lua_pushnumber(L, static_cast<double>(response_code));
    lua_setfield(L, -2, "code");
    lua_pushstring(L, redirect_url ? redirect_url : "");
    lua_setfield(L, -2, "redirect_url");
    lua_pushnil(L);
    lua_setfield(L, -2, "error");
    return 1;
}

// --- Read / call helpers ----------------------------------------------------

// Phase 3: directory listing backing the SimpleGraphic NewFileSearch stub.
// pob.listDir(path, dirsOnly, pattern) -> array of { name, modified }.
// `path` is a directory (the engine passes a trailing wildcard which we split
// off into the name filter). `dirsOnly` lists sub-folders only; otherwise files.
int LuaEngine::l_pob_listDir(lua_State* L) {
    if (lua_gettop(L) < 1) { lua_pushnil(L); return 1; }
    std::string path = luaL_checkstring(L, 1);
    bool dirsOnly = (lua_gettop(L) >= 2) ? lua_toboolean(L, 2) : false;
    std::string pat = (lua_gettop(L) >= 3) ? luaL_checkstring(L, 3) : std::string("*");

    QDir dir(QString::fromUtf8(path.c_str()));
    QDir::Filters filters = QDir::NoDotAndDotDot;
    if (dirsOnly) filters |= QDir::Dirs; else filters |= QDir::Files;
    dir.setFilter(filters);
    dir.setNameFilters(QStringList() << QString::fromUtf8(pat.c_str()));

    const QFileInfoList list = dir.entryInfoList();
    lua_newtable(L);
    int idx = 1;
    for (const QFileInfo& fi : list) {
        lua_pushinteger(L, idx++);
        lua_newtable(L);
        lua_pushstring(L, "name");
        lua_pushstring(L, fi.fileName().toUtf8().constData());
        lua_settable(L, -3);
        lua_pushstring(L, "modified");
        lua_pushnumber(L, static_cast<double>(fi.lastModified().toSecsSinceEpoch()));
        lua_settable(L, -3);
        lua_settable(L, -3);
    }
    return 1;
}


QVariant LuaEngine::getGlobal(const QString& name) const {
    if (!m_L) return {};
    lua_getglobal(m_L, name.toUtf8().constData());
    QVariant v = luaToVariant(m_L, -1);
    lua_pop(m_L, 1);
    return v;
}

QVariant LuaEngine::getPath(const QString& path) const {
    if (!m_L) return {};
    QStringList parts = path.split('.');
    lua_getglobal(m_L, parts[0].toUtf8().constData());
    for (int i = 1; i < parts.size(); i++) {
        if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return {}; }
        lua_getfield(m_L, -1, parts[i].toUtf8().constData());
        lua_remove(m_L, -2);
    }
    QVariant v = luaToVariant(m_L, -1);
    lua_pop(m_L, 1);
    return v;
}

QVariant LuaEngine::callGlobal(const QString& name, const QVariantList& args) {
    if (!m_L) return {};
    lua_getglobal(m_L, name.toUtf8().constData());
    if (!lua_isfunction(m_L, -1)) { lua_pop(m_L, 1); return {}; }
    for (const auto& a : args) pushVariant(m_L, a);
    if (lua_pcall(m_L, int(args.size()), 1, 0) != LUA_OK) {
        qCritical() << "callGlobal" << name << "error:" << lua_tostring(m_L, -1);
        lua_pop(m_L, 1);
        return {};
    }
    QVariant v = luaToVariant(m_L, -1);
    lua_pop(m_L, 1);
    return v;
}

QVariant LuaEngine::callMethod(const QString& objectPath, const QString& method, const QVariantList& args) {
    if (!m_L) return {};
    QStringList parts = objectPath.split('.');
    lua_getglobal(m_L, parts[0].toUtf8().constData());
    for (int i = 1; i < parts.size(); i++) {
        if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return {}; }
        lua_getfield(m_L, -1, parts[i].toUtf8().constData());
        lua_remove(m_L, -2);
    }
    if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return {}; }
    lua_getfield(m_L, -1, method.toUtf8().constData());
    if (!lua_isfunction(m_L, -1)) { lua_pop(m_L, 2); return {}; }
    lua_pushvalue(m_L, -2); // self
    for (const auto& a : args) pushVariant(m_L, a);
    int nargs = int(args.size()) + 1;
    if (lua_pcall(m_L, nargs, 1, 0) != LUA_OK) {
        qCritical() << "callMethod" << objectPath << method << "error:" << lua_tostring(m_L, -1);
        lua_pop(m_L, 2); // error + object
        return {};
    }
    QVariant v = luaToVariant(m_L, -1);
    lua_pop(m_L, 2); // result + object
    return v;
}

QStringList LuaEngine::modeNames() const {
    QStringList out;
    if (!m_L) return out;
    lua_getglobal(m_L, "main");
    if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return out; }
    lua_getfield(m_L, -1, "modes");
    if (!lua_istable(m_L, -1)) { lua_pop(m_L, 2); return out; }
    lua_pushnil(m_L);
    while (lua_next(m_L, -2) != 0) {
        if (lua_isstring(m_L, -2))
            out << QString::fromUtf8(lua_tostring(m_L, -2));
        lua_pop(m_L, 1); // pop value, keep key for next iteration
    }
    lua_pop(m_L, 2); // pop modes, main

    // main.modes is a hash table, so lua_next (pairs) yields its keys in an
    // unspecified, run-to-run-variable order — the top-bar mode buttons flipped
    // between LIST/BUILD orderings across runs. Impose a stable order matching
    // the engine's own registration sequence (Modules/Main.lua registers LIST
    // then BUILD); any unknown/future mode sorts alphabetically after the known
    // ones so the ordering stays deterministic regardless.
    static const QStringList kModeOrder = { "LIST", "BUILD" };
    std::stable_sort(out.begin(), out.end(), [](const QString& a, const QString& b) {
        int ia = kModeOrder.indexOf(a);
        int ib = kModeOrder.indexOf(b);
        if (ia < 0) ia = kModeOrder.size();
        if (ib < 0) ib = kModeOrder.size();
        if (ia != ib) return ia < ib;
        return a < b; // stable, deterministic tiebreak for unknown modes
    });
    return out;
}

// --- QML shell bridge helpers (Phase 1a) ------------------------------------

// Write a dotted Lua path to `value`. Navigates the table chain to the parent
// and sets the final field. Used to drive engine state that the engine itself
// normally mutates (e.g. buildMode.viewMode). No-op if any segment is missing.
void LuaEngine::setPath(const QString& path, const QVariant& value) {
    if (!m_L) return;
    QStringList parts = path.split('.');
    if (parts.size() < 2) return;
    lua_getglobal(m_L, parts[0].toUtf8().constData());
    for (int i = 1; i < parts.size() - 1; i++) {
        if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return; }
        lua_getfield(m_L, -1, parts[i].toUtf8().constData());
        lua_remove(m_L, -2);
    }
    if (!lua_istable(m_L, -1)) { lua_pop(m_L, 1); return; }
    pushVariant(m_L, value);
    lua_setfield(m_L, -2, parts.last().toUtf8().constData());
    lua_pop(m_L, 1);
}

// Drive an engine callback (OnInit/OnFrame/...) through the Lua runCallback
// global. runCallback(name, ...) dispatches to launch[name] or main[name].
QVariant LuaEngine::runCallback(const QString& name, const QVariantList& args) {
    QVariantList full;
    full << QVariant(name);
    full << args;
    return callGlobal("runCallback", full);
}

// Switch the active engine mode. This calls main:SetMode(mode) which only
// records the pending mode (self.newMode); the actual Init happens on the next
// OnFrame. We also pump one OnFrame synchronously so the flip is observable
// immediately (e.g. from a QML button click on the GUI thread).
void LuaEngine::setMode(const QString& mode) {
    if (mode == "BUILD") {
        // Reopen the LAST build the user had open (GetArgs persistence) rather
        // than force-opening a fresh "Unnamed build" on every toggle back to
        // BUILD. The decision — which dbFileName/buildName to replay and the
        // genuine first-run "Unnamed build" fallback — lives in the
        // pob_setBuildMode Lua global so it can read main.modes.BUILD:GetArgs()
        // naturally (Build.lua). buildMode:Init still reverts to LIST if it is
        // handed no buildName, so the fallback always supplies one. See
        // app/lua/pob_host.lua.
        callGlobal("pob_setBuildMode");
    } else {
        callMethod("main", "SetMode", {mode});
    }
    runCallback("OnFrame");
    emit modeChanged();
    emit viewChanged();
    emit currentModeChanged();
    emit currentViewChanged();
    qDebug().noquote() << "[lua] setMode requested:" << mode
                       << "-> current:" << currentMode();
}

// Current mode name string (main.mode).
QString LuaEngine::currentMode() const {
    return getPath("main.mode").toString();
}

// Phase 2a: write main.modes.BUILD.buildName. Used by the change-notification
// demonstration in main.cpp; harmless no-op if the build mode is unavailable.
void LuaEngine::setBuildName(const QString& name) {
    setPath("main.modes.BUILD.buildName", name);
    emit buildDataChanged();
}

// Phase 2b: build save/load bridge. Each delegates to a top-level Lua global in
// app/lua/pob_host.lua (callGlobal does a single lua_getglobal, so the helpers
// MUST be top-level globals, not dotted names). They wrap the engine's
// Build:SaveDB / Build:LoadDB seam, exercising the real xml.lua serialiser.
bool LuaEngine::saveBuild(const QString& path) {
    return callGlobal("pob_saveBuild", { path }).toBool();
}

bool LuaEngine::loadBuildXML(const QString& xml) {
    return callGlobal("pob_loadBuildXML", { xml }).toBool();
}

QString LuaEngine::getBuildXML() {
    QVariant v = callGlobal("pob_getBuildXML");
    return v.toString();
}

// Phase 1c: read the active BUILD view id (buildMode.viewMode).
QString LuaEngine::currentView() const {
    return getPath("main.modes.BUILD.viewMode").toString();
}

// Phase 1c: switch the active BUILD view by writing buildMode.viewMode, then
// pump one OnFrame so the engine (Draw dispatch, sidebar highlight) reflects it.
void LuaEngine::setActiveView(const QString& viewId) {
    if (currentMode() != "BUILD")
        return;
    setPath("main.modes.BUILD.viewMode", viewId);
    runCallback("OnFrame");
    emit viewChanged();
    emit currentViewChanged();
}

// Phase 3: LIST-mode (build library) operations. Each delegates to a top-level
// Lua global in app/lua/pob_host.lua (callGlobal does a single lua_getglobal,
// so the helpers MUST be top-level globals, not dotted names). They wrap the
// engine's BuildList / Build seams so the exact same file-load / save paths the
// real app uses are exercised.
bool LuaEngine::openBuild(const QString& fullFileName) {
    bool ok = callGlobal("pob_openBuild", { fullFileName }).toBool();
    if (ok) emit modeChanged();
    return ok;
}

bool LuaEngine::createBuild() {
    bool ok = callGlobal("pob_createBuild").toBool();
    if (ok) emit modeChanged();
    return ok;
}

bool LuaEngine::deleteBuild(const QString& fullFileName) {
    bool ok = callGlobal("pob_deleteBuild", { fullFileName }).toBool();
    if (ok) emit buildListChanged();
    return ok;
}

bool LuaEngine::renameBuild(const QString& fullFileName, const QString& newName) {
    bool ok = callGlobal("pob_renameBuild", { fullFileName, newName }).toBool();
    if (ok) emit buildListChanged();
    return ok;
}

bool LuaEngine::importBuildFromURL(const QString& url) {
    bool ok = callGlobal("pob_importBuildFromURL", { url }).toBool();
    if (ok) emit modeChanged();
    return ok;
}

bool LuaEngine::createFolder(const QString& name) {
    bool ok = callGlobal("pob_createFolder", { name }).toBool();
    if (ok) emit buildListChanged();
    return ok;
}

bool LuaEngine::deleteFolder(const QString& name) {
    bool ok = callGlobal("pob_deleteFolder", { name }).toBool();
    if (ok) emit buildListChanged();
    return ok;
}

// Switch the engine to LIST mode (build library). Mirrors setMode("LIST").
void LuaEngine::setListMode() {
    setMode("LIST");
}

// Phase 4a: passive-tree data bridge. Delegates to the top-level Lua global
// pob_getTreeData (callGlobal does a single lua_getglobal, so the helper MUST
// be a top-level global, not a dotted name).
QVariant LuaEngine::getTreeData() {
    return callGlobal("pob_getTreeData");
}

// Phase 4b: passive-tree interaction bridge. Each delegates to a top-level Lua
// global in app/lua/pob_host.lua (callGlobal does a single lua_getglobal, so the
// helpers MUST be top-level globals, not dotted names).
QVariant LuaEngine::allocNode(int id) {
    QVariant r = callGlobal("pob_allocNode", { id });
    emit treeChanged();
    emit calcsChanged();
    emit skillsChanged();
    emit configChanged();
    return r;
}

QVariant LuaEngine::deallocNode(int id) {
    QVariant r = callGlobal("pob_deallocNode", { id });
    emit treeChanged();
    emit calcsChanged();
    emit skillsChanged();
    emit configChanged();
    return r;
}

QVariant LuaEngine::toggleNode(int id) {
    QVariant r = callGlobal("pob_toggleNode", { id });
    emit treeChanged();
    emit calcsChanged();
    emit skillsChanged();
    emit configChanged();
    return r;
}

QVariant LuaEngine::getNodeTooltip(int id) {
    return callGlobal("pob_getNodeTooltip", { id });
}

QVariantList LuaEngine::setTreeSearch(const QString& str) {
    QVariant v = callGlobal("pob_setTreeSearch", { str });
    emit treeChanged();
    return v.toList();
}

QVariantList LuaEngine::getTreeSearchResults() {
    return callGlobal("pob_getTreeSearchResults").toList();
}

// Phase 5a: ItemsTab (ITEMS view) bridge. Each delegates to a top-level
// Lua global in app/lua/pob_host.lua (callGlobal does a single
// lua_getglobal, so the helpers MUST be top-level globals, not dotted names).
// They wrap the engine's ItemsTab (main.modes.BUILD.itemsTab) so the QML
// ITEMS view can browse items, equipped slots and tree jewel sockets, and
// add/delete items from raw text.
QVariantList LuaEngine::getItems() {
    QVariant v = callGlobal("pob_getItems");
    return v.toList();
}

QVariantList LuaEngine::getItemSlots() {
    QVariant v = callGlobal("pob_getItemSlots");
    return v.toList();
}

QVariantList LuaEngine::getJewelSockets() {
    QVariant v = callGlobal("pob_getJewelSockets");
    return v.toList();
}

int LuaEngine::addItemFromRaw(const QString& raw) {
    QVariant v = callGlobal("pob_addItemFromRaw", { raw });
    bool ok = false;
    int id = v.toInt(&ok);
    if (ok) {
        emit itemsChanged();
        emit calcsChanged();
    }
    return ok ? id : -1;
}

bool LuaEngine::deleteItem(int id) {
    bool ok = callGlobal("pob_deleteItem", { id }).toBool();
    if (ok) {
        emit itemsChanged();
        emit calcsChanged();
    }
    return ok;
}

// Phase 5b: SkillsTab (SKILLS view) bridge. Each delegates to a top-level Lua
// global in app/lua/pob_host.lua (callGlobal does a single lua_getglobal, so
// the helpers MUST be top-level globals, not dotted names).
QVariantList LuaEngine::getSocketGroups() {
    return callGlobal("pob_getSocketGroups").toList();
}

QVariantList LuaEngine::getActiveSkills() {
    return callGlobal("pob_getActiveSkills").toList();
}

int LuaEngine::addSocketGroupWithGem(const QString& label, const QString& gemName) {
    QVariant v = callGlobal("pob_addSocketGroupWithGem", { label, gemName });
    bool ok = false;
    int id = v.toInt(&ok);
    return ok ? id : -1;
}

void LuaEngine::setActiveSkill(int socketGroupId, int index) {
    callGlobal("pob_setActiveSkill", { socketGroupId, index });
    emit skillsChanged();
    emit calcsChanged();
}

// Part 2.2: recalc orchestration bridge. Delegates to the top-level Lua
// globals pob_recalculate / pob_getOutputRevision.
QVariant LuaEngine::recalculate() {
    QVariant r = callGlobal("pob_recalculate");
    if (r.typeId() == QMetaType::QVariantMap && r.toMap().value("recalculated").toBool()) {
        emit calcsChanged();
    }
    return r;
}

qint64 LuaEngine::outputRevision() {
    return callGlobal("pob_getOutputRevision").toLongLong();
}

// Phase 5c: CalcsTab (CALCS view) bridge. Delegates to the top-level Lua
// globals pob_getCalcOutput / pob_getCalcBreakdown (callGlobal does a single
// lua_getglobal, so the helpers MUST be top-level globals, not dotted names).
QVariant LuaEngine::getCalcOutput() {
    return callGlobal("pob_getCalcOutput");
}

QVariantList LuaEngine::getCalcBreakdown(const QString& section, const QString& stat) {
    QVariant res = callGlobal("pob_getCalcBreakdown", { section, stat });
    // The Lua helper returns a map { lines, hasTable }; expose the lines list
    // (the text breakdown the QML popup renders). Empty list when no breakdown.
    if (res.typeId() == QMetaType::QVariantMap) {
        return res.toMap().value("lines").toList();
    }
    return { };
}

// Part 2.3: sidebar output bridge. Delegates to the top-level Lua global
// pob_getOutput (callGlobal does a single lua_getglobal, so the helper MUST be
// a top-level global, not a dotted name).
QVariant LuaEngine::getOutput() {
    return callGlobal("pob_getOutput");
}

// Part 2.4: comparison-calculator bridge. Delegates to the top-level Lua
// globals pob_compareOverride / pob_compareNodes (callGlobal does a single
// lua_getglobal, so the helpers MUST be top-level globals, not dotted names).
QVariant LuaEngine::compareOverride(const QVariantMap& override) {
    return callGlobal("pob_compareOverride", { override });
}

QVariant LuaEngine::compareNodes(const QVariantList& nodeIds) {
    return callGlobal("pob_compareNodes", { nodeIds });
}

// Part 2.5: Config usage-set export bridge. Delegates to the top-level Lua
// global pob_getConfigUsageSets (callGlobal does a single lua_getglobal, so
// the helper MUST be a top-level global, not a dotted name).
QVariant LuaEngine::getConfigUsageSets() {
    return callGlobal("pob_getConfigUsageSets");
}

// Phase 5d: ConfigTab (CONFIG view) bridge. Delegates to the top-level Lua
// globals pob_getConfigOptions / pob_setConfigOption (callGlobal does a single
// lua_getglobal, so the helpers MUST be top-level globals, not dotted names).
QVariantList LuaEngine::getConfigOptions() {
    QVariant res = callGlobal("pob_getConfigOptions");
    if (res.typeId() == QMetaType::QVariantList) {
        return res.toList();
    }
    return { };
}

QVariant LuaEngine::setConfigOption(const QString& name, const QVariant& value) {
    QVariant r = callGlobal("pob_setConfigOption", { name, value });
    emit configChanged();
    emit calcsChanged();
    return r;
}

// Part 1.4: Options dialog bridge. See the header for the live-vs-commit split.
QVariantList LuaEngine::getOptions() {
    QVariant res = callGlobal("pob_getOptions");
    if (res.typeId() == QMetaType::QVariantList) {
        return res.toList();
    }
    return { };
}

QVariant LuaEngine::previewOption(const QString& key, const QVariant& value) {
    QVariant r = callGlobal("pob_previewOption", { key, value });
    // Live-preview fields (node-power theme, hex colours, ...) are mutated on the
    // engine immediately; emit configChanged so any live-bound QML refreshes.
    emit configChanged();
    return r;
}

bool LuaEngine::commitOptions(const QVariantMap& values) {
    bool ok = callGlobal("pob_commitOptions", QVariantList{ QVariant(values) }).toBool();
    emit configChanged();
    return ok;
}

// Part 1.4 (bullet 5): toast bridge. Delegates to the top-level Lua globals
// pob_getToasts / pob_dismissToast (callGlobal resolves only top-level globals).
QVariantList LuaEngine::getToasts() {
    QVariant v = callGlobal("pob_getToasts");
    if (v.typeId() == QMetaType::QVariantList) return v.toList();
    return { };
}

void LuaEngine::dismissToast(const QString& id) {
    callGlobal("pob_dismissToast", { id });
    // pob_dismissToast -> ToastNotification:Remove -> the wrap's pob.toastsChanged()
    // already emits toastsChanged() synchronously; nothing further to do here.
}

// Part 1.4 (bullet 6): About popup content bridge. Delegates to the top-level
// Lua global pob_getAboutContent (callGlobal resolves only top-level globals).
QVariant LuaEngine::getAboutContent() {
    return callGlobal("pob_getAboutContent");
}

void LuaEngine::openURL(const QString& url) {
    callGlobal("OpenURL", { url });
}

// Phase 5e: Notes/Import/Compare/Party (utility) tabs bridge. Delegates
// to the top-level Lua globals pob_getNotes / pob_setNotes /
// pob_importFromCode / pob_getCompareEntries / pob_getPartyMembers
// (callGlobal does a single lua_getglobal, so the helpers MUST be
// top-level globals, not dotted names).
QString LuaEngine::getNotes() {
    QVariant v = callGlobal("pob_getNotes");
    return v.toString();
}

void LuaEngine::setNotes(const QString& text) {
    callGlobal("pob_setNotes", { text });
    emit notesChanged();
}

bool LuaEngine::importFromCode(const QString& code) {
    bool ok = callGlobal("pob_importFromCode", { code }).toBool();
    if (ok) emit modeChanged();
    return ok;
}

QVariantList LuaEngine::getCompareEntries() {
    QVariant v = callGlobal("pob_getCompareEntries");
    return v.toList();
}

QVariantList LuaEngine::getPartyMembers() {
    QVariant v = callGlobal("pob_getPartyMembers");
    return v.toList();
}

bool LuaEngine::runSelfTest() {
    return pob_run_all_selftests(*this);
}
