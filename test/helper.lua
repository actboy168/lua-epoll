local socket = require "bee.socket"

local m = {}

function m.SimpleServer(protocol, ...)
    local fd = assert(socket.create(protocol))
    assert(fd:bind(...))
    assert(fd:listen())
    return fd
end

function m.SimpleClient(protocol, ...)
    local fd = assert(socket.create(protocol))
    local ok, err = fd:connect(...)
    assert(ok ~= nil, err)
    return fd
end

return m
