# PythonInLua Architecture Notes

## Overview

PythonInLua executes real CPython 3.13 `.pyc` files in a Lua 5.1 virtual machine. The workflow is:

1. Write Python source (`.py`)
2. Compile to `.pyc` using CPython 3.13 (`python -m py_compile` or `py_compile.compile()`)
3. Run the `.pyc` through the Lua VM: `lua5.1 src/main.lua file.pyc`

## File Structure

```
src/
  main.lua              CLI entry point
  vm/
    init.lua            Top-level VM API (run_pyc, run_code, load_pyc)
    marshal.lua         .pyc file parser + marshal format unmarshaller
    opcodes.lua         Python 3.13 opcode definitions (name↔number, cache counts)
    interpreter.lua     Stack-based bytecode interpreter (the core eval loop)
    types.lua           Python value representations (PyNone, PyFunction, truthiness)
    builtins.lua        Built-in functions (print, len, type)
  lib/
    luabit.lua          Vendored LuaBit — portable 32-bit bitwise ops for Lua 5.1
    native.lua          LuaBit native backend (Lua 5.3+ only, auto-selected)
test/
  run_tests.lua         Test runner (compiles .py→.pyc, runs through VM, checks output)
  test_*.py             Test files with # Expect / # Output headers
```

## Key Design Decisions

### Python None Representation

Lua `nil` cannot be stored in tables or on the VM stack (it disappears). Python `None` is represented as a unique singleton table `types.PyNone` with `_pytype = "NoneType"`. This means:

- `nil` in Lua context ≈ "absent" (used only for marshal's NULL sentinel)
- `types.PyNone` in VM context = Python's `None`
- `frame:get_const(idx)` converts Lua nil to PyNone automatically

**Caveat**: Marshal stores `None` as Lua `nil` in `co_consts` tuples. Since `nil` can't occupy a Lua array slot, tuples like `(None, 2)` become `{[2]=2}` in Lua. Direct index access (`t[2]`) still works, but `#t` and `ipairs` may behave unexpectedly. Always use direct index access for co_consts.

### Call Protocol (CALL_NULL Sentinel)

Python 3.13 uses a two-slot call protocol: `callable, self_or_null` on the stack before arguments. The `self_or_null` slot is `NULL` for plain function calls or `self` for method calls.

We represent this NULL as `CALL_NULL`, a unique sentinel table distinct from any Python value. It lives only on the VM stack, never in Python-visible namespaces.

### Bytecodes are 2-Byte Words

Python 3.13 bytecode is word-oriented: every instruction is exactly 2 bytes (opcode + arg). The instruction pointer counts in word offsets. Some instructions are followed by CACHE words (opcode=0) that must be skipped during interpretation.

### Require Path Setup

All Lua modules use dot-separated paths (e.g., `require("src.vm.opcodes")`). The CLI entry point (`src/main.lua`) prepends `./?.lua;./?/init.lua;` to `package.path`. **All commands must be run from the project root directory.**
