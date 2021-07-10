#include "luaref.h"
#include <assert.h>

luaref luaref_init(lua_State* L) {
    lua_State* refL = lua_newthread(L);
    lua_rawsetp(L, LUA_REGISTRYINDEX, refL);
    lua_newtable(refL);
    return refL;
}

void luaref_close(lua_State* L, luaref refL) {
    lua_pushnil(L);
    lua_rawsetp(L, LUA_REGISTRYINDEX, refL);
}

int luaref_ref(luaref refL, lua_State* L) {
    if (!lua_checkstack(refL, 3)) {
        return LUA_NOREF;
    }
    lua_xmove(L, refL, 1);
    lua_pushnil(refL);
    if (!lua_next(refL, 1)) {
        return lua_gettop(refL);
    }
    int r = (int)lua_tointeger(L, -2);
    lua_pop(refL, 1);
    lua_pushnil(refL);
    lua_rawset(refL, 1);
    lua_replace(refL, r);
    return r;
}

void luaref_unref(luaref refL, int ref) {
    if (ref == LUA_NOREF) {
        return;
    }
    int top = lua_gettop(refL);
    if (top != ref) {
        lua_pushinteger(refL, ref);
        lua_pushboolean(refL, 1);
        lua_rawset(refL, 1);
        lua_pushnil(refL);
        lua_replace(refL, ref);
        return;
    }
    for (--top; top > 1;--top) {
        lua_pushinteger(refL, top);
        if (LUA_TNIL == lua_rawget(refL, 1)) {
            lua_pop(refL, 1);
            break;
        }
        lua_pop(refL, 1);
    }
    lua_settop(refL, top);
}

void luaref_get(luaref refL, lua_State* L, int ref) {
    assert(ref != LUA_NOREF);
    lua_pushvalue(refL, ref);
    lua_xmove(refL, L, 1);
}
