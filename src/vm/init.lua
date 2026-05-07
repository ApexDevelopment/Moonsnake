-- PythonInLua VM: top-level entry point
--
-- Usage:
--   local vm = require("src.vm")
--   vm.run_pyc("path/to/file.pyc")

local marshal     = require("src.vm.marshal")
local interpreter = require("src.vm.interpreter")
local builtins    = require("src.vm.builtins")

local M = {}

-- Merge extras (Lua function table) into a copy of the builtins namespace.
local function make_builtins(extras)
    if not extras then return builtins.builtins end
    local t = {}
    for k, v in pairs(builtins.builtins) do t[k] = v end
    for k, v in pairs(extras) do t[k] = v end
    return t
end

--- Load and execute a .pyc file.
--- @param filepath string   Path to the .pyc file
--- @param extras  table|nil Optional table of Lua functions to inject into the Python global namespace
--- @return any  The return value of the module (usually None)
function M.run_pyc(filepath, extras)
    local code = marshal.load_pyc(filepath)
    return interpreter.execute(code, make_builtins(extras))
end

--- Execute a code object directly (useful for testing).
--- @param code   table      A code object from the marshal module
--- @param extras table|nil  Optional extra natives (same as run_pyc)
--- @return any  The return value
function M.run_code(code, extras)
    return interpreter.execute(code, make_builtins(extras))
end

--- Load a .pyc file and return the code object without executing.
--- @param filepath string  Path to the .pyc file
--- @return table  The code object
function M.load_pyc(filepath)
    return marshal.load_pyc(filepath)
end

return M
