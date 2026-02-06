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
        -- POP_JUMP_IF_FALSE target
        -- Pop TOS; if falsy, jump to target (absolute word offset).
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_FALSE then
            local val = frame:pop()
            if not types.is_truthy(val) then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_TRUE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_TRUE then
            local val = frame:pop()
            if types.is_truthy(val) then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_NONE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_NONE then
            local val = frame:pop()
            if val == types.PyNone then
                frame.ip = frame.ip + arg
            end

        ---------------------------------------------------------------
        -- POP_JUMP_IF_NOT_NONE target
        ---------------------------------------------------------------
        elseif opcode == op.POP_JUMP_IF_NOT_NONE then
            local val = frame:pop()
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
            -- arg encodes the operation type
            -- From CPython: 0=+, 1=&, 2=//,3=<<,4=@,5=%,6=*,7=>>
            --               8=-, 9=/, 10=^, 11=|, 13=**
            -- Also +=, &=, etc. are arg+13
            local binop = arg
            if binop >= 13 then binop = binop - 13 end  -- in-place variants

            if binop == 0 then      -- +
                result = lhs + rhs
            elseif binop == 8 then   -- -
                result = lhs - rhs
            elseif binop == 6 then   -- *
                result = lhs * rhs
            elseif binop == 9 then   -- /
                result = lhs / rhs
            elseif binop == 2 then   -- //
                result = math.floor(lhs / rhs)
            elseif binop == 5 then   -- %
                result = lhs % rhs
            elseif binop == 13 then  -- **
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
            -- arg >> 4 gives the comparison type in 3.13
            local cmp = math.floor(arg / 16)
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
