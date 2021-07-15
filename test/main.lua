package.path = table.concat({
    "?.lua",
    "3rd/ltest/?.lua",
}, ";")

local lt = require "ltest"

require "test.luaref"

os.exit(lt.run(), true)
