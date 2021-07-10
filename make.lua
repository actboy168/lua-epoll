local lm = require "luamake"

lm:lua_dll "epoll" {
    sources = {
        "src/epoll.cpp",
        "src/luaref.cpp",
    },
    windows = {
        includes = "3rd/wepoll",
        sources = "3rd/wepoll/wepoll.c",
        defines = "_CRT_SECURE_NO_WARNINGS",
        links = "ws2_32",
    }
}
