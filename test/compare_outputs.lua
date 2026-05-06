-- test/compare_outputs.lua
-- Runs every test through CPython (ground truth) AND our VM,
-- then shows a side-by-side diff of their outputs.
--
-- Usage: lua5.1 test/compare_outputs.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
local vm = require("src.vm")

local IS_WINDOWS = package.config:sub(1,1) == "\\"

local function list_test_files()
    local files = {}
    local handle = IS_WINDOWS
        and io.popen('dir /b test\\test_*.py 2>nul')
        or  io.popen('ls test/test_*.py 2>/dev/null')
    if handle then
        for line in handle:lines() do
            local name = line:match("([^/\\]+)$")
            if name then files[#files + 1] = "test/" .. name end
        end
        handle:close()
    end
    table.sort(files)
    return files
end

local function compile_py(py_path, pyc_path)
    local cmd = string.format(
        'python -c "import py_compile; py_compile.compile(\'%s\', \'%s\', doraise=True)" 2>%s',
        py_path:gsub("\\", "/"), pyc_path:gsub("\\", "/"),
        IS_WINDOWS and "nul" or "/dev/null")
    local ok = os.execute(cmd)
    return ok == 0 or ok == true
end

local function run_python(py_path)
    local cmd = IS_WINDOWS
        and ('python "' .. py_path:gsub("/", "\\") .. '" 2>nul')
        or  ('python3 "' .. py_path .. '" 2>/dev/null')
    local h = io.popen(cmd)
    if not h then return "" end
    local out = h:read("*a")
    h:close()
    return out or ""
end

local function run_vm(pyc_path)
    local captured = {}
    local old_write = io.write
    io.write = function(...)
        for i = 1, select("#", ...) do
            captured[#captured + 1] = tostring(select(i, ...))
        end
    end
    local ok, err = pcall(function() vm.run_pyc(pyc_path) end)
    io.write = old_write
    return table.concat(captured), ok, err
end

local function normalize(s)
    local tokens = {}
    for tok in (s or ""):gmatch("%S+") do tokens[#tokens + 1] = tok end
    return table.concat(tokens, " ")
end

-- ── main ──────────────────────────────────────────────────────────────────

local pyc_dir = "test/.pyc_cache"
os.execute(IS_WINDOWS
    and ('if not exist "' .. pyc_dir .. '" mkdir "' .. pyc_dir .. '"')
    or  ('mkdir -p ' .. pyc_dir))

local test_files  = list_test_files()
local n_match     = 0
local mismatches  = {}
local vm_errors   = {}
local compile_fails = {}

for _, py_path in ipairs(test_files) do
    local name     = py_path:match("test/(.+)%.py$")
    local pyc_path = pyc_dir .. "/" .. name .. ".pyc"

    if not compile_py(py_path, pyc_path) then
        compile_fails[#compile_fails + 1] = name
    else
        local py_out          = normalize(run_python(py_path))
        local vm_out, ok, err = run_vm(pyc_path)
        local vm_norm         = ok and normalize(vm_out)
                                   or ("VM ERROR: " .. tostring(err):match("[^\n]+"))

        if py_out == vm_norm then
            n_match = n_match + 1
        elseif not ok then
            vm_errors[#vm_errors + 1] = { name = name, py = py_out, vm = vm_norm }
        else
            mismatches[#mismatches + 1] = { name = name, py = py_out, vm = vm_norm }
        end
    end
end

-- ── report ────────────────────────────────────────────────────────────────

local total = #test_files - #compile_fails
io.write(string.format("\n%d / %d tests match CPython output exactly\n\n",
    n_match, total))

if #mismatches > 0 then
    io.write("── Output mismatches ─────────────────────────────────────────\n")
    for _, t in ipairs(mismatches) do
        io.write(string.format("  %s\n", t.name))
        io.write(string.format("    CPython : %s\n", t.py))
        io.write(string.format("    VM      : %s\n", t.vm))
    end
    io.write("\n")
end

if #vm_errors > 0 then
    io.write("── VM errors (CPython runs fine) ─────────────────────────────\n")
    for _, t in ipairs(vm_errors) do
        io.write(string.format("  %s\n", t.name))
        io.write(string.format("    CPython : %s\n", t.py))
        io.write(string.format("    VM      : %s\n", t.vm))
    end
    io.write("\n")
end

if #compile_fails > 0 then
    io.write("── Compile failures ──────────────────────────────────────────\n")
    for _, name in ipairs(compile_fails) do
        io.write(string.format("  %s\n", name))
    end
    io.write("\n")
end
