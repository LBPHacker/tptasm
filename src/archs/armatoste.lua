local config = require("config")
local opcode = require("opcode")
local detect = require("detect")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%define dw `dw'
		%define org `org'

		%macro mov OutRegis, InRegOrImm
			orr OutRegis, r0, InRegOrImm
		%endmacro

		%macro not OutRegis, In
			sub te, r0, 1
			xor outRegis, te, In
		%endmacro

		%macro nop
			orr r0, r0, r0
		%endmacro

		%macro jum Address
			jal r0, Address
		%endmacro

		%macro bls In1, In2, Address
			sls	te, In1, In2
			bne	te, r0, Address
		%endmacro

		%macro bge In1, In2, Address
			sls	te, In1, In2
			beq	te, r0, Address
		%endmacro

		%macro bgr In1, In2, Address
			sls	te, In2, In1
			bne	te, r0, Address
		%endmacro

		%macro ble In1, In2, Address
			sls	te, In2, In1
			beq	te, r0, Address
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 29

local nop = opcode.make(32):merge(0x2C000000, 0)

local entities = {
	[  "r0" ] = { type = "register", offset =  0 },
	[  "r1" ] = { type = "register", offset =  1 },
	[  "r2" ] = { type = "register", offset =  2 },
	[  "r3" ] = { type = "register", offset =  3 },
	[  "r4" ] = { type = "register", offset =  4 },
	[  "r5" ] = { type = "register", offset =  5 },
	[  "r6" ] = { type = "register", offset =  6 },
	[  "r7" ] = { type = "register", offset =  7 },
	[  "r8" ] = { type = "register", offset =  8 },
	[  "r9" ] = { type = "register", offset =  9 },
	[ "r10" ] = { type = "register", offset = 10 },
	[ "r11" ] = { type = "register", offset = 11 },
	[ "r12" ] = { type = "register", offset = 12 },
	[ "r13" ] = { type = "register", offset = 13 },
	[ "r14" ] = { type = "register", offset = 14 },
	[ "r15" ] = { type = "register", offset = 15 },
}
entities["ra"] = entities["r10"]
entities["rb"] = entities["r11"]
entities["rc"] = entities["r12"]
entities["rd"] = entities["r13"]
entities["re"] = entities["r14"]
entities["rf"] = entities["r15"]
entities["ze"] = entities["r0"]
entities["te"] = entities["r13"]
entities["jl"] = entities["r14"]
entities["sp"] = entities["r15"]

local mnemonics = {}

local mnemonic_to_class_code = {
	[ "mju" ] = { class = " BX", code = 0x20000000 },
	[ "wmj" ] = { class = " BX", code = 0x20100000 },
	[ "jal" ] = { class = "A X", code = 0x21000000 },
	[ "beq" ] = { class = "ABX", code = 0x22000000 },
	[ "bne" ] = { class = "ABX", code = 0x23000000 },
	[ "loa" ] = { class = "ABX", code = 0x24000000 },
	[ "inn" ] = { class = "ABX", code = 0x25000000 },
	[ "sto" ] = { class = "ABX", code = 0x26000000 },
	[ "out" ] = { class = "ABX", code = 0x27000000 },
	[ "add" ] = { class = "ABX", code = 0x28000000 },
	[ "sub" ] = { class = "ABX", code = 0x29000000 },
	[ "lbl" ] = { class = "ABX", code = 0x2A000000 },
	[ "lbr" ] = { class = "ABX", code = 0x2B000000 },
	[ "and" ] = { class = "ABX", code = 0x2C000000 },
	[ "orr" ] = { class = "ABX", code = 0x2D000000 },
	[ "xor" ] = { class = "ABX", code = 0x2E000000 },
	[ "sls" ] = { class = "ABX", code = 0x2F000000 },
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
				value = ix_param[1].entity.offset,
			})

		elseif #ix_param == 1
		   and ix_param[1]:number() then
			table.insert(operands, {
				type = "imm",
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
	local code = opcode.make(32):merge(class_code.code, 0)
	local ok = true
	local function push(operand, shift)
		if operand.type == "reg" then
			code = code:merge(operand.value, shift)
		elseif shift == 0 and operand.type == "imm" then
			local width = 16
			local value = operand.value
			if value >= 2 ^ width then
				value = value % 2 ^ width
				operand.token:blamef(printf.warn, "number truncated to " .. width .. " bits")
			end
			code = code:merge(0x10000000, 0):merge(value, 0)
		else
			ok = false
		end
	end
	local index = 0
	if class_code.class:find("A") then
		index = index + 1
		push(operands[index], 20)
	end
	if class_code.class:find("B") then
		index = index + 1
		push(operands[index], 16)
	end
	if class_code.class:find("X") then
		index = index + 1
		push(operands[index],  0)
	end
	if index ~= #operands then
		ok = false
	end
	if ok then
		final_code = code
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

	local function filt(column, row)
		return x + 1 + column, y + 7 - row
	end

	local ram_width = 128
	local max_ram_height_order = 6
	local space_needed = #opcodes + 1
	local ram_height_order

	local vertical_space
	local seen_empty = false
	for row = 0, 2 ^ max_ram_height_order - 1 do
		local filled = true
		local empty = true
		for column = 0, ram_width - 1 do
			local id = sim.partID(filt(column, row))
			if id then
				empty = false
				if sim.partProperty(id, "type") ~= elem.DEFAULT_PT_FILT then
					filled = false
				end
			end
		end
		if filled and not seen_empty or empty then
			vertical_space = row + 1
		else
			break
		end
		if empty then
			seen_empty = true
		end
	end

	for order = 0, max_ram_height_order do
		if space_needed <= ram_width * 2 ^ order then
			if vertical_space < 2 ^ order then
				printf.err("out of vertical space; code takes %i cells, planned to build %i rows of RAM, could only build %i", space_needed, 2 ^ order, vertical_space)
				return
			end
			ram_height_order = order
			break
		end
	end
	if not ram_height_order then
		local space_available = ram_width * 2 ^ max_ram_height_order
		printf.err("out of space; code takes %i cells, only have at most %i", space_needed, space_available)
		return
	end

	for row = 0, vertical_space - 1 do
		for column = 0, ram_width - 1 do
			local xx, yy = filt(column, row)
			local id = sim.partID(xx, yy)
			if row >= 2 ^ ram_height_order then
				if id then
					sim.partKill(id)
				end
			else
				if not id then
					id = sim.partCreate(-3, xx, yy, elem.DEFAULT_PT_FILT)
					if id == -1 then
						printf.err("out of particle IDs")
						return
					end
				end
				local index = row * ram_width + column
				local opcode = opcodes[index] and opcodes[index].dwords[1] or nop.dwords[1]
				sim.partProperty(id, "ctype", opcode)
			end
		end
	end

	sim.partProperty(sim.partID(x - 4, y + 1), "ctype", 0x10000000 + 2 ^ (ram_height_order + 1) - 1)
end

return {
	includes = includes,
	dw_bits = dw_bits,
	nop = nop,
	entities = entities,
	mnemonics = mnemonics,
	flash = flash,
}
