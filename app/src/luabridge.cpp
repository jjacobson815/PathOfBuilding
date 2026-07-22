#include "luabridge.h"
#include <QVariantMap>
#include <QVariantList>
#include <QMetaType>
#include <cmath>

static QVariant luaToVariantRec(lua_State* L, int index, int depth) {
    if (depth > 64)
        return QVariant();

    int t = lua_type(L, index);
    switch (t) {
    case LUA_TNIL:
        return QVariant();
    case LUA_TBOOLEAN:
        return QVariant(bool(lua_toboolean(L, index)));
    case LUA_TNUMBER: {
        double d = lua_tonumber(L, index);
        // LuaJIT numbers are doubles; treat integral values as integers.
        if (std::isfinite(d) && std::floor(d) == d && d >= -9.0e18 && d <= 9.0e18)
            return QVariant(qint64(d));
        return QVariant(d);
    }
    case LUA_TSTRING:
        return QVariant(QString::fromUtf8(lua_tostring(L, index)));
    case LUA_TTABLE: {
        int abs = (index < 0) ? lua_gettop(L) + 1 + index : index;
        // Heuristic: array if every key is an integer 1..n with no gaps/extras.
        bool onlyInt = true;
        int maxKey = 0;
        int count = 0;
        lua_pushnil(L);
        while (lua_next(L, abs) != 0) {
            count++;
            if (lua_type(L, -2) == LUA_TNUMBER) {
                int k = int(lua_tointeger(L, -2));
                if (k > maxKey) maxKey = k;
            } else {
                onlyInt = false;
            }
            lua_pop(L, 1);
        }
        bool isArray = onlyInt && maxKey == count && count > 0;

        if (isArray) {
            QVariantList list;
            for (int i = 1; i <= maxKey; i++) {
                lua_rawgeti(L, abs, i);
                list.append(luaToVariantRec(L, -1, depth + 1));
                lua_pop(L, 1);
            }
            return list;
        } else {
            QVariantMap map;
            lua_pushnil(L);
            while (lua_next(L, abs) != 0) {
                QString key;
                int kt = lua_type(L, -2);
                if (kt == LUA_TSTRING)
                    key = QString::fromUtf8(lua_tostring(L, -2));
                else if (kt == LUA_TNUMBER)
                    key = QString::number(lua_tointeger(L, -2));
                else
                    key = QString("key_%1").arg(count);
                map.insert(key, luaToVariantRec(L, -1, depth + 1));
                lua_pop(L, 1);
            }
            return map;
        }
    }
    default:
        return QVariant();
    }
}

QVariant luaToVariant(lua_State* L, int index, int depth) {
    return luaToVariantRec(L, index, depth);
}

void pushVariant(lua_State* L, const QVariant& v) {
    switch (v.typeId()) {
    case QMetaType::QString:
        lua_pushstring(L, v.toString().toUtf8().constData());
        break;
    case QMetaType::Int:
    case QMetaType::LongLong:
        lua_pushinteger(L, v.toLongLong());
        break;
    case QMetaType::Double:
        lua_pushnumber(L, v.toDouble());
        break;
    case QMetaType::Bool:
        lua_pushboolean(L, v.toBool());
        break;
    case QMetaType::QVariantList: {
        QVariantList l = v.toList();
        lua_createtable(L, int(l.size()), 0);
        for (int i = 0; i < l.size(); i++) {
            pushVariant(L, l[i]);
            lua_rawseti(L, -2, i + 1);
        }
        break;
    }
    case QMetaType::QVariantMap: {
        QVariantMap m = v.toMap();
        lua_createtable(L, 0, int(m.size()));
        for (auto it = m.begin(); it != m.end(); ++it) {
            lua_pushstring(L, it.key().toUtf8().constData());
            pushVariant(L, it.value());
            lua_settable(L, -3);
        }
        break;
    }
    default:
        lua_pushstring(L, v.toString().toUtf8().constData());
        break;
    }
}
