#pragma once

#include <lua.hpp>
typedef lua_State* luaref;

luaref luaref_init  (lua_State* L);
void   luaref_close (lua_State* L, luaref refL);
int    luaref_ref   (luaref refL, lua_State* L);
void   luaref_unref (luaref refL, int ref);
void   luaref_get   (luaref refL, lua_State* L, int ref);
