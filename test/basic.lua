local lt = require "ltest"
local epoll = require "epoll"
local helper = require "test.helper"
local stringify = require "stringify"

local m = lt.test "basic"

local function assertSuccess(expected, actual, errmsg)
    if not lt.equals(actual, expected) then
        lt.failure("expected: %s, actual: %s.%s", stringify(expected), stringify(actual), errmsg or '')
    end
end

local function assertFailed(expected_errmsg, actual, actual_errmsg)
    if actual ~= nil then
        lt.failure('No failed but expected errmsg: %s', stringify(expected_errmsg))
    end
    if not lt.equals(actual_errmsg, expected_errmsg) then
        lt.failure("expected errmsg: %s, actual errmsg: %s.", stringify(expected_errmsg), stringify(actual_errmsg))
    end
end

function m.test_create()
    assertFailed("maxevents is less than or equal to zero.", epoll.create(-1))
    assertFailed("maxevents is less than or equal to zero.", epoll.create(0))
    local epfd <close> = epoll.create(16)
    lt.assertIsUserdata(epfd)
end

function m.test_close()
    local epfd = epoll.create(16)
    local fd <close> = helper.SimpleServer("tcp", "127.0.0.1", 0)
    assertSuccess(true, epfd:event_add(fd:handle(), 0))
    assertSuccess(true, epfd:close())
    assertFailed("(9) Bad file descriptor", epfd:close())
    assertFailed("(9) Bad file descriptor", epfd:event_add(fd:handle(), 0))
end

function m.test_event()
    local epfd = epoll.create(16)
    local fd <close> = helper.SimpleServer("tcp", "127.0.0.1", 0)
    lt.assertIsNil(epfd:event_mod(fd:handle(), 0))
    lt.assertIsNil(epfd:event_del(fd:handle()))

    assertSuccess(true, epfd:event_add(fd:handle(), 0))
    lt.assertIsNil(epfd:event_add(fd:handle(), 0))
    assertSuccess(true, epfd:event_mod(fd:handle(), 0))
    assertSuccess(true, epfd:event_del(fd:handle()))
    lt.assertIsNil(epfd:event_mod(fd:handle(), 0))
    lt.assertIsNil(epfd:event_del(fd:handle()))
    assertSuccess(true, epfd:event_add(fd:handle(), 0))
    lt.assertIsNil(epfd:event_add(fd:handle(), 0))
    assertSuccess(true, epfd:event_mod(fd:handle(), 0))
    assertSuccess(true, epfd:event_del(fd:handle()))

    epfd:close()
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
    if epoll.type == "wepoll" then
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
        lt.assertIsNil(epfd:wait())
    end
    do
        local epfd <close> = epoll.create(16)
        lt.assertIsFunction(epfd:wait(0))
        for _ in epfd:wait(0) do
            lt.failure "Shouldn't run to here."
        end
    end
    local epfd <close> = epoll.create(16)
    local fd <close> = helper.SimpleServer("tcp", "127.0.0.1", 0)
    epfd:event_add(fd:handle(), 0, fd)
    for _ in epfd:wait(0) do
        lt.failure "Shouldn't run to here."
    end
end
