local lt = require "ltest"
local epoll = require "epoll"
local socket = require "bee.socket"
local platform = require "bee.platform"

local function isWindows()
    return platform.OS == "Windows"
end

local m = lt.test "basic"

function m.test_create()
    lt.assertErrorMsgEquals("maxevents is less than or equal to zero.", epoll.create, -1)
    lt.assertErrorMsgEquals("maxevents is less than or equal to zero.", epoll.create, 0)
    local epfd <close> = epoll.create(16)
    lt.assertIsUserdata(epfd)
end

function m.test_close()
    local epfd = epoll.create(16)
    local fd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    epfd:event_init(fd:handle(), 0)
    epfd:close()
    lt.assertErrorMsgEquals("(9) Bad file descriptor", epfd.close, epfd)
    lt.assertErrorMsgEquals("(9) Bad file descriptor", epfd.event_init, epfd, fd:handle(), 0)
end

function m.test_event()
    local epfd = epoll.create(16)
    local fd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    lt.assertError(epfd.event_add, epfd, fd:handle(), 0)
    lt.assertError(epfd.event_mod, epfd, fd:handle(), 0)
    lt.assertError(epfd.event_del, epfd, fd:handle())
    lt.assertError(epfd.event_close, epfd, fd:handle())
    epfd:event_init(fd:handle(), 0)
    lt.assertError(epfd.event_add, epfd, fd:handle(), 0)
    epfd:event_mod(fd:handle(), 0)
    epfd:event_del(fd:handle())
    lt.assertError(epfd.event_mod, epfd, fd:handle(), 0)
    lt.assertError(epfd.event_del, epfd, fd:handle())
    epfd:event_add(fd:handle(), 0)
    lt.assertError(epfd.event_add, epfd, fd:handle(), 0)
    epfd:event_mod(fd:handle(), 0)
    epfd:event_close(fd:handle())
    lt.assertError(epfd.event_add, epfd, fd:handle(), 0)
    lt.assertError(epfd.event_mod, epfd, fd:handle(), 0)
    lt.assertError(epfd.event_del, epfd, fd:handle())
    lt.assertError(epfd.event_close, epfd, fd:handle())
    epfd:close()
end

function m.test_handle()
    local epfd <close> = epoll.create(16)
    lt.assertIsUserdata(epfd:handle())
end

function m.test_enum()
    lt.assertEquals(epoll.EPOLLIN,     1 << 0)
    lt.assertEquals(epoll.EPOLLPRI,    1 << 1)
    lt.assertEquals(epoll.EPOLLOUT,    1 << 2)
    lt.assertEquals(epoll.EPOLLERR,    1 << 3)
    lt.assertEquals(epoll.EPOLLHUP,    1 << 4)
    lt.assertEquals(epoll.EPOLLRDNORM, 1 << 6)
    lt.assertEquals(epoll.EPOLLRDBAND, 1 << 7)
    lt.assertEquals(epoll.EPOLLWRNORM, 1 << 8)
    lt.assertEquals(epoll.EPOLLWRBAND, 1 << 9)
    lt.assertEquals(epoll.EPOLLMSG,    1 << 10)
    lt.assertEquals(epoll.EPOLLRDHUP,  1 << 13)
    if isWindows() then
        lt.assertEquals(epoll.EPOLLONESHOT, 1 << 31)
    else
        lt.assertEquals(epoll.EPOLLONESHOT, 1 << 30)
        lt.assertEquals(epoll.EPOLLET,      1 << 31)
    end
end

function m.test_wait()
    do
        local epfd = epoll.create(16)
        epfd:close()
        lt.assertError(epfd.wait, epfd, 0)
    end
    do
        local epfd <close> = epoll.create(16)
        lt.assertIsFunction(epfd:wait(0))
        for _ in epfd:wait(0) do
            lt.failure "Shouldn't run to here."
        end
    end
    local epfd <close> = epoll.create(16)
    local fd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    epfd:event_init(fd:handle(), 0)
    for _ in epfd:wait(0) do
        lt.failure "Shouldn't run to here."
    end
end
