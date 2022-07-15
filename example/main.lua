package.path = package.path .. ";example/?.lua"

local task = require "task"
local socket = require "socket"
local network = require "network"

local function server_thread()
    local severfd = assert(socket.listen("tcp", "127.0.0.1", 12306))
    while true do
        local clientfd = assert(severfd:accept())
        task.fork(function ()
            while true do
                local data = clientfd:recv(4)
                print("server recv: "..data)
                if data == "PING" then
                    clientfd:send "PONG"
                elseif data == "QUIT" then
                    clientfd:close()
                    return
                end
            end
        end)
        return
    end
end
local function client_thread()
    local clientfd = assert(socket.connect("tcp", "127.0.0.1", 12306))
    for _ = 1, 4 do
        clientfd:send "PING"
        assert(clientfd:recv(4) == "PONG")
        print "client recv: PONG"
    end
    clientfd:send "QUIT"
    clientfd:close()
end

task.fork(server_thread)
task.fork(client_thread)
network.mainloop()
