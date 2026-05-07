-- Example native extension file for Moonsnake.
-- Pass to the CLI via:  lua5.1 src/main.lua --native test/natives_example.lua script.pyc
-- Or to the API via:    vm.run_pyc("script.pyc", require("test.natives_example"))

local types = require("src.vm.types")

return {
    -- Low-level value inspector: prints Python repr + Lua type side by side.
    debug_inspect = function(val)
        io.write(string.format("[inspect] %s  (%s)\n",
            types.py_repr(val), type(val)))
        return types.PyNone
    end,

    -- Assert two values are equal; errors loudly if not.
    assert_equal = function(a, b)
        if a ~= b then
            error(string.format("AssertionError: %s != %s",
                types.py_repr(a), types.py_repr(b)))
        end
        return types.PyNone
    end,
}
