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
        if obj._pytype == "dict" then return #obj.keys end
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
-- range(stop) / range(start, stop[, step])
---------------------------------------------------------------------------
function M.range(...)
    local args = { ... }
    local n = select("#", ...)
    local start, stop, step
    if n == 1 then
        start, stop, step = 0, args[1], 1
    elseif n == 2 then
        start, stop, step = args[1], args[2], 1
    elseif n == 3 then
        start, stop, step = args[1], args[2], args[3]
    else
        error("TypeError: range expected 1 to 3 arguments, got " .. n)
    end
    if step == 0 then
        error("ValueError: range() arg 3 must not be zero")
    end
    return {
        _pytype = "range",
        start   = start,
        stop    = stop,
        step    = step,
    }
end

---------------------------------------------------------------------------
-- int(x) — convert to integer
---------------------------------------------------------------------------
function M.int(x)
    if type(x) == "number" then
        return math.floor(x)
    elseif type(x) == "string" then
        local n = tonumber(x)
        if n == nil then
            error("ValueError: invalid literal for int() with base 10: '" .. x .. "'")
        end
        return math.floor(n)
    elseif x == true then
        return 1
    elseif x == false then
        return 0
    else
        error("TypeError: int() argument must be a string or a number, not '" .. type(x) .. "'")
    end
end

---------------------------------------------------------------------------
-- str(x) — convert to string
---------------------------------------------------------------------------
function M.str(x)
    return types.py_str(x)
end

---------------------------------------------------------------------------
-- abs(x)
---------------------------------------------------------------------------
function M.abs(x)
    if type(x) == "number" then
        return math.abs(x)
    end
    error("TypeError: bad operand type for abs(): '" .. type(x) .. "'")
end

---------------------------------------------------------------------------
-- min / max
---------------------------------------------------------------------------
function M.min(...)
    local args = { ... }
    local n = select("#", ...)
    if n == 0 then error("TypeError: min expected at least 1 argument, got 0") end
    local result = args[1]
    for i = 2, n do
        if args[i] < result then result = args[i] end
    end
    return result
end

function M.max(...)
    local args = { ... }
    local n = select("#", ...)
    if n == 0 then error("TypeError: max expected at least 1 argument, got 0") end
    local result = args[1]
    for i = 2, n do
        if args[i] > result then result = args[i] end
    end
    return result
end

---------------------------------------------------------------------------
-- bool(x)
---------------------------------------------------------------------------
function M.bool(x)
    return types.is_truthy(x)
end

---------------------------------------------------------------------------
-- open(path, mode='r')
---------------------------------------------------------------------------
function M.open(path, mode)
    if mode == nil or mode == types.PyNone then mode = "r" end
    -- Map Python modes to Lua modes
    local lua_mode = mode:gsub("b", "")  -- strip 'b' for binary; Lua handles both
    local handle, err = io.open(path, lua_mode)
    if not handle then
        error("FileNotFoundError: [Errno 2] No such file or directory: '" .. path .. "': " .. tostring(err))
    end
    return types.PyFile(handle, path, mode)
end

---------------------------------------------------------------------------
-- Builtin namespace: a table mapping name -> function
---------------------------------------------------------------------------
M.builtins = {
    print = M.print,
    len   = M.len,
    type  = M.type,
    range = M.range,
    int   = M.int,
    str   = M.str,
    abs   = M.abs,
    min   = M.min,
    max   = M.max,
    bool  = M.bool,
    open  = M.open,
}

return M
