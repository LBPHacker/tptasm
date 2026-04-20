local printf = require("tptasm.printf")
local config = require("tptasm.config")
local opcode = require("tptasm.opcode")
local detect = require("tptasm.detect")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%define dw `dw'
		%define org `org'

		%macro data thing
			dw { 0x10000000 thing | }
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 30

local nop = opcode.make(32):merge(0x10000000, 0)

local entities = {}
local mnemonics = {}

local mnemonic_to_class_code = {
    [ "add"  ] = { operands = 1, code = 0x14000000 },
    [ "sub"  ] = { operands = 1, code = 0x16000000 },
    [ "upd"  ] = { operands = 1, code = 0x20000000 },
    [ "upd0" ] = { operands = 1, code = 0x22000000 },
    [ "nop"  ] = { operands = 0, code = 0x10000000 },
    [ "halt" ] = { operands = 0, code = 0x3E000000 },
    [ "jlz"  ] = { operands = 1, code = 0x02000000 },
    [ "jgz"  ] = { operands = 1, code = 0x04000000 },
    [ "jez"  ] = { operands = 1, code = 0x06000000 },
}

local mnemonic_desc = {}
function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end

function mnemonic_desc.emit(mnemonic_token, parameters)
	local operands = {}
	for ix, ix_param in ipairs(parameters) do
		if #ix_param == 1 and ix_param[1]:number() then
			table.insert(operands, {
				value = ix_param[1].parsed,
				token = ix_param[1],
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

	local final_code
	local class_code = mnemonic_to_class_code[mnemonic_token.value]
	if class_code.operands == #operands then
		final_code = opcode.make(32):merge(class_code.code, 0)
		for i = 1, #operands do
			local width = 25
			local value = operands[i].value
			if value >= 2 ^ width then
				value = value % 2 ^ width
				operands[i].token:blamef(printf.warn, "number truncated to " .. width .. " bits")
			end
			final_code:merge(value, 0)
		end
	end

	if not final_code then
		local operands_repr = {}
		for _, ix_oper in ipairs(operands) do
			table.insert(operands_repr, ix_oper.type)
		end
		mnemonic_token:blamef(printf.err, "no variant of %s exists that takes '%s' operands", mnemonic_token.value, table.concat(operands_repr, ", "))
		return false
	end

	return true, { final_code }
end

for mnemonic in pairs(mnemonic_to_class_code) do
	mnemonics[mnemonic] = mnemonic_desc
end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local space_available = 0x200
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	for index = 0, space_available - 1 do
		local id = sim.partID(x + 525 - index, y - 137)
		local opcode = opcodes[index] and opcodes[index].dwords[1] or nop.dwords[1]
		sim.partProperty(id, "ctype", opcode)
	end
end

return {
	includes  = includes,
	dw_bits   = dw_bits,
	nop       = nop,
	entities  = entities,
	mnemonics = mnemonics,
	flash     = flash,
}
