-- PythonInLua: Python 3.13 marshal/pyc unmarshaller
-- Reads .pyc files and returns code objects as Lua tables.
--
-- Reference: CPython Tools/build/umarshal.py, Python/marshal.c

local bit = require("src.lib.luabit")

local M = {}

---------------------------------------------------------------------------
-- Marshal type codes (from marshal.c)
---------------------------------------------------------------------------
local TYPE_NULL               = string.byte("0")  -- 0x30
local TYPE_NONE               = string.byte("N")  -- 0x4E
local TYPE_FALSE              = string.byte("F")  -- 0x46
local TYPE_TRUE               = string.byte("T")  -- 0x54
local TYPE_STOPITER           = string.byte("S")  -- 0x53
local TYPE_ELLIPSIS           = string.byte(".")  -- 0x2E
local TYPE_INT                = string.byte("i")  -- 0x69
local TYPE_INT64              = string.byte("I")  -- 0x49
local TYPE_FLOAT              = string.byte("f")  -- 0x66
local TYPE_BINARY_FLOAT       = string.byte("g")  -- 0x67
local TYPE_COMPLEX            = string.byte("x")  -- 0x78
local TYPE_BINARY_COMPLEX     = string.byte("y")  -- 0x79
local TYPE_LONG               = string.byte("l")  -- 0x6C
local TYPE_STRING             = string.byte("s")  -- 0x73
local TYPE_INTERNED           = string.byte("t")  -- 0x74
local TYPE_REF                = string.byte("r")  -- 0x72
local TYPE_TUPLE              = string.byte("(")  -- 0x28
local TYPE_LIST               = string.byte("[")  -- 0x5B
local TYPE_DICT               = string.byte("{")  -- 0x7B
local TYPE_CODE               = string.byte("c")  -- 0x63
local TYPE_UNICODE            = string.byte("u")  -- 0x75
local TYPE_UNKNOWN            = string.byte("?")  -- 0x3F
local TYPE_SET                = string.byte("<")  -- 0x3C
local TYPE_FROZENSET          = string.byte(">")  -- 0x3E
local TYPE_ASCII              = string.byte("a")  -- 0x61
local TYPE_ASCII_INTERNED     = string.byte("A")  -- 0x41
local TYPE_SMALL_TUPLE        = string.byte(")")  -- 0x29
local TYPE_SHORT_ASCII        = string.byte("z")  -- 0x7A
local TYPE_SHORT_ASCII_INTERNED = string.byte("Z") -- 0x5A

local FLAG_REF = 0x80

-- Sentinel for marshal NULL (distinct from Lua nil)
local MARSHAL_NULL = { _type = "MARSHAL_NULL" }
M.MARSHAL_NULL = MARSHAL_NULL

---------------------------------------------------------------------------
-- Reader object
---------------------------------------------------------------------------
local Reader = {}
Reader.__index = Reader

function Reader.new(data)
    local self = setmetatable({}, Reader)
    self.data = data
    self.pos = 1  -- Lua is 1-indexed
    self.len = #data
    self.refs = {}
    return self
end

function Reader:r_byte()
    if self.pos > self.len then
        error("marshal: unexpected end of data")
    end
    local b = string.byte(self.data, self.pos)
    self.pos = self.pos + 1
    return b
end

function Reader:r_bytes(n)
    if self.pos + n - 1 > self.len then
        error("marshal: unexpected end of data (need " .. n .. " bytes at pos " .. self.pos .. ")")
    end
    local s = string.sub(self.data, self.pos, self.pos + n - 1)
    self.pos = self.pos + n
    return s
end

--- Read a little-endian unsigned 16-bit integer
function Reader:r_ushort()
    local b0 = self:r_byte()
    local b1 = self:r_byte()
    return b0 + b1 * 256
end

--- Read a little-endian signed 16-bit integer
function Reader:r_short()
    local x = self:r_ushort()
    if x >= 0x8000 then
        x = x - 0x10000
    end
    return x
end

--- Read a little-endian unsigned 32-bit value (as a Lua number)
function Reader:r_ulong()
    local b0 = self:r_byte()
    local b1 = self:r_byte()
    local b2 = self:r_byte()
    local b3 = self:r_byte()
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

--- Read a little-endian signed 32-bit integer
function Reader:r_long()
    local x = self:r_ulong()
    if x >= 2147483648 then  -- 0x80000000
        x = x - 4294967296    -- 0x100000000
    end
    return x
end

--- Read a little-endian signed 64-bit integer (approximate, within Lua number precision)
function Reader:r_long64()
    local lo = self:r_ulong()
    local hi = self:r_ulong()
    -- Lua 5.1 doubles can represent integers exactly up to 2^53
    if hi >= 2147483648 then
        hi = hi - 4294967296
    end
    return hi * 4294967296 + lo
end

--- Read a Python long integer (arbitrary precision, stored as 15-bit digits)
function Reader:r_PyLong()
    local n = self:r_long()
    local size = math.abs(n)
    local x = 0
    for i = 0, size - 1 do
        local digit = self:r_ushort()
        x = x + digit * (2 ^ (i * 15))
    end
    if n < 0 then
        x = -x
    end
    return x
end

--- Read a binary-encoded 64-bit float (IEEE 754 double, little-endian)
function Reader:r_float_bin()
    local bytes = self:r_bytes(8)
    -- Decode IEEE 754 double from 8 bytes (little-endian)
    -- We use a manual decode since Lua 5.1 lacks string.unpack
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)

    -- Reassemble the 64-bit value
    local sign = math.floor(b8 / 128)
    local exponent = (b8 % 128) * 16 + math.floor(b7 / 16)
    local mantissa = (b7 % 16) * 2^48
                   + b6 * 2^40
                   + b5 * 2^32
                   + b4 * 2^24
                   + b3 * 2^16
                   + b2 * 2^8
                   + b1

    local value
    if exponent == 0 then
        if mantissa == 0 then
            value = 0.0
        else
            -- Denormalized
            value = mantissa / 2^52 * 2^(-1022)
        end
    elseif exponent == 2047 then
        if mantissa == 0 then
            value = math.huge
        else
            value = 0/0  -- NaN
        end
    else
        value = (1 + mantissa / 2^52) * 2^(exponent - 1023)
    end

    if sign == 1 then
        value = -value
    end
    return value
end

--- Read a string-encoded float
function Reader:r_float_str()
    local n = self:r_byte()
    local s = self:r_bytes(n)
    return tonumber(s)
end

---------------------------------------------------------------------------
-- Reference tracking (marshal v3+ object sharing)
---------------------------------------------------------------------------

function Reader:r_ref(obj)
    -- Append to ref table and return obj
    self.refs[#self.refs + 1] = obj
    return obj
end

function Reader:r_ref_reserve()
    local idx = #self.refs + 1
    self.refs[idx] = false  -- placeholder
    return idx
end

function Reader:r_ref_insert(obj, idx)
    self.refs[idx] = obj
    return obj
end

---------------------------------------------------------------------------
-- Object reader
---------------------------------------------------------------------------

function Reader:r_object()
    local code_byte = self:r_byte()
    local flag = bit.band(code_byte, FLAG_REF)
    local type_code = bit.band(code_byte, bit.bnot(FLAG_REF))

    -- Helper: conditionally add to ref table
    local function R_REF(obj)
        if flag ~= 0 then
            return self:r_ref(obj)
        end
        return obj
    end

    -- NULL
    if type_code == TYPE_NULL then
        return MARSHAL_NULL

    -- None
    elseif type_code == TYPE_NONE then
        return nil  -- We'll use a sentinel in types.lua; for marshal, nil works in consts

    -- False
    elseif type_code == TYPE_FALSE then
        return false

    -- True
    elseif type_code == TYPE_TRUE then
        return true

    -- Ellipsis
    elseif type_code == TYPE_ELLIPSIS then
        return { _type = "ellipsis" }

    -- StopIteration
    elseif type_code == TYPE_STOPITER then
        return { _type = "stopiter" }

    -- 32-bit integer
    elseif type_code == TYPE_INT then
        return R_REF(self:r_long())

    -- 64-bit integer
    elseif type_code == TYPE_INT64 then
        return R_REF(self:r_long64())

    -- Arbitrary-precision integer
    elseif type_code == TYPE_LONG then
        return R_REF(self:r_PyLong())

    -- String-encoded float (version 0)
    elseif type_code == TYPE_FLOAT then
        return R_REF(self:r_float_str())

    -- Binary float
    elseif type_code == TYPE_BINARY_FLOAT then
        return R_REF(self:r_float_bin())

    -- String-encoded complex (version 0)
    elseif type_code == TYPE_COMPLEX then
        local real = self:r_float_str()
        local imag = self:r_float_str()
        return R_REF({ _type = "complex", real = real, imag = imag })

    -- Binary complex
    elseif type_code == TYPE_BINARY_COMPLEX then
        local real = self:r_float_bin()
        local imag = self:r_float_bin()
        return R_REF({ _type = "complex", real = real, imag = imag })

    -- Bytes (TYPE_STRING is the Python 2 name; it's bytes in Python 3)
    elseif type_code == TYPE_STRING then
        local n = self:r_long()
        return R_REF(self:r_bytes(n))

    -- ASCII string (long length)
    elseif type_code == TYPE_ASCII or type_code == TYPE_ASCII_INTERNED then
        local n = self:r_long()
        return R_REF(self:r_bytes(n))

    -- Short ASCII string (byte length)
    elseif type_code == TYPE_SHORT_ASCII or type_code == TYPE_SHORT_ASCII_INTERNED then
        local n = self:r_byte()
        return R_REF(self:r_bytes(n))

    -- Unicode string (UTF-8 encoded)
    elseif type_code == TYPE_INTERNED or type_code == TYPE_UNICODE then
        local n = self:r_long()
        return R_REF(self:r_bytes(n))

    -- Small tuple (byte-sized count)
    elseif type_code == TYPE_SMALL_TUPLE then
        local n = self:r_byte()
        local idx
        if flag ~= 0 then
            idx = self:r_ref_reserve()
        end
        local t = {}
        for i = 1, n do
            t[i] = self:r_object()
        end
        if flag ~= 0 then
            self:r_ref_insert(t, idx)
        end
        return t

    -- Tuple (long-sized count)
    elseif type_code == TYPE_TUPLE then
        local n = self:r_long()
        local idx
        if flag ~= 0 then
            idx = self:r_ref_reserve()
        end
        local t = {}
        for i = 1, n do
            t[i] = self:r_object()
        end
        if flag ~= 0 then
            self:r_ref_insert(t, idx)
        end
        return t

    -- List
    elseif type_code == TYPE_LIST then
        local n = self:r_long()
        local t = R_REF({})
        for i = 1, n do
            t[i] = self:r_object()
        end
        return t

    -- Dict
    elseif type_code == TYPE_DICT then
        local t = R_REF({})
        while true do
            local key = self:r_object()
            if key == MARSHAL_NULL then break end
            local val = self:r_object()
            t[key] = val
        end
        return t

    -- Set
    elseif type_code == TYPE_SET then
        local n = self:r_long()
        local t = R_REF({})
        for _ = 1, n do
            local v = self:r_object()
            t[v] = true
        end
        return t

    -- Frozenset
    elseif type_code == TYPE_FROZENSET then
        local n = self:r_long()
        local idx
        if flag ~= 0 then
            idx = self:r_ref_reserve()
        end
        local t = {}
        for _ = 1, n do
            local v = self:r_object()
            t[v] = true
        end
        if flag ~= 0 then
            self:r_ref_insert(t, idx)
        end
        return t

    -- Code object
    elseif type_code == TYPE_CODE then
        local co = { _type = "code" }

        -- Apply ref reservation for code objects
        if flag ~= 0 then
            local idx = self:r_ref_reserve()
            -- Read all fields in the exact CPython 3.13 order
            co.co_argcount        = self:r_long()
            co.co_posonlyargcount = self:r_long()
            co.co_kwonlyargcount  = self:r_long()
            co.co_stacksize       = self:r_long()
            co.co_flags           = self:r_long()
            co.co_code            = self:r_object()  -- bytes (bytecode)
            co.co_consts          = self:r_object()  -- tuple
            co.co_names           = self:r_object()  -- tuple
            co.co_localsplusnames = self:r_object()  -- tuple
            co.co_localspluskinds = self:r_object()  -- bytes
            co.co_filename        = self:r_object()  -- string
            co.co_name            = self:r_object()  -- string
            co.co_qualname        = self:r_object()  -- string
            co.co_firstlineno     = self:r_long()
            co.co_linetable       = self:r_object()  -- bytes
            co.co_exceptiontable  = self:r_object()  -- bytes
            self:r_ref_insert(co, idx)
        else
            co.co_argcount        = self:r_long()
            co.co_posonlyargcount = self:r_long()
            co.co_kwonlyargcount  = self:r_long()
            co.co_stacksize       = self:r_long()
            co.co_flags           = self:r_long()
            co.co_code            = self:r_object()
            co.co_consts          = self:r_object()
            co.co_names           = self:r_object()
            co.co_localsplusnames = self:r_object()
            co.co_localspluskinds = self:r_object()
            co.co_filename        = self:r_object()
            co.co_name            = self:r_object()
            co.co_qualname        = self:r_object()
            co.co_firstlineno     = self:r_long()
            co.co_linetable       = self:r_object()
            co.co_exceptiontable  = self:r_object()
        end

        return co

    -- Reference to a previously-seen object
    elseif type_code == TYPE_REF then
        local n = self:r_long()
        -- refs are 0-indexed in CPython, 1-indexed in our Lua table
        local obj = self.refs[n + 1]
        if obj == nil then
            error("marshal: invalid reference index " .. n)
        end
        return obj

    else
        error(string.format("marshal: unknown type code 0x%02X ('%s') at position %d",
              type_code, string.char(type_code), self.pos - 1))
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Unmarshal a bytes string into a Lua representation
function M.loads(data)
    local reader = Reader.new(data)
    return reader:r_object()
end

--- Read a .pyc file and return the code object.
--- Validates the magic number for Python 3.13.
function M.load_pyc(filepath)
    local f, err = io.open(filepath, "rb")
    if not f then
        error("Cannot open file: " .. filepath .. " (" .. tostring(err) .. ")")
    end
    local data = f:read("*a")
    f:close()

    if #data < 16 then
        error("Invalid .pyc file: too short (" .. #data .. " bytes)")
    end

    -- Read 16-byte header
    local magic_lo = string.byte(data, 1) + string.byte(data, 2) * 256
    local magic_hi = string.byte(data, 3) + string.byte(data, 4) * 256

    -- Python 3.13 magic: 3571 (0x0DF3), followed by 0x0D0A
    if magic_lo ~= 3571 or magic_hi ~= 0x0A0D then
        error(string.format(
            "Bad magic number: expected 3571/0x0A0D (Python 3.13), got %d/0x%04X. " ..
            "This VM only supports Python 3.13 .pyc files.",
            magic_lo, magic_hi))
    end

    -- Bytes 5-8: flags (uint32), 9-12: timestamp, 13-16: source size
    -- We skip these; they're for cache invalidation, not execution.

    -- Bytes 17+: marshalled code object
    local marshal_data = string.sub(data, 17)
    return M.loads(marshal_data)
end

return M
