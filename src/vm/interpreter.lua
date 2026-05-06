-- PythonInLua: Python 3.13 bytecode interpreter
--
-- Stack-based virtual machine. Each call frame has its own value stack
-- and instruction pointer. The interpreter reads 2-byte instruction words
-- (opcode, arg) from code.co_code.
--
-- Python 3.13 bytecode is word-oriented: each instruction is 2 bytes
-- (1 byte opcode + 1 byte arg). The instruction pointer counts in
-- *word* offsets (i.e., ip=0 means bytes 0-1, ip=1 means bytes 2-3).

local opcodes = require("src.vm.opcodes")
local types   = require("src.vm.types")

local M = {}

local op = opcodes.opmap  -- shorthand: op.LOAD_CONST, etc.

---------------------------------------------------------------------------
-- Call frame
---------------------------------------------------------------------------
local Frame = {}
Frame.__index = Frame

function Frame.new(code, globals, locals, builtins)
    local self = setmetatable({}, Frame)
    self.code     = code
    self.globals  = globals      -- table: name -> value
    self.locals   = locals or {} -- table: index (0-based) -> value
    self.builtins = builtins     -- table: name -> value
    self.stack    = {}           -- value stack for this frame
    self.sp       = 0            -- stack pointer (index of top element, 0 = empty)
    self.ip       = 0            -- instruction pointer (word index, 0-based)
    return self
end

function Frame:push(val)
    self.sp = self.sp + 1
    self.stack[self.sp] = val
end

function Frame:pop()
    if self.sp <= 0 then
        error("VM error: stack underflow in " .. tostring(self.code.co_name))
    end
    local val = self.stack[self.sp]
    self.stack[self.sp] = nil
    self.sp = self.sp - 1
    return val
end

function Frame:peek(n)
    -- peek(0) = TOS, peek(1) = TOS-1, etc.
    n = n or 0
    return self.stack[self.sp - n]
end

--- Read the instruction word at the current ip, advance ip.
--- Returns opcode, arg
function Frame:fetch()
    local bytecode = self.code.co_code
    -- Convert word-index to byte-index (1-based for Lua strings)
    local byte_offset = self.ip * 2 + 1  -- +1 for Lua 1-indexing
    local opcode = string.byte(bytecode, byte_offset)
    local arg    = string.byte(bytecode, byte_offset + 1)
    if opcode == nil then
        error("VM error: reading past end of bytecode in " .. tostring(self.code.co_name))
    end
    self.ip = self.ip + 1
    return opcode, arg
end

--- Get a constant from co_consts. Index is 0-based (Python convention).
function Frame:get_const(idx)
    -- co_consts is a Lua table (1-indexed), Python index is 0-based
    local val = self.code.co_consts[idx + 1]
    -- nil in the consts table means Python None
    if val == nil then
        return types.PyNone
    end
    return val
end

--- Get a name from co_names. Index is 0-based.
function Frame:get_name(idx)
    return self.code.co_names[idx + 1]
end

--- Resolve a name: locals → globals → builtins
function Frame:load_name(name)
    -- For module-level code, "locals" and "globals" are the same namespace.
    -- We check globals first (which serves as locals at module level),
    -- then builtins.
    if self.globals[name] ~= nil then
        return self.globals[name]
    end
    if self.builtins[name] ~= nil then
        return self.builtins[name]
    end
    error("NameError: name '" .. name .. "' is not defined")
end

---------------------------------------------------------------------------
-- Interpreter: execute one frame to completion
---------------------------------------------------------------------------

--- The NULL sentinel pushed by PUSH_NULL for the call protocol.
--- Must be distinct from any Python value.
local CALL_NULL = { _sentinel = "CALL_NULL" }

function M.exec_frame(frame)
    local bytecode_len = #frame.code.co_code / 2  -- total instruction words

    while frame.ip < bytecode_len do
        local opcode, arg = frame:fetch()

        ---------------------------------------------------------------
        -- No-ops
        ---------------------------------------------------------------
        if opcode == op.NOP or opcode == op.RESUME or opcode == op.CACHE then
            -- do nothing

        ---------------------------------------------------------------
        -- LOAD_CONST idx
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_CONST then
            frame:push(frame:get_const(arg))

        ---------------------------------------------------------------
        -- LOAD_NAME idx  — resolve name through namespaces
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_NAME then
            local name = frame:get_name(arg)
            frame:push(frame:load_name(name))

        ---------------------------------------------------------------
        -- LOAD_GLOBAL idx
        -- In 3.13, arg encodes (namei << 1) | push_null.
        -- If bit 0 is set, push the value then NULL (for call protocol).
        -- Stack result: value, [NULL]  (NULL on top if bit 0 set)
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_GLOBAL then
            local push_null = (arg % 2) == 1
            local namei = math.floor(arg / 2)
            local name = frame:get_name(namei)
            local val = frame.globals[name]
            if val == nil then
                val = frame.builtins[name]
            end
            if val == nil then
                error("NameError: name '" .. name .. "' is not defined")
            end
            frame:push(val)
            if push_null then
                frame:push(CALL_NULL)
            end
            -- Skip cache entries
            local caches = opcodes.cache_count[op.LOAD_GLOBAL] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- LOAD_FAST idx  — load from locals by index
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_FAST then
            local val = frame.locals[arg]
            if val == nil then
                -- In CPython this would be UnboundLocalError
                -- co_localsplusnames has the name for error messages
                local name = frame.code.co_localsplusnames
                    and frame.code.co_localsplusnames[arg + 1]
                    or ("local#" .. arg)
                error("UnboundLocalError: local variable '" .. name .. "' referenced before assignment")
            end
            frame:push(val)

        ---------------------------------------------------------------
        -- STORE_NAME idx
        ---------------------------------------------------------------
        elseif opcode == op.STORE_NAME then
            local name = frame:get_name(arg)
            frame.globals[name] = frame:pop()

        ---------------------------------------------------------------
        -- STORE_FAST idx — store into locals by index
        ---------------------------------------------------------------
        elseif opcode == op.STORE_FAST then
            frame.locals[arg] = frame:pop()

        ---------------------------------------------------------------
        -- LOAD_FAST_LOAD_FAST — load two locals at once (super-instruction)
        -- arg encodes two 4-bit indices: push locals[arg>>4] then locals[arg&0xF]
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_FAST_LOAD_FAST then
            local idx1 = math.floor(arg / 16)  -- arg >> 4
            local idx2 = arg % 16               -- arg & 0xF
            local val1 = frame.locals[idx1]
            local val2 = frame.locals[idx2]
            if val1 == nil then
                local name = frame.code.co_localsplusnames and frame.code.co_localsplusnames[idx1 + 1] or ("local#" .. idx1)
                error("UnboundLocalError: local variable '" .. name .. "' referenced before assignment")
            end
            if val2 == nil then
                local name = frame.code.co_localsplusnames and frame.code.co_localsplusnames[idx2 + 1] or ("local#" .. idx2)
                error("UnboundLocalError: local variable '" .. name .. "' referenced before assignment")
            end
            frame:push(val1)
            frame:push(val2)

        ---------------------------------------------------------------
        -- STORE_FAST_LOAD_FAST — store TOS into locals[arg>>4], load locals[arg&0xF]
        ---------------------------------------------------------------
        elseif opcode == op.STORE_FAST_LOAD_FAST then
            local idx_store = math.floor(arg / 16)
            local idx_load  = arg % 16
            frame.locals[idx_store] = frame:pop()
            local val = frame.locals[idx_load]
            if val == nil then
                local name = frame.code.co_localsplusnames and frame.code.co_localsplusnames[idx_load + 1] or ("local#" .. idx_load)
                error("UnboundLocalError: local variable '" .. name .. "' referenced before assignment")
            end
            frame:push(val)

        ---------------------------------------------------------------
        -- STORE_FAST_STORE_FAST — store TOS into locals[arg&0xF], TOS1 into locals[arg>>4]
        ---------------------------------------------------------------
        elseif opcode == op.STORE_FAST_STORE_FAST then
            local idx1 = math.floor(arg / 16)  -- arg >> 4
            local idx2 = arg % 16               -- arg & 0xF
            -- TOS goes to idx1, TOS1 goes to idx2 (reverse of load order)
            local tos  = frame:pop()
            local tos1 = frame:pop()
            frame.locals[idx1] = tos
            frame.locals[idx2] = tos1

        ---------------------------------------------------------------
        -- STORE_GLOBAL idx
        ---------------------------------------------------------------
        elseif opcode == op.STORE_GLOBAL then
            local name = frame:get_name(arg)
            frame.globals[name] = frame:pop()

        ---------------------------------------------------------------
        -- POP_TOP
        ---------------------------------------------------------------
        elseif opcode == op.POP_TOP then
            frame:pop()

        ---------------------------------------------------------------
        -- PUSH_NULL — push a sentinel for the call protocol
        ---------------------------------------------------------------
        elseif opcode == op.PUSH_NULL then
            frame:push(CALL_NULL)

        ---------------------------------------------------------------
        -- CALL argc
        -- Stack layout (bottom to top):
        --   callable, self_or_null, arg_1, ..., arg_n
        -- argc = number of positional arguments
        ---------------------------------------------------------------
        elseif opcode == op.CALL then
            local argc = arg

            -- Collect arguments (top of stack = last arg)
            local args = {}
            for i = argc, 1, -1 do
                args[i] = frame:pop()
            end

            -- Pop self_or_null (NULL sentinel or bound self)
            local self_or_null = frame:pop()

            -- Pop the callable
            local callable = frame:pop()

            -- Invoke
            local result
            if type(callable) == "function" then
                -- Native Lua function (builtin)
                result = callable(unpack(args))
            elseif type(callable) == "table" and callable._pytype == "function" then
                -- Python function: create a new frame
                result = M.call_pyfunction(callable, args, frame.builtins)
            else
                error("TypeError: '" .. tostring(callable) .. "' is not callable")
            end

            frame:push(result)

            -- Skip cache entries
            local caches = opcodes.cache_count[op.CALL] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- RETURN_VALUE — return TOS
        ---------------------------------------------------------------
        elseif opcode == op.RETURN_VALUE then
            return frame:pop()

        ---------------------------------------------------------------
        -- RETURN_CONST idx — return co_consts[idx]
        ---------------------------------------------------------------
        elseif opcode == op.RETURN_CONST then
            return frame:get_const(arg)

        ---------------------------------------------------------------
        -- MAKE_FUNCTION
        -- TOS is a code object. Create a function from it.
        ---------------------------------------------------------------
        elseif opcode == op.MAKE_FUNCTION then
            local code_obj = frame:pop()
            local func = types.PyFunction(code_obj, frame.globals)
            frame:push(func)

        ---------------------------------------------------------------
        -- GET_ITER — convert TOS to an iterator
        ---------------------------------------------------------------
        elseif opcode == op.GET_ITER then
            local val = frame:pop()
            frame:push(types.get_iter(val))

        ---------------------------------------------------------------
        -- FOR_ITER arg
        -- TOS is an iterator. Try to advance it.
        -- If success: push next value, continue to loop body.
        -- If exhausted: pop iterator, jump forward (past END_FOR).
        ---------------------------------------------------------------
        elseif opcode == op.FOR_ITER then
            -- Skip cache entries first
            local caches = opcodes.cache_count[op.FOR_ITER] or 0
            frame.ip = frame.ip + caches

            local iter = frame:peek()
            local value = types.iter_next(iter)
            if value ~= nil then
                -- Iterator produced a value; push it for STORE_NAME/STORE_FAST
                frame:push(value)
            else
                -- Exhausted: jump to END_FOR, leave iterator on stack
                -- END_FOR is a NOP, then POP_TOP cleans up the iterator
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- END_FOR — cleanup at end of for loop
        -- In normal exhaustion: iterator is still on stack, next POP_TOP removes it.
        -- Reached by falling through from FOR_ITER jump.
        ---------------------------------------------------------------
        elseif opcode == op.END_FOR then
            -- No-op in normal path; POP_TOP follows to clean up iterator

        ---------------------------------------------------------------
        -- POP_JUMP_IF_FALSE target
        -- Pop TOS; if falsy, jump to target (absolute word offset).
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_FALSE then
            local val = frame:pop()
            -- Skip cache entries first, then apply jump offset
            local caches = opcodes.cache_count[op.POP_JUMP_IF_FALSE] or 0
            frame.ip = frame.ip + caches
            if not types.is_truthy(val) then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_TRUE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_TRUE then
            local val = frame:pop()
            local caches = opcodes.cache_count[op.POP_JUMP_IF_TRUE] or 0
            frame.ip = frame.ip + caches
            if types.is_truthy(val) then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_NONE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_NONE then
            local val = frame:pop()
            local caches = opcodes.cache_count[op.POP_JUMP_IF_NONE] or 0
            frame.ip = frame.ip + caches
            if val == types.PyNone then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_NOT_NONE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_NOT_NONE then
            local val = frame:pop()
            local caches = opcodes.cache_count[op.POP_JUMP_IF_NOT_NONE] or 0
            frame.ip = frame.ip + caches
            if val ~= types.PyNone then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- JUMP_FORWARD delta — relative jump forward by delta words
        ---------------------------------------------------------------
        elseif opcode == op.JUMP_FORWARD then
            frame.ip = frame.ip + arg

        ---------------------------------------------------------------
        -- JUMP_BACKWARD delta — relative jump backward by delta words
        ---------------------------------------------------------------
        elseif opcode == op.JUMP_BACKWARD then
            local caches = opcodes.cache_count[op.JUMP_BACKWARD] or 0
            frame.ip = frame.ip + caches
            frame.ip = frame.ip - arg

        ---------------------------------------------------------------
        -- TO_BOOL — convert TOS to bool (for if-statement optimization)
        ---------------------------------------------------------------
        elseif opcode == op.TO_BOOL then
            local val = frame:pop()
            frame:push(types.is_truthy(val))
            -- Skip cache entries
            local caches = opcodes.cache_count[op.TO_BOOL] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- BINARY_OP op_type
        -- TOS1 op TOS (e.g. +, -, *, etc.)
        ---------------------------------------------------------------
        elseif opcode == op.BINARY_OP then
            local rhs = frame:pop()
            local lhs = frame:pop()
            local result
            -- arg encodes the operation type (CPython 3.13 NB_* constants)
            -- 0=+, 1=&, 2=//, 3=<<, 4=@, 5=*, 6=%, 7=|, 8=**, 9=>>, 10=-, 11=/, 12=^
            -- In-place variants (+=, &=, etc.) are arg+13
            local binop = arg
            if binop >= 13 then binop = binop - 13 end  -- in-place variants

            if binop == 0 then       -- +
                if type(lhs) == "string" and type(rhs) == "string" then
                    result = lhs .. rhs
                else
                    result = lhs + rhs
                end
            elseif binop == 10 then  -- -
                result = lhs - rhs
            elseif binop == 5 then   -- *
                result = lhs * rhs
            elseif binop == 11 then  -- /
                result = lhs / rhs
            elseif binop == 2 then   -- //
                result = math.floor(lhs / rhs)
            elseif binop == 6 then   -- %
                result = lhs % rhs
            elseif binop == 8 then   -- **
                result = lhs ^ rhs
            else
                error(string.format("NotImplementedError: BINARY_OP %d not implemented", arg))
            end
            frame:push(result)
            -- Skip cache entries
            local caches = opcodes.cache_count[op.BINARY_OP] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- COMPARE_OP oparg
        ---------------------------------------------------------------
        elseif opcode == op.COMPARE_OP then
            local rhs = frame:pop()
            local lhs = frame:pop()
            -- arg >> 5 gives the comparison type in 3.13
            -- (lower 5 bits are flags: bit 4 = bool result, etc.)
            local cmp = math.floor(arg / 32)
            local result
            if cmp == 0 then       -- <
                result = lhs < rhs
            elseif cmp == 1 then   -- <=
                result = lhs <= rhs
            elseif cmp == 2 then   -- ==
                result = lhs == rhs
            elseif cmp == 3 then   -- !=
                result = lhs ~= rhs
            elseif cmp == 4 then   -- >
                result = lhs > rhs
            elseif cmp == 5 then   -- >=
                result = lhs >= rhs
            else
                error(string.format("NotImplementedError: COMPARE_OP cmp=%d", cmp))
            end
            frame:push(result)
            -- Skip cache entries
            local caches = opcodes.cache_count[op.COMPARE_OP] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- UNARY_NOT
        ---------------------------------------------------------------
        elseif opcode == op.UNARY_NOT then
            local val = frame:pop()
            frame:push(not types.is_truthy(val))

        ---------------------------------------------------------------
        -- UNARY_NEGATIVE
        ---------------------------------------------------------------
        elseif opcode == op.UNARY_NEGATIVE then
            local val = frame:pop()
            frame:push(-val)

        ---------------------------------------------------------------
        -- COPY i — copy the i-th item from TOS to TOS
        ---------------------------------------------------------------
        elseif opcode == op.COPY then
            local val = frame:peek(arg - 1)
            frame:push(val)

        ---------------------------------------------------------------
        -- SWAP i — swap TOS with the i-th element
        ---------------------------------------------------------------
        elseif opcode == op.SWAP then
            local idx1 = frame.sp
            local idx2 = frame.sp - arg + 1
            frame.stack[idx1], frame.stack[idx2] = frame.stack[idx2], frame.stack[idx1]

        ---------------------------------------------------------------
        -- BUILD_LIST n — create a list from top n stack items
        ---------------------------------------------------------------
        elseif opcode == op.BUILD_LIST then
            local list = { _pytype = "list" }
            for i = arg, 1, -1 do
                list[arg - i + 1] = frame:pop()
            end
            -- Reverse to correct order (popped in reverse)
            local n = #list
            for i = 1, math.floor(n / 2) do
                list[i], list[n - i + 1] = list[n - i + 1], list[i]
            end
            frame:push(list)

        ---------------------------------------------------------------
        -- BUILD_TUPLE n — create a tuple from top n stack items
        ---------------------------------------------------------------
        elseif opcode == op.BUILD_TUPLE then
            local tup = {}
            for i = arg, 1, -1 do
                tup[i] = frame:pop()
            end
            frame:push(tup)

        ---------------------------------------------------------------
        -- LIST_EXTEND i — extend list at stack[-i] with TOS
        ---------------------------------------------------------------
        elseif opcode == op.LIST_EXTEND then
            local iterable = frame:pop()
            local list = frame:peek(arg - 1)
            -- iterable is typically a tuple from co_consts
            if type(iterable) == "table" then
                for _, v in ipairs(iterable) do
                    list[#list + 1] = v
                end
            else
                error("TypeError: cannot extend list with " .. type(iterable))
            end

        ---------------------------------------------------------------
        -- IS_OP invert — test identity (is / is not)
        ---------------------------------------------------------------
        elseif opcode == op.IS_OP then
            local rhs = frame:pop()
            local lhs = frame:pop()
            local result = (lhs == rhs)
            -- For Python None, True, False identity checks, == works
            -- because we use singletons (types.PyNone, true, false)
            if arg == 1 then
                result = not result  -- "is not"
            end
            frame:push(result)

        ---------------------------------------------------------------
        -- CONTAINS_OP invert — test membership (in / not in)
        ---------------------------------------------------------------
        elseif opcode == op.CONTAINS_OP then
            local rhs = frame:pop()  -- the container
            local lhs = frame:pop()  -- the value to check
            local found = false
            if type(rhs) == "table" and rhs._pytype == "list" then
                for _, v in ipairs(rhs) do
                    if v == lhs then found = true; break end
                end
            elseif type(rhs) == "string" then
                if type(lhs) == "string" then
                    found = rhs:find(lhs, 1, true) ~= nil
                end
            else
                error("TypeError: argument of type '" .. type(rhs) .. "' is not iterable")
            end
            local result = found
            -- arg bit 0: invert for "not in"
            if (arg % 2) == 1 then
                result = not result
            end
            frame:push(result)
            -- Skip cache entries
            local caches = opcodes.cache_count[op.CONTAINS_OP] or 0
            frame.ip = frame.ip + caches

        ---------------------------------------------------------------
        -- UNPACK_SEQUENCE n — unpack TOS into n values
        ---------------------------------------------------------------
        elseif opcode == op.UNPACK_SEQUENCE then
            local seq = frame:pop()
            -- Skip cache entries
            local caches = opcodes.cache_count[op.UNPACK_SEQUENCE] or 0
            frame.ip = frame.ip + caches
            -- Push values in reverse order so first element ends up on top
            for i = #seq, 1, -1 do
                frame:push(seq[i])
            end

        ---------------------------------------------------------------
        -- FORMAT_SIMPLE — convert TOS to its str() representation
        ---------------------------------------------------------------
        elseif opcode == op.FORMAT_SIMPLE then
            local val = frame:pop()
            frame:push(types.py_str(val))

        ---------------------------------------------------------------
        -- FORMAT_WITH_SPEC — format TOS1 using TOS as a format spec
        -- Stack before: ..., value, spec   (spec = TOS)
        -- Stack after:  ..., formatted_string
        ---------------------------------------------------------------
        elseif opcode == op.FORMAT_WITH_SPEC then
            local spec = frame:pop()   -- TOS: format spec string
            local val  = frame:pop()   -- TOS1: value to format
            frame:push(types.py_format(val, spec))

        ---------------------------------------------------------------
        -- BUILD_STRING n — concatenate top n strings into one string
        ---------------------------------------------------------------
        elseif opcode == op.BUILD_STRING then
            local parts = {}
            -- Pop in reverse so parts[1] = leftmost (bottom of n items)
            for i = arg, 1, -1 do
                parts[i] = frame:pop()
            end
            frame:push(table.concat(parts))

        ---------------------------------------------------------------
        -- CONVERT_VALUE conv — apply !s/!r/!a conversion to TOS
        -- arg: 1 = str, 2 = repr, 3 = ascii
        ---------------------------------------------------------------
        elseif opcode == op.CONVERT_VALUE then
            local val = frame:pop()
            local converted
            if arg == 1 then
                converted = types.py_str(val)
            elseif arg == 2 then
                converted = types.py_repr(val)
            elseif arg == 3 then
                converted = types.py_ascii(val)
            else
                error(string.format("NotImplementedError: CONVERT_VALUE arg=%d", arg))
            end
            frame:push(converted)

        ---------------------------------------------------------------
        -- LOAD_ATTR namei
        -- In 3.13, arg encodes (namei << 1) | is_method_call.
        -- is_method=0: pop obj, push getattr(obj, name)
        -- is_method=1: pop obj, push bound_callable, push CALL_NULL
        --   so CALL sees: bound_callable, CALL_NULL, args... (normal call protocol)
        ---------------------------------------------------------------
        elseif opcode == op.LOAD_ATTR then
            local is_method = (arg % 2) == 1
            local namei     = math.floor(arg / 2)
            local name      = frame:get_name(namei)
            local obj       = frame:pop()
            -- Skip cache entries before any error that might propagate
            local caches = opcodes.cache_count[op.LOAD_ATTR] or 0
            frame.ip = frame.ip + caches

            local attr = types.get_attr(obj, name)

            if is_method and type(attr) == "function" then
                -- Wrap into a bound closure so CALL can invoke without self slot
                local bound = function(...) return attr(obj, ...) end
                frame:push(bound)
                frame:push(CALL_NULL)
            elseif is_method then
                -- Plain (non-callable) attribute accessed via method opcode variant
                frame:push(CALL_NULL)
                frame:push(attr)
            else
                frame:push(attr)
            end

        ---------------------------------------------------------------
        -- STORE_ATTR namei
        -- Stack before: obj (TOS), value (TOS1)
        -- Sets obj.name = value, pops both.
        ---------------------------------------------------------------
        elseif opcode == op.STORE_ATTR then
            local name  = frame:get_name(arg)
            local obj   = frame:pop()   -- TOS
            local val   = frame:pop()   -- TOS1
            local caches = opcodes.cache_count[op.STORE_ATTR] or 0
            frame.ip = frame.ip + caches
            types.set_attr(obj, name, val)

        ---------------------------------------------------------------
        -- BINARY_SUBSCR — TOS1[TOS]
        ---------------------------------------------------------------
        elseif opcode == op.BINARY_SUBSCR then
            local key = frame:pop()
            local obj = frame:pop()
            local caches = opcodes.cache_count[op.BINARY_SUBSCR] or 0
            frame.ip = frame.ip + caches
            frame:push(types.get_subscript(obj, key))

        ---------------------------------------------------------------
        -- STORE_SUBSCR — TOS1[TOS] = TOS2
        ---------------------------------------------------------------
        elseif opcode == op.STORE_SUBSCR then
            local key = frame:pop()   -- TOS
            local obj = frame:pop()   -- TOS1
            local val = frame:pop()   -- TOS2
            local caches = opcodes.cache_count[op.STORE_SUBSCR] or 0
            frame.ip = frame.ip + caches
            types.set_subscript(obj, key, val)

        ---------------------------------------------------------------
        -- EXTENDED_ARG — next instruction's arg is (this arg << 8 | next arg)
        ---------------------------------------------------------------
        elseif opcode == op.EXTENDED_ARG then
            local next_op, next_arg = frame:fetch()
            local extended_arg = arg * 256 + next_arg
            -- Re-dispatch with the extended argument
            -- We temporarily set ip back and overwrite, but it's simpler
            -- to just handle it inline. We push the fetch back.
            -- Actually, let's just recursively handle:
            -- We need to process next_op with extended_arg.
            -- For now, store and let the loop handle it... no, we already fetched.
            -- The simplest approach: un-fetch and modify the arg in-place.
            -- Let's handle it by manually dispatching. But that duplicates code.
            -- Better approach: rewind ip by 1 and patch the bytecode arg.
            -- Actually simplest: just note that EXTENDED_ARG chains are rare in
            -- basic code. For now, error out and implement when needed.
            error("NotImplementedError: EXTENDED_ARG (arg=" .. arg .. ", next_op=" .. next_op .. ")")

        ---------------------------------------------------------------
        -- Unknown opcode
        ---------------------------------------------------------------
        else
            local name = opcodes.opname[opcode] or "UNKNOWN"
            error(string.format(
                "NotImplementedError: opcode %d (%s) with arg %d in %s",
                opcode, name, arg, tostring(frame.code.co_name)))
        end
    end

    -- If we fall off the end without a RETURN, return None
    return types.PyNone
end

---------------------------------------------------------------------------
-- Call a Python function
---------------------------------------------------------------------------

function M.call_pyfunction(func, args, builtins)
    local code = func.code
    -- Create new locals table, populating from args
    local locals = {}
    local nargs = code.co_argcount or 0
    for i = 0, nargs - 1 do
        locals[i] = args[i + 1]  -- args is 1-indexed
        if locals[i] == nil then
            locals[i] = types.PyNone
        end
    end

    local frame = Frame.new(code, func.globals, locals, builtins)
    return M.exec_frame(frame)
end

---------------------------------------------------------------------------
-- Public API: execute a code object
---------------------------------------------------------------------------

function M.execute(code, builtins_table)
    local globals = {}
    local frame = Frame.new(code, globals, {}, builtins_table)
    return M.exec_frame(frame)
end

return M
