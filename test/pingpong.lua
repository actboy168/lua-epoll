local lt = require "ltest"
local helper = require "test.helper"

local m = lt.test "framework"
local epoll = require "epoll"
local epfd = epoll.create(512)

local EPOLLIN <const> = epoll.EPOLLIN
local EPOLLOUT <const> = epoll.EPOLLOUT
local EPOLLERR <const> = epoll.EPOLLERR
local EPOLLHUP <const> = epoll.EPOLLHUP

local function create_stream(fd)
    local sock = {fd = fd}
    local kMaxReadBufSize <const> = 4 * 1024
    local rbuf = ""
    local wbuf = ""
    local closed = false
    local halfclose_r = false
    local halfclose_w = false
    local event_r = false
    local event_w = false
    local event_mask = 0
    local function closefd()
        epfd:event_del(fd:handle())
        fd:close()
    end
    local function event_update()
        local mask = 0
        if event_r then
            mask = mask | EPOLLIN
        end
        if event_w then
            mask = mask | EPOLLOUT
        end
        if mask ~= event_mask then
            epfd:event_mod(fd:handle(), mask)
            event_mask = mask
        end
    end
    local function force_close()
        closefd()
        assert(halfclose_r)
        assert(halfclose_w)
    end
    local function on_read()
        local data, err = fd:recv()
        if data == nil then
            if err then
                lt.failure("recv error: %s", err)
            end
            halfclose_r = true
            event_r = false
            if halfclose_w then
                force_close()
            elseif #wbuf == 0 then
                halfclose_w = true
                event_w = false
                force_close()
            else
                event_update()
            end
        elseif data == false then
        else
            rbuf = rbuf .. data
            if #rbuf > kMaxReadBufSize then
                event_r = false
                event_update()
            end
            sock:on_recv()
        end
    end
    local function on_write()
        local n, err = fd:send(wbuf)
        if n == nil then
            if err then
                lt.failure("send error: %s", err)
            end
            halfclose_w = true
            event_w = false
            if halfclose_r then
                force_close()
            else
                event_update()
            end
        elseif n == false then
        else
            wbuf = wbuf:sub(n + 1)
            if #wbuf == 0 then
                event_w = false
                event_update()
            end
        end
    end
    local function on_event(e)
        if e & (EPOLLERR | EPOLLHUP) ~= 0 then
            e = e & (EPOLLIN | EPOLLOUT)
        end
        if e & EPOLLIN ~= 0 then
            assert(not halfclose_r)
            on_read()
        end
        if e & EPOLLOUT ~= 0 then
            if not halfclose_w then
                on_write()
            end
        end
    end
    epfd:event_add(fd:handle(), 0, on_event)
    event_r = true
    event_update()

    function sock:send(data)
        if closed then
            return
        end
        if #data > 0 then
            wbuf = wbuf .. data
            event_w = true
            event_update()
        end
    end
    function sock:recv(n)
        if n == 0 then
            return ""
        end
        local res
        local full = #rbuf >= kMaxReadBufSize
        if n == nil then
            res = rbuf
            rbuf = ""
        elseif n <= #rbuf then
            res = rbuf:sub(1, n)
            rbuf = rbuf:sub(n+1)
        elseif n >= kMaxReadBufSize then
            res = rbuf
            rbuf = ""
        else
            return
        end
        if full then
            event_r = true
            event_update()
        end
        return res
    end
    function sock:close()
        if closed or halfclose_r then
            return
        end
        halfclose_r = true
        event_r = false
        if halfclose_w then
            force_close()
        else
            event_update()
        end
    end
    return sock
end

local function create_listen(fd)
    local sock = {fd = fd}
    local function closefd()
        epfd:event_del(fd:handle())
        fd:close()
    end
    local function on_event(e)
        if e & (EPOLLERR | EPOLLHUP) ~= 0 then
            closefd()
            return
        end
        if e & EPOLLIN ~= 0 then
            sock:on_accept()
        end
    end
    epfd:event_add(fd:handle(), EPOLLIN, on_event)
    return sock
end

function m.test()
    local quit = false
    local s = helper.SimpleServer("tcp", "127.0.0.1", 0)
    local server = create_listen(s)
    function server:on_accept()
        local newfd = assert(self.fd:accept())
        local session = create_stream(newfd)
        function session:on_recv()
            local res = self:recv(6)
            if res == nil then
                return
            end
            local strid = res:match "^PING%-(%d)$"
            lt.assertIsString(strid)
            self:send("PONG-"..strid)
        end
    end

    local c = helper.SimpleClient("tcp", s:info "socket")
    local client = create_stream(c)
    client:send "PING-1"
    function client:on_recv()
        local res = self:recv(6)
        if res == nil then
            return
        end
        local strid = res:match "^PONG%-(%d)$"
        lt.assertIsString(strid)
        local id = tonumber(strid)
        if id < 9 then
            self:send("PING-"..(id+1))
        else
            quit = true
        end
    end

    while not quit do
        for f, event in epfd:wait() do
            f(event)
        end
    end
end
