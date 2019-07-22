-- "Micro Computer v2.1" by RockerM4NHUN, id:1599945

local config = require("config")
local opcode = require("opcode")
local detect = require("detect")
local xbit32 = require("xbit32")
local printf = require("printf")

local arch_micro21 = {}

local macros_str
do
	local macros_arr = {}
	for macro, code in pairs({
		[  "c"] = "if  s,  1",
		[  "a"] = "if  s,  2",
		[  "e"] = "if  s,  4",
		[  "b"] = "ifn s,  6",
		[ "2z"] = "if  s,  8",
		[ "1z"] = "if  s, 16",
		[ "ly"] = "if  s, 32",
		[ "nc"] = "ifn s,  1",
		[ "na"] = "ifn s,  2",
		[ "ne"] = "ifn s,  4",
		[ "nb"] = "if  s,  6",
		["n2z"] = "ifn s,  8",
		["n1z"] = "ifn s, 16",
		[ "ln"] = "ifn s, 32",
	}) do
		table.insert(macros_arr, ([==[
			%%macro if%s
				%s
			%%endmacro
		]==]):format(macro, code))
		table.insert(macros_arr, ([==[
			%%macro j%s loc
				if%s
				jmp loc
			%%endmacro
		]==]):format(macro, macro))
	end
	macros_str = table.concat(macros_arr)
end

arch_micro21.includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%define dw `dw'
		%define org `org'

		%macro ifz reg
			ifn reg, 0xFF
		%endmacro

		%macro ifnz reg
			if reg, 0xFF
		%endmacro
	]==] .. macros_str .. [==[

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

arch_micro21.dw_bits = 17

arch_micro21.nop = opcode.make(17)

arch_micro21.entities = {
	["a"] = { type = "register", offset = 1 },
	["b"] = { type = "register", offset = 2 },
	["s"] = { type = "register", offset = 3 },
}

arch_micro21.mnemonics = {}
do
	local mnemonic_to_class_code = {
		[ "stop"] = { class = "nop", code = 0x00000 },
		["stopv"] = { class = "nop", code = 0x00FFF },
		[  "jmp"] = { class =   "0", code = 0x01000 },
		[   "if"] = { class =  "01", code = 0x02000 },
		[  "ifn"] = { class =  "01", code = 0x03000 },
		[  "nin"] = { class =   "0", code = 0x04000 },
		[ "copy"] = { class =  "01", code = 0x05000 },
		[  "lin"] = { class = "nop", code = 0x06000 },
		[  "rnd"] = { class = "nop", code = 0x07000 },
		[  "adc"] = { class =  "01", code = 0x08000 },
		[  "add"] = { class =  "01", code = 0x09000 },
		[  "lod"] = { class =  "01", code = 0x0A000 },
		[  "sto"] = { class =  "01", code = 0x0B000 },
		[  "and"] = { class =  "01", code = 0x0C000 },
		[   "or"] = { class =  "01", code = 0x0D000 },
		[  "xor"] = { class =  "01", code = 0x0E000 },
		[  "shr"] = { class =  "01", code = 0x10000 },
		[  "shl"] = { class =  "01", code = 0x11000 },
		[  "rtr"] = { class =  "01", code = 0x12000 },
		[  "rtl"] = { class =  "01", code = 0x13000 },
		[  "out"] = { class =  "0?", code = 0x14000 },
		[ "stip"] = { class = "nop", code = 0x15000 },
		[ "test"] = { class =  "01", code = 0x16000 },
		[ "sysr"] = { class = "nop", code = 0x17000 },
		[  "neg"] = { class =  "01", code = 0x18000 },
		[  "nop"] = { class = "nop", code = 0x1F000 },
		[ "nopv"] = { class = "nop", code = 0x1FFFF },
	}

	local mnemonic_desc = {}
	function mnemonic_desc.length()
		return true, 1 -- * RISC :)
	end

	function mnemonic_desc.emit(mnemonic_token, parameters)
		local operands = {}
		for ix, ix_param in ipairs(parameters) do
			if #ix_param == 1
			   and ix_param[1]:is("entity") and ix_param[1].entity.type == "register" then
				table.insert(operands, {
					type = "reg",
					value = ix_param[1].entity.offset
				})

			elseif #ix_param == 1
			   and ix_param[1]:number() then
				table.insert(operands, {
					type = "imm",
					value = ix_param[1].parsed,
					token = ix_param[1]
				})
			   
			else
				if ix_param[1] then
					ix_param[1]:blamef(printf.err, "operand format not recognised")
				else
					ix_param.before:blamef_after(printf.err, "operand format not recognised")
				end
				return false

			end
		end

		local desc = mnemonic_to_class_code[mnemonic_token.value]
		local operand_mode_valid = false
		if (desc.class == "nop" and #operands == 0)
		or ((desc.class == "0" or desc.class == "0?") and #operands == 1)
		or ((desc.class == "01" or desc.class == "0?") and #operands == 2) then
			operand_mode_valid = true
		end
		if #operands == 2 and operands[1].type == "imm" and operands[2].type == "imm" then
			operand_mode_valid = false
		end
		if not operand_mode_valid then
			local operands_repr = {}
			for _, ix_oper in ipairs(operands) do
				table.insert(operands_repr, ix_oper.type)
			end
			mnemonic_token:blamef(printf.err, "no variant of %s exists that takes '%s' operands", mnemonic_token.value, table.concat(operands_repr, ", "))
			return false
		end

		local final_code = opcode.make(17):merge(desc.code, 0)
		local function bind_operand(slot, operand)
			if operand.type == "imm" then
				local truncated = operand.value % 0x100
				local value = operand.value
				if value >= 0x100 then
					value = value % 0x100
					operands[ix].token:blamef(printf.warn, "number truncated to 8 bits")
				end
				final_code:merge(value, 0)
			elseif operand.type == "reg" then
				final_code:merge(operand.value, 12 - slot * 2)
			end
		end
		for ix, ix_op in ipairs(operands) do
			bind_operand(ix, ix_op)
		end
		return true, { final_code }
	end
	for mnemonic in pairs(mnemonic_to_class_code) do
		arch_micro21.mnemonics[mnemonic] = mnemonic_desc
	end
end

function arch_micro21.flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end
	local space_available = 0x80
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end
	local colour_codes = {
		[ 0] = 0xFF00FF00,
		[ 1] = 0xFF00FF00,
		[ 2] = 0xFF00FF00,
		[ 3] = 0xFF00FF00,
		[ 4] = 0xFF00FF00,
		[ 5] = 0xFF00FF00,
		[ 6] = 0xFF00FF00,
		[ 7] = 0xFF00FF00,
		[ 8] = 0xFFFF00FF,
		[ 9] = 0xFFFF00FF,
		[10] = 0xFFFFFF00,
		[11] = 0xFFFFFF00,
		[12] = 0xFFFF0000,
		[13] = 0xFFFF0000,
		[14] = 0xFFFF0000,
		[15] = 0xFFFF0000,
		[16] = 0xFFFF0000,
	}
	for iy = 0, 127 do
		local code = opcodes[iy] and opcodes[iy].dwords[1] or 0
		for ix = 0, 16 do
			local px, py = x - ix + 354, y + iy + 73
			local old_id = sim.partID(px, py)
			if old_id then
				sim.partKill(old_id)
			end
			if xbit32.band(code, 2 ^ ix) ~= 0 then
				local new_id = sim.partCreate(-2, px, py, elem.DEFAULT_PT_ARAY)
				local colour_code = colour_codes[ix]
				if code == 0x1FFFF or code == 0x00FFF then
					colour_code = 0xFF00FFFF
				end
				if xbit32.band(code, 0x1F000) == 0x01000 and ix < 8 then
					colour_code = 0xFF00FFFF
				end
				sim.partProperty(new_id, "dcolour", colour_code)
			end
		end
	end
end

return arch_micro21
