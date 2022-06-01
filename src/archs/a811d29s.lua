local config = require("config")
local opcode = require("opcode")
local detect = require("detect")
local xbit32 = require("xbit32")
local hacks = require("archs.hacks")

local arch_a811d29s = {}

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
	[ "r0" ] = { type = "register", offset = 0 },
	[ "r1" ] = { type = "register", offset = 1 },
	[ "r2" ] = { type = "register", offset = 2 },
	[ "r3" ] = { type = "register", offset = 3 },
	[ "r4" ] = { type = "register", offset = 4 },
	[ "r5" ] = { type = "register", offset = 5 },
	[ "r6" ] = { type = "register", offset = 6 },
	[ "r7" ] = { type = "register", offset = 7 },
}

local mnemonics = {
	[ "nop"  ] = { class = "", value = 0x0000000, flags = "    " }, -- * c: control group
	[ "ldm"  ] = { class = "", value = 0x0000800, flags = "d   " }, -- * m: memory group
	[ "ldr"  ] = { class = "", value = 0x0001000, flags = "d1 r" }, -- * d: default group
	[ "str"  ] = { class = "", value = 0x0002000, flags = "d1 r" }, -- * 8: locks a8 (a[7..0])
	[ "rm"   ] = { class = "", value = 0x0004000, flags = "m18a" }, -- * 1: locks a11 (a[10..8])
	[ "rmb"  ] = { class = "", value = 0x0008000, flags = "m   " },
	[ "jp"   ] = { class = "", value = 0x0010000, flags = "c18a" },
	[ "jpf"  ] = { class = "", value = 0x0020000, flags = "c18a" },
	[ "jpc"  ] = { class = "", value = 0x0040000, flags = "c18a" },
	[ "jpz"  ] = { class = "", value = 0x0080000, flags = "c18a" },
	[ "sipc" ] = { class = "", value = 0x0100000, flags = "d   " },
	[ "sta"  ] = { class = "", value = 0x0200000, flags = "d   " },
	[ "add"  ] = { class = "", value = 0x0400000, flags = "d   " },
	[ "lda"  ] = { class = "", value = 0x0800000, flags = "d   " },
	[ "inv"  ] = { class = "", value = 0x1000000, flags = "d   " },
	[ "in"   ] = { class = "", value = 0x4000000, flags = "d   " },
	[ "out"  ] = { class = "", value = 0x8000000, flags = "d   " },
}

local nop = opcode.make(28):merge(0x20000000, 0)

local dw_bits = 29

local clam_slot_name = {
}

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
	-- local clam_slot_used = {}
	local a8_locked = false
	local a8_value = 0
	local a11_locked = false
	local a11_value = 0
	for _, subinst in ipairs(sub_instructions) do
		-- for clam_slot in subinst.instr_desc.flags:gmatch("[clam]") do
		-- 	if clam_slot_used[clam_slot] then
		-- 		subinst.mnemonic_token:blamef(printf.warn, "micro-instruction slot '%s' used multiple times", clam_slot_name[clam_slot])
		-- 		clam_slot_used[clam_slot]:blamef(printf.info, "first used here")
		-- 		return false
		-- 	end
		-- 	clam_slot_used[clam_slot] = subinst.mnemonic_token
		-- end

		local temp_flags = subinst.instr_desc.flags

		local imm
		if temp_flags:find("a") then
			if subinst.operand and subinst.operand:number() then

			else
				imm = subinst.operand.parsed
				local bits = subinst.instr_desc.flags:find("o") and 1 or 8
				local trunc = 2 ^ bits
				if subinst.instr_desc.flags:find("q") then
					imm = imm - local_config.org_data_base
				end
				if imm >= trunc then
					imm = imm % trunc
					subinst.operand:blamef(printf.warn, "number truncated to %i bits", bits)
				end
			end
		end

		if temp_flags:find("1") then
			if a11_locked and subinst.operand.parsed ~= a11_value then
				subinst.mnemonic_token:blamef(printf.err, "a10..a8 already locked")
				a11_locked:blamef(printf.info, "locked by this")
				return false
			end
			a11_locked = subinst.mnemonic_token
			a11_value = imm
		end

		if temp_flags:find("8") then
			if a8_locked and subinst.operand.parsed ~= a8_value then
				subinst.mnemonic_token:blamef(printf.err, "a7..a0 already locked")
				a8_locked:blamef(printf.info, "locked by this")
				return false
			end
			a8_locked = subinst.mnemonic_token
			a8_value = imm
		end

		final_code:merge(subinst.instr_desc.value, 11)
	end
	final_code:merge(a11_value, 8)
	final_code:merge(a8_value, 0)

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

	local space_available = 0 -- TODO
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	-- TODO
end

return {
	includes = includes,
	dw_bits = dw_bits,
	nop = nop,
	entities = entities,
	mnemonics = mnemonics,
	flash = flash,
}
