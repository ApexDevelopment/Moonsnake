-- PythonInLua: CLI entry point
-- Usage: lua src/main.lua <file.pyc>

-- Set up the module search path so require() finds our modules.
-- We assume this is run from the project root.
package.path = "./?.lua;./?/init.lua;" .. package.path

local vm = require("src.vm")

local args = arg or {}

-- Parse: lua src/main.lua [--native <natives.lua>] <file.pyc>
local filepath    = nil
local native_file = nil
local i = 1
while i <= #args do
    if args[i] == "--native" and args[i + 1] then
        native_file = args[i + 1]
        i = i + 2
    else
        filepath = args[i]
        i = i + 1
    end
end

if not filepath then
    io.stderr:write("Usage: lua src/main.lua [--native <natives.lua>] <file.pyc>\n")
    io.stderr:write("  --native <file>  Lua file that returns a table of functions to\n")
    io.stderr:write("                   inject into the Python global namespace.\n")
    os.exit(1)
end

-- Load optional native extensions
local extras = nil
if native_file then
    local chunk, load_err = loadfile(native_file)
    if not chunk then
        io.stderr:write("Error loading native file: " .. tostring(load_err) .. "\n")
        os.exit(1)
    end
    extras = chunk()
    if type(extras) ~= "table" then
        io.stderr:write("Native file must return a table of functions, got: " .. type(extras) .. "\n")
        os.exit(1)
    end
end

local ok, err = pcall(function()
    vm.run_pyc(filepath, extras)
end)

if not ok then
    io.stderr:write("Error: " .. tostring(err) .. "\n")
    os.exit(1)
end
