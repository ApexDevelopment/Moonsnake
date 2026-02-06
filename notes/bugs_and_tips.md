# Bugs Encountered & Workarounds

## Bug 1: CALL stack order was reversed

**Symptom**: `TypeError: 'table: ...' is not callable` on every test.

**Root cause**: The CALL opcode handler was popping `callable` before `self_or_null`. The correct stack layout (bottom to top) is:

```
callable, self_or_null, arg1, ..., argN   ← bottom to top
```

So after popping N args, the next pop is `self_or_null`, then `callable`.

**Fix**: Swap the two pop calls in the CALL handler.

## Bug 2: LOAD_GLOBAL push order was wrong

**Symptom**: Function calls via LOAD_GLOBAL (inside Python function bodies) failed because the callable and NULL sentinel were in the wrong stack positions.

**Root cause**: LOAD_GLOBAL with `push_null=1` was pushing NULL *before* the value. But `CALL` expects `callable` below `self_or_null`. So LOAD_GLOBAL should push `value` first, then `NULL` on top.

**Fix**: Push value first, then conditionally push CALL_NULL.

**Note**: This differs from LOAD_NAME + PUSH_NULL (separate instructions) where LOAD_NAME pushes the value and PUSH_NULL pushes NULL. The combined behavior of LOAD_GLOBAL must match that order: value below, NULL above.

## Bug 3: test_if_statements.py had Lua syntax

**Symptom**: Test file used `if True then ... else ... end` instead of Python's `if True: ... else: ...`.

**Fix**: Corrected syntax. This was a known issue from project setup.

---

# Tips for Future Development

## Inspecting Bytecode

Use this Python script to inspect what CPython generates for any snippet:

```python
import dis
code = compile("your_code_here", "<test>", "exec")
dis.dis(code)
print("co_consts:", code.co_consts)
print("co_names:", code.co_names)
```

This is invaluable for understanding what opcodes need implementing.

## CACHE Instructions

Python 3.13 inserts CACHE (opcode=0) words after many instructions. These are for CPython's adaptive/specializing interpreter and contain runtime metadata. **The Lua VM must skip them.** The number of CACHE words per opcode is defined in `opcodes.lua`'s `cache_count` table.

If you encounter odd behavior after a CALL, LOAD_GLOBAL, or COMPARE_OP, check whether the IP is correctly skipping cache entries.

## Marshal None in co_consts

When marshal deserializes `(1, None)`, None becomes Lua `nil`. Since `nil` can't be stored in Lua array slots, `co_consts` may have "holes." The `frame:get_const(idx)` method handles this by converting `nil` to `types.PyNone`.

## Lua 5.1 Limitations

- No `string.unpack` — IEEE 754 float decoding is done manually in `marshal.lua`
- No native bitwise operators — LuaBit provides the fallback
- `unpack` is a global (not `table.unpack` like in 5.2+)
- `os.execute` returns 0 on success (not `true` like in 5.2+)
- Numbers are all doubles (no integer subtype) — fine for most Python ints up to 2^53

## Running Tests

From the project root:

```
lua5.1 test/run_tests.lua
```

The test runner:
1. Finds all `test/test_*.py` files
2. Compiles each to `test/.pyc_cache/<name>.pyc` using CPython
3. Runs through the Lua VM with stdout captured
4. Normalizes whitespace and compares against `# Output:` header

## Adding New Opcodes

1. Check the opcode number in `src/vm/opcodes.lua` (already has all 3.13 opcodes defined)
2. Add an `elseif` branch in `interpreter.lua`'s main loop
3. Don't forget to skip CACHE entries if the opcode has them (check `cache_count`)
4. Write a test in `test/test_<feature>.py` with appropriate header
