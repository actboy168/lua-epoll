#include "epoll.h"
#include "luaref.h"
#include <lua.hpp>

static const epoll_handle epoll_invalid_handle = (epoll_handle)-1;

struct lua_epoll {
    epoll_handle fd;
    int max_events;
    int i;
    int n;
    luaref ref;
    struct epoll_event events[1];
};

struct lua_epoll* ep_get(lua_State *L) {
    return (struct lua_epoll*)luaL_checkudata(L, 1, "EPOLL");
}

static int ep_pusherr(lua_State *L) {
    lua_pushnil(L);
    lua_pushfstring(L, "(%d) %s", errno, strerror(errno));
    return 2;
}

static int ep_pusherr(lua_State *L, const char* msg) {
    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 2;
}

static int ep_pushsuc(lua_State *L) {
    lua_pushboolean(L, 1);
    return 1;
}

static epoll_fd ep_tofd(lua_State *L, int idx) {
    return (epoll_fd)(intptr_t)lua_touserdata(L, idx);
}

static int ep_events(lua_State *L) {
    struct lua_epoll* ep = (struct lua_epoll*)lua_touserdata(L, lua_upvalueindex(1));
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
    int n = epoll_wait(ep->fd, ep->events, ep->max_events, timeout);
    if (n == -1) {
        return ep_pusherr(L);
    }
    ep->i = 0;
    ep->n = n;
    lua_getiuservalue(L, 1, 2);
    return 1;
}

static bool ep_close_epoll(struct lua_epoll* ep) {
    if (epoll_close(ep->fd) == -1) {
        return false;
    }
    ep->fd = epoll_invalid_handle;
    return true;
}

static int ep_close(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    if (!ep_close_epoll(ep)) {
        return ep_pusherr(L);
    }
    return ep_pushsuc(L);
}

static int ep_mt_gc(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    ep_close_epoll(ep);
    luaref_close(ep->ref);
    return 0;
}

static int ep_mt_close(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    ep_close_epoll(ep);
    return 0;
}

static void storeref(lua_State *L, int r) {
    lua_getiuservalue(L, 1, 1);
    lua_pushvalue(L, 2);
    lua_pushinteger(L, r);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}

static int cleanref(lua_State *L) {
    lua_getiuservalue(L, 1, 1);
    lua_pushvalue(L, 2);
    if (LUA_TNUMBER != lua_rawget(L, -2)) {
        lua_pop(L, 2);
        return LUA_NOREF;
    }
    int r = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);
    lua_pushvalue(L, 2);
    lua_pushnil(L);
    lua_rawset(L, -3);
    lua_pop(L, 1);
    return r;
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
    if (ep->fd == epoll_invalid_handle) {
        errno = EBADF;
        return ep_pusherr(L);
    }
    epoll_fd fd = ep_tofd(L, 2);
    lua_pushvalue(L, 3);
    int r = luaref_ref(ep->ref, L);
    if (r == LUA_NOREF) {
        return ep_pusherr(L, "Too many events.");
    }
    storeref(L, r);
    if (!lua_isnoneornil(L, 4)) {
        struct epoll_event ev;
        ev.events = (uint32_t)luaL_checkinteger(L, 4);
        ev.data.u32 = r;
        if (epoll_ctl(ep->fd, EPOLL_CTL_ADD, fd, &ev) == -1){
            return ep_pusherr(L);
        }
    }
    return ep_pushsuc(L);
}

static int ep_event_close(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    int r = cleanref(L);
    if (r == LUA_NOREF) {
        return ep_pusherr(L, "event is not initialized.");
    }
    luaref_unref(ep->ref, r);
    epoll_ctl(ep->fd, EPOLL_CTL_DEL, fd, NULL);
    return ep_pushsuc(L);
}

static int ep_event_add(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    int r = findref(L);
    if (r == LUA_NOREF) {
        return ep_pusherr(L, "event is not initialized.");
    }
    struct epoll_event ev;
    ev.events = (uint32_t)luaL_checkinteger(L, 3);
    ev.data.u32 = r;
    if (epoll_ctl(ep->fd, EPOLL_CTL_ADD, fd, &ev) == -1){
        return ep_pusherr(L);
    }
    return ep_pushsuc(L);
}

static int ep_event_mod(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    int r = findref(L);
    if (r == LUA_NOREF) {
        return ep_pusherr(L, "event is not initialized.");
    }
    struct epoll_event ev;
    ev.events = (uint32_t)luaL_checkinteger(L, 3);
    ev.data.u32 = r;
    if (epoll_ctl(ep->fd, EPOLL_CTL_MOD, fd, &ev) == -1) {
        return ep_pusherr(L);
    }
    return ep_pushsuc(L);
}

static int ep_event_del(lua_State *L) {
    struct lua_epoll* ep = ep_get(L);
    epoll_fd fd = ep_tofd(L, 2);
    if (epoll_ctl(ep->fd, EPOLL_CTL_DEL, fd, NULL) == -1) {
        return ep_pusherr(L);
    }
    return ep_pushsuc(L);
}

static int ep_create(lua_State *L) {
    int max_events = (int)luaL_checkinteger(L, 1);
    if (max_events <= 0) {
        return ep_pusherr(L, "maxevents is less than or equal to zero.");
    }
    epoll_handle epfd = epoll_create(1);
    if (epfd == epoll_invalid_handle) {
        return ep_pusherr(L);
    }
    size_t sz = sizeof(struct lua_epoll) + (max_events - 1) * sizeof(struct epoll_event);
    struct lua_epoll* ep = (struct lua_epoll*)lua_newuserdatauv(L, sz, 2);
    lua_newtable(L);
    lua_setiuservalue(L, -2, 1);
    lua_pushvalue(L, -1);
    lua_pushcclosure(L, ep_events, 1);
    lua_setiuservalue(L, -2, 2);
    ep->fd = epfd;
    ep->max_events = max_events;
    ep->ref = luaref_init(L);
    ep->i = 0;
    ep->n = 0;
    if (luaL_newmetatable(L, "EPOLL")) {
        luaL_Reg l[] = {
            { "wait", ep_wait },
            { "close", ep_close },
            { "event_init", ep_event_init },
            { "event_close", ep_event_close },
            { "event_add", ep_event_add },
            { "event_mod", ep_event_mod },
            { "event_del", ep_event_del },
            { "__gc", ep_mt_gc },
            { "__close", ep_mt_close },
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

#if !defined(LUAEPOLL_STATIC)
#    if defined(_WIN32)
#        define LUAEPOLL_API extern "C" __declspec(dllexport)
#    else
#        define LUAEPOLL_API extern "C" __attribute__((visibility("default")))
#    endif
#else
#    define LUAEPOLL_API extern "C"
#endif

LUAEPOLL_API
int luaopen_epoll(lua_State *L) {
    struct luaL_Reg l[] = {
        { "create", ep_create },
        { NULL, NULL },
    };
    luaL_newlib(L, l);

    lua_pushstring(L, EPOLL_TYPE);
    lua_setfield(L, -2, "type");

#define SETENUM(E) \
    lua_pushinteger(L, E); \
    lua_setfield(L, -2, #E)

    SETENUM(EPOLLIN);
    SETENUM(EPOLLPRI);
    SETENUM(EPOLLOUT);
    SETENUM(EPOLLERR);
    SETENUM(EPOLLHUP);
    SETENUM(EPOLLRDNORM);
    SETENUM(EPOLLRDBAND);
    SETENUM(EPOLLWRNORM);
    SETENUM(EPOLLWRBAND);
    SETENUM(EPOLLMSG);
    SETENUM(EPOLLRDHUP);
    SETENUM(EPOLLONESHOT);
#if !defined(_WIN32)
    SETENUM(EPOLLET);
#endif
    return 1;
}
