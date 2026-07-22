#pragma once
#include <lua.hpp>
#include <QVariant>

// Convert a Lua value at stack index `index` to a QVariant.
// Tables become QVariantList (array) or QVariantMap (object).
// Depth-limited (64) to avoid cycles / runaway recursion.
QVariant luaToVariant(lua_State* L, int index, int depth = 0);

// Push a QVariant onto the Lua stack.
void pushVariant(lua_State* L, const QVariant& v);
