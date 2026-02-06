-- PythonInLua VM: top-level entry point
--
-- Usage:
--   local vm = require("src.vm")
--   vm.run_pyc("path/to/file.pyc")

local marshal     = require("src.vm.marshal")
local interpreter = require("src.vm.interpreter")
local builtins    = require("src.vm.builtins")

local M = {}

--- Load and execute a .pyc file.
--- @param filepath string  Path to the .pyc file
--- @return any  The return value of the module (usually None)
function M.run_pyc(filepath)
    local code = marshal.load_pyc(filepath)
    return interpreter.execute(code, builtins.builtins)
end

--- Execute a code object directly (useful for testing).
--- @param code table  A code object from the marshal module
--- @return any  The return value
function M.run_code(code)
    return interpreter.execute(code, builtins.builtins)
end

--- Load a .pyc file and return the code object without executing.
--- @param filepath string  Path to the .pyc file
--- @return table  The code object
function M.load_pyc(filepath)
    return marshal.load_pyc(filepath)
end

return M
