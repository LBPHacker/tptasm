local config = require("config")
local opcode = require("opcode")
local detect = require("detect")
local xbit32 = require("xbit32")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%define dw `dw'
		%define org `org'

		%macro jz Label
			jnzg . `peerlabel' _Jz `macrounique', Label
		. `peerlabel' _Jz `macrounique':
		%endmacro

		%macro jzg Label, GLabel
			jnzg GLabel, Label
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local entities = {}
local nop = opcode.make(18)
local dw_bits = 18

local mnemonic_to_class_code_g = {
	[  "st" ] = { class = "S1", code = 0x00000 },
	[  "gt" ] = { class =  "1", code = 0x00280 },
	[  "lt" ] = { class =  "1", code = 0x00200 },
	[ "jnz" ] = { class = "C1", code = 0x00400 },
	[  "ld" ] = { class =  "1", code = 0x00680 },
	[ "xor" ] = { class =  "1", code = 0x01080 },
	[ "add" ] = { class =  "1", code = 0x01280 },
	[ "and" ] = { class =  "1", code = 0x01400 },
	[  "or" ] = { class =  "1", code = 0x01680 },
	[ "shl" ] = { class =  "0", code = 0x00900 },
	[ "shr" ] = { class =  "0", code = 0x00B00 },
}
local mnemonic_to_class_code = {}
for mnemonic, class_code in pairs(mnemonic_to_class_code_g) do
	mnemonic_to_class_code[mnemonic       ] = { class = class_code.class       , code = class_code.code }
	mnemonic_to_class_code[mnemonic .. "g"] = { class = class_code.class .. "G", code = class_code.code }
end
local mnemonic_desc = {}

function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end

function mnemonic_desc.emit(mnemonic_token, parameters, offset)
	local operands = {}
	for ix, ix_param in ipairs(parameters) do
		if #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:number()
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "mem",
				value = ix_param[2].parsed,
				token = ix_param[2]
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
	local wants_operands = (desc.class:find("1") and 1 or 0) + (desc.class:find("G") and 1 or 0)
	if #operands == wants_operands then
		operand_mode_valid = true
	end
	if wants_operands == 1 and desc.class:find("C") and operands[1].type ~= "imm" then
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

	local goto_target = offset + 1
	local imm_operand = 0
	if desc.class:find("G") then
		local operand = operands[#operands]
		local truncated = operand.value % 0x80
		local value = operand.value
		if value >= 0x80 then
			value = value % 0x80
			operand.token:blamef(printf.warn, "number truncated to 7 bits")
		end
		goto_target = value
		operands[#operands] = nil
	end
	if desc.class:find("1") then
		local limit = desc.class:find("C") and 7 or 5
		local operand = operands[#operands]
		local truncated = operand.value % 2 ^ limit
		local value = operand.value
		if value >= 2 ^ limit then
			value = value % 2 ^ limit
			operand.token:blamef(printf.warn, "number truncated to " .. limit .. " bits")
		end
		imm_operand = value
		if operand.type == "mem" and imm_operand >= 0x10 and not desc.class:find("S") then
			imm_operand = imm_operand % 2 * 2 + 0x10
		end
		if operand.type == "imm" and not desc.class:find("C") then
			imm_operand = xbit32.band(xbit32.rshift(imm_operand, 4), 1) + xbit32.band(xbit32.rshift(imm_operand, 2), 2) + xbit32.lshift(xbit32.band(imm_operand, 3), 3) + xbit32.band(imm_operand, 4) + 0x20
		end
	end

	local final_code = opcode.make(18):merge(desc.code, 0)
	if desc.class:find("C") then
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 6), 1),  7)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 5), 1), 13)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 4), 1), 11)
		final_code:merge(xbit32.band(              imm_operand    , 1), 15)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 1), 1), 17)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 2), 1), 16)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 3), 1), 14)
	else
		final_code:merge(xbit32.band(              imm_operand    , 15), 14)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 4),  1), 13)
		final_code:merge(xbit32.band(xbit32.rshift(imm_operand, 5),  1), 11)
	end
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 5), 1), 0)
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 4), 1), 1)
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 1), 1), 2)
	final_code:merge(xbit32.band(              goto_target    , 1), 3)
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 2), 1), 4)
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 6), 1), 5)
	final_code:merge(xbit32.band(xbit32.rshift(goto_target, 3), 1), 6)

	return true, { final_code }
end

local mnemonics = {}
for key in pairs(mnemonic_to_class_code) do
	mnemonics[key] = mnemonic_desc
end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local space_available = 0x80
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	for ix = 0, 127 do
		local opcode = opcodes[ix] and opcodes[ix].dwords[1] or 0x00E00
		local x_ = x + bit.band(bit.rshift(ix, 6), 1)
		local y_ = y + 1 + bit.band(ix, 63)
		for ib = 0, 17 do
			local old = sim.partID(x_ + ib * 2, y_)
			if old then
				sim.partKill(old)
			end
			if bit.band(opcode, bit.lshift(1, ib)) ~= 0 then
				local new = sim.partCreate(-3, x_ + ib * 2, y_, elem.DEFAULT_PT_FILT)
				sim.partProperty(new, "ctype", 0x20000001)
			end
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
