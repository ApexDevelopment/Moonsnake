-- Smoke test: injects Lua native functions and verifies they're callable from Python.
-- Run from project root: lua5.1 test/test_natives_api.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local vm    = require("src.vm")
local types = require("src.vm.types")

local py_src = [[
x = 10
double_it(x)
assert_equal(square(x), 100)
]]

-- Compile the source snippet to a .pyc
local py_tmp  = "test/.pyc_cache/_natives_test.py"
local pyc_tmp = "test/.pyc_cache/_natives_test.pyc"

local f = io.open(py_tmp, "w")
f:write(py_src)
f:close()

local ok = os.execute(string.format(
    'python -c "import py_compile; py_compile.compile(\'%s\', \'%s\', doraise=True)"',
    py_tmp:gsub("\\", "/"), pyc_tmp:gsub("\\", "/")))

assert(ok == 0 or ok == true, "Python compile failed")

-- Custom natives
local side_effect = {}
local extras = {
    double_it = function(n)
        side_effect[#side_effect + 1] = n * 2
        return types.PyNone
    end,
    square = function(n)
        return n * n
    end,
    assert_equal = function(a, b)
        if a ~= b then
            error(string.format("assert_equal failed: %s ~= %s", tostring(a), tostring(b)))
        end
        return types.PyNone
    end,
}

local run_ok, err = pcall(function()
    vm.run_pyc(pyc_tmp, extras)
end)

os.remove(py_tmp)
os.remove(pyc_tmp)

assert(run_ok, "VM error: " .. tostring(err))
assert(side_effect[1] == 20, "double_it should have produced 20, got " .. tostring(side_effect[1]))

print("PASS: native functions callable from Python")
print("PASS: return values usable in Python expressions")
print("PASS: side effects visible in Lua after execution")
