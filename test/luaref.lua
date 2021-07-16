local lt = require "ltest"
local luaref = require "testlib.luaref"

local m = lt.test "luaref"

function m.test_init()
    local ref = luaref.init()
    luaref.close(ref)
end

function m.test_ref()
    local ref = luaref.init()
    lt.assertEquals(luaref.ref(ref), 2)
    lt.assertEquals(luaref.ref(ref), 3)
    lt.assertEquals(luaref.ref(ref), 4)
    luaref.close(ref)
end

function m.test_get()
    local ref = luaref.init()
    local lst = {
        1, 2, 3, 4, 5,
        1.2345, {}, "ok"
    }
    local r = {}
    for i, v in ipairs(lst) do
        r[i] = luaref.ref(ref, v)
    end
    for i, v in ipairs(lst) do
        lt.assertEquals(v, luaref.get(ref, r[i]))
    end
    luaref.close(ref)
end

function m.test_unref()
    local ref = luaref.init()
    local r = luaref.ref(ref, "hello")
    lt.assertEquals(luaref.get(ref, r), "hello")
    luaref.unref(ref, r)
    lt.assertError(luaref.get, ref, r)
    luaref.close(ref)
end

function m.test_isvalid()
    local ref = luaref.init()
    lt.assertEquals(luaref.isvalid(ref, -1), false)
    lt.assertEquals(luaref.isvalid(ref, 0), false)
    lt.assertEquals(luaref.isvalid(ref, 1), false)
    lt.assertEquals(luaref.isvalid(ref, 2), false)

    lt.assertEquals(luaref.ref(ref), 2)
    lt.assertEquals(luaref.isvalid(ref, 2), true)
    lt.assertEquals(luaref.isvalid(ref, 3), false)
    luaref.unref(ref, 2)
    lt.assertEquals(luaref.isvalid(ref, 2), false)

    lt.assertEquals(luaref.ref(ref), 2)
    lt.assertEquals(luaref.ref(ref), 3)
    lt.assertEquals(luaref.isvalid(ref, 2), true)
    lt.assertEquals(luaref.isvalid(ref, 3), true)
    lt.assertEquals(luaref.isvalid(ref, 4), false)
    luaref.unref(ref, 2)
    lt.assertEquals(luaref.isvalid(ref, 2), false)
    lt.assertEquals(luaref.isvalid(ref, 3), true)
    lt.assertEquals(luaref.isvalid(ref, 4), false)

    luaref.close(ref)
end

function m.test_freelist()
    local ref = luaref.init()

    lt.assertEquals(luaref.ref(ref), 2)
    luaref.unref(ref, 2)
    lt.assertEquals(luaref.ref(ref), 2)

    lt.assertEquals(luaref.ref(ref), 3)
    lt.assertEquals(luaref.ref(ref), 4)
    luaref.unref(ref, 3)
    lt.assertEquals(luaref.ref(ref), 3)

    luaref.close(ref)
end

function m.test_random()
    local ref = luaref.init()
    local map = {}
    local function add()
        local t = math.random()
        local r = luaref.ref(ref, t)
        map[t] = r
        return r
    end
    local function del()
        local t, r = next(map)
        if r then
            lt.assertEquals(t, luaref.get(ref, r))
            luaref.unref(ref, r)
            map[t] = nil
            return true
        end
    end
    for _ = 1, 2000 do
        add()
    end
    for _ = 1, 1000 do
        del()
    end
    for t, r in pairs(map) do
        lt.assertEquals(t, luaref.get(ref, r))
    end
    for _ = 1, 10000 do
        if 1 == math.random(2) then
            del()
        else
            add()
        end
    end
    while del() do
    end
    lt.assertIsNil(next(map))
    luaref.close(ref)
end
