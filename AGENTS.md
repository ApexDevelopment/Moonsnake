# Project Summary

PythonInLua is a project that aims to be a zero-dependency Python implementation in Lua. It will be able to compile a Python script into PyC bytecode, then execute it in an entirely Lua-based Python virtual machine. The compiler and virtual machine will be separated so that the virtual machine can be shipped alongside Python bytecode for a more compact distribution.

# Current Status

The virtual machine is under active development and can execute a meaningful subset of Python 3.13 bytecode. The compiler has not been started yet.

## What Works

- **Marshal/pyc loading**: Reads CPython 3.13 `.pyc` files (magic number 3571)
- **Core opcodes**: LOAD_CONST, LOAD_NAME, LOAD_GLOBAL, LOAD_FAST, STORE_NAME, STORE_FAST, STORE_GLOBAL, POP_TOP, PUSH_NULL, RETURN_VALUE, RETURN_CONST, MAKE_FUNCTION, CALL
- **Arithmetic**: BINARY_OP (`+`, `-`, `*`, `/`, `//`, `%`, `**`), including string concatenation via `+` and in-place variants (`+=`, etc.)
- **Comparisons**: COMPARE_OP (`<`, `<=`, `==`, `!=`, `>`, `>=`)
- **Unary ops**: UNARY_NOT, UNARY_NEGATIVE
- **Control flow**: POP_JUMP_IF_FALSE/TRUE, POP_JUMP_IF_NONE/NOT_NONE, JUMP_FORWARD, JUMP_BACKWARD, TO_BOOL
- **For loops**: GET_ITER, FOR_ITER, END_FOR with iterator protocol
- **Super-instructions**: LOAD_FAST_LOAD_FAST, STORE_FAST_LOAD_FAST, STORE_FAST_STORE_FAST
- **Collections**: BUILD_LIST, BUILD_TUPLE, LIST_EXTEND, UNPACK_SEQUENCE
- **Identity/membership**: IS_OP, CONTAINS_OP
- **Stack ops**: COPY, SWAP
- **Builtins**: `print`, `len`, `type`, `range`, `int`, `str`, `abs`, `min`, `max`, `bool`
- **Functions**: User-defined functions, recursion, multiple arguments, closures over globals

## What's Not Yet Implemented

- Classes and objects
- Exception handling (try/except/finally)
- Closures over local variables (LOAD_DEREF, STORE_DEREF, MAKE_CELL)
- LOAD_ATTR / STORE_ATTR
- List/dict/set comprehensions
- String formatting (f-strings, FORMAT_SIMPLE, BUILD_STRING)
- Import system
- EXTENDED_ARG (for functions with >255 locals/consts)
- Many builtins (input, map, filter, zip, enumerate, sorted, reversed, etc.)

# Testing

Tests are located under `test/`. Each test is a Python script with a header comment that specifies the expected output. The test runner compiles `.py` files to `.pyc` via CPython 3.13, then runs them through the Lua VM.

Run all tests from the project root:

```
lua5.1 test/run_tests.lua
```

Test format:
```python
# Expect: Success
# Output: hello world

print("hello", "world")
```

There are currently 37 passing tests covering arithmetic, comparisons, control flow, for/while loops, recursion, function calls, builtins, and more.

# Notes for Agents

**Read `notes/` before making changes.** The `notes/` directory contains critical reference material:

- `architecture.md` — File structure, design decisions, key invariants (PyNone representation, CALL_NULL sentinel, etc.)
- `bytecode_format.md` — .pyc header, marshal format, instruction encoding, opcode reference
- `python313_specifics.md` — Why we target 3.13, cache counts, useful debugging commands
- `bugs_and_tips.md` — **Every bug encountered and its fix**, plus practical tips for development

**When you encounter and fix a bug or learn something non-obvious, write it down in `bugs_and_tips.md`.** Future agents will benefit enormously from knowing about pitfalls like the COMPARE_OP encoding (`arg >> 5`, not `>> 4`) or the missing cache counts on jump opcodes. The few minutes spent documenting saves hours of re-discovery.

## Development Workflow

1. Write a test in `test/test_<feature>.py` with `# Expect:` and `# Output:` headers
2. Run `lua5.1 test/run_tests.lua` to see what fails
3. Use a `_debug_*.py` script to inspect bytecode (`dis.dis()`) rather than inline `python -c` commands (which break on Windows due to shell escaping)
4. Implement the needed opcodes/builtins in `src/vm/interpreter.lua` and `src/vm/builtins.lua`
5. Don't forget CACHE entries — check `opcodes.lua` `cache_count` table and query `from opcode import _inline_cache_entries` if unsure
6. Run tests again, iterate
7. Document any surprises in `notes/bugs_and_tips.md`