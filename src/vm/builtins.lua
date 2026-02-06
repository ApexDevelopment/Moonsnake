-- PythonInLua: Built-in functions
--
-- Each builtin is a Lua function that receives Python-style arguments
-- (as a flat list from the VM stack) and returns a Python value.

local types = require("src.vm.types")

local M = {}

---------------------------------------------------------------------------
-- print(*args, sep=' ', end='\n')
-- For now we only support positional args (no keyword args).
---------------------------------------------------------------------------
function M.print(...)
    local args = { ... }
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = types.py_str(args[i])
    end
    local output = table.concat(parts, " ")
    io.write(output .. "\n")
    return types.PyNone
end

---------------------------------------------------------------------------
-- len(obj)
---------------------------------------------------------------------------
function M.len(obj)
    if type(obj) == "string" then
        return #obj
    end
    if type(obj) == "table" then
        -- For list-like tables (array part)
        return #obj
    end
    error("TypeError: object of type '" .. type(obj) .. "' has no len()")
end

---------------------------------------------------------------------------
-- type(obj)  — returns the type name as a string for now
---------------------------------------------------------------------------
function M.type(obj)
    if obj == types.PyNone then
        return "<class 'NoneType'>"
    elseif obj == true or obj == false then
        return "<class 'bool'>"
    elseif type(obj) == "number" then
        if obj == math.floor(obj) then
            return "<class 'int'>"
        else
            return "<class 'float'>"
        end
    elseif type(obj) == "string" then
        return "<class 'str'>"
    elseif type(obj) == "table" and obj._pytype == "function" then
        return "<class 'function'>"
    else
        return "<class '" .. type(obj) .. "'>"
    end
end

---------------------------------------------------------------------------
-- Builtin namespace: a table mapping name -> function
---------------------------------------------------------------------------
M.builtins = {
    print = M.print,
    len   = M.len,
    type  = M.type,
}

return M
