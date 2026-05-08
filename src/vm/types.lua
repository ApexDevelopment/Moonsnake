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
    if type(val) == "table" and val._pytype == "file" then
        return "<_io.TextIOWrapper name='" .. tostring(val._name) .. "' mode='" .. tostring(val._mode) .. "' encoding='UTF-8'>"
    end
    if type(val) == "table" and val._pytype == "list" then
        local parts = {}
        for i = 1, #val do
            parts[i] = M.py_repr(val[i])
        end
        return "[" .. table.concat(parts, ", ") .. "]"
    end
    if type(val) == "table" and val._pytype == "dict" then
        local parts = {}
        for i, k in ipairs(val.keys) do
            parts[i] = M.py_repr(k) .. ": " .. M.py_repr(val.data[k])
        end
        return "{" .. table.concat(parts, ", ") .. "}"
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
    if type(val) == "table" and val._pytype == "dict" then
        -- Dict iteration yields keys in insertion order
        return M.make_list_iter(val.keys)
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

---------------------------------------------------------------------------
-- Attribute access: string and list method dispatch
---------------------------------------------------------------------------

-- Escape characters special inside a Lua [ ] character class.
local function cc(chars)
    return "[" .. chars:gsub("([%^%-%]%%])", "%%%1") .. "]"
end

local str_methods = {
    upper = function(s) return s:upper() end,
    lower = function(s) return s:lower() end,

    strip = function(s, chars)
        if chars == nil or chars == M.PyNone then
            return (s:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        local p = cc(chars)
        return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", ""))
    end,
    lstrip = function(s, chars)
        if chars == nil or chars == M.PyNone then return (s:gsub("^%s+", "")) end
        return (s:gsub("^" .. cc(chars) .. "+", ""))
    end,
    rstrip = function(s, chars)
        if chars == nil or chars == M.PyNone then return (s:gsub("%s+$", "")) end
        return (s:gsub(cc(chars) .. "+$", ""))
    end,

    split = function(s, sep, maxsplit)
        if maxsplit == nil or maxsplit == M.PyNone then maxsplit = -1 end
        local result = { _pytype = "list" }
        if sep == nil or sep == M.PyNone then
            for tok in s:gmatch("%S+") do result[#result + 1] = tok end
        else
            local start, count = 1, 0
            while true do
                if maxsplit >= 0 and count >= maxsplit then
                    result[#result + 1] = s:sub(start); break
                end
                local b, e = s:find(sep, start, true)
                if not b then result[#result + 1] = s:sub(start); break end
                result[#result + 1] = s:sub(start, b - 1)
                start = e + 1; count = count + 1
            end
        end
        return result
    end,

    join = function(s, iterable)
        local items = {}
        local iter = M.get_iter(iterable)
        local v = M.iter_next(iter)
        while v ~= nil do
            if type(v) ~= "string" then
                error("TypeError: sequence item must be str, not '" .. type(v) .. "'")
            end
            items[#items + 1] = v
            v = M.iter_next(iter)
        end
        return table.concat(items, s)
    end,

    replace = function(s, old, new, count)
        if count == nil or count == M.PyNone then count = -1 end
        if #old == 0 then
            local p = { new }
            for i = 1, #s do p[#p + 1] = s:sub(i,i); p[#p + 1] = new end
            return table.concat(p)
        end
        local result, start, n = {}, 1, 0
        while true do
            if count >= 0 and n >= count then result[#result + 1] = s:sub(start); break end
            local b, e = s:find(old, start, true)
            if not b then result[#result + 1] = s:sub(start); break end
            result[#result + 1] = s:sub(start, b - 1)
            result[#result + 1] = new
            start = e + 1; n = n + 1
        end
        return table.concat(result)
    end,

    find = function(s, sub, start)
        local ls = (start == nil or start == M.PyNone) and 0 or start
        local lua_s = ls >= 0 and ls + 1 or math.max(1, #s + ls + 1)
        local pos = s:find(sub, lua_s, true)
        return pos ~= nil and pos - 1 or -1
    end,
    index = function(s, sub, start)
        local ls = (start == nil or start == M.PyNone) and 0 or start
        local lua_s = ls >= 0 and ls + 1 or math.max(1, #s + ls + 1)
        local pos = s:find(sub, lua_s, true)
        if not pos then error("ValueError: substring not found") end
        return pos - 1
    end,

    startswith = function(s, prefix) return s:sub(1, #prefix) == prefix end,
    endswith   = function(s, suffix)
        if #suffix == 0 then return true end
        return s:sub(-#suffix) == suffix
    end,

    count = function(s, sub)
        if #sub == 0 then return #s + 1 end
        local n, start = 0, 1
        while true do
            local b, e = s:find(sub, start, true)
            if not b then break end
            n = n + 1; start = e + 1
        end
        return n
    end,

    isdigit = function(s) return #s > 0 and s:match("^%d+$") ~= nil end,
    isalpha = function(s) return #s > 0 and s:match("^%a+$") ~= nil end,
    isalnum = function(s) return #s > 0 and s:match("^%w+$") ~= nil end,
    isspace = function(s) return #s > 0 and s:match("^%s+$") ~= nil end,
    islower = function(s) return #s > 0 and s == s:lower() and s:match("%a") ~= nil end,
    isupper = function(s) return #s > 0 and s == s:upper() and s:match("%a") ~= nil end,

    zfill = function(s, w)
        local pad = w - #s
        if pad <= 0 then return s end
        local sign = s:sub(1,1)
        if sign == "+" or sign == "-" then return sign .. string.rep("0", pad) .. s:sub(2) end
        return string.rep("0", pad) .. s
    end,
    center = function(s, w, fill)
        fill = (fill == nil or fill == M.PyNone) and " " or fill
        local pad = w - #s
        if pad <= 0 then return s end
        local lp = math.floor(pad / 2)
        return string.rep(fill, lp) .. s .. string.rep(fill, pad - lp)
    end,
    ljust = function(s, w, fill)
        fill = (fill == nil or fill == M.PyNone) and " " or fill
        local pad = w - #s
        return pad > 0 and s .. string.rep(fill, pad) or s
    end,
    rjust = function(s, w, fill)
        fill = (fill == nil or fill == M.PyNone) and " " or fill
        local pad = w - #s
        return pad > 0 and string.rep(fill, pad) .. s or s
    end,
}

local list_methods = {
    append = function(lst, item)
        lst[#lst + 1] = item; return M.PyNone
    end,
    extend = function(lst, iterable)
        local iter = M.get_iter(iterable)
        local v = M.iter_next(iter)
        while v ~= nil do lst[#lst + 1] = v; v = M.iter_next(iter) end
        return M.PyNone
    end,
    pop = function(lst, index)
        local n = #lst
        if n == 0 then error("IndexError: pop from empty list") end
        if index == nil or index == M.PyNone then index = n - 1 end
        local lua_i = index >= 0 and index + 1 or n + index + 1
        if lua_i < 1 or lua_i > n then error("IndexError: pop index out of range") end
        local val = lst[lua_i]
        table.remove(lst, lua_i)
        return val
    end,
    insert = function(lst, index, item)
        local n = #lst
        local lua_i = index >= 0 and index + 1 or n + index + 2
        lua_i = math.max(1, math.min(n + 1, lua_i))
        table.insert(lst, lua_i, item)
        return M.PyNone
    end,
    remove = function(lst, item)
        for i = 1, #lst do
            if lst[i] == item then table.remove(lst, i); return M.PyNone end
        end
        error("ValueError: list.remove(x): x not in list")
    end,
    sort = function(lst)
        table.sort(lst, function(a, b)
            if type(a) == type(b) then return a < b end
            return M.py_str(a) < M.py_str(b)
        end)
        return M.PyNone
    end,
    reverse = function(lst)
        local n = #lst
        for i = 1, math.floor(n / 2) do lst[i], lst[n-i+1] = lst[n-i+1], lst[i] end
        return M.PyNone
    end,
    index = function(lst, item, start)
        local ls = (start == nil or start == M.PyNone) and 0 or start
        local lua_s = ls >= 0 and ls + 1 or math.max(1, #lst + ls + 1)
        for i = lua_s, #lst do
            if lst[i] == item then return i - 1 end
        end
        error("ValueError: " .. M.py_repr(item) .. " is not in list")
    end,
    count = function(lst, item)
        local n = 0
        for i = 1, #lst do if lst[i] == item then n = n + 1 end end
        return n
    end,
    clear = function(lst)
        for i = #lst, 1, -1 do lst[i] = nil end; return M.PyNone
    end,
    copy = function(lst)
        local r = { _pytype = "list" }
        for i = 1, #lst do r[i] = lst[i] end
        return r
    end,
}

local dict_methods = {
    keys = function(d)
        local r = { _pytype = "list" }
        for i, k in ipairs(d.keys) do r[i] = k end
        return r
    end,
    values = function(d)
        local r = { _pytype = "list" }
        for i, k in ipairs(d.keys) do r[i] = d.data[k] end
        return r
    end,
    items = function(d)
        local r = { _pytype = "list" }
        for i, k in ipairs(d.keys) do r[i] = { k, d.data[k] } end
        return r
    end,
    get = function(d, key, default)
        local v = d.data[key]
        if v ~= nil then return v end
        if default == nil then return M.PyNone end
        return default
    end,
    setdefault = function(d, key, default)
        local v = d.data[key]
        if v ~= nil then return v end
        if default == nil then default = M.PyNone end
        d.keys[#d.keys + 1] = key
        d.data[key] = default
        return default
    end,
    pop = function(d, key, default)
        local v = d.data[key]
        if v ~= nil then
            d.data[key] = nil
            for i, k in ipairs(d.keys) do
                if k == key then table.remove(d.keys, i); break end
            end
            return v
        end
        if default ~= nil then return default end
        error("KeyError: " .. M.py_repr(key))
    end,
    update = function(d, other)
        if type(other) == "table" and other._pytype == "dict" then
            for _, k in ipairs(other.keys) do
                if d.data[k] == nil then d.keys[#d.keys + 1] = k end
                d.data[k] = other.data[k]
            end
        else
            -- Iterable of (k,v) pairs
            local iter = M.get_iter(other)
            local pair = M.iter_next(iter)
            while pair ~= nil do
                local k, v = pair[1], pair[2]
                if d.data[k] == nil then d.keys[#d.keys + 1] = k end
                d.data[k] = v
                pair = M.iter_next(iter)
            end
        end
        return M.PyNone
    end,
    clear = function(d)
        for i = #d.keys, 1, -1 do d.keys[i] = nil end
        for k in pairs(d.data) do d.data[k] = nil end
        return M.PyNone
    end,
    copy = function(d)
        local r = { _pytype = "dict", keys = {}, data = {} }
        for i, k in ipairs(d.keys) do r.keys[i] = k; r.data[k] = d.data[k] end
        return r
    end,
}

---------------------------------------------------------------------------
-- File object
---------------------------------------------------------------------------

local file_methods = {
    read = function(self, n)
        if self._closed then error("ValueError: I/O operation on closed file") end
        if n == nil or n == M.PyNone then
            return self._handle:read("*a") or ""
        end
        if type(n) == "number" then
            if n < 0 then return self._handle:read("*a") or "" end
            return self._handle:read(n) or ""
        end
        error("TypeError: read() argument must be int or None")
    end,

    readline = function(self)
        if self._closed then error("ValueError: I/O operation on closed file") end
        -- Read char-by-char so we can preserve the \n (Lua "*l" strips it)
        local buf = {}
        while true do
            local c = self._handle:read(1)
            if c == nil then break end
            buf[#buf + 1] = c
            if c == "\n" then break end
        end
        return table.concat(buf)
    end,

    readlines = function(self)
        if self._closed then error("ValueError: I/O operation on closed file") end
        local lines = { _pytype = "list" }
        while true do
            local buf = {}
            while true do
                local c = self._handle:read(1)
                if c == nil then break end
                buf[#buf + 1] = c
                if c == "\n" then break end
            end
            if #buf == 0 then break end
            lines[#lines + 1] = table.concat(buf)
        end
        return lines
    end,

    write = function(self, s)
        if self._closed then error("ValueError: I/O operation on closed file") end
        if type(s) ~= "string" then
            error("TypeError: write() argument must be str, not '" .. type(s) .. "'")
        end
        self._handle:write(s)
        return #s
    end,

    close = function(self)
        if not self._closed then
            self._handle:close()
            self._closed = true
        end
        return M.PyNone
    end,

    __enter__ = function(self)
        return self
    end,

    __exit__ = function(self, ...)
        if not self._closed then
            self._handle:close()
            self._closed = true
        end
        return false
    end,
}

--- Construct a file object wrapping a Lua file handle.
function M.PyFile(handle, name, mode)
    return { _pytype = "file", _handle = handle, _name = name, _mode = mode, _closed = false }
end

--- Return the named attribute from obj, or error with AttributeError.
--- Methods are returned as raw functions taking (self, ...).
function M.get_attr(obj, name)
    if type(obj) == "string" then
        local m = str_methods[name]
        if m then return m end
        error("AttributeError: 'str' object has no attribute '" .. name .. "'")
    end
    if type(obj) == "table" then
        if obj._pytype == "list" then
            local m = list_methods[name]
            if m then return m end
            error("AttributeError: 'list' object has no attribute '" .. name .. "'")
        end
        if obj._pytype == "dict" then
            local m = dict_methods[name]
            if m then return m end
            error("AttributeError: 'dict' object has no attribute '" .. name .. "'")
        end
        if obj._pytype == "file" then
            local m = file_methods[name]
            if m then return m end
            error("AttributeError: '_io.TextIOWrapper' object has no attribute '" .. name .. "'")
        end
        if obj._pytype == "function" then
            if name == "__name__" then return obj.name or "<unknown>" end
            error("AttributeError: 'function' object has no attribute '" .. name .. "'")
        end
        if obj._pytype == "NoneType" then
            error("AttributeError: 'NoneType' object has no attribute '" .. name .. "'")
        end
        -- Generic object with attrs dict (class instances once classes land)
        if obj.attrs then
            local v = obj.attrs[name]
            if v ~= nil then return v end
        end
    end
    error("AttributeError: '" .. M.py_str(obj) .. "' object has no attribute '" .. name .. "'")
end

--- Set an attribute on obj.
function M.set_attr(obj, name, val)
    if type(obj) == "table" then
        if obj.attrs == nil then obj.attrs = {} end
        obj.attrs[name] = val
        return
    end
    error("AttributeError: cannot set attribute '" .. name .. "' on " .. type(obj))
end

--- Subscript read: obj[key]  (0-based integer key for sequences, hash key for dicts).
function M.get_subscript(obj, key)
    if type(obj) == "string" then
        local n = #obj
        local i = key >= 0 and key + 1 or n + key + 1
        if i < 1 or i > n then error("IndexError: string index out of range") end
        return obj:sub(i, i)
    end
    if type(obj) == "table" then
        if obj._pytype == "dict" then
            local v = obj.data[key]
            if v == nil then error("KeyError: " .. M.py_repr(key)) end
            return v
        end
        if obj._pytype == "list" or obj._pytype == nil then
            local n = #obj
            local i = key >= 0 and key + 1 or n + key + 1
            if i < 1 or i > n then error("IndexError: list index out of range") end
            local v = obj[i]
            return v ~= nil and v or M.PyNone
        end
    end
    error("TypeError: '" .. M.py_str(obj) .. "' object is not subscriptable")
end

--- Subscript write: obj[key] = val.
function M.set_subscript(obj, key, val)
    if type(obj) == "table" then
        if obj._pytype == "dict" then
            if obj.data[key] == nil then
                obj.keys[#obj.keys + 1] = key
            end
            obj.data[key] = val
            return
        end
        if obj._pytype == "list" or obj._pytype == nil then
            local n = #obj
            local i = key >= 0 and key + 1 or n + key + 1
            obj[i] = val
            return
        end
    end
    error("TypeError: '" .. M.py_str(obj) .. "' object does not support item assignment")
end

--- Subscript delete: del obj[key].
function M.del_subscript(obj, key)
    if type(obj) == "table" then
        if obj._pytype == "dict" then
            if obj.data[key] == nil then error("KeyError: " .. M.py_repr(key)) end
            obj.data[key] = nil
            for i, k in ipairs(obj.keys) do
                if k == key then table.remove(obj.keys, i); break end
            end
            return
        end
        if obj._pytype == "list" then
            local n = #obj
            local i = key >= 0 and key + 1 or n + key + 1
            if i < 1 or i > n then error("IndexError: list assignment index out of range") end
            table.remove(obj, i)
            return
        end
    end
    error("TypeError: '" .. M.py_str(obj) .. "' object does not support item deletion")
end

return M
