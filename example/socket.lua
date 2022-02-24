local task = require "task"

local mt = {}
mt.__index = mt

function mt:accept(...)
    local fd, err = task.call("accept", self.fd, ...)
    if not fd then
        return nil, err
    end
    return setmetatable({fd=fd}, mt)
end

function mt:send(...)
    return task.call("send", self.fd, ...)
end

function mt:recv(...)
    return task.call("recv", self.fd, ...)
end

function mt:close(...)
    return task.call("close", self.fd, ...)
end

local socket = {}

function socket.listen(...)
    local fd, err = task.call("listen", ...)
    if not fd then
        return nil, err
    end
    return setmetatable({fd=fd}, mt)
end

function socket.connect(...)
    local fd, err = task.call("connect", ...)
    if not fd then
        return nil, err
    end
    return setmetatable({fd=fd}, mt)
end

return socket
