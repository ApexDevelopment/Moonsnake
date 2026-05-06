-- PythonInLua: Python type representations in Lua
--
-- Python has distinct None, True, False singletons and a strict truthiness
-- model. Lua's nil and boolean don't map cleanly (nil disappears from tables,
-- Python False is falsy but Lua false also means "absent" in many idioms).
-- This module provides sentinel values and truthiness helpers.

local M = {}

---------------------------------------------------------------------------
-- Singletons
---------------------------------------------------------------------------

--- Python None, represented as a unique table so it is distinct from Lua nil.
--- We need this because nil cannot be stored in Lua tables or pushed onto
--- the VM stack as a real value.
M.PyNone = { _pytype = "NoneType" }
setmetatable(M.PyNone, {
    __tostring = function() return "None" end,
})

--- We reuse Lua booleans for True/False since they compare correctly.
--- These aliases exist for clarity.
M.PyTrue  = true
M.PyFalse = false

---------------------------------------------------------------------------
-- Python function object
---------------------------------------------------------------------------

--- Create a Python function value wrapping a code object.
--- @param code table  The code object from marshal
--- @param globals table  The global namespace the function closes over
--- @param name string|nil  Optional function name
function M.PyFunction(code, globals, name)
    return {
        _pytype  = "function",
        code     = code,
        globals  = globals,
        name     = name or code.co_name or "<unknown>",
    }
end

---------------------------------------------------------------------------
-- Truthiness
---------------------------------------------------------------------------

--- Python truthiness rules:
---   False, None, 0, 0.0, "", empty containers → falsy
---   Everything else → truthy
function M.is_truthy(val)
    if val == nil or val == false then
        return false
    end
    if val == M.PyNone then
        return false
    end
    if val == 0 or val == 0.0 then
        return false
    end
    if type(val) == "string" and val == "" then
        return false
    end
    if type(val) == "table" then
        -- Empty list/dict/set: table with _pytype and no elements
        -- For now, non-sentinel tables are truthy (containers TBD)
    end
    return true
end

---------------------------------------------------------------------------
-- String conversion (for print, str(), etc.)
---------------------------------------------------------------------------

--- Convert a Python value to its string representation (like str())
function M.py_str(val)
    if val == nil then
        -- This shouldn't happen on the VM stack (we use PyNone), but safety:
        return "None"
    end
    if val == M.PyNone then
        return "None"
    end
    if val == true then
        return "True"
    end
    if val == false then
        return "False"
    end
    if type(val) == "number" then
        -- Python prints integers without .0
        if val == math.floor(val) and val ~= math.huge and val ~= -math.huge then
            return string.format("%d", val)
        else
            return tostring(val)
        end
    end
    if type(val) == "string" then
        return val
    end
    if type(val) == "table" and val._pytype == "function" then
        return "<function " .. (val.name or "?") .. ">"
    end
    return tostring(val)
end

--- Convert a Python value to its repr() form
function M.py_repr(val)
    if type(val) == "string" then
        local escaped = val:gsub("\\", "\\\\"):gsub("'", "\\'")
                           :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return "'" .. escaped .. "'"
    end
    return M.py_str(val)
end

--- Convert a Python value to its ascii() form (repr with non-ASCII escaped).
--- For ASCII-only strings this is identical to repr().
function M.py_ascii(val)
    local r = M.py_repr(val)
    -- Replace non-ASCII bytes with \xNN escapes (simple Lua 5.1 approach)
    return (r:gsub("[\128-\255]", function(c)
        return string.format("\\x%02x", string.byte(c))
    end))
end

---------------------------------------------------------------------------
-- Python format() — implements the format spec mini-language
---------------------------------------------------------------------------

--- Apply a Python format spec string to val.
--- Handles the common subset: [[fill]align][sign][0][width][.prec][type]
--- Types: f, F, e, E, g, G, d, x, X, o, b, s, c, % and empty (str)
function M.py_format(val, spec)
    if spec == nil or spec == "" then
        return M.py_str(val)
    end

    local s = spec
    local fill  = " "
    local align = nil
    local sign  = ""
    local width = 0
    local precision = nil
    local ftype = ""

    -- [[fill]align]
    if #s >= 2 then
        local ch2 = s:sub(2, 2)
        if ch2 == "<" or ch2 == ">" or ch2 == "^" or ch2 == "=" then
            fill  = s:sub(1, 1)
            align = ch2
            s = s:sub(3)
        end
    end
    if align == nil and #s >= 1 then
        local ch1 = s:sub(1, 1)
        if ch1 == "<" or ch1 == ">" or ch1 == "^" or ch1 == "=" then
            align = ch1
            s = s:sub(2)
        end
    end

    -- [sign]
    if #s >= 1 then
        local c = s:sub(1, 1)
        if c == "+" or c == "-" or c == " " then
            sign = c
            s = s:sub(2)
        end
    end

    -- [#] alternate — skip silently
    if #s >= 1 and s:sub(1, 1) == "#" then
        s = s:sub(2)
    end

    -- [0] zero-padding shorthand
    if #s >= 1 and s:sub(1, 1) == "0" and align == nil then
        fill  = "0"
        align = "="
        s = s:sub(2)
    end

    -- [width]
    local wm = s:match("^(%d+)")
    if wm then
        width = tonumber(wm)
        s = s:sub(#wm + 1)
    end

    -- [grouping: _ or ,] — skip silently
    if #s >= 1 and (s:sub(1, 1) == "_" or s:sub(1, 1) == ",") then
        s = s:sub(2)
    end

    -- [.precision]
    if #s >= 1 and s:sub(1, 1) == "." then
        s = s:sub(2)
        local pm = s:match("^(%d*)")
        precision = tonumber(pm) or 0
        s = s:sub(#pm + 1)
    end

    ftype = s  -- whatever remains is the type char

    -- Format the value into a string
    local result
    local is_num = type(val) == "number"

    if ftype == "f" or ftype == "F" then
        local prec = precision ~= nil and precision or 6
        result = string.format("%." .. prec .. "f", val)
        if ftype == "F" then result = result:upper() end
    elseif ftype == "e" or ftype == "E" then
        local prec = precision ~= nil and precision or 6
        result = string.format("%." .. prec .. ftype, val)
    elseif ftype == "g" or ftype == "G" then
        local prec = (precision ~= nil and precision > 0) and precision or 6
        result = string.format("%." .. prec .. ftype, val)
    elseif ftype == "d" or ftype == "i" or ftype == "u" then
        result = string.format("%d", math.floor(val))
    elseif ftype == "x" then
        result = string.format("%x", math.floor(val))
    elseif ftype == "X" then
        result = string.format("%X", math.floor(val))
    elseif ftype == "o" then
        result = string.format("%o", math.floor(val))
    elseif ftype == "b" then
        local n = math.abs(math.floor(val))
        if n == 0 then
            result = "0"
        else
            local bits = {}
            while n > 0 do
                table.insert(bits, 1, tostring(n % 2))
                n = math.floor(n / 2)
            end
            result = table.concat(bits)
        end
        if val < 0 then result = "-" .. result end
    elseif ftype == "%" then
        local prec = precision ~= nil and precision or 6
        result = string.format("%." .. prec .. "f%%", val * 100)
    elseif ftype == "c" then
        result = type(val) == "number" and string.char(math.floor(val)) or M.py_str(val)
    else
        -- "s" or ""
        result = M.py_str(val)
        if precision ~= nil then
            result = result:sub(1, precision)
        end
    end

    -- Apply sign to positive numbers
    if is_num and sign == "+" and result:sub(1, 1) ~= "-" then
        result = "+" .. result
    elseif is_num and sign == " " and result:sub(1, 1) ~= "-" then
        result = " " .. result
    end

    -- Apply width / alignment padding
    if width > 0 and #result < width then
        local pad = width - #result
        local eff = align or (is_num and ">" or "<")
        if eff == "<" then
            result = result .. string.rep(fill, pad)
        elseif eff == ">" then
            result = string.rep(fill, pad) .. result
        elseif eff == "^" then
            local lp = math.floor(pad / 2)
            result = string.rep(fill, lp) .. result .. string.rep(fill, pad - lp)
        elseif eff == "=" then
            -- sign-aware: padding goes between sign/prefix and digits
            local prefix = ""
            local rest   = result
            local fc = result:sub(1, 1)
            if fc == "+" or fc == "-" or fc == " " then
                prefix = fc
                rest   = result:sub(2)
            end
            result = prefix .. string.rep(fill, pad) .. rest
        end
    end

    return result
end

---------------------------------------------------------------------------
-- Iterator protocol
---------------------------------------------------------------------------

--- Create a range iterator. Returns a table with _pytype="iterator"
--- and a next() method that returns nil when exhausted.
function M.make_range_iter(start, stop, step)
    local current = start
    return {
        _pytype = "iterator",
        next = function()
            if step > 0 then
                if current >= stop then return nil end
            else
                if current <= stop then return nil end
            end
            local val = current
            current = current + step
            return val
        end,
    }
end

--- Create a list iterator.
function M.make_list_iter(list)
    local idx = 1
    return {
        _pytype = "iterator",
        next = function()
            if idx > #list then return nil end
            local val = list[idx]
            idx = idx + 1
            return val
        end,
    }
end

--- Get an iterator from a value (Python __iter__ protocol).
function M.get_iter(val)
    if type(val) == "table" and val._pytype == "iterator" then
        return val  -- already an iterator
    end
    if type(val) == "table" and val._pytype == "range" then
        return M.make_range_iter(val.start, val.stop, val.step)
    end
    if type(val) == "table" and val._pytype == "list" then
        return M.make_list_iter(val)
    end
    if type(val) == "string" then
        -- Iterate over characters
        local idx = 1
        return {
            _pytype = "iterator",
            next = function()
                if idx > #val then return nil end
                local ch = val:sub(idx, idx)
                idx = idx + 1
                return ch
            end,
        }
    end
    error("TypeError: '" .. M.py_str(val) .. "' object is not iterable")
end

--- Advance an iterator, returning the next value or nil if exhausted.
function M.iter_next(iter)
    if type(iter) == "table" and iter._pytype == "iterator" and iter.next then
        return iter.next()
    end
    error("TypeError: not an iterator")
end

return M
