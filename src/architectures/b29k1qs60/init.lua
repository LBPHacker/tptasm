-- "B29K1QS60" by unnick, id:2435570

local config = require("config")
local opcode = require("opcode")
local detect = require("detect")
local printf = require("printf")

local arch_b29k1qs60 = {}

arch_b29k1qs60.includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

arch_b29k1qs60.dw_bits = 29 -- * TODO: figure out how dw even works here

arch_b29k1qs60.nop = opcode.make(192)
	:merge(0x20000000,   0)
	:merge(0x20000000,  32)
	:merge(0x20000000,  64)
	:merge(0x20000000,  96)
	:merge(0x20000000, 128)
	:merge(0x20000000, 160)

arch_b29k1qs60.entities = {}

local jmem_mnemonics = {
	["mvaz"] = { code = 0x20000000, jump = false, mask = false },
	["mvjz"] = { code = 0x20000001, jump =  true, mask = false },
	["ldaz"] = { code = 0x20000002, jump = false, mask =  true },
	["ldjz"] = { code = 0x20000003, jump =  true, mask =  true },
	["staz"] = { code = 0x20000004, jump = false, mask = false },
	["stjz"] = { code = 0x20000005, jump =  true, mask = false },
	["exaz"] = { code = 0x20000006, jump = false, mask = false },
	["exjz"] = { code = 0x20000007, jump =  true, mask = false },
}

local mnemonic_desc = {}
function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end
function mnemonic_desc.emit(mnemonic_token, parameters)
	local parameter_ix = 0
	local function take_parameter(role)
		parameter_ix = parameter_ix + 1
		if not parameters[parameter_ix] then
			mnemonic_token:blamef(printf.err, "%s not specified", role)
			return false
		end
		local parameter = parameters[parameter_ix]
		if #parameter < 1 then
			parameter.before:blamef(printf.err, "no tokens in %s", role)
			return false
		end
		if #parameter > 1 then
			parameter[2]:blamef(printf.err, "excess tokens in %s", role)
			return false
		end
		if not parameter[1]:number() then
			parameter[1]:blamef(printf.err, "%s is not a number", role)
			return false
		end
		return parameter[1].parsed
	end

	local final_code = arch_b29k1qs60.nop:clone()
	local instr_desc = jmem_mnemonics[mnemonic_token.value]
	final_code:merge(instr_desc.code, 128)
	do
		local set = take_parameter("bits to set")
		if not set then
			return false
		end
		final_code:merge(set, 0)
	end
	do
		local reset = take_parameter("bits to reset")
		if not reset then
			return false
		end
		final_code:merge(reset, 32)
	end
	if instr_desc.jump then
		do
			local condition = take_parameter("jump condition")
			if not condition then
				return false
			end
			final_code:merge(condition, 64)
		end
		do
			local target = take_parameter("jump target")
			if not target then
				return false
			end
			final_code:merge(target, 96)
		end
	end
	if instr_desc.mask and not instr_desc.jump then
		do
			local mask = take_parameter("read mask")
			if not mask then
				return false
			end
			final_code:merge(mask, 64)
		end
	end
	return true, { final_code }
end

arch_b29k1qs60.mnemonics = {}
for key in pairs(jmem_mnemonics) do
	arch_b29k1qs60.mnemonics[key] = mnemonic_desc
end

function arch_b29k1qs60.flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end
	local space_available = 0x100
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end
	for ix = 0, #opcodes do
		for iy = 1, 6 do
			sim.partProperty(sim.partID(x + ix, y + iy + 3), "ctype", opcodes[ix].dwords[iy])
		end
	end
end

return arch_b29k1qs60
