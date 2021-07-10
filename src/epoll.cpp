#include "epoll.h"
#include "luaref.h"
#include <lua.hpp>
#include <assert.h>

inline static const epoll_handle epoll_invalid_handle = (epoll_handle)-1;

struct lua_epoll {
    epoll_handle fd;
    int max_events;
    int i;
    int n;
    lua_State* ref;
    struct epoll_event events[1];
};

struct lua_epoll* ep_get(lua_State *L) {
    return (struct lua_epoll*)luaL_checkudata(L, 1, "EPOLL");
}

static int ep_pusherr(lua_State *L) {
#if !defined(LUAEPOLL_RETURN_ERROR)
    lua_pushstring(L, strerror(errno));
    return lua_error(L);
#else
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
#endif
}

static epoll_fd ep_tofd(lua_State *L, int idx) {
    return (epoll_fd)(intptr_t)lua_touserdata(L, idx);
}

static int ep_wait_error(lua_State *L) {
    if (lua_type(L, 2) != LUA_TSTRING) {
        return 0;
    }
    lua_pushboolean(L, 0);
    lua_insert(L, -2);
    return 2;
}

static int ep_wait_iter(lua_State *L) {
    struct lua_epoll* ep = (struct lua_epoll*)lua_touserdata(L, 1);
    if (ep->i >= ep->n) {
        return 0;
    }
    struct epoll_event const& ev = ep->events[ep->i];
    luaref_get(ep->ref, L, ev.data.u32);
    lua_pushinteger(L, ev.events);
    ep->i++;
    return 2;
}

static int ep_wait(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    int timeout = (int)luaL_optinteger(L, 2, -1);
    ep->n = epoll_wait(ep->fd, ep->events, ep->max_events, timeout);
    if (ep->n == -1) {
        lua_pushcfunction(L, ep_wait_error);
        ep_pusherr(L);
        return 3;
    }
    ep->i = 0;
    lua_pushcfunction(L, ep_wait_iter);
    lua_pushvalue(L, 1);
    return 2;
}

static int ep_close(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    if (ep->fd != epoll_invalid_handle) {
        if (epoll_close(ep->fd) == -1) {
            return ep_pusherr(L);
        }
        ep->fd = epoll_invalid_handle;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int ep_gc(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    if (ep->fd != epoll_invalid_handle && epoll_close(ep->fd) != -1) {
        ep->fd = epoll_invalid_handle;
    }
    luaref_close(L, ep->ref);
    return 0;
}

static void storeref(lua_State *L, int r) {
    lua_getiuservalue(L, 1, 1);
    lua_pushvalue(L, 2);
    lua_pushinteger(L, r);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}

static int findref(lua_State *L) {
    lua_getiuservalue(L, 1, 1);
    lua_pushvalue(L, 2);
    if (LUA_TNUMBER != lua_rawget(L, -2)) {
        lua_pop(L, 2);
        return LUA_NOREF;
    }
    int r = (int)lua_tointeger(L, -1);
    lua_pop(L, 2);
    return r;
}

static int ep_event_init(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    struct epoll_event ev;
    ev.events = (uint32_t)luaL_checkinteger(L, 3);
    if (lua_isnoneornil(L, 4)) {
        lua_pushvalue(L, 2);
    }
    else {
        lua_settop(L, 4);
    }
    ev.data.u32 = luaref_ref(ep->ref, L);
    storeref(L, ev.data.u32);
    if (epoll_ctl(ep->fd, EPOLL_CTL_ADD, fd, &ev) == -1){
        return ep_pusherr(L);
    }
    lua_pushboolean(L,1);
    return 1;
}

static int ep_event_close(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    luaref_unref(ep->ref, findref(L));
    return 0;
}

static int ep_event_add(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    struct epoll_event ev;
    ev.events = (uint32_t)luaL_checkinteger(L, 3);
    ev.data.u32 = findref(L);
    if (epoll_ctl(ep->fd, EPOLL_CTL_ADD, fd, &ev) == -1){
        return ep_pusherr(L);
    }
    lua_pushboolean(L,1);
    return 1;
}

static int ep_event_mod(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    struct epoll_event ev;
    ev.events = (uint32_t)luaL_checkinteger(L, 3);
    ev.data.u32 = findref(L);
    if (epoll_ctl(ep->fd, EPOLL_CTL_MOD, fd, &ev) == -1) {
        return ep_pusherr(L);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int ep_event_del(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    if (epoll_ctl(ep->fd, EPOLL_CTL_DEL, fd, NULL) == -1) {
        return ep_pusherr(L);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int ep_create(lua_State *L) {
    int max_events = (int)luaL_checkinteger(L, 1);
    if (max_events <= 0) {
        return luaL_error(L, "maxevents is less than or equal to zero.");
    }
    epoll_handle epfd = epoll_create(1);
    if (epfd == epoll_invalid_handle) {
        return ep_pusherr(L);
    }
    size_t sz = sizeof(struct lua_epoll) + (max_events - 1) * sizeof(struct epoll_event);
    struct lua_epoll* ep = (struct lua_epoll*)lua_newuserdatauv(L, sz, 1);
    lua_newtable(L);
    lua_setiuservalue(L, -2, 1);
    ep->fd = epfd;
    ep->max_events = max_events;
    ep->ref = luaref_init(L);
    if (luaL_newmetatable(L, "EPOLL")) {
        luaL_Reg l[] = {
            { "wait", ep_wait },
            { "close", ep_close },
            { "event_init", ep_event_init },
            { "event_close", ep_event_close },
            { "event_add", ep_event_add },
            { "event_mod", ep_event_mod },
            { "event_del", ep_event_del },
            { "__gc", ep_gc },
            { "__index", NULL },
            { NULL, NULL },
        };
        luaL_setfuncs(L, l, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}

#if defined(_WIN32)
extern "C" __declspec(dllexport)
#else
extern "C" __attribute__((visibility("default")))
#endif
int luaopen_epoll(lua_State *L) {
    struct luaL_Reg l[] = {
        { "create", ep_create },
        { NULL, NULL },
    };
    luaL_newlib(L, l);

#define SETENUM(E) \
    lua_pushinteger(L, E); \
    lua_setfield(L, -2, #E)

    SETENUM(EPOLLIN);
    SETENUM(EPOLLPRI);
    SETENUM(EPOLLOUT);
    SETENUM(EPOLLRDNORM);
    SETENUM(EPOLLRDBAND);
    SETENUM(EPOLLWRNORM);
    SETENUM(EPOLLWRBAND);
    SETENUM(EPOLLMSG);
    SETENUM(EPOLLERR);
    SETENUM(EPOLLHUP);
    SETENUM(EPOLLRDHUP);
    SETENUM(EPOLLONESHOT);
#if !defined(_WIN32)
    SETENUM(EPOLLET);
#endif
    return 1;
}
