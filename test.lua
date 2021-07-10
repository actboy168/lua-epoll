local socket = require "bee.socket"
local epoll = require "epoll"
local epfd = epoll.create(512)

local EPOLLIN <const> = epoll.EPOLLIN
local EPOLLOUT <const> = epoll.EPOLLOUT
local EPOLLERR <const> = epoll.EPOLLERR
local EPOLLHUP <const> = epoll.EPOLLHUP

local function initfd(fd)
    local sock = {fd=fd}
    epfd:event_init(fd:handle(), EPOLLIN | EPOLLOUT, sock)
    return sock
end

local function closefd(fd)
    local h = fd:handle()
    epfd:event_del(h)
    epfd:event_close(h)
    fd:close()
end

local s = assert(socket.bind("tcp", "127.0.0.1", 16333))
local server = initfd(s)
function server:on_read()
    local fd = self.fd
    local newfd = assert(fd:accept())
    local session = initfd(newfd)
    function session:on_read()
        assert("PING" == self.fd:recv(4))
    end
    function session:on_write()
        self.fd:send "PONG"
    end
    function session:on_error()
        closefd(self.fd)
    end
end
function server:on_error()
    closefd(self.fd)
end

local c = assert(socket.connect("tcp", "127.0.0.1", 16333))
local client = initfd(c)
function client:on_read()
    local pong = self.fd:recv(4)
    print(pong)
    assert("PONG" == pong)
end
function client:on_write()
    print "PING"
    self.fd:send "PING"
end
function client:on_error()
    closefd(self.fd)
end

while true do
    for fd, event in epfd:wait() do
        if event & (EPOLLERR | EPOLLHUP) ~= 0 then
            fd:on_error()
        else
            if event & EPOLLIN ~= 0 then
                fd:on_read()
            end
            if event & EPOLLOUT ~= 0 then
                fd:on_write()
            end
        end
    end
end
