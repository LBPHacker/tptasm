local printf = require("tptasm.printf")
local config = require("tptasm.config")
local opcode = require("tptasm.opcode")
local detect = require("tptasm.detect")
local xbit32 = require("tptasm.xbit32")
local hacks  = require("tptasm.archs.hacks")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%define dw `dw'
		%define org `org'

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local entities = {
	["r0"] = { type = "register", offset = 0 },
	["r1"] = { type = "register", offset = 1 },
	["r2"] = { type = "register", offset = 2 },
	["r3"] = { type = "register", offset = 3 },
}

local mnemonics = {
	[  "ldi"] = { class = "1I", bit =  0, flags = " s n " }, -- * r: write to and lock RP
	[   "ld"] = { class = "1R", bit =  3, flags = "r    " }, -- * s: redirect explicit branch ptr to P
	[   "st"] = { class = "1R", bit =  4, flags = "r    " }, -- * b: write to and lock EBP^
	[  "stl"] = { class = "0" , bit =  5, flags = "     " }, -- * n: write to and lock NIP
	["andrl"] = { class = "0" , bit =  6, flags = "     " }, -- * p: write to and lock P
	[  "xor"] = { class = "0" , bit =  7, flags = "     " },
	[   "rr"] = { class = "0" , bit =  8, flags = "     " },
	[ "setc"] = { class = "0" , bit =  9, flags = "     " },
	[  "brc"] = { class = "1I", bit = 10, flags = " s n " },
	[ "brnc"] = { class = "1I", bit = 10, flags = "    p" },
	[  "out"] = { class = "0" , bit = 11, flags = "     " },
	[ "bsto"] = { class = "0" , bit = 12, flags = "     " },
	[  "ldb"] = { class = "0" , bit = 13, flags = " s   " },
	[   "br"] = { class = "1I", bit = -1, flags = "  b  " },
}

local nop = opcode.make(28)

local dw_bits = 29

local mnemonic_desc = {}

function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end

function mnemonic_desc.emit(mnemonic_token_hax, parameters_hax, offset)
	local sub_instructions = hacks.pig(mnemonic_token_hax, parameters_hax, mnemonics)
	if not sub_instructions then
		return false
	end

	local final_code = nop:clone()
	local bit_invoked_by = {}
	local rp_locked = false
	local rp_value = 0
	local nip_locked = false
	local nip_value = 0
	local p_locked = false
	local p_value = 0
	local explicit_branch = false
	local branch_to_p = false
	for _, subinst in ipairs(sub_instructions) do
		if subinst.instr_desc.flags:find("s") then
			branch_to_p = true
		end
	end
	for _, subinst in ipairs(sub_instructions) do
		local bit = subinst.instr_desc.bit
		if bit_invoked_by[bit] then
			subinst.mnemonic_token:blamef(printf.err, "micro-instruction invoked multiple times")
			bit_invoked_by[bit]:blamef(printf.info, "first invoked here")
			return false
		end
		bit_invoked_by[bit] = subinst.mnemonic_token

		local imm
		if subinst.operand and subinst.operand:number() then
			imm = subinst.operand.parsed
			local trunc = 0x80
			if imm >= trunc then
				imm = imm % trunc
				subinst.operand:blamef(printf.warn, "number truncated to 7 bits")
			end
		end

		local temp_flags = subinst.instr_desc.flags
		if temp_flags:find("b") then
			explicit_branch = true
			if branch_to_p then
				temp_flags = temp_flags .. "p"
			else
				temp_flags = temp_flags .. "n"
			end
		end

		if temp_flags:find("p") then
			if p_locked and subinst.operand.parsed ~= p_value then
				subinst.mnemonic_token:blamef(printf.err, "general pointer already locked")
				p_locked:blamef(printf.info, "locked by this")
				return false
			end
			p_locked = subinst.mnemonic_token
			p_value = imm
		end

		if temp_flags:find("n") then
			if nip_locked and subinst.operand.parsed ~= nip_value then
				subinst.mnemonic_token:blamef(printf.err, "next instruction pointer already locked")
				nip_locked:blamef(printf.info, "locked by this")
				return false
			end
			nip_locked = subinst.mnemonic_token
			nip_value = imm
		end

		if temp_flags:find("r") then
			if rp_locked and subinst.operand.entity.offset ~= rp_value then
				subinst.mnemonic_token:blamef(printf.err, "register bits already locked")
				rp_locked:blamef(printf.info, "locked by this")
				return false
			end
			rp_locked = subinst.mnemonic_token
			rp_value = subinst.operand.entity.offset
		end

		final_code:merge(1, bit)
	end
	if not explicit_branch then
		local next_inst = xbit32.band(offset + 1, 0x7F)
		if branch_to_p then
			p_value = next_inst
		else
			nip_value = next_inst
		end
	end
	final_code:merge(p_value, 21)
	final_code:merge(nip_value, 14)
	final_code:merge(rp_value, 1)

	return true, { final_code }
end

local mnemonics = {}
for key in pairs(mnemonics) do
	mnemonics[key] = mnemonic_desc
end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local space_available = ({
		["A728D280"] =  0,
		["A728D28A"] = 16,
	})[model]
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	for ix = 0, #opcodes do
		sim.partProperty(sim.partID(x + 18 - ix, y - 9), "ctype", 0x20000000 + opcodes[ix].dwords[1])
	end
end

return {
	includes = includes,
	dw_bits = dw_bits,
	nop = nop,
	entities = entities,
	mnemonics = mnemonics,
	flash = flash,
}
