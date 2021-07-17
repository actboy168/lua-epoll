package.path = table.concat({
    "?.lua",
    "3rd/ltest/?.lua",
}, ";")

local lt = require "ltest"

require "test.luaref"
require "test.basic"
require "test.event"
require "test.pingpong"

os.exit(lt.run(), true)
