-- LuaBit native backend for Lua 5.3+
-- Vendored from https://github.com/ApexDevelopment/LuaBit

local M = {}

local mask32 = 0xFFFFFFFF

function M.band(a, b) return (a & b) & mask32 end
function M.bor(a, b)  return (a | b) & mask32 end
function M.bxor(a, b) return (a ~ b) & mask32 end
function M.bnot(a)    return (~a) & mask32 end
function M.lshift(a, b) return (a << b) & mask32 end
function M.rshift(a, b) return (a >> b) & mask32 end
function M.rol(a, b)
	b = b % 32
	return ((a << b) | (a >> (32 - b))) & mask32
end
function M.ror(a, b)
	b = b % 32
	return ((a >> b) | (a << (32 - b))) & mask32
end
return M
