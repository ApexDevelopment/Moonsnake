# Python 3.13 Bytecode Format Reference

## .pyc File Header (16 bytes)

| Offset | Size | Field | Value for 3.13 |
|--------|------|-------|-----------------|
| 0-1 | 2B | Magic number | 3571 (0x0DF3) |
| 2-3 | 2B | CRLF marker | 0x0D0A |
| 4-7 | 4B | Flags | Usually 0 |
| 8-11 | 4B | Modification timestamp | Unix timestamp |
| 12-15 | 4B | Source file size | In bytes |
| 16+ | var | Marshal data | Code object |

All multi-byte integers are little-endian.

## Marshal Format

Each object is preceded by a type byte. The high bit (0x80 = FLAG_REF) indicates the object should be added to a reference table for later reuse via TYPE_REF ('r').

### Type Codes

| Byte | Char | Type |
|------|------|------|
| 0x30 | '0' | NULL (sentinel, not Python None) |
| 0x4E | 'N' | None |
| 0x46 | 'F' | False |
| 0x54 | 'T' | True |
| 0x69 | 'i' | int (signed 32-bit LE) |
| 0x49 | 'I' | int64 (signed 64-bit LE) |
| 0x6C | 'l' | long (arbitrary precision, 15-bit digit chunks) |
| 0x67 | 'g' | binary float (IEEE 754 double, 8 bytes LE) |
| 0x73 | 's' | bytes (4B length + data) |
| 0x75 | 'u' | unicode string (4B length + UTF-8 data) |
| 0x74 | 't' | interned string (4B length + UTF-8 data) |
| 0x61 | 'a' | ASCII string (4B length + data) |
| 0x41 | 'A' | ASCII interned (4B length + data) |
| 0x7A | 'z' | short ASCII (1B length + data) |
| 0x5A | 'Z' | short ASCII interned (1B length + data) |
| 0x28 | '(' | tuple (4B count + elements) |
| 0x29 | ')' | small tuple (1B count + elements) |
| 0x5B | '[' | list (4B count + elements) |
| 0x7B | '{' | dict (key-value pairs until NULL) |
| 0x63 | 'c' | code object (see below) |
| 0x72 | 'r' | reference (4B index into ref table) |

### Code Object Fields (read order)

1. `co_argcount` — int32
2. `co_posonlyargcount` — int32
3. `co_kwonlyargcount` — int32
4. `co_stacksize` — int32
5. `co_flags` — int32
6. `co_code` — bytes (the bytecode)
7. `co_consts` — tuple (constant pool)
8. `co_names` — tuple (global/attribute name table)
9. `co_localsplusnames` — tuple (local + cell + free variable names)
10. `co_localspluskinds` — bytes (kind flags per local)
11. `co_filename` — string
12. `co_name` — string
13. `co_qualname` — string
14. `co_firstlineno` — int32
15. `co_linetable` — bytes
16. `co_exceptiontable` — bytes

## Instruction Format

Every instruction is 2 bytes: `[opcode, arg]`. The instruction pointer advances by 1 word (2 bytes) per instruction.

Some opcodes are followed by CACHE words (opcode=0, arg=0) that contain runtime optimization data from CPython's adaptive interpreter. **These must be skipped** (they are no-ops).

### Key Opcodes for Basic Execution

| Opcode | Value | CACHE | Stack Effect | Notes |
|--------|-------|-------|-------------|-------|
| RESUME | 149 | 0 | - | Entry preamble, no-op |
| NOP | 30 | 0 | - | No-op |
| CACHE | 0 | 0 | - | Skip (padding for adaptive interpreter) |
| LOAD_CONST | 83 | 0 | → val | Push co_consts[arg] |
| LOAD_NAME | 92 | 0 | → val | Resolve name from co_names[arg] |
| LOAD_GLOBAL | 91 | 4 | → val [NULL] | arg = (namei<<1)\|push_null. **4 CACHE words follow** |
| LOAD_FAST | 85 | 0 | → val | Push locals[arg] |
| STORE_NAME | 114 | 0 | val → | Pop into globals[name] |
| STORE_FAST | 110 | 0 | val → | Pop into locals[arg] |
| PUSH_NULL | 34 | 0 | → NULL | Push call-protocol sentinel |
| CALL | 53 | 3 | callable NULL args → result | **3 CACHE words follow** |
| POP_TOP | 32 | 0 | val → | Discard TOS |
| RETURN_VALUE | 36 | 0 | val → | Return TOS |
| RETURN_CONST | 103 | 0 | → | Return co_consts[arg] |
| MAKE_FUNCTION | 26 | 0 | code → func | Create function from code object |
| POP_JUMP_IF_FALSE | 97 | 0 | val → | Jump forward by arg words if falsy |
| POP_JUMP_IF_TRUE | 100 | 0 | val → | Jump forward by arg words if truthy |
| JUMP_FORWARD | 79 | 0 | - | Jump forward by arg words |
| JUMP_BACKWARD | 77 | 0 | - | Jump backward by arg words |

### LOAD_GLOBAL Encoding

The arg byte encodes two things:
- `namei = arg >> 1` — index into co_names
- `push_null = arg & 1` — if set, push NULL after the value (for call protocol)

### CALL Stack Protocol

Before CALL, the stack must contain (bottom to top):
```
callable, self_or_null, arg1, arg2, ..., argN
```

- `callable` — the function/builtin to call
- `self_or_null` — CALL_NULL sentinel for regular calls, or self for method calls
- `arg1..argN` — positional arguments (N = CALL's arg)

CALL pops all of these and pushes the return value.
