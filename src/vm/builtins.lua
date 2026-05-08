-- PythonInLua: Built-in functions
--
-- Each builtin is a Lua function that receives Python-style arguments
-- (as a flat list from the VM stack) and returns a Python value.

local types       = require("src.vm.types")
local interpreter = require("src.vm.interpreter")

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
-- enumerate(iterable, start=0)
---------------------------------------------------------------------------
function M.enumerate(iterable, start)
    if start == nil or start == types.PyNone then start = 0 end
    local iter = types.get_iter(iterable)
    local idx = start
    return {
        _pytype = "iterator",
        next = function()
            local v = types.iter_next(iter)
            if v == nil then return nil end
            local pair = { idx, v }
            idx = idx + 1
            return pair
        end,
    }
end

---------------------------------------------------------------------------
-- zip(*iterables) — stops at the shortest iterable
---------------------------------------------------------------------------
function M.zip(...)
    local n = select("#", ...)
    if n == 0 then
        return { _pytype = "iterator", next = function() return nil end }
    end
    local iters = {}
    for i = 1, n do iters[i] = types.get_iter((select(i, ...))) end
    return {
        _pytype = "iterator",
        next = function()
            local result = {}
            for i = 1, n do
                local v = types.iter_next(iters[i])
                if v == nil then return nil end
                result[i] = v
            end
            return result
        end,
    }
end

---------------------------------------------------------------------------
-- map(func, *iterables) — yields func(item_1, ..., item_n) per step
---------------------------------------------------------------------------
function M.map(func, ...)
    local n = select("#", ...)
    if n == 0 then error("TypeError: map() requires at least one iterable") end
    local iters = {}
    for i = 1, n do iters[i] = types.get_iter((select(i, ...))) end
    return {
        _pytype = "iterator",
        next = function()
            local args = {}
            for i = 1, n do
                local v = types.iter_next(iters[i])
                if v == nil then return nil end
                args[i] = v
            end
            return interpreter.call_any(func, args)
        end,
    }
end

---------------------------------------------------------------------------
-- filter(func, iterable) — yields items where func(item) is truthy.
-- If func is None, yields items that are themselves truthy.
---------------------------------------------------------------------------
function M.filter(func, iterable)
    local iter = types.get_iter(iterable)
    local none_func = (func == nil or func == types.PyNone)
    return {
        _pytype = "iterator",
        next = function()
            while true do
                local v = types.iter_next(iter)
                if v == nil then return nil end
                local keep
                if none_func then
                    keep = types.is_truthy(v)
                else
                    keep = types.is_truthy(interpreter.call_any(func, { v }))
                end
                if keep then return v end
            end
        end,
    }
end

---------------------------------------------------------------------------
-- reversed(seq) — materializes the sequence then iterates back-to-front.
---------------------------------------------------------------------------
function M.reversed(seq)
    local items = {}
    if type(seq) == "string" then
        for i = 1, #seq do items[i] = seq:sub(i, i) end
    elseif type(seq) == "table" and (seq._pytype == "list" or seq._pytype == nil) then
        for i = 1, #seq do items[i] = seq[i] end
    elseif type(seq) == "table" and seq._pytype == "range" then
        local iter = types.get_iter(seq)
        local v = types.iter_next(iter)
        while v ~= nil do items[#items + 1] = v; v = types.iter_next(iter) end
    else
        error("TypeError: argument to reversed() must be a sequence")
    end
    local i = #items
    return {
        _pytype = "iterator",
        next = function()
            if i < 1 then return nil end
            local v = items[i]
            i = i - 1
            return v
        end,
    }
end

---------------------------------------------------------------------------
-- sorted(iterable) — returns a new sorted list. (key/reverse are kw-only
-- in CPython and CALL_KW isn't implemented yet, so we don't accept them.)
---------------------------------------------------------------------------
function M.sorted(iterable)
    local result = { _pytype = "list" }
    local iter = types.get_iter(iterable)
    local v = types.iter_next(iter)
    while v ~= nil do
        result[#result + 1] = v
        v = types.iter_next(iter)
    end
    table.sort(result, function(a, b)
        if type(a) == type(b) then return a < b end
        return types.py_str(a) < types.py_str(b)
    end)
    return result
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
    bool      = M.bool,
    open      = M.open,
    enumerate = M.enumerate,
    zip       = M.zip,
    map       = M.map,
    filter    = M.filter,
    reversed  = M.reversed,
    sorted    = M.sorted,
}

return M
