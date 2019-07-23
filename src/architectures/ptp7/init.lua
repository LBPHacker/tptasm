-- "PTP7" by unnick, id unknown atm

local config = require("config")
local opcode = require("opcode")
local detect = require("detect")
local printf = require("printf")

local arch_ptp7 = {}

arch_ptp7.includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%ifndef _CONST_MINUS_1
		% error "_CONST_MINUS_1 must be defined and must resolve to an address that holds the constant value 0x1FFFFFFF"
		%endif

		%define dw `dw'
		%define org `org'
		
		%macro jmp loc
			adc [_CONST_MINUS_1]
			jc loc
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

arch_ptp7.nop = opcode.make(29)

arch_ptp7.entities = {}

local mnemonics = {
	[ "shl"] = { class = "1V", code = 0x00 },
	[ "shr"] = { class = "1V", code = 0x01 },
	[ "add"] = { class = "1M", code = 0x02 },
	[ "adc"] = { class = "1M", code = 0x12 },
	["flip"] = { class = "0V", code = 0x03 },
	[ "mov"] = { class = "1M", code = 0x04 },
	["sync"] = { class = "0V", code = 0x05 },
	[ "nop"] = { class = "0V", code = 0x06 },
	[  "jc"] = { class = "1V", code = 0x07 },
}

local mnemonic_desc = {}
function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end
function mnemonic_desc.emit(mnemonic_token, parameters)
	local final_code = arch_ptp7.nop:clone()
	local instr_desc = mnemonics[mnemonic_token.value]
	final_code:merge(instr_desc.code, 24)

	local operands = {}
	for ix, ix_param in ipairs(parameters) do
		if #ix_param == 1
		   and ix_param[1]:number() then
			table.insert(operands, {
				type = "imm",
				value = ix_param[1].parsed,
				token = ix_param[1]
			})

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:number()
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "immaddr",
				value = ix_param[2].parsed,
				token = ix_param[2]
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

	local operand_mode_valid = false
	if instr_desc.class == "0V" then
		if #operands == 0 then
			operand_mode_valid = true
		end

	elseif instr_desc.class == "1V" then
		if #operands == 1 and operands[1].type == "imm" then
			operand_mode_valid = true
		end

	elseif instr_desc.class == "1M" then
		if #operands == 1 and operands[1].type == "immaddr" then
			operand_mode_valid = true
		end

	end
	if not operand_mode_valid then
		local operands_repr = {}
		for _, ix_oper in ipairs(operands) do
			table.insert(operands_repr, ix_oper.type)
		end
		mnemonic_token:blamef(printf.err, "no variant of %s exists that takes '%s' operands", mnemonic_token.value, table.concat(operands_repr, ", "))
		return false
	end

	if #operands == 1 then
		local value = operands[1].value
		if value >= 0x1000000 then
			value = value % 0x1000000
			operands[1].token:blamef(printf.warn, "number truncated to 24 bits")
		end
		final_code:merge(value, 0)
	end

	return true, { final_code }
end

arch_ptp7.dw_bits = 29

arch_ptp7.mnemonics = {}
for key in pairs(mnemonics) do
	arch_ptp7.mnemonics[key] = mnemonic_desc
end

function arch_ptp7.flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end
	local space_available = 0x1000
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end
	for ix = 0, 0xFFF do
		sim.partProperty(sim.partID(x + (ix % 128) - 1, y + math.floor(ix / 128) - 34), "ctype", 0x20000000 + (opcodes[ix] and opcodes[ix].dwords[1] or 0))
	end
end

return arch_ptp7
