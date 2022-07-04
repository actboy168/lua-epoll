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
    },
    macos = {
        sources = "src/epoll_kqueue.cpp",
    },
    netbsd = {
        sources = "src/epoll_kqueue.cpp",
    },
    freebsd = {
        sources = "src/epoll_kqueue.cpp",
    }
}

lm:lua_dll "testlib" {
    includes = "src",
    sources = {
        "src/luaref.cpp",
        "test/src/test_luaref.cpp",
    },
    export_luaopen = "off",
}

lm:build "runtest" {
    deps = {
        "epoll",
        "testlib"
    },
    "$luamake", "test"
}

lm:default "epoll"
