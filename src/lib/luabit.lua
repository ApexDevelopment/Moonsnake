-- LuaBit - 32-Bitwise operations for Lua 5.x, portable and environment-agnostic
-- Vendored from https://github.com/ApexDevelopment/LuaBit

local M = {}

local major, minor = _VERSION:match("Lua (%d)%.(%d)")
major, minor = tonumber(major), tonumber(minor)

-- Lua 5.3+ has native bitwise operators
local has_native_bitops = major and minor and (major > 5 or (major == 5 and minor >= 3))

if has_native_bitops then
	return require("native")
end

-- Lua 5.2 has the bit32 library
if bit32 then
	M.band   = bit32.band
	M.bor    = bit32.bor
	M.bxor   = bit32.bxor
	M.bnot   = bit32.bnot
	M.lshift = bit32.lshift
	M.rshift = bit32.rshift
	M.rol    = bit32.lrotate
	M.ror    = bit32.rrotate
	return M
end

-- Lua 5.1 with external bit lib (backport or LuaJIT)
local ok, bit = pcall(require, "bit")
if ok and bit then
	M.band   = bit.band
	M.bor    = bit.bor
	M.bxor   = bit.bxor
	M.bnot   = bit.bnot
	M.lshift = bit.lshift
	M.rshift = bit.rshift
	function M.rol(a, b)
		b = b % 32
		return M.band(bit.lshift(a, b) + bit.rshift(a, 32 - b), 0xFFFFFFFF)
	end
	function M.ror(a, b)
		b = b % 32
		return M.band(bit.rshift(a, b) + bit.lshift(a, 32 - b), 0xFFFFFFFF)
	end
	return M
end

-- Pure Lua fallback
local function to_u32(n)
	return n % 2^32
end

local function getbit(n, i)
	return math.floor(n / 2^i) % 2
end

function M.band(a, b)
	local res = 0
	for i = 0, 31 do
		if getbit(a, i) == 1 and getbit(b, i) == 1 then
			res = res + 2^i
		end
	end
	return to_u32(res)
end

function M.bor(a, b)
	local res = 0
	for i = 0, 31 do
		if getbit(a, i) == 1 or getbit(b, i) == 1 then
			res = res + 2^i
		end
	end
	return to_u32(res)
end

function M.bxor(a, b)
	local res = 0
	for i = 0, 31 do
		if getbit(a, i) ~= getbit(b, i) then
			res = res + 2^i
		end
	end
	return to_u32(res)
end

function M.bnot(a)
	local res = 0
	for i = 0, 31 do
		if getbit(a, i) == 0 then
			res = res + 2^i
		end
	end
	return to_u32(res)
end

function M.lshift(a, b)
	return to_u32(a * 2^b)
end

function M.rshift(a, b)
	return math.floor(to_u32(a) / 2^b)
end

function M.rol(a, b)
	b = b % 32
	return to_u32(M.lshift(a, b) + M.rshift(a, 32 - b))
end

function M.ror(a, b)
	b = b % 32
	return to_u32(M.rshift(a, b) + M.lshift(a, 32 - b))
end

return M
