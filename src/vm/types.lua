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
        return "'" .. val .. "'"
    end
    return M.py_str(val)
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
