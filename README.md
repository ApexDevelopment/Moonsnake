# Moonsnake

## What

Moonsnake is a project that aims to be a zero-dependency Python implementation in Lua. It will be able to compile a Python script into PyC bytecode, then execute it in an entirely Lua-based Python virtual machine. The compiler and virtual machine will be separated so that the virtual machine can be shipped alongside Python bytecode for a more compact distribution.

## Why

## Current Status

The virtual machine can execute a significant subset of Python 3.13 bytecode. The compiler has not been started yet.

## What Works

- Variables, arithmetic, comparisons, boolean logic, bitwise operators
- if/elif/else, while, for (over range, list, str)
- Functions: user-defined, recursion, closures over globals
- str, dict, and list with full method suites, subscript access (`s[0]`, `lst[-1]`)
- f-strings with format specs (`.2f`, `:x`, width/alignment) and `!r`/`!s`/`!a`
- File I/O: `open`, `read`, `write`, `readline`, `readlines`, `close`, `with` statement
- Iteration: `enumerate`, `zip`, `map`, `filter`, `reversed`, `sorted`
- Closures over locals: inner functions capture outer locals; `nonlocal` writes; decorators
- Builtins: `print`, `len`, `range`, `int`, `str`, `bool`, `abs`, `min`, `max`, `type`, `open`
- Marshal/pyc loading for CPython 3.13 files

See `notes/parity.md` for a complete opcode-by-opcode and feature-by-feature breakdown.

## What Doesn't Work Yet

- Classes and objects
- Exception handling (try/except/finally)
- Set type
- Comprehensions
- Import system
- Many builtins (`input`, `hasattr`, `getattr`, `isinstance`, …)

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

Compiled `.pyc` files are cached in `test/.pyc_cache/` and reused across runs when the source hasn't changed.