local task = require "task"
local socket = require "bee.socket"
local epoll = require "epoll"

local epfd = epoll.create(512)

local kMaxReadBufSize <const> = 4 * 1024

local status = {}
local handle = {}

local EPOLLIN <const> = epoll.EPOLLIN
local EPOLLOUT <const> = epoll.EPOLLOUT
local EPOLLERR <const> = epoll.EPOLLERR
local EPOLLHUP <const> = epoll.EPOLLHUP

local function event_update(s)
    local mask = 0
    if s.event_r then
        mask = mask | EPOLLIN
    end
    if s.event_w then
        mask = mask | EPOLLOUT
    end
    if mask ~= s.event_mask then
        if mask == 0 then
            epfd:event_del(s.fd:handle())
        elseif s.event_mask == 0 then
            epfd:event_add(s.fd:handle(), mask)
        else
            epfd:event_mod(s.fd:handle(), mask)
        end
        s.event_mask = mask
    end
end

local function fd_set_read(fd)
    local s = status[fd]
    s.event_r = true
    event_update(s)
end

local function fd_clr_read(fd)
    local s = status[fd]
    s.event_r = false
    event_update(s)
end

local function fd_set_write(fd)
    local s = status[fd]
    s.event_w = true
    event_update(s)
end

local function fd_clr_write(fd)
    local s = status[fd]
    s.event_w = false
    event_update(s)
end

local function fd_init(fd)
    local s = status[fd]
    local function on_event(e)
        if e & (EPOLLERR | EPOLLHUP) ~= 0 then
            e = e & (EPOLLIN | EPOLLOUT)
        end
        if e & EPOLLIN ~= 0 then
            assert(not s.halfclose_r)
            s:on_read()
        end
        if e & EPOLLOUT ~= 0 then
            if not s.halfclose_w then
                s:on_write()
            end
        end
    end
    epfd:event_init(fd:handle(), on_event)
end

local function create_handle(fd)
    local h = handle[fd]
    if h then
        return h
    end
    h = #handle + 1
    handle[h] = fd
    handle[fd] = h
    return h
end

local function close(s)
    local fd = s.fd
    epfd:event_close(fd:handle())
    fd:close()
    assert(s.halfclose_r)
    assert(s.halfclose_w)
    if s.wait_read then
        assert(#s.wait_read == 0)
    end
    if s.wait_write then
        assert(#s.wait_write == 0)
    end
    if s.wait_close then
        for _, token in ipairs(s.wait_close) do
            task.wakeup(token)
        end
    end
end

local function close_write(s)
    if s.halfclose_r and s.halfclose_w then
        return
    end
    if not s.halfclose_w then
        s.halfclose_w = true
        fd_clr_write(s.fd)
    end
    if s.halfclose_r then
        fd_clr_read(s.fd)
        close(s)
    end
end

local function close_read(s)
    if s.halfclose_r and s.halfclose_w then
        return
    end
    if not s.halfclose_r then
        s.halfclose_r = true
        fd_clr_read(s.fd)
        if s.wait_read then
            for i, token in ipairs(s.wait_read) do
                task.wakeup(token)
                s.wait_read[i] = nil
            end
        end
    end
    if s.halfclose_w then
        close(s)
    elseif not s.wait_write or #s.wait_write == 0 then
        s.halfclose_w = true
        fd_clr_write(s.fd)
        close(s)
    end
end

local function stream_on_read(s)
    local data = s.fd:recv()
    if data == nil then
        close_read(s)
    elseif data == false then
    else
        s.readbuf = s.readbuf .. data

        while #s.wait_read > 0 do
            local token = s.wait_read[1]
            if not token then
                break
            end
            local n = token[1]
            if n == nil then
                task.wakeup(token, s.readbuf)
                s.readbuf = ""
                table.remove(s.wait_read, 1)
            else
                if n > #s.readbuf then
                    break
                end
                task.wakeup(token, s.readbuf:sub(1, n))
                s.readbuf = s.readbuf:sub(n+1)
                table.remove(s.wait_read, 1)
            end
        end

        if #s.readbuf > kMaxReadBufSize then
            fd_clr_read(s.fd)
        end
    end
end

local function stream_on_write(s)
    while #s.wait_write > 0 do
        local data = s.wait_write[1]
        local n, err = s.fd:send(data[1])
        if n == nil then
            for i, token in ipairs(s.wait_write) do
                task.interrupt(token, err or "Write close.")
                s.wait_write[i] = nil
            end
            close_write(s)
            return
        elseif n == false then
            return
        else
            if n == #data[1] then
                local token = table.remove(s.wait_write, 1)
                task.wakeup(token, n)
                if #s.wait_write == 0 then
                    fd_clr_write(s.fd)
                    return
                end
            else
                data[1] = data[1]:sub(n + 1)
                return
            end
        end
    end
end

local function create_stream(newfd)
    status[newfd]  = {
        fd = newfd,
        readbuf = "",
        wait_read = {},
        wait_write = {},
        halfclose_r = false,
        halfclose_w = false,
        event_r = false,
        event_w = false,
        event_mask = 0,
        on_read = stream_on_read,
        on_write = stream_on_write,
    }
    fd_init(newfd)
    fd_set_read(newfd)
    return create_handle(newfd)
end

local S = {}

function S.listen(protocol, ...)
    local fd, err = socket(protocol)
    if not fd then
        return nil, err
    end
    local ok, err = fd:bind(...)
    if not ok then
        return nil, err
    end
    ok, err = fd:listen()
    if not ok then
        return nil, err
    end
    status[fd] = {
        fd = fd,
        halfclose_r = false,
        halfclose_w = true,
        event_r = false,
        event_w = false,
        event_mask = 0,
    }
    fd_init(fd)
    return create_handle(fd)
end

function S.connect(protocol, ...)
    local fd, err = socket(protocol)
    if not fd then
        return nil, err
    end
    local r, err = fd:connect(...)
    if r == nil then
        return nil, err
    end
    return create_stream(fd)
end

function S.accept(h)
    local fd = assert(handle[h], "Invalid fd.")
    local s = status[fd]
    s.on_read = task.wakeup
    fd_set_read(fd)
    task.wait(s)
    local newfd = fd:accept()
    if newfd:status() then
        return create_stream(newfd)
    end
end

function S.send(h, data)
    local fd = assert(handle[h], "Invalid fd.")
    local s = status[fd]
    if not s.wait_write then
        error "Write not allowed."
        return
    end
    if s.halfclose_w then
        return
    end
    if data == "" then
        return 0
    end
    if #s.wait_write == 0 then
        fd_set_write(fd)
    end

    local token = {
        data,
    }
    s.wait_write[#s.wait_write+1] = token
    return task.wait(token)
end

function S.recv(h, n)
    local fd = assert(handle[h], "Invalid fd.")
    local s = status[fd]
    if not s.readbuf then
        error "Read not allowed."
        return
    end
    if s.halfclose_r then
        if not n then
            if s.readbuf == "" then
                return
            end
        else
            if n > kMaxReadBufSize then
                n = kMaxReadBufSize
            end
            if n > #s.readbuf then
                return
            end
        end
    end
    local sz = #s.readbuf
    if not n then
        if sz == 0 then
            local token = {
            }
            s.wait_read[#s.wait_read+1] = token
            return task.wait(token)
        end
        local ret = s.readbuf
        if sz > kMaxReadBufSize then
            fd_set_read(s.fd)
        end
        s.readbuf = ""
        return ret
    else
        if n > kMaxReadBufSize then
            n = kMaxReadBufSize
        end
        if n <= sz then
            local ret = s.readbuf:sub(1, n)
            if sz > kMaxReadBufSize and sz - n <= kMaxReadBufSize then
                fd_set_read(s.fd)
            end
            s.readbuf = s.readbuf:sub(n+1)
            return ret
        else
            local token = {
                n,
            }
            s.wait_read[#s.wait_read+1] = token
            return task.wait(token)
        end
    end
end

function S.close(h)
    local fd = handle[h]
    if fd then
        local s = status[fd]
        close_read(s)
        if not s.halfclose_w then
            local token = {}
            if s.wait_close then
                s.wait_close[#s.wait_close+1] = token
            else
                s.wait_close = {token}
            end
            task.wait(token)
        end
        handle[h] = nil
        handle[fd] = nil
        status[fd] = nil
    end
end

local function schedule()
    for f, event in epfd:wait(1) do
        f(event)
    end
end

local function mainloop()
    task.dispatch(S)
    while task.schedule() do
        schedule()
    end
end

return {
    message = S,
    schedule = schedule,
    mainloop = mainloop,
}
