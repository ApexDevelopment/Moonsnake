-- PythonInLua: Test runner
-- Compiles each test/*.py file to .pyc via CPython, runs it through the Lua VM,
-- and compares output against the expected output in the test header.
--
-- Usage: lua test/run_tests.lua

-- Set up module path (run from project root)
package.path = "./?.lua;./?/init.lua;" .. package.path

local vm = require("src.vm")

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Parse the test header from a .py file.
--- Expected format:
---   # Expect: Success|Error
---   # Output: <whitespace-separated expected tokens>
---
--- Returns: expect_success (bool), expected_output (string or nil)
local function parse_test_header(filepath)
    local f = io.open(filepath, "r")
    if not f then
        return nil, nil, "Cannot open " .. filepath
    end

    local expect_success = true
    local expected_output = nil

    for line in f:lines() do
        -- Strip leading/trailing whitespace
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed:match("^# Expect:%s*") then
            local val = trimmed:match("^# Expect:%s*(.+)$")
            if val then
                val = val:match("^%s*(.-)%s*$")
                expect_success = (val:lower() == "success")
            end
        elseif trimmed:match("^# Output:%s*") then
            expected_output = trimmed:match("^# Output:%s*(.*)$") or ""
        elseif not trimmed:match("^#") and trimmed ~= "" then
            break  -- stop at first non-comment, non-empty line
        end
    end

    f:close()
    return expect_success, expected_output
end

--- Compile a .py file to .pyc using CPython.
--- Returns the path to the .pyc file, or nil + error message.
local function compile_py(py_path, pyc_path)
    -- Use py_compile to generate deterministic output path
    local cmd = string.format(
        'python -c "import py_compile; py_compile.compile(\'%s\', \'%s\', doraise=True)"',
        py_path:gsub("\\", "/"),
        pyc_path:gsub("\\", "/")
    )
    local ok = os.execute(cmd)
    -- os.execute returns different things in Lua 5.1 vs 5.2+
    if ok == 0 or ok == true then
        return pyc_path
    else
        return nil, "Failed to compile " .. py_path
    end
end

--- Normalize whitespace for comparison: split on whitespace, rejoin with single space.
local function normalize_ws(s)
    if not s then return "" end
    local tokens = {}
    for token in s:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    return table.concat(tokens, " ")
end

--- Capture stdout from running a .pyc file through the VM.
--- Returns the captured output string and success boolean.
local function run_and_capture(pyc_path)
    -- Redirect io.write to capture output
    local captured = {}
    local old_write = io.write
    io.write = function(...)
        for i = 1, select("#", ...) do
            captured[#captured + 1] = tostring(select(i, ...))
        end
    end

    local success, err = pcall(function()
        vm.run_pyc(pyc_path)
    end)

    io.write = old_write

    local output = table.concat(captured)
    return output, success, err
end

---------------------------------------------------------------------------
-- List test files
---------------------------------------------------------------------------

local function list_test_files()
    local files = {}
    -- Use ls/dir to find test files
    local handle
    if package.config:sub(1,1) == "\\" then
        -- Windows
        handle = io.popen('dir /b test\\test_*.py 2>nul')
    else
        -- Unix
        handle = io.popen('ls test/test_*.py 2>/dev/null')
    end
    if handle then
        for line in handle:lines() do
            local name = line:match("([^/\\]+)$")
            if name then
                files[#files + 1] = "test/" .. name
            end
        end
        handle:close()
    end
    table.sort(files)
    return files
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function main()
    local test_files = list_test_files()

    if #test_files == 0 then
        print("No test files found in test/")
        os.exit(1)
    end

    local passed = 0
    local failed = 0
    local errors = {}

    -- Create temp directory for .pyc files
    local pyc_dir = "test/.pyc_cache"
    if package.config:sub(1,1) == "\\" then
        os.execute('if not exist "' .. pyc_dir .. '" mkdir "' .. pyc_dir .. '"')
    else
        os.execute("mkdir -p " .. pyc_dir)
    end

    for _, py_path in ipairs(test_files) do
        local test_name = py_path:match("test/(.+)%.py$")
        local expect_success, expected_output = parse_test_header(py_path)

        -- Compile
        local pyc_path = pyc_dir .. "/" .. test_name .. ".pyc"
        local compiled, compile_err = compile_py(py_path, pyc_path)

        if not compiled then
            failed = failed + 1
            errors[#errors + 1] = string.format("  COMPILE FAIL: %s — %s", test_name, compile_err)
        else
            -- Run
            local output, success, runtime_err = run_and_capture(pyc_path)

            if expect_success then
                if not success then
                    failed = failed + 1
                    errors[#errors + 1] = string.format(
                        "  FAIL: %s — expected success but got error: %s",
                        test_name, tostring(runtime_err))
                elseif expected_output ~= nil then
                    local norm_expected = normalize_ws(expected_output)
                    local norm_actual   = normalize_ws(output)
                    if norm_expected == norm_actual then
                        passed = passed + 1
                        print(string.format("  PASS: %s", test_name))
                    else
                        failed = failed + 1
                        errors[#errors + 1] = string.format(
                            "  FAIL: %s — expected output [%s] but got [%s]",
                            test_name, norm_expected, norm_actual)
                    end
                else
                    -- No expected output specified, just check it didn't error
                    passed = passed + 1
                    print(string.format("  PASS: %s (no output check)", test_name))
                end
            else
                -- We expect an error
                if success then
                    failed = failed + 1
                    errors[#errors + 1] = string.format(
                        "  FAIL: %s — expected error but succeeded",
                        test_name)
                else
                    passed = passed + 1
                    print(string.format("  PASS: %s (expected error)", test_name))
                end
            end
        end
    end

    print()
    if #errors > 0 then
        print("Failures:")
        for _, e in ipairs(errors) do
            print(e)
        end
        print()
    end
    print(string.format("Results: %d passed, %d failed, %d total",
        passed, failed, passed + failed))

    if failed > 0 then
        os.exit(1)
    end
end

main()
