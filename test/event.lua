local lt = require "ltest"
local epoll = require "epoll"
local socket = require "bee.socket"
local time = require "bee.time"

local events = {
    "EPOLLIN",
    "EPOLLPRI",
    "EPOLLOUT",
    "EPOLLERR",
    "EPOLLHUP",
    "EPOLLRDNORM",
    "EPOLLRDBAND",
    "EPOLLWRNORM",
    "EPOLLWRBAND",
    "EPOLLMSG",
    "EPOLLRDHUP",
    "EPOLLONESHOT",
    "EPOLLET",
}

local function event_tostring(e)
    if e == 0 then
        lt.failure "unknown flags: 0"
        return "0"
    end
    local r = {}
    for _, name in ipairs(events) do
        local v = epoll[name]
        if v and e & v ~= 0 then
            r[#r+1] = name
            e = e - v
            if e == 0 then
                return table.concat(r, " | ")
            end
        end
    end
    r[#r+1] = string.format("0x%x", e)
    local res = table.concat(r, " | ")
    lt.failure("unknown flags: %s", res)
    return res
end

local function event_tointeger(e)
    local r = 0
    for name in e:gmatch "[A-Z]+" do
        local v = epoll[name]
        if v then
            r = r & v
        end
    end
    return r
end

local function event_bor(a, b)
    if a then
        return event_tostring(event_tointeger(a) | b)
    end
    return event_tostring(b)
end

local function assertEpollWait(epfd, values)
    local actual = {}
    local expected = {}
    if type(values[1]) == "table" then
        for _, v in ipairs(values) do
            expected[v[1]] = v[2]
        end
    else
        local v = values
        if v[1] then
            expected[v[1]] = v[2]
        end
    end

    local start = time.monotonic()
    while time.monotonic() - start < 100 do
        for s, event in epfd:wait(1) do
            actual[s] = event_bor(actual[s], event)
        end
        if lt.equals(actual, expected) then
            return
        end
    end
    lt.assertEquals(actual, expected)
end

local function get_port(fd)
    local _, port = fd:info "socket"
    return port
end

local m = lt.test "event"

function m.test_connect()
    local sfd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    local cfd <close> = assert(socket.connect("tcp", "127.0.0.1", get_port(sfd)))
    local sep <const> = epoll.create(16)
    local cep <const> = epoll.create(16)
    sep:event_init(sfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT, sfd)
    cep:event_init(cfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT, cfd)
    assertEpollWait(sep, {sfd, "EPOLLIN"})
    assertEpollWait(cep, {cfd, "EPOLLOUT"})
end

function m.test_send_recv()
    local sfd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    local cfd <close> = assert(socket.connect("tcp", "127.0.0.1", get_port(sfd)))
    local sep <const> = epoll.create(16)
    local cep <const> = epoll.create(16)
    sep:event_init(sfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT, sfd)
    cep:event_init(cfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT, cfd)
    assertEpollWait(sep, {sfd, "EPOLLIN"})
    assertEpollWait(cep, {cfd, "EPOLLOUT"})
    local newfd = sfd:accept()
    sep:event_init(newfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT, newfd)
    assertEpollWait(sep, {newfd, "EPOLLOUT"})
    local function test(data)
        lt.assertEquals(newfd:send(data), #data)
        assertEpollWait(sep, {newfd, "EPOLLOUT"})
        assertEpollWait(cep, {cfd, "EPOLLIN | EPOLLOUT"})
        lt.assertEquals(cfd:recv(), data)
        lt.assertEquals({cfd:recv()}, {false})
        assertEpollWait(cep, {cfd, "EPOLLOUT"})
    end
    test "1234567890"
end

function m.test_shutdown()
    local sfd <close> = assert(socket.bind("tcp", "127.0.0.1", 0))
    local cfd <close> = assert(socket.connect("tcp", "127.0.0.1", get_port(sfd)))
    local sep <const> = epoll.create(16)
    local cep <const> = epoll.create(16)
    sep:event_init(sfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT | epoll.EPOLLRDHUP, sfd)
    cep:event_init(cfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT | epoll.EPOLLRDHUP, cfd)
    assertEpollWait(sep, {sfd, "EPOLLIN"})
    assertEpollWait(cep, {cfd, "EPOLLOUT"})
    local newfd <close> = sfd:accept()
    sep:event_init(newfd:handle(), epoll.EPOLLIN | epoll.EPOLLOUT | epoll.EPOLLRDHUP, newfd)

    newfd:shutdown "w"
    assertEpollWait(sep, {newfd, "EPOLLOUT"})
    lt.assertIsNil(newfd:send "")
    assertEpollWait(cep, {cfd, "EPOLLIN | EPOLLOUT | EPOLLRDHUP"})
    lt.assertEquals({newfd:recv()}, {false})

    newfd:shutdown "r"
    assertEpollWait(cep, {cfd, "EPOLLIN | EPOLLOUT | EPOLLRDHUP"})
    lt.assertIsNil(newfd:recv())
end
