# Project Summary

PythonInLua is a project that aims to be a zero-dependency Python implementation in Lua. It will be able to compile a Python script into PyC bytecode, then execute it in an entirely Lua-based Python virtual machine. The compiler and virtual machine will be separated so that the virtual machine can be shipped alongside Python bytecode for a more compact distribution.

# Current Status

The project is currently in the early stages of development. The virtual machine will be implemented first, followed by the compiler.

# Testing

Tests are located under `test/`. Each test is a Python script with a header comment that specifies the expected output. A test runner is not yet implemented.