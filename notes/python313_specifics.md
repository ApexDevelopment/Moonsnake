# Python 3.13 Specifics

## Why 3.13?

The project targets Python 3.13 exclusively because:
- Bytecode format changed significantly between 3.11 and 3.12 (instruction widths, opcode numbers)
- 3.13 is the version installed on the development machine
- Locking to one version simplifies the marshal reader and opcode tables

**The magic number for 3.13 .pyc files is 3571 (bytes: F3 0D 0D 0A).**

## Changes from 3.12 to 3.13

Key differences an implementer should know:

- LOAD_GLOBAL encoding: `arg = (namei << 1) | push_null`
- CALL replaces CALL_FUNCTION from older versions; uses a 2-slot protocol (callable + self/null)
- RETURN_CONST is used instead of LOAD_CONST + RETURN_VALUE as an optimization
- Many instructions have trailing CACHE words for the adaptive interpreter
- Instruction format is always 2 bytes (opcode + arg); no variable-width instructions
- EXTENDED_ARG (opcode 71) extends the arg to 16+ bits by chaining

## Opcode Cache Counts

These are critical — if you forget to skip caches, the IP will desync:

| Opcode | CACHE words |
|--------|-----------|
| BINARY_SUBSCR | 1 |
| STORE_SUBSCR | 1 |
| BINARY_OP | 1 |
| UNPACK_SEQUENCE | 1 |
| STORE_ATTR | 4 |
| LOAD_ATTR | 9 |
| COMPARE_OP | 1 |
| LOAD_GLOBAL | 4 |
| LOAD_SUPER_ATTR | 1 |
| CALL | 3 |
| CALL_KW | 3 |
| FOR_ITER | 1 |
| SEND | 1 |
| TO_BOOL | 3 |

## CPython Reference Implementation

CPython's own pure-Python marshal reader is at:
`Tools/build/umarshal.py` in the CPython repo (https://github.com/python/cpython)

The C implementation is at `Python/marshal.c`. The type code definitions start around line 48.

## Useful Commands

```bash
# Compile a .py to .pyc with a specific output path
python -c "import py_compile; py_compile.compile('input.py', 'output.pyc', doraise=True)"

# Disassemble a .py file
python -m dis input.py

# Disassemble inline code
python -c "import dis; dis.dis(compile('print(1)', '<test>', 'exec'))"

# Get all opcode names and numbers
python -c "import opcode; [print(f'{v:3d} = {n}') for n, v in sorted(opcode.opmap.items(), key=lambda x: x[1])]"
```
