# Moonsnake

## What

Moonsnake is a project that aims to be a zero-dependency Python implementation in Lua. It will be able to compile a Python script into PyC bytecode, then execute it in an entirely Lua-based Python virtual machine. The compiler and virtual machine will be separated so that the virtual machine can be shipped alongside Python bytecode for a more compact distribution.

## Why

## Current Status

The virtual machine is under active development and can execute a meaningful subset of Python 3.13 bytecode. The compiler has not been started yet.

## What Works

- Variables, arithmetic, comparisons, boolean logic
- if/elif/else, while, for (over range, list, str)
- Functions: user-defined, recursion, closures over globals
- str and list with full method suites, subscript access (`s[0]`, `lst[-1]`)
- f-strings with format specs (`.2f`, `:x`, width/alignment) and `!r`/`!s`/`!a`
- Builtins: `print`, `len`, `range`, `int`, `str`, `bool`, `abs`, `min`, `max`, `type`
- Marshal/pyc loading for CPython 3.13 files

See `notes/parity.md` for a complete opcode-by-opcode and feature-by-feature breakdown.

## What's Not Yet Implemented

- Classes and objects
- Exception handling (try/except/finally)
- Closures over locals (LOAD_DEREF / MAKE_CELL)
- Dict and set types
- Comprehensions
- Import system
- Many builtins (`enumerate`, `zip`, `map`, `filter`, `sorted`, `reversed`, …)

# Roadmap

Planned implementation order, roughly by impact-to-effort ratio.

### 1. Dict type
`BUILD_MAP`, `BINARY_SUBSCR`/`STORE_SUBSCR` on dicts, and the core dict methods (`keys`, `values`, `items`, `get`, `update`, `pop`). Unlocks memoization, frequency counting, graph adjacency maps, and most algorithms that currently need an awkward list-of-pairs workaround.

### 2. File I/O
Add `open` as a native builtin returning a file object with `read`, `write`, `readline`, `readlines`, and context manager support (`__enter__`/`__exit__` via `BEFORE_WITH`). Makes Moonsnake useful for real text-processing scripts.

### 3. `enumerate`, `zip`, and other iteration builtins
`enumerate`, `zip`, `map`, `filter`, `reversed`, `sorted` — all implementable as native iterators without any new opcodes. Cleans up a large class of for-loop patterns that currently require manual index tracking.

### 4. Closures over locals
`LOAD_DEREF`, `STORE_DEREF`, `MAKE_CELL`, `COPY_FREE_VARS` — the cell/free variable machinery that CPython uses for inner functions that close over outer locals. Required for decorators, factory functions, and `nonlocal`.

### 5. …
*More to be decided.*

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

There are currently 46 passing tests covering arithmetic, comparisons, control flow, for/while loops, recursion, function calls, builtins, string formatting, string/list methods, and subscript access.