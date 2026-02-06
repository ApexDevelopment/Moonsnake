-- PythonInLua: CLI entry point
-- Usage: lua src/main.lua <file.pyc>

-- Set up the module search path so require() finds our modules.
-- We assume this is run from the project root.
package.path = "./?.lua;./?/init.lua;" .. package.path

local vm = require("src.vm")

local args = arg or {}
if #args < 1 then
    io.stderr:write("Usage: lua src/main.lua <file.pyc>\n")
    os.exit(1)
end

local filepath = args[1]

local ok, err = pcall(function()
    vm.run_pyc(filepath)
end)

if not ok then
    io.stderr:write("Error: " .. tostring(err) .. "\n")
    os.exit(1)
end
