# Moonsnake VM Parity Table

Status of Python 3.13 features in the Lua VM. "Partial" means common cases work but edge cases or sub-features are missing.

## Opcodes

| Opcode(s) | Status | Notes |
|---|---|---|
| LOAD_CONST, LOAD_NAME, LOAD_GLOBAL | done | LOAD_GLOBAL handles push-null encoding |
| LOAD_FAST, STORE_FAST, STORE_NAME, STORE_GLOBAL | done | |
| LOAD_FAST_LOAD_FAST, STORE_FAST_LOAD_FAST, STORE_FAST_STORE_FAST | done | super-instructions |
| LOAD_ATTR, STORE_ATTR | done | method-call variant (is_method flag) supported |
| LOAD_DEREF, STORE_DEREF, MAKE_CELL, COPY_FREE_VARS | missing | closures over locals |
| LOAD_BUILD_CLASS | missing | needed for class definitions |
| POP_TOP, PUSH_NULL, RETURN_VALUE, RETURN_CONST | done | |
| MAKE_FUNCTION | done | |
| CALL, CALL_KW, CALL_FUNCTION_EX | partial | CALL done; CALL_KW, CALL_FUNCTION_EX missing |
| BINARY_OP | partial | all arithmetic and bitwise ops done; matrix multiply (@) missing |
| BINARY_SUBSCR, STORE_SUBSCR | done | 0-based, negative indices |
| BINARY_SLICE, STORE_SLICE | missing | slicing |
| COMPARE_OP | done | |
| IS_OP, CONTAINS_OP | done | |
| UNARY_NOT, UNARY_NEGATIVE, UNARY_INVERT | done | |
| BUILD_LIST, BUILD_TUPLE, BUILD_MAP, BUILD_SET | partial | LIST, TUPLE, MAP done; SET missing |
| BUILD_CONST_KEY_MAP | done | constant-key dict literals |
| DELETE_SUBSCR | done | `del d[k]`, `del lst[i]` |
| BUILD_STRING | done | f-string concatenation |
| LIST_EXTEND, LIST_APPEND | partial | LIST_EXTEND done; LIST_APPEND opcode (used in comprehensions) missing |
| DICT_MERGE, DICT_UPDATE, SET_ADD, MAP_ADD | missing | |
| UNPACK_SEQUENCE | done | |
| UNPACK_EX | missing | starred unpacking |
| GET_ITER, FOR_ITER, END_FOR | done | |
| FORMAT_SIMPLE, FORMAT_WITH_SPEC, CONVERT_VALUE | done | f-string formatting |
| COPY, SWAP | done | |
| TO_BOOL | done | |
| POP_JUMP_IF_FALSE/TRUE/NONE/NOT_NONE | done | |
| JUMP_FORWARD, JUMP_BACKWARD | done | |
| EXTENDED_ARG | missing | limits functions to <256 locals/consts |
| BEFORE_WITH | done | context manager entry; happy-path `with` works |
| WITH_EXCEPT_START | missing | exception path inside `with` blocks |
| PUSH_EXC_INFO, POP_EXCEPT, RAISE_VARARGS, RERAISE | missing | exception handling |
| IMPORT_NAME, IMPORT_FROM | missing | import system |
| RESUME, NOP, CACHE | done | treated as no-ops |

## Built-in Types

| Type | Status | Notes |
|---|---|---|
| int | done | arbitrary via Lua number |
| float | done | |
| bool | done | |
| NoneType | done | singleton |
| str | done | methods: upper, lower, strip, split, join, replace, find, index, startswith, endswith, count, is*, zfill, center, ljust, rjust |
| list | done | methods: append, extend, pop, insert, remove, sort, reverse, index, count, clear, copy |
| tuple | partial | create/iterate/unpack work; no methods |
| dict | done | insertion-ordered; methods: `keys`, `values`, `items`, `get`, `setdefault`, `pop`, `update`, `clear`, `copy`. Tuple keys not supported (Lua identity semantics) |
| set | missing | |
| file | done | methods: read, readline, readlines, write, close; context manager via \_\_enter\_\_/\_\_exit\_\_ |
| range | done | used as iterator; no slicing or len |
| bytes / bytearray | missing | |

## Built-in Functions

| Function | Status | Notes |
|---|---|---|
| print | done | |
| len | done | |
| range | done | |
| int, str, bool, abs | done | |
| min, max | done | |
| type | partial | returns string, not a real type object |
| input | missing | |
| enumerate | done | accepts optional `start` |
| zip | done | stops at shortest |
| map, filter | done | dispatches to Lua or PyFunction callables |
| sorted, reversed | partial | positional-only; no `key`/`reverse` (kw-only, blocked on CALL_KW) |
| list, tuple, dict, set | missing | |
| open | done | returns file object; supports r/w/a and binary modes |
| hasattr, getattr, setattr | missing | |
| isinstance, issubclass | missing | |
| repr | missing | used internally; not exposed as builtin |

## Language Features

| Feature | Status | Notes |
|---|---|---|
| Variables, assignment | done | |
| Arithmetic and comparisons | done | |
| if / elif / else | done | |
| while loops | done | |
| for loops | done | over range, list, str, iterator |
| Functions (def) | done | recursion, multiple args, globals closure |
| Default / keyword arguments | missing | |
| *args / **kwargs | missing | |
| Closures over locals | missing | LOAD_DEREF not implemented |
| Lambda | missing | |
| Classes (class) | missing | |
| Inheritance | missing | |
| Exception handling (try/except/finally) | missing | |
| raise | missing | |
| with / context managers | partial | happy path works; exceptions inside `with` not handled |
| Generators / yield | missing | |
| async / await | missing | |
| Decorators | missing | |
| List / dict / set comprehensions | missing | |
| f-strings | done | format specs and !r/!s/!a conversions |
| String % formatting | missing | |
| Walrus operator (:=) | missing | |
| Import system | missing | |
| Global / nonlocal declarations | partial | global works; nonlocal requires LOAD_DEREF |
