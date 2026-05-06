# Notes for Agents

**Read the README.md and `notes/` before making changes.** The `notes/` directory contains critical reference material:

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