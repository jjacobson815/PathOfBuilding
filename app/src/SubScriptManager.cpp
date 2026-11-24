#include "SubScriptManager.h"
#include "LuaEngine.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QHostInfo>
#include <QMetaObject>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTextStream>
#include <QThread>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <curl/curl.h>
#include <lua.hpp>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

// Binary-safe, nil-preserving cross-state Lua value container.
// Unlike QVariant+pushVariant (which turns invalid QVariant into ""), LuaVal
// preserves exact nil slots in multi-return tuples and embedded NUL bytes.
struct LuaVal {
    enum class Kind { Nil, Bool, Int, Num, Str, Arr, Map };
    Kind kind = Kind::Nil;
    bool b = false;
    qint64 i = 0;
    double n = 0.0;
    QByteArray s;
    std::vector<LuaVal> arr;
    std::vector<std::pair<QByteArray, LuaVal>> map;

    static LuaVal makeNil() { return LuaVal{}; }
    static LuaVal makeBool(bool v) { LuaVal r; r.kind = Kind::Bool; r.b = v; return r; }
    static LuaVal makeInt(qint64 v) { LuaVal r; r.kind = Kind::Int; r.i = v; return r; }
    static LuaVal makeNum(double v) { LuaVal r; r.kind = Kind::Num; r.n = v; return r; }
    static LuaVal makeStr(const QByteArray& v) { LuaVal r; r.kind = Kind::Str; r.s = v; return r; }
};

LuaVal luaValFromStack(lua_State* L, int index, int depth = 0) {
    if (depth > 64) return LuaVal::makeNil();
    const int t = lua_type(L, index);
    switch (t) {
    case LUA_TNIL:
    case LUA_TNONE:
        return LuaVal::makeNil();
    case LUA_TBOOLEAN:
        return LuaVal::makeBool(lua_toboolean(L, index) != 0);
    case LUA_TNUMBER: {
        const double d = lua_tonumber(L, index);
        if (std::isfinite(d) && std::floor(d) == d && d >= -9.0e18 && d <= 9.0e18)
            return LuaVal::makeInt(static_cast<qint64>(d));
        return LuaVal::makeNum(d);
    }
    case LUA_TSTRING: {
        size_t len = 0;
        const char* p = lua_tolstring(L, index, &len);
        return LuaVal::makeStr(QByteArray(p ? p : "", static_cast<qsizetype>(len)));
    }
    case LUA_TTABLE: {
        const int abs = (index < 0) ? (lua_gettop(L) + 1 + index) : index;
        bool onlyInt = true;
        int maxKey = 0;
        int count = 0;
        lua_pushnil(L);
        while (lua_next(L, abs) != 0) {
            ++count;
            if (lua_type(L, -2) == LUA_TNUMBER) {
                const double kd = lua_tonumber(L, -2);
                const int ki = static_cast<int>(kd);
                if (std::floor(kd) == kd && ki >= 1) {
                    if (ki > maxKey) maxKey = ki;
                } else {
                    onlyInt = false;
                }
            } else {
                onlyInt = false;
            }
            lua_pop(L, 1);
        }
        if (onlyInt && count > 0 && maxKey == count) {
            LuaVal out;
            out.kind = LuaVal::Kind::Arr;
            out.arr.reserve(static_cast<size_t>(maxKey));
            for (int k = 1; k <= maxKey; ++k) {
                lua_rawgeti(L, abs, k);
                out.arr.push_back(luaValFromStack(L, -1, depth + 1));
                lua_pop(L, 1);
            }
            return out;
        }
        LuaVal out;
        out.kind = LuaVal::Kind::Map;
        lua_pushnil(L);
        while (lua_next(L, abs) != 0) {
            QByteArray key;
            if (lua_type(L, -2) == LUA_TSTRING) {
                size_t klen = 0;
                const char* kp = lua_tolstring(L, -2, &klen);
                key = QByteArray(kp ? kp : "", static_cast<qsizetype>(klen));
            } else if (lua_type(L, -2) == LUA_TNUMBER) {
                key = QByteArray::number(lua_tonumber(L, -2));
            } else {
                key = QByteArray("key_") + QByteArray::number(count);
            }
            out.map.emplace_back(std::move(key), luaValFromStack(L, -1, depth + 1));
            lua_pop(L, 1);
        }
        return out;
    }
    default:
        return LuaVal::makeNil();
    }
}

void pushLuaVal(lua_State* L, const LuaVal& v) {
    switch (v.kind) {
    case LuaVal::Kind::Nil:
        lua_pushnil(L);
        break;
    case LuaVal::Kind::Bool:
        lua_pushboolean(L, v.b ? 1 : 0);
        break;
    case LuaVal::Kind::Int:
        lua_pushinteger(L, static_cast<lua_Integer>(v.i));
        break;
    case LuaVal::Kind::Num:
        lua_pushnumber(L, v.n);
        break;
    case LuaVal::Kind::Str:
        lua_pushlstring(L, v.s.constData(), static_cast<size_t>(v.s.size()));
        break;
    case LuaVal::Kind::Arr:
        lua_createtable(L, static_cast<int>(v.arr.size()), 0);
        for (size_t idx = 0; idx < v.arr.size(); ++idx) {
            pushLuaVal(L, v.arr[idx]);
            lua_rawseti(L, -2, static_cast<int>(idx + 1));
        }
        break;
    case LuaVal::Kind::Map:
        lua_createtable(L, 0, static_cast<int>(v.map.size()));
        for (const auto& kv : v.map) {
            lua_pushlstring(L, kv.first.constData(), static_cast<size_t>(kv.first.size()));
            pushLuaVal(L, kv.second);
            lua_settable(L, -3);
        }
        break;
    }
}

LuaVal luaValFromVariant(const QVariant& v, int depth = 0) {
    if (depth > 64 || !v.isValid() || v.isNull())
        return LuaVal::makeNil();
    switch (v.typeId()) {
    case QMetaType::Bool:
        return LuaVal::makeBool(v.toBool());
    case QMetaType::Int:
    case QMetaType::LongLong:
    case QMetaType::UInt:
    case QMetaType::ULongLong:
        return LuaVal::makeInt(v.toLongLong());
    case QMetaType::Double:
    case QMetaType::Float:
        return LuaVal::makeNum(v.toDouble());
    case QMetaType::QByteArray:
        return LuaVal::makeStr(v.toByteArray());
    case QMetaType::QString:
        return LuaVal::makeStr(v.toString().toUtf8());
    case QMetaType::QVariantList: {
        const QVariantList list = v.toList();
        LuaVal out;
        out.kind = LuaVal::Kind::Arr;
        out.arr.reserve(static_cast<size_t>(list.size()));
        for (const QVariant& item : list)
            out.arr.push_back(luaValFromVariant(item, depth + 1));
        return out;
    }
    case QMetaType::QVariantMap: {
        const QVariantMap mp = v.toMap();
        LuaVal out;
        out.kind = LuaVal::Kind::Map;
        out.map.reserve(static_cast<size_t>(mp.size()));
        for (auto it = mp.constBegin(); it != mp.constEnd(); ++it)
            out.map.emplace_back(it.key().toUtf8(), luaValFromVariant(it.value(), depth + 1));
        return out;
    }
    default:
        return LuaVal::makeStr(v.toString().toUtf8());
    }
}

struct SharedState {
    std::mutex mutex;
    SubScriptManager* mgr = nullptr;
    LuaEngine* engine = nullptr;
    QThread* uiThread = nullptr;
    std::atomic<bool> shuttingDown{false};
};

struct WorkerTask {
    int id = 0;
    std::shared_ptr<SharedState> shared;
    std::atomic<bool> aborted{false};
    std::atomic<bool> running{true};
    std::atomic<bool> workerExited{false};

    QString scriptText;
    QStringList funcList;
    QStringList subList;
    std::vector<LuaVal> args;

    QString srcDir;
    QString runtimeDir;
    QString userDir;
    QString luaDir;
};

static const char kTaskRegKey[] = "pob_worker_task";
static const char kSocketMeta[] = "pob.socket.tcp";

WorkerTask* taskOf(lua_State* L) {
    lua_getfield(L, LUA_REGISTRYINDEX, kTaskRegKey);
    auto* t = static_cast<WorkerTask*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return t;
}

bool isTaskAborted(const WorkerTask* t) {
    return !t || t->aborted.load(std::memory_order_relaxed)
           || t->shared->shuttingDown.load(std::memory_order_relaxed);
}

void workerCountHook(lua_State* L, lua_Debug* /*ar*/) {
    WorkerTask* t = taskOf(L);
    if (isTaskAborted(t)) {
        luaL_error(L, "SubScript aborted");
    }
}

// --- Abort-aware worker pob.http (libcurl) ----------------------------------

struct WorkerHttpBuffers {
    std::string body;
    std::string header;
};

size_t workerHttpWriteCb(char* ptr, size_t size, size_t nmemb, void* userdata) {
    const size_t n = size * nmemb;
    static_cast<std::string*>(userdata)->append(ptr, n);
    return n;
}

int workerHttpXferInfoCb(void* clientp, curl_off_t /*dltotal*/, curl_off_t /*dlnow*/,
                         curl_off_t /*ultotal*/, curl_off_t /*ulnow*/) {
    const auto* t = static_cast<const WorkerTask*>(clientp);
    return isTaskAborted(t) ? 1 : 0;
}

int l_worker_http(lua_State* L) {
    WorkerTask* task = taskOf(L);
    if (isTaskAborted(task)) {
        return luaL_error(L, "SubScript aborted");
    }
    if (lua_gettop(L) < 1 || !lua_istable(L, 1)) {
        lua_pushnil(L);
        lua_pushstring(L, "pob.http: expected options table");
        return 2;
    }

    auto getBytes = [&](const char* k) -> std::string {
        lua_getfield(L, 1, k);
        std::string v;
        if (lua_type(L, -1) == LUA_TSTRING) {
            size_t len = 0;
            const char* p = lua_tolstring(L, -1, &len);
            if (p) v.assign(p, len);
        }
        lua_pop(L, 1);
        return v;
    };
    auto getLong = [&](const char* k, long def) -> long {
        lua_getfield(L, 1, k);
        long v = def;
        if (lua_isboolean(L, -1))
            v = lua_toboolean(L, -1) ? 1L : 0L;
        else if (lua_isnumber(L, -1))
            v = static_cast<long>(lua_tonumber(L, -1));
        lua_pop(L, 1);
        return v;
    };

    const std::string url = getBytes("url");
    const std::string method = getBytes("method");
    const std::string postfields = getBytes("postfields");
    const std::string useragent = getBytes("useragent");
    const std::string acceptEncoding = getBytes("accept_encoding");
    const std::string proxy = getBytes("proxy");

    std::vector<std::string> headers;
    lua_getfield(L, 1, "httpheader");
    if (lua_istable(L, -1)) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            if (lua_type(L, -1) == LUA_TSTRING) {
                size_t len = 0;
                const char* p = lua_tolstring(L, -1, &len);
                if (p) headers.emplace_back(p, len);
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);

    const long followlocation = getLong("followlocation", 0);
    const long sslVerifypeer = getLong("ssl_verifypeer", 1);
    const long sslVerifyhost = getLong("ssl_verifyhost", 1);
    const long ipresolve = getLong("ipresolve", 0);
    const long timeoutSec = getLong("timeout", 0);
    const long connectTimeoutSec = getLong("connecttimeout", 15);

    CURL* curl = curl_easy_init();
    if (!curl) {
        lua_pushnil(L);
        lua_pushstring(L, "curl_easy_init failed");
        return 2;
    }

    WorkerHttpBuffers bufs;
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, workerHttpWriteCb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &bufs.body);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, workerHttpWriteCb);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &bufs.header);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING,
                     acceptEncoding.empty() ? "" : acceptEncoding.c_str());
    if (!useragent.empty())
        curl_easy_setopt(curl, CURLOPT_USERAGENT, useragent.c_str());
    if (followlocation)
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, sslVerifypeer ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, sslVerifyhost ? 2L : 0L);
    if (!proxy.empty())
        curl_easy_setopt(curl, CURLOPT_PROXY, proxy.c_str());
    if (ipresolve == 1)
        curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V4);
    else if (ipresolve == 2)
        curl_easy_setopt(curl, CURLOPT_IPRESOLVE, CURL_IPRESOLVE_V6);
    if (timeoutSec > 0)
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeoutSec);
    if (connectTimeoutSec > 0)
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, connectTimeoutSec);

    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, workerHttpXferInfoCb);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, task);

    struct curl_slist* hlist = nullptr;
    for (const auto& h : headers)
        hlist = curl_slist_append(hlist, h.c_str());
    if (hlist)
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, hlist);

    if (method == "POST" || !postfields.empty()) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postfields.data());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(postfields.size()));
    }

    const CURLcode res = curl_easy_perform(curl);
    long responseCode = 0;
    char* redirectUrl = nullptr;
    char* effectiveUrl = nullptr;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &responseCode);
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &redirectUrl);
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effectiveUrl);
    const std::string redirCopy = redirectUrl ? redirectUrl : "";
    const std::string effCopy = effectiveUrl ? effectiveUrl : "";

    if (hlist) curl_slist_free_all(hlist);
    curl_easy_cleanup(curl);

    if (isTaskAborted(task)) {
        return luaL_error(L, "SubScript aborted");
    }
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
    lua_pushnumber(L, static_cast<double>(responseCode));
    lua_setfield(L, -2, "code");
    lua_pushlstring(L, redirCopy.data(), redirCopy.size());
    lua_setfield(L, -2, "redirect_url");
    lua_pushlstring(L, effCopy.data(), effCopy.size());
    lua_setfield(L, -2, "effective_url");
    lua_pushnil(L);
    lua_setfield(L, -2, "error");
    return 1;
}

// --- QTcpServer / QTcpSocket LuaSocket shim for worker states ---------------

struct LuaTcpSocket {
    bool ipv6 = false;
    double timeoutSec = -1.0; // <0 blocking, >=0 seconds
    std::unique_ptr<QTcpServer> server;
    std::unique_ptr<QTcpSocket> client;
    QByteArray readBuf;

    void closeAll() {
        if (client) {
            if (client->bytesToWrite() > 0)
                client->waitForBytesWritten(200);
            // Drain unread request headers (e.g. LaunchServer.lua reads only the
            // HTTP request line via receive("*l")) so Windows Winsock sends FIN
            // instead of RST to the HTTP client on close().
            if (client->bytesAvailable() > 0 || client->waitForReadyRead(5))
                client->readAll();
            client->disconnectFromHost();
            if (client->state() != QAbstractSocket::UnconnectedState)
                client->waitForDisconnected(50);
            client->close();
            client.reset();
        }
        if (server) {
            server->close();
            server.reset();
        }
        readBuf.clear();
    }
};

LuaTcpSocket* checkTcp(lua_State* L, int idx = 1) {
    void* ud = luaL_checkudata(L, idx, kSocketMeta);
    return *static_cast<LuaTcpSocket**>(ud);
}

QHostAddress resolveBindAddress(const QString& host, bool ipv6) {
    const QString h = host.trimmed();
    if (h.isEmpty() || h == QLatin1String("*"))
        return ipv6 ? QHostAddress(QHostAddress::AnyIPv6) : QHostAddress(QHostAddress::AnyIPv4);
    if (h.compare(QLatin1String("localhost"), Qt::CaseInsensitive) == 0)
        return ipv6 ? QHostAddress(QHostAddress::LocalHostIPv6) : QHostAddress(QHostAddress::LocalHost);
    QHostAddress direct;
    if (direct.setAddress(h))
        return direct;
    const QHostInfo info = QHostInfo::fromName(h);
    for (const QHostAddress& a : info.addresses()) {
        if (!ipv6 && a.protocol() == QAbstractSocket::IPv4Protocol) return a;
        if (ipv6 && a.protocol() == QAbstractSocket::IPv6Protocol) return a;
    }
    if (!info.addresses().isEmpty())
        return info.addresses().first();
    return ipv6 ? QHostAddress(QHostAddress::LocalHostIPv6) : QHostAddress(QHostAddress::LocalHost);
}

int pushLuaSocketUserdata(lua_State* L, std::unique_ptr<LuaTcpSocket> ptr) {
    auto** slot = static_cast<LuaTcpSocket**>(lua_newuserdata(L, sizeof(LuaTcpSocket*)));
    *slot = ptr.release();
    luaL_getmetatable(L, kSocketMeta);
    lua_setmetatable(L, -2);
    return 1;
}

int l_tcp_gc(lua_State* L) {
    auto** slot = static_cast<LuaTcpSocket**>(luaL_checkudata(L, 1, kSocketMeta));
    if (slot && *slot) {
        (*slot)->closeAll();
        delete *slot;
        *slot = nullptr;
    }
    return 0;
}

int l_tcp_close(lua_State* L) {
    LuaTcpSocket* s = checkTcp(L, 1);
    if (s) s->closeAll();
    lua_pushinteger(L, 1);
    return 1;
}

int l_tcp_settimeout(lua_State* L) {
    LuaTcpSocket* s = checkTcp(L, 1);
    if (lua_isnoneornil(L, 2)) {
        s->timeoutSec = -1.0;
    } else {
        s->timeoutSec = luaL_checknumber(L, 2);
    }
    lua_pushinteger(L, 1);
    return 1;
}

int l_tcp_bind(lua_State* L) {
    WorkerTask* task = taskOf(L);
    if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");

    LuaTcpSocket* s = checkTcp(L, 1);
    const QString host = QString::fromUtf8(luaL_checkstring(L, 2));
    const int port = static_cast<int>(luaL_checkinteger(L, 3));
    if (port < 0 || port > 65535) {
        lua_pushnil(L);
        lua_pushstring(L, "invalid port");
        return 2;
    }

    // Reset any failed prior attempt so `server:bind(a) or server:bind(b)` works.
    if (s->server) {
        s->server->close();
        s->server.reset();
    }
    s->server = std::make_unique<QTcpServer>();
    s->server->setMaxPendingConnections(32);

    const QHostAddress addr = resolveBindAddress(host, s->ipv6);
    if (!s->server->listen(addr, static_cast<quint16>(port))) {
        const QByteArray err = s->server->errorString().toUtf8();
        s->server->close();
        s->server.reset();
        lua_pushnil(L);
        lua_pushlstring(L, err.constData(), static_cast<size_t>(err.size()));
        return 2;
    }
    lua_pushinteger(L, 1);
    return 1;
}

int l_tcp_listen(lua_State* L) {
    LuaTcpSocket* s = checkTcp(L, 1);
    const int backlog = lua_isnoneornil(L, 2) ? 32 : std::max(1, static_cast<int>(luaL_checkinteger(L, 2)));
    if (!s->server || !s->server->isListening()) {
        lua_pushnil(L);
        lua_pushstring(L, "closed");
        return 2;
    }
    s->server->setMaxPendingConnections(backlog);
    lua_pushinteger(L, 1);
    return 1;
}

int l_tcp_getsockname(lua_State* L) {
    LuaTcpSocket* s = checkTcp(L, 1);
    if (s->server && s->server->isListening()) {
        const QByteArray ip = s->server->serverAddress().toString().toUtf8();
        lua_pushlstring(L, ip.constData(), static_cast<size_t>(ip.size()));
        lua_pushinteger(L, static_cast<lua_Integer>(s->server->serverPort()));
        return 2;
    }
    if (s->client) {
        const QByteArray ip = s->client->localAddress().toString().toUtf8();
        lua_pushlstring(L, ip.constData(), static_cast<size_t>(ip.size()));
        lua_pushinteger(L, static_cast<lua_Integer>(s->client->localPort()));
        return 2;
    }
    lua_pushnil(L);
    lua_pushstring(L, "closed");
    return 2;
}

int l_tcp_getpeername(lua_State* L) {
    LuaTcpSocket* s = checkTcp(L, 1);
    if (s->client && s->client->state() == QAbstractSocket::ConnectedState) {
        const QByteArray ip = s->client->peerAddress().toString().toUtf8();
        lua_pushlstring(L, ip.constData(), static_cast<size_t>(ip.size()));
        lua_pushinteger(L, static_cast<lua_Integer>(s->client->peerPort()));
        return 2;
    }
    lua_pushnil(L);
    lua_pushstring(L, "closed");
    return 2;
}

int l_tcp_accept(lua_State* L) {
    WorkerTask* task = taskOf(L);
    LuaTcpSocket* s = checkTcp(L, 1);
    if (!s->server || !s->server->isListening()) {
        lua_pushnil(L);
        lua_pushstring(L, "closed");
        return 2;
    }

    const bool hasDeadline = (s->timeoutSec >= 0.0);
    const qint64 budgetMs = hasDeadline ? static_cast<qint64>(s->timeoutSec * 1000.0) : -1;
    QElapsedTimer timer;
    timer.start();

    for (;;) {
        if (isTaskAborted(task)) {
            return luaL_error(L, "SubScript aborted");
        }
        if (!s->server || !s->server->isListening()) {
            lua_pushnil(L);
            lua_pushstring(L, "closed");
            return 2;
        }
        if (s->server->hasPendingConnections()) {
            QTcpSocket* raw = s->server->nextPendingConnection();
            if (raw) {
                raw->setParent(nullptr);
                auto wrapped = std::make_unique<LuaTcpSocket>();
                wrapped->ipv6 = s->ipv6;
                wrapped->client.reset(raw);
                return pushLuaSocketUserdata(L, std::move(wrapped));
            }
        }
        int waitMs = 50;
        if (hasDeadline) {
            const qint64 rem = budgetMs - timer.elapsed();
            if (rem <= 0) {
                bool timedOut = false;
                s->server->waitForNewConnection(0, &timedOut);
                if (s->server->hasPendingConnections()) continue;
                lua_pushnil(L);
                lua_pushstring(L, "timeout");
                return 2;
            }
            waitMs = static_cast<int>(std::min<qint64>(50, rem));
        }
        bool timedOut = false;
        s->server->waitForNewConnection(waitMs, &timedOut);
    }
}

int l_tcp_connect(lua_State* L) {
    WorkerTask* task = taskOf(L);
    LuaTcpSocket* s = checkTcp(L, 1);
    const QString host = QString::fromUtf8(luaL_checkstring(L, 2));
    const int port = static_cast<int>(luaL_checkinteger(L, 3));

    s->closeAll();
    s->client = std::make_unique<QTcpSocket>();
    const QHostAddress addr = resolveBindAddress(host, s->ipv6);
    s->client->connectToHost(addr, static_cast<quint16>(port));

    const bool hasDeadline = (s->timeoutSec >= 0.0);
    const qint64 budgetMs = hasDeadline ? static_cast<qint64>(s->timeoutSec * 1000.0) : 30000;
    QElapsedTimer timer;
    timer.start();

    while (s->client->state() != QAbstractSocket::ConnectedState) {
        if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");
        if (s->client->state() == QAbstractSocket::UnconnectedState) {
            const QByteArray err = s->client->errorString().toUtf8();
            lua_pushnil(L);
            lua_pushlstring(L, err.constData(), static_cast<size_t>(err.size()));
            return 2;
        }
        const qint64 rem = budgetMs - timer.elapsed();
        if (rem <= 0) {
            s->client->abort();
            lua_pushnil(L);
            lua_pushstring(L, "timeout");
            return 2;
        }
        s->client->waitForConnected(static_cast<int>(std::min<qint64>(50, rem)));
    }
    lua_pushinteger(L, 1);
    return 1;
}

int l_tcp_receive(lua_State* L) {
    WorkerTask* task = taskOf(L);
    LuaTcpSocket* s = checkTcp(L, 1);
    if (!s->client) {
        lua_pushnil(L);
        lua_pushstring(L, "closed");
        return 2;
    }

    enum class Mode { Line, All, Bytes };
    Mode mode = Mode::Line;
    qsizetype wantBytes = 0;
    if (!lua_isnoneornil(L, 2)) {
        if (lua_type(L, 2) == LUA_TNUMBER) {
            mode = Mode::Bytes;
            wantBytes = std::max<qsizetype>(0, static_cast<qsizetype>(lua_tointeger(L, 2)));
        } else {
            const char* pat = luaL_checkstring(L, 2);
            if (std::strcmp(pat, "*a") == 0) mode = Mode::All;
            else mode = Mode::Line;
        }
    }
    QByteArray prefix;
    if (!lua_isnoneornil(L, 3)) {
        size_t plen = 0;
        const char* pp = luaL_checklstring(L, 3, &plen);
        prefix.assign(pp, pp + plen);
    }

    if (mode == Mode::Bytes && wantBytes == 0) {
        lua_pushlstring(L, prefix.constData(), static_cast<size_t>(prefix.size()));
        return 1;
    }

    const bool hasDeadline = (s->timeoutSec >= 0.0);
    const qint64 budgetMs = hasDeadline ? static_cast<qint64>(s->timeoutSec * 1000.0) : -1;
    QElapsedTimer timer;
    timer.start();

    for (;;) {
        if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");

        if (s->client->bytesAvailable() > 0) {
            s->readBuf.append(s->client->readAll());
        }

        if (mode == Mode::Line) {
            const qsizetype nl = s->readBuf.indexOf('\n');
            if (nl >= 0) {
                QByteArray line = s->readBuf.left(nl);
                if (line.endsWith('\r')) line.chop(1);
                s->readBuf.remove(0, nl + 1);
                const QByteArray out = prefix + line;
                lua_pushlstring(L, out.constData(), static_cast<size_t>(out.size()));
                return 1;
            }
        } else if (mode == Mode::Bytes) {
            if (s->readBuf.size() >= wantBytes) {
                const QByteArray out = prefix + s->readBuf.left(wantBytes);
                s->readBuf.remove(0, wantBytes);
                lua_pushlstring(L, out.constData(), static_cast<size_t>(out.size()));
                return 1;
            }
        }

        const bool peerClosed = (s->client->state() == QAbstractSocket::UnconnectedState
                                 && s->client->bytesAvailable() == 0);
        if (peerClosed) {
            if (mode == Mode::All) {
                const QByteArray out = prefix + s->readBuf;
                s->readBuf.clear();
                lua_pushlstring(L, out.constData(), static_cast<size_t>(out.size()));
                return 1;
            }
            const QByteArray partial = prefix + s->readBuf;
            s->readBuf.clear();
            lua_pushnil(L);
            lua_pushstring(L, "closed");
            lua_pushlstring(L, partial.constData(), static_cast<size_t>(partial.size()));
            return 3;
        }

        int waitMs = 50;
        if (hasDeadline) {
            const qint64 rem = budgetMs - timer.elapsed();
            if (rem <= 0) {
                s->client->waitForReadyRead(0);
                if (s->client->bytesAvailable() > 0) continue;
                QByteArray partial = prefix;
                if (mode == Mode::Bytes || mode == Mode::All) {
                    partial += s->readBuf;
                    s->readBuf.clear();
                }
                lua_pushnil(L);
                lua_pushstring(L, "timeout");
                lua_pushlstring(L, partial.constData(), static_cast<size_t>(partial.size()));
                return 3;
            }
            waitMs = static_cast<int>(std::min<qint64>(50, rem));
        }
        s->client->waitForReadyRead(waitMs);
    }
}

int l_tcp_send(lua_State* L) {
    WorkerTask* task = taskOf(L);
    LuaTcpSocket* s = checkTcp(L, 1);
    if (!s->client) {
        lua_pushnil(L);
        lua_pushstring(L, "closed");
        return 2;
    }
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    lua_Integer startIdx = lua_isnoneornil(L, 3) ? 1 : luaL_checkinteger(L, 3);
    lua_Integer endIdx = lua_isnoneornil(L, 4) ? static_cast<lua_Integer>(len) : luaL_checkinteger(L, 4);
    if (startIdx < 0) startIdx = static_cast<lua_Integer>(len) + startIdx + 1;
    if (endIdx < 0) endIdx = static_cast<lua_Integer>(len) + endIdx + 1;
    if (startIdx < 1) startIdx = 1;
    if (endIdx > static_cast<lua_Integer>(len)) endIdx = static_cast<lua_Integer>(len);
    if (startIdx > endIdx || len == 0) {
        lua_pushinteger(L, 0);
        return 1;
    }

    const char* ptr = data + (startIdx - 1);
    qint64 remaining = static_cast<qint64>(endIdx - startIdx + 1);
    while (remaining > 0) {
        if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");
        const qint64 written = s->client->write(ptr, remaining);
        if (written < 0) {
            const QByteArray err = s->client->errorString().toUtf8();
            lua_pushnil(L);
            lua_pushlstring(L, err.constData(), static_cast<size_t>(err.size()));
            return 2;
        }
        ptr += written;
        remaining -= written;
    }

    const bool hasDeadline = (s->timeoutSec >= 0.0);
    const qint64 budgetMs = hasDeadline ? static_cast<qint64>(s->timeoutSec * 1000.0) : 10000;
    QElapsedTimer timer;
    timer.start();
    while (s->client->bytesToWrite() > 0) {
        if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");
        if (s->client->state() == QAbstractSocket::UnconnectedState) break;
        const qint64 rem = budgetMs - timer.elapsed();
        if (rem <= 0) {
            lua_pushnil(L);
            lua_pushstring(L, "timeout");
            return 2;
        }
        s->client->waitForBytesWritten(static_cast<int>(std::min<qint64>(50, rem)));
    }
    s->client->flush();
    lua_pushinteger(L, endIdx);
    return 1;
}

int l_tcp_setoption(lua_State* L) {
    checkTcp(L, 1);
    lua_pushinteger(L, 1);
    return 1;
}

int l_socket_tcp(lua_State* L) {
    auto s = std::make_unique<LuaTcpSocket>();
    s->ipv6 = false;
    return pushLuaSocketUserdata(L, std::move(s));
}

int l_socket_tcp4(lua_State* L) {
    auto s = std::make_unique<LuaTcpSocket>();
    s->ipv6 = false;
    return pushLuaSocketUserdata(L, std::move(s));
}

int l_socket_tcp6(lua_State* L) {
    auto s = std::make_unique<LuaTcpSocket>();
    s->ipv6 = true;
    return pushLuaSocketUserdata(L, std::move(s));
}

int l_socket_bind(lua_State* L) {
    const char* host = luaL_checkstring(L, 1);
    const lua_Integer port = luaL_checkinteger(L, 2);
    const lua_Integer backlog = lua_isnoneornil(L, 3) ? 32 : luaL_checkinteger(L, 3);

    l_socket_tcp4(L); // pushes sock at top
    const int sockIdx = lua_gettop(L);

    lua_pushcfunction(L, l_tcp_bind);
    lua_pushvalue(L, sockIdx);
    lua_pushstring(L, host);
    lua_pushinteger(L, port);
    lua_call(L, 3, 2);
    if (lua_isnil(L, -2)) {
        return 2; // nil, err
    }
    lua_pop(L, 2);

    lua_pushcfunction(L, l_tcp_listen);
    lua_pushvalue(L, sockIdx);
    lua_pushinteger(L, backlog);
    lua_call(L, 2, 2);
    if (lua_isnil(L, -2)) {
        return 2;
    }
    lua_pop(L, 2);
    return 1; // sock at sockIdx
}

int l_socket_sleep(lua_State* L) {
    WorkerTask* task = taskOf(L);
    const double sec = luaL_checknumber(L, 1);
    if (sec <= 0.0) return 0;
    const qint64 totalMs = static_cast<qint64>(sec * 1000.0);
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < totalMs) {
        if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");
        const qint64 rem = totalMs - timer.elapsed();
        if (rem <= 0) break;
        QThread::msleep(static_cast<unsigned long>(std::min<qint64>(20, rem)));
    }
    if (isTaskAborted(task)) return luaL_error(L, "SubScript aborted");
    return 0;
}

int l_socket_gettime(lua_State* L) {
    lua_pushnumber(L, static_cast<double>(QDateTime::currentMSecsSinceEpoch()) / 1000.0);
    return 1;
}

int luaopen_pob_socket(lua_State* L) {
    if (luaL_newmetatable(L, kSocketMeta)) {
        static const luaL_Reg methods[] = {
            { "bind",        l_tcp_bind },
            { "listen",      l_tcp_listen },
            { "accept",      l_tcp_accept },
            { "connect",     l_tcp_connect },
            { "receive",     l_tcp_receive },
            { "send",        l_tcp_send },
            { "close",       l_tcp_close },
            { "settimeout",  l_tcp_settimeout },
            { "setoption",   l_tcp_setoption },
            { "getsockname", l_tcp_getsockname },
            { "getpeername", l_tcp_getpeername },
            { nullptr,       nullptr }
        };
        lua_newtable(L);
        luaL_setfuncs(L, methods, 0);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, l_tcp_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);

    static const luaL_Reg modFuncs[] = {
        { "tcp",     l_socket_tcp },
        { "tcp4",    l_socket_tcp4 },
        { "tcp6",    l_socket_tcp6 },
        { "bind",    l_socket_bind },
        { "sleep",   l_socket_sleep },
        { "gettime", l_socket_gettime },
        { nullptr,   nullptr }
    };
    lua_newtable(L);
    luaL_setfuncs(L, modFuncs, 0);
    return 1;
}

// --- Cross-thread proxy closures --------------------------------------------

// funcList: synchronous blocking proxy to UI thread's main lua_State.
int l_worker_func_proxy(lua_State* L) {
    WorkerTask* task = taskOf(L);
    if (isTaskAborted(task)) {
        return luaL_error(L, "SubScript aborted");
    }
    const char* fnName = lua_tostring(L, lua_upvalueindex(1));
    if (!fnName) return 0;
    const QByteArray funcBytes(fnName);

    const int nargs = lua_gettop(L);
    std::vector<LuaVal> callArgs;
    callArgs.reserve(static_cast<size_t>(nargs));
    for (int i = 1; i <= nargs; ++i)
        callArgs.push_back(luaValFromStack(L, i));

    SubScriptManager* mgr = nullptr;
    LuaEngine* engine = nullptr;
    QThread* uiThread = nullptr;
    {
        std::lock_guard<std::mutex> lk(task->shared->mutex);
        if (!isTaskAborted(task) && task->shared->mgr && task->shared->engine) {
            mgr = task->shared->mgr;
            engine = task->shared->engine;
            uiThread = task->shared->uiThread;
        }
    }
    if (!mgr || !engine) {
        return luaL_error(L, "SubScript aborted");
    }

    std::vector<LuaVal> rets;
    QByteArray callErr;
    bool abortedDuringCall = false;

    auto runOnMain = [&]() {
        if (isTaskAborted(task) || !engine->state()) {
            abortedDuringCall = true;
            return;
        }
        lua_State* mainL = engine->state();
        const int base = lua_gettop(mainL);
        lua_getglobal(mainL, funcBytes.constData());
        if (!lua_isfunction(mainL, -1)) {
            lua_pop(mainL, 1);
            return; // undefined global -> nil return
        }
        for (const LuaVal& a : callArgs)
            pushLuaVal(mainL, a);
        if (lua_pcall(mainL, static_cast<int>(callArgs.size()), LUA_MULTRET, 0) != LUA_OK) {
            const char* em = lua_tostring(mainL, -1);
            callErr = QByteArray(em ? em : "funcList call failed");
            lua_settop(mainL, base);
            return;
        }
        const int nret = lua_gettop(mainL) - base;
        rets.reserve(static_cast<size_t>(std::max(0, nret)));
        for (int r = 1; r <= nret; ++r)
            rets.push_back(luaValFromStack(mainL, base + r));
        lua_settop(mainL, base);
    };

    if (QThread::currentThread() == uiThread) {
        runOnMain();
    } else {
        QMetaObject::invokeMethod(mgr, runOnMain, Qt::BlockingQueuedConnection);
    }

    if (abortedDuringCall || isTaskAborted(task)) {
        return luaL_error(L, "SubScript aborted");
    }
    if (!callErr.isEmpty()) {
        return luaL_error(L, "%s", callErr.constData());
    }
    for (const LuaVal& r : rets)
        pushLuaVal(L, r);
    return static_cast<int>(rets.size());
}

// subList: async fire-and-forget queued to runCallback("OnSubCall", name, ...) on UI thread.
int l_worker_sub_proxy(lua_State* L) {
    WorkerTask* task = taskOf(L);
    if (isTaskAborted(task)) {
        return luaL_error(L, "SubScript aborted");
    }
    const char* subName = lua_tostring(L, lua_upvalueindex(1));
    if (!subName) return 0;
    const QByteArray subBytes(subName);

    const int nargs = lua_gettop(L);
    std::vector<LuaVal> callArgs;
    callArgs.reserve(static_cast<size_t>(nargs));
    for (int i = 1; i <= nargs; ++i)
        callArgs.push_back(luaValFromStack(L, i));

    std::lock_guard<std::mutex> lk(task->shared->mutex);
    if (isTaskAborted(task) || !task->shared->mgr || !task->shared->engine)
        return 0;

    SubScriptManager* mgr = task->shared->mgr;
    LuaEngine* engine = task->shared->engine;
    std::shared_ptr<SharedState> shared = task->shared;
    QMetaObject::invokeMethod(
        mgr,
        [shared, engine, taskPtr = task, subBytes, callArgs = std::move(callArgs)]() {
            if (shared->shuttingDown.load() || taskPtr->aborted.load() || !engine || !engine->state())
                return;
            lua_State* mainL = engine->state();
            const int base = lua_gettop(mainL);
            lua_getglobal(mainL, "runCallback");
            if (!lua_isfunction(mainL, -1)) {
                lua_settop(mainL, base);
                return;
            }
            lua_pushstring(mainL, "OnSubCall");
            lua_pushlstring(mainL, subBytes.constData(), static_cast<size_t>(subBytes.size()));
            for (const LuaVal& a : callArgs)
                pushLuaVal(mainL, a);
            if (lua_pcall(mainL, static_cast<int>(2 + callArgs.size()), 0, 0) != LUA_OK) {
                lua_settop(mainL, base);
            }
        },
        Qt::QueuedConnection);
    return 0;
}

// --- Headless event-pump helpers exposed on main-state `pob` table ----------

int l_main_processEvents(lua_State* L) {
    const int maxMs = (lua_gettop(L) >= 1 && lua_isnumber(L, 1))
        ? std::clamp(static_cast<int>(lua_tointeger(L, 1)), 0, 200)
        : 10;
    if (QCoreApplication::instance()) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, maxMs);
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    }
    return 0;
}

int l_main_sleepMs(lua_State* L) {
    const int ms = (lua_gettop(L) >= 1 && lua_isnumber(L, 1))
        ? std::clamp(static_cast<int>(lua_tointeger(L, 1)), 0, 100)
        : 1;
    if (ms > 0)
        QThread::msleep(static_cast<unsigned long>(ms));
    return 0;
}

// --- Worker QThread execution -----------------------------------------------

class SubScriptThread : public QThread {
public:
    explicit SubScriptThread(std::shared_ptr<WorkerTask> task)
        : m_task(std::move(task)) {}

protected:
    void run() override {
        runWorker();
        m_task->workerExited.store(true, std::memory_order_release);
    }

private:
    std::shared_ptr<WorkerTask> m_task;

    void queueCompletion(bool ok, std::vector<LuaVal> rets, QByteArray errMsg) {
        std::lock_guard<std::mutex> lk(m_task->shared->mutex);
        if (isTaskAborted(m_task.get()) || !m_task->shared->mgr || !m_task->shared->engine) {
            m_task->running.store(false, std::memory_order_release);
            return;
        }
        SubScriptManager* mgr = m_task->shared->mgr;
        LuaEngine* engine = m_task->shared->engine;
        std::shared_ptr<WorkerTask> task = m_task;
        QMetaObject::invokeMethod(
            mgr,
            [task, engine, ok, rets = std::move(rets), errMsg = std::move(errMsg)]() {
                if (task->shared->shuttingDown.load() || task->aborted.load()) {
                    task->running.store(false, std::memory_order_release);
                    return;
                }
                // Mark not-running right before invoking OnSubFinished/OnSubError so
                // IsSubScriptRunning(id) is false both inside and immediately after
                // the callback, while staying true until delivery actually happens.
                task->running.store(false, std::memory_order_release);

                if (!engine || !engine->state()) return;
                lua_State* mainL = engine->state();
                const int base = lua_gettop(mainL);
                lua_getglobal(mainL, "runCallback");
                if (!lua_isfunction(mainL, -1)) {
                    lua_settop(mainL, base);
                    return;
                }
                if (ok) {
                    lua_pushstring(mainL, "OnSubFinished");
                    lua_pushinteger(mainL, task->id);
                    for (const LuaVal& r : rets)
                        pushLuaVal(mainL, r);
                    if (lua_pcall(mainL, static_cast<int>(2 + rets.size()), 0, 0) != LUA_OK) {
                        lua_settop(mainL, base);
                    }
                } else {
                    lua_pushstring(mainL, "OnSubError");
                    lua_pushinteger(mainL, task->id);
                    lua_pushlstring(mainL, errMsg.constData(), static_cast<size_t>(errMsg.size()));
                    if (lua_pcall(mainL, 3, 0, 0) != LUA_OK) {
                        lua_settop(mainL, base);
                    }
                }
                engine->emitNamedSignal(QStringLiteral("network"));
            },
            Qt::QueuedConnection);
    }

    void runWorker() {
        if (isTaskAborted(m_task.get())) {
            m_task->running.store(false, std::memory_order_release);
            return;
        }

        lua_State* L = luaL_newstate();
        if (!L) {
            queueCompletion(false, {}, QByteArray("luaL_newstate failed in SubScript"));
            return;
        }
        luaL_openlibs(L);

        lua_pushlightuserdata(L, m_task.get());
        lua_setfield(L, LUA_REGISTRYINDEX, kTaskRegKey);
        lua_sethook(L, workerCountHook, LUA_MASKCOUNT, 1000);

        const QByteArray srcB = m_task->srcDir.toUtf8();
        const QByteArray rtB = m_task->runtimeDir.toUtf8();
        const QByteArray usrB = m_task->userDir.toUtf8();
        const QByteArray luaB = m_task->luaDir.toUtf8();

        lua_pushlstring(L, srcB.constData(), static_cast<size_t>(srcB.size()));
        lua_setglobal(L, "_SRC_DIR");
        lua_pushlstring(L, rtB.constData(), static_cast<size_t>(rtB.size()));
        lua_setglobal(L, "_RUNTIME_DIR");
        lua_pushlstring(L, usrB.constData(), static_cast<size_t>(usrB.size()));
        lua_setglobal(L, "_USER_DIR");
        lua_pushlstring(L, luaB.constData(), static_cast<size_t>(luaB.size()));
        lua_setglobal(L, "_POB_LUA_DIR");

        //Worker `pob` bridge table (off-UI-thread http + stateless zlib).
        static const luaL_Reg workerPobFuncs[] = {
            { "http",    l_worker_http },
            { "inflate", LuaEngine::pobInflate },
            { "deflate", LuaEngine::pobDeflate },
            { nullptr,   nullptr }
        };
        lua_newtable(L);
        luaL_setfuncs(L, workerPobFuncs, 0);
        lua_setglobal(L, "pob");

        lua_pushcfunction(L, LuaEngine::pobInflate);
        lua_setglobal(L, "Inflate");
        lua_pushcfunction(L, LuaEngine::pobDeflate);
        lua_setglobal(L, "Deflate");

        // Preload QTcpServer/QTcpSocket-backed LuaSocket shim for LaunchServer.lua.
        lua_getglobal(L, "package");
        if (lua_istable(L, -1)) {
            lua_getfield(L, -1, "preload");
            if (lua_istable(L, -1)) {
                lua_pushcfunction(L, luaopen_pob_socket);
                lua_setfield(L, -2, "socket");
                lua_pushcfunction(L, luaopen_pob_socket);
                lua_setfield(L, -2, "socket.core");
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);

        // Configure package.path, package.cpath, and lua-utf8 fallback matching pob_host.lua.
        static const char kWorkerBoot[] = R"LUA(
            package.path = _SRC_DIR .. "/?.lua;" .. _SRC_DIR .. "/?/init.lua;"
                         .. _RUNTIME_DIR .. "/lua/?.lua;" .. _RUNTIME_DIR .. "/lua/?/init.lua;"
                         .. _POB_LUA_DIR .. "/?.lua;" .. _POB_LUA_DIR .. "/?/init.lua;"
                         .. package.path
            package.cpath = _RUNTIME_DIR .. "/?.dll;" .. _RUNTIME_DIR .. "/lua/?.dll;"
                          .. _RUNTIME_DIR .. "/?.so;" .. _RUNTIME_DIR .. "/lua/?.so;"
                          .. package.cpath
            local l_req = require
            function require(name)
                if name == "lua-utf8" then
                    local ok, mod = pcall(l_req, "lua-utf8")
                    if ok then return mod end
                    name = "utf8"
                end
                return l_req(name)
            end
        )LUA";
        if (luaL_dostring(L, kWorkerBoot) != LUA_OK) {
            const char* em = lua_tostring(L, -1);
            const QByteArray err(em ? em : "worker bootstrap failed");
            lua_close(L);
            queueCompletion(false, {}, err);
            return;
        }

        // Register funcList (sync blocking proxies) and subList (async OnSubCall proxies).
        for (const QString& fn : m_task->funcList) {
            const QByteArray b = fn.toUtf8();
            lua_pushlstring(L, b.constData(), static_cast<size_t>(b.size()));
            lua_pushcclosure(L, l_worker_func_proxy, 1);
            lua_setglobal(L, b.constData());
        }
        for (const QString& sn : m_task->subList) {
            const QByteArray b = sn.toUtf8();
            lua_pushlstring(L, b.constData(), static_cast<size_t>(b.size()));
            lua_pushcclosure(L, l_worker_sub_proxy, 1);
            lua_setglobal(L, b.constData());
        }

        // Engine file-based subscripts (e.g. src/UpdateCheck.lua) start with `#@`.
        // luaL_loadfile skips an initial `#` line, whereas luaL_loadbuffer does not;
        // blank the `#` line in-place so line numbers stay identical.
        QByteArray code = m_task->scriptText.toUtf8();
        if (code.startsWith('#')) {
            for (qsizetype idx = 0; idx < code.size() && code[idx] != '\n'; ++idx) {
                if (code[idx] != '\r') code[idx] = ' ';
            }
        }

        const QByteArray chunkName = QByteArray("=SubScript#") + QByteArray::number(m_task->id);
        const int base = lua_gettop(L);
        if (luaL_loadbuffer(L, code.constData(), static_cast<size_t>(code.size()), chunkName.constData()) != LUA_OK) {
            const char* em = lua_tostring(L, -1);
            const QByteArray err(em ? em : "SubScript compile error");
            lua_close(L);
            if (!isTaskAborted(m_task.get()))
                queueCompletion(false, {}, err);
            else
                m_task->running.store(false, std::memory_order_release);
            return;
        }

        for (const LuaVal& a : m_task->args)
            pushLuaVal(L, a);

        const int rc = lua_pcall(L, static_cast<int>(m_task->args.size()), LUA_MULTRET, 0);
        if (isTaskAborted(m_task.get())) {
            lua_close(L);
            m_task->running.store(false, std::memory_order_release);
            return;
        }

        if (rc != LUA_OK) {
            const char* em = lua_tostring(L, -1);
            const QByteArray err(em ? em : "SubScript runtime error");
            lua_close(L);
            queueCompletion(false, {}, err);
            return;
        }

        const int nret = lua_gettop(L) - base;
        std::vector<LuaVal> rets;
        rets.reserve(static_cast<size_t>(std::max(0, nret)));
        for (int r = 1; r <= nret; ++r)
            rets.push_back(luaValFromStack(L, base + r));

        // Close worker lua_State on this QThread so any QTcpServer/QTcpSocket userdata
        // runs its __gc destructor on the exact thread that created it.
        lua_close(L);
        queueCompletion(true, std::move(rets), {});
    }
};

struct TaskEntry {
    std::shared_ptr<WorkerTask> task;
    SubScriptThread* thread = nullptr;
};

QStringList splitCsvIdentifiers(const QString& csv) {
    QStringList out;
    const QStringList raw = csv.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString& part : raw) {
        const QString t = part.trimmed();
        if (!t.isEmpty()) out.append(t);
    }
    return out;
}

} // namespace

struct SubScriptManager::Impl {
    std::shared_ptr<SharedState> shared = std::make_shared<SharedState>();
    std::mutex tasksMutex;
    std::map<int, std::shared_ptr<TaskEntry>> tasks;
    int nextId = 1;
    bool mainHelpersRegistered = false;

    void ensureMainHelpers(LuaEngine* engine) {
        if (mainHelpersRegistered || !engine || !engine->state())
            return;
        lua_State* L = engine->state();
        lua_getglobal(L, "pob");
        if (lua_istable(L, -1)) {
            lua_pushcfunction(L, l_main_processEvents);
            lua_setfield(L, -2, "processEvents");
            lua_pushcfunction(L, l_main_sleepMs);
            lua_setfield(L, -2, "sleepMs");
            mainHelpersRegistered = true;
        }
        lua_pop(L, 1);
    }

    void reapFinishedLocked() {
        for (auto it = tasks.begin(); it != tasks.end(); ) {
            const auto& entry = it->second;
            if (!entry->task->running.load(std::memory_order_acquire)
                && entry->task->workerExited.load(std::memory_order_acquire)) {
                if (entry->thread) {
                    entry->thread->wait();
                    delete entry->thread;
                    entry->thread = nullptr;
                }
                it = tasks.erase(it);
            } else {
                ++it;
            }
        }
    }
};

SubScriptManager::SubScriptManager(LuaEngine* engine)
    : QObject(engine), m_impl(std::make_unique<Impl>()), m_engine(engine) {
    m_impl->shared->mgr = this;
    m_impl->shared->engine = engine;
    m_impl->shared->uiThread = this->thread();
}

SubScriptManager::~SubScriptManager() {
    shutdown();
}

int SubScriptManager::launch(const QString& scriptText,
                             const QString& funcListCsv,
                             const QString& subListCsv,
                             const QVariantList& args) {
    if (!m_impl || !m_engine || m_impl->shared->shuttingDown.load())
        return 0;

    m_impl->ensureMainHelpers(m_engine);

    auto task = std::make_shared<WorkerTask>();
    task->shared = m_impl->shared;
    task->scriptText = scriptText;
    task->funcList = splitCsvIdentifiers(funcListCsv);
    task->subList = splitCsvIdentifiers(subListCsv);
    task->args.reserve(static_cast<size_t>(args.size()));
    for (const QVariant& a : args)
        task->args.push_back(luaValFromVariant(a));

    auto readGlobalDir = [&](const char* gname, const QString& fallback) -> QString {
        lua_State* mainL = m_engine->state();
        if (!mainL) return fallback;
        lua_getglobal(mainL, gname);
        const QString val = (lua_type(mainL, -1) == LUA_TSTRING)
            ? QString::fromUtf8(lua_tostring(mainL, -1))
            : QString();
        lua_pop(mainL, 1);
        return val.isEmpty() ? fallback : val;
    };
    task->srcDir = readGlobalDir("_SRC_DIR", m_engine->srcDir());
    task->runtimeDir = readGlobalDir("_RUNTIME_DIR", m_engine->runtimeDir());
    task->userDir = readGlobalDir("_USER_DIR", m_engine->userDir());
    task->luaDir = readGlobalDir("_POB_LUA_DIR", m_engine->luaDir());

    auto entry = std::make_shared<TaskEntry>();
    entry->task = task;

    int assignedId = 0;
    {
        std::lock_guard<std::mutex> lk(m_impl->tasksMutex);
        m_impl->reapFinishedLocked();
        assignedId = m_impl->nextId++;
        task->id = assignedId;
        entry->thread = new SubScriptThread(task);
        m_impl->tasks[assignedId] = entry;
    }

    entry->thread->start();
    m_engine->emitNamedSignal(QStringLiteral("network"));
    return assignedId;
}

void SubScriptManager::abort(int id) {
    if (!m_impl || id <= 0) return;
    bool changed = false;
    {
        std::lock_guard<std::mutex> lk(m_impl->tasksMutex);
        auto it = m_impl->tasks.find(id);
        if (it != m_impl->tasks.end()) {
            it->second->task->aborted.store(true, std::memory_order_release);
            changed = it->second->task->running.exchange(false, std::memory_order_acq_rel);
        }
        m_impl->reapFinishedLocked();
    }
    if (changed && m_engine && !m_impl->shared->shuttingDown.load()) {
        m_engine->emitNamedSignal(QStringLiteral("network"));
    }
}

bool SubScriptManager::isRunning(int id) {
    if (!m_impl) return false;
    if (m_engine) m_impl->ensureMainHelpers(m_engine);
    if (id <= 0) return false;
    std::lock_guard<std::mutex> lk(m_impl->tasksMutex);
    m_impl->reapFinishedLocked();
    auto it = m_impl->tasks.find(id);
    if (it == m_impl->tasks.end()) return false;
    return it->second->task->running.load(std::memory_order_acquire);
}

void SubScriptManager::shutdown() {
    if (!m_impl) return;
    m_impl->shared->shuttingDown.store(true, std::memory_order_release);

    std::vector<std::shared_ptr<TaskEntry>> entries;
    {
        std::lock_guard<std::mutex> lk(m_impl->tasksMutex);
        entries.reserve(m_impl->tasks.size());
        for (auto& kv : m_impl->tasks) {
            kv.second->task->aborted.store(true, std::memory_order_release);
            kv.second->task->running.store(false, std::memory_order_release);
            entries.push_back(kv.second);
        }
        m_impl->tasks.clear();
    }

    // Service any in-flight BlockingQueuedConnection meta-calls targeted at `this`
    // while workers observe `shuttingDown` and exit, preventing UI <-> worker deadlock.
    const bool onOwnerThread = (QThread::currentThread() == this->thread());
    for (;;) {
        bool anyAlive = false;
        for (const auto& e : entries) {
            if (!e->task->workerExited.load(std::memory_order_acquire)) {
                anyAlive = true;
                break;
            }
        }
        if (!anyAlive) break;
        if (onOwnerThread && QCoreApplication::instance()) {
            QCoreApplication::sendPostedEvents(this, QEvent::MetaCall);
        }
        QThread::msleep(1);
    }

    for (const auto& e : entries) {
        if (e->thread) {
            e->thread->wait();
            delete e->thread;
            e->thread = nullptr;
        }
    }

    {
        std::lock_guard<std::mutex> lk(m_impl->shared->mutex);
        m_impl->shared->mgr = nullptr;
        m_impl->shared->engine = nullptr;
    }
}

bool SubScriptManager::registerUriScheme() {
#ifdef POB_NO_GUI
    return false;
#else
    if (!QCoreApplication::instance()) return false;
    const QString exePath = QCoreApplication::applicationFilePath();
    if (exePath.isEmpty() || exePath.contains(QStringLiteral("selftest"), Qt::CaseInsensitive))
        return false;

#if defined(Q_OS_WIN)
    const QString nativeExe = QDir::toNativeSeparators(exePath);
    QSettings root(QStringLiteral("HKEY_CURRENT_USER\\Software\\Classes\\pob"), QSettings::NativeFormat);
    if (!root.isWritable()) return false;
    root.setValue(QStringLiteral("."), QStringLiteral("URL:Path of Building Protocol"));
    root.setValue(QStringLiteral("URL Protocol"), QString());
    root.setValue(QStringLiteral("DefaultIcon/."), QStringLiteral("\"%1\",0").arg(nativeExe));
    root.setValue(QStringLiteral("shell/open/command/."),
                  QStringLiteral("\"%1\" \"%2\"").arg(nativeExe, QStringLiteral("%1")));
    root.sync();
    return root.status() == QSettings::NoError;
#elif defined(Q_OS_LINUX)
    const QString appsDir = QDir::homePath() + QStringLiteral("/.local/share/applications");
    if (!QDir().mkpath(appsDir)) return false;
    QFile desktop(appsDir + QStringLiteral("/pob-qt-uri.desktop"));
    if (!desktop.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return false;
    QTextStream ts(&desktop);
    ts << "[Desktop Entry]\n"
       << "Type=Application\n"
       << "Name=Path of Building\n"
       << "Exec=\"" << exePath << "\" %u\n"
       << "NoDisplay=true\n"
       << "MimeType=x-scheme-handler/pob;\n";
    desktop.close();
    return true;
#else
    return false;
#endif
#endif
}

QString SubScriptManager::parseStartupUri(const QStringList& args) {
    for (int i = 1; i < args.size(); ++i) {
        QString candidate = args[i].trimmed();
        if (candidate.size() >= 2 && candidate.startsWith(QLatin1Char('"'))
            && candidate.endsWith(QLatin1Char('"'))) {
            candidate = candidate.mid(1, candidate.size() - 2).trimmed();
        }
        if (candidate.startsWith(QStringLiteral("pob://"), Qt::CaseInsensitive)
            || candidate.startsWith(QStringLiteral("pob:"), Qt::CaseInsensitive)) {
            return candidate;
        }
    }
    return {};
}
