local printf = require("tptasm.printf")
local config = require("tptasm.config")
local opcode = require("tptasm.opcode")
local detect = require("tptasm.detect")
local xbit32 = require("tptasm.xbit32")
local hacks  = require("tptasm.archs.hacks")

local arch_i8m7d28s = {}

local local_config = {
	org_data_base = 0x100
}
local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%define dw `dw'
		%define org `org'

		%define org_data_base `org_data_base'

		%macro org_data origin
			org { org_data_base origin + }
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap] or local_config[cap]
	end)
}

local entities = {
	-- * lol nothing
}

local mnemonics = {
	[   "nop"] = { class =  "0", value = 0x000, flags = "clam " }, -- * c: control slot
	[   "pop"] = { class =  "0", value = 0x200, flags = "   m " }, -- * l: logical slot
	[  "stsp"] = { class =  "0", value = 0x400, flags = "   m " }, -- * a: arithmetical slot
	[  "push"] = { class =  "0", value = 0x600, flags = "   m " }, -- * m: memory slot
	[   "ldm"] = { class = "1I", value = 0x800, flags = "   mp" }, -- * p: write to and lock P
	[    "ld"] = { class = "1I", value = 0x800, flags = "q  mp" }, -- * s: redirect explicit branch ptr to P
	["puship"] = { class =  "0", value = 0xA00, flags = "   m " }, -- * b: write to and lock EBP^
	[   "stm"] = { class = "1I", value = 0xC00, flags = "   mp" }, -- * n: write to and lock IP
	[    "st"] = { class = "1I", value = 0xC00, flags = "q  mp" }, -- * o: write to in/out 1-bit offset
	[ "pushi"] = { class = "1I", value = 0xE00, flags = "   mp" }, -- * q: subtract org_data_base from immediate
	[   "sta"] = { class =  "0", value = 0x040, flags = "  a  " },
	[   "dec"] = { class =  "0", value = 0x080, flags = "  a  " },
	[   "inc"] = { class =  "0", value = 0x0C0, flags = "  a  " },
	[  "subi"] = { class = "1I", value = 0x100, flags = "  a p" },
	[  "addi"] = { class = "1I", value = 0x140, flags = "  a p" },
	[   "sub"] = { class =  "0", value = 0x180, flags = "  a  " },
	[   "add"] = { class =  "0", value = 0x1C0, flags = "  a  " },
	[    "or"] = { class =  "0", value = 0x008, flags = " l   " },
	[   "and"] = { class =  "0", value = 0x010, flags = " l   " },
	[   "xor"] = { class =  "0", value = 0x018, flags = " l   " },
	[    "rr"] = { class =  "0", value = 0x020, flags = " l   " },
	[    "rl"] = { class =  "0", value = 0x028, flags = " l   " },
	[   "rng"] = { class =  "0", value = 0x030, flags = " l   " },
	[   "stl"] = { class =  "0", value = 0x038, flags = " l   " },
	[    "jp"] = { class = "1I", value = 0x000, flags = "  b  " },
	[   "jpb"] = { class =  "0", value = 0x001, flags = "c    " },
	[    "jz"] = { class = "1I", value = 0x002, flags = "c   p" },
	[    "jc"] = { class = "1I", value = 0x003, flags = "c   p" },
	[   "jnz"] = { class = "1I", value = 0x002, flags = "c ns " },
	[   "jnc"] = { class = "1I", value = 0x003, flags = "c ns " },
	[   "out"] = { class = "1I", value = 0x004, flags = "co   " },
	[    "in"] = { class = "1I", value = 0x005, flags = "co   " },
}

local nop = opcode.make(28):merge(0x20000000, 0)

local dw_bits = 29

local clam_slot_name = {
	["c"] = "control",
	["l"] = "logical",
	["a"] = "arithmetical",
	["m"] = "memory"
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
	local clam_slot_used = {}
	local ip_locked = false
	local ip_value = 0
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
		for clam_slot in subinst.instr_desc.flags:gmatch("[clam]") do
			if clam_slot_used[clam_slot] then
				subinst.mnemonic_token:blamef(printf.err, "micro-instruction slot '%s' used multiple times", clam_slot_name[clam_slot])
				clam_slot_used[clam_slot]:blamef(printf.info, "first used here")
				return false
			end
			clam_slot_used[clam_slot] = subinst.mnemonic_token
		end

		local imm
		if subinst.operand and subinst.operand:number() then
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
			if ip_locked and subinst.operand.parsed ~= ip_value then
				subinst.mnemonic_token:blamef(printf.err, "instruction pointer already locked")
				ip_locked:blamef(printf.info, "locked by this")
				return false
			end
			ip_locked = subinst.mnemonic_token
			ip_value = imm
		end

		if temp_flags:find("o") then
			final_code:merge(imm, 1)
		end

		final_code:merge(subinst.instr_desc.value, 0)
	end
	if not explicit_branch then
		local next_inst = xbit32.band(offset + 1, 0xFF)
		if branch_to_p then
			p_value = next_inst
		else
			ip_value = next_inst
		end
	end
	final_code:merge(p_value, 12)
	final_code:merge(ip_value, 20)

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

	local space_available = 0x180
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	do
		local frame_pos = -1
		while sim.partProperty(sim.partID(x + frame_pos, y + 3), "type") == elem.DEFAULT_PT_PSTN do
			frame_pos = frame_pos + 1
		end
		for ix = 0x00, 0xFF do
			local code = opcodes[ix] and opcodes[ix].dwords[1] or 0x20000000
			local column = ix % 32
			local row = (ix - column) / 32
			sim.partProperty(sim.partID(x + frame_pos + 2 + column, y + 5 + row), "ctype", code)
		end
	end
	do
		local frame_pos = -3
		while sim.partProperty(sim.partID(x + frame_pos, y + 50), "type") == elem.DEFAULT_PT_PSTN do
			frame_pos = frame_pos + 1
		end
		for ix = 0x00, 0x7F do
			local data = opcodes[ix + 0x100] and opcodes[ix + 0x100].dwords[1] or 0x20000000
			local column = ix % 16
			local row = (ix - column) / 16
			sim.partProperty(sim.partID(x + frame_pos + 2 + column, y + 57 + row), "ctype", data)
		end
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
