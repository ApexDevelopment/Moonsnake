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

## Bug 4: COMPARE_OP encoding was wrong

**Symptom**: Comparisons like `<`, `>=` etc. inside functions produced wrong results (e.g., `COMPARE_OP cmp=10` error).

**Root cause**: The comparison type was extracted with `arg >> 4`, but Python 3.13 encodes it as `arg >> 5` (lower 5 bits are flags: bit 4 = bool result flag, bits 0-3 for adaptive interpreter).

**Fix**: Changed `math.floor(arg / 16)` to `math.floor(arg / 32)`.

## Bug 5: BINARY_OP constants were wrong

**Symptom**: `mul(3, 5)` returned 3 instead of 15 — operators were mapped incorrectly.

**Root cause**: The NB_* operation constants were wrong. Correct mapping (CPython 3.13): `0=+, 1=&, 2=//, 3=<<, 4=@, 5=*, 6=%, 7=|, 8=**, 9=>>, 10=-, 11=/, 12=^`. In-place variants are +13.

**Fix**: Updated the BINARY_OP dispatch table.

## Bug 6: Missing cache counts for jump opcodes

**Symptom**: `classify(0)` returned "positive" instead of "zero" — conditional jumps inside functions were off by one word.

**Root cause**: `POP_JUMP_IF_FALSE`, `POP_JUMP_IF_TRUE`, `POP_JUMP_IF_NONE`, `POP_JUMP_IF_NOT_NONE`, and `JUMP_BACKWARD` all have 1 CACHE entry in Python 3.13 that wasn't being skipped. The cache must be skipped *before* applying the jump offset.

**Fix**: Added cache counts to `opcodes.lua` and updated all jump handlers to skip caches before computing jump targets. Verified with `python -c "from opcode import _inline_cache_entries; ..."`.

## Bug 7: STORE_FAST_STORE_FAST assignment order was reversed

**Symptom**: `a, b = b, a + b` tuple swap in fibonacci produced wrong results (swapped values).

**Root cause**: The oparg encoding for STORE_FAST_STORE_FAST uses `oparg>>4` and `oparg&0xF`. TOS goes to `oparg>>4` (first index) and TOS1 goes to `oparg&0xF` (second index), which is the reverse of the load order.

**Fix**: Pop TOS and TOS1 separately, assign TOS→locals[arg>>4], TOS1→locals[arg&0xF].

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

## Getting Definitive Cache Counts

Don't guess cache counts from documentation or the CPython source — they change between minor versions. Query the **installed Python directly**:

```python
from opcode import _inline_cache_entries
for name, count in sorted(_inline_cache_entries.items()):
    if count > 0:
        print(f"  {name}: {count}")
```

This is how we discovered `POP_JUMP_IF_FALSE`, `POP_JUMP_IF_TRUE`, `POP_JUMP_IF_NONE`, `POP_JUMP_IF_NOT_NONE`, and `JUMP_BACKWARD` all have 1 CACHE entry — these were missing from the initial `cache_count` table and caused subtle off-by-one jump bugs.

## Getting Definitive BINARY_OP Constants

Similarly, don't guess the BINARY_OP dispatch codes. Write a debug script that compiles each operator and inspects the raw `arg` byte:

```python
import dis
for expr, sym in [("a+b","+"), ("a-b","-"), ("a*b","*"), ("a/b","/"), ("a//b","//"), ("a%b","%"), ("a**b","**")]:
    code = compile(f"def f(a,b): return {expr}", "<t>", "exec")
    for const in code.co_consts:
        if hasattr(const, 'co_code'):
            for instr in dis.get_instructions(const):
                if instr.opname == "BINARY_OP":
                    print(f"  {sym:4s} -> arg={instr.arg}")
```

## Running Python Commands in the Terminal

**Inline Python one-liners with special characters often fail** on Windows in PowerShell. Quotes, parentheses, angle brackets, and escaping interact badly between PowerShell's parser and Python's. Symptoms include `Access is denied`, `The system cannot find the file specified`, or mangled command strings.

**Workaround**: Instead of fighting with escaping, write a small `_debug_*.py` script file, run it with `python test/_debug_foo.py`, then delete it when done. This is far more reliable than trying to get inline `-c` commands working. Example workflow:

1. Create `test/_debug_cmp.py` with your inspection code
2. Run `python test/_debug_cmp.py`
3. Read the output
4. Delete the file when done (`Remove-Item test/_debug_cmp.py`)

Simple one-liners that avoid special characters (like `python -c "import opcode; print(opcode.cmp_op)"`) do work fine.

## COMPARE_OP Encoding Is Not What You'd Expect

The COMPARE_OP arg in Python 3.13 is **not** a simple comparison index. The comparison type is at `arg >> 5` (5-bit shift), not `arg >> 4`. The lower 5 bits encode flags for the adaptive interpreter (bit 4 = "produces bool result" flag). This differs from some online documentation that says `>> 4`.

## Super-Instructions (LOAD_FAST_LOAD_FAST, etc.)

Python 3.13 uses "super-instructions" that combine two operations into one opcode for performance. The arg packs two 4-bit indices:
- `arg >> 4` = first index
- `arg & 0xF` = second index

For `LOAD_FAST_LOAD_FAST`: push `locals[arg>>4]`, then push `locals[arg&0xF]`.
For `STORE_FAST_STORE_FAST`: pop TOS → `locals[arg>>4]`, pop TOS1 → `locals[arg&0xF]`. **Note the store order is the reverse of what you might expect** — TOS goes to the first (higher) index, TOS1 to the second.

## FOR_ITER Exhaustion Behavior

When `FOR_ITER` detects iterator exhaustion, it jumps forward by `arg` words but does **not** pop the iterator itself. The iterator stays on the stack. The `END_FOR` instruction (which is essentially a no-op) is followed by a `POP_TOP` that cleans up the iterator. Don't try to pop the iterator in `FOR_ITER` or you'll get stack underflows.
