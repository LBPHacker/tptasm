local config = require("config")
local opcode = require("opcode")
local xbit32 = require("xbit32")
local detect = require("detect")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%define dw `dw'
		%define org `org'

		%define ja jnbe
		%define jna jbe
		%define jae jnc
		%define jnae jc
		%define je jz
		%define jne jnz
		%define jg jnle
		%define jng jle
		%define jge jnl
		%define jnge jl
		%define jb jc
		%define jnb jnc

		%define jya jynbe
		%define jyna jybe
		%define jyae jync
		%define jynae jyc
		%define jye jyz
		%define jyne jynz
		%define jyg jynle
		%define jyng jyle
		%define jyge jynl
		%define jynge jyl
		%define jyb jyc
		%define jynb jync

		%macro test pri, sec
			and r0, pri, sec
		%endmacro

		%macro cmp pri, sec
			sub r0, pri, sec
		%endmacro

		%macro nop
			mov r0, r0, r1
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 32

local nop = opcode.make(32):merge(0x00000000, 0)

local entities = {}
for i = 0, 31 do
	entities["r" .. i] = { type = "register", offset = i }
end

local mnemonics = {}

local function transform(tbl, func)
	local newtbl = {}
	for key, value in pairs(tbl) do
		func(newtbl, key, value)
	end
	return newtbl
end

local function shallow_copy(tbl)
	return transform(tbl, function(newtbl, key, value)
		newtbl[key] = value
	end)
end

local cond_info = {
	[    "" ] = { code = 0x00000000 },
	[  "be" ] = { code = 0x00100000 },
	[   "l" ] = { code = 0x00200000 },
	[  "le" ] = { code = 0x00300000 },
	[   "s" ] = { code = 0x00400000 },
	[   "z" ] = { code = 0x00500000 },
	[   "o" ] = { code = 0x00600000 },
	[   "c" ] = { code = 0x00700000 },
	[   "n" ] = { code = 0x00800000 },
	[ "nbe" ] = { code = 0x00900000 },
	[  "nl" ] = { code = 0x00A00000 },
	[ "nle" ] = { code = 0x00B00000 },
	[  "ns" ] = { code = 0x00C00000 },
	[  "nz" ] = { code = 0x00D00000 },
	[  "no" ] = { code = 0x00E00000 },
	[  "nc" ] = { code = 0x00F00000 },
}
local mnemonic_info = {
	-- F: updates flags, append s to the mnemonic to suppress them
	-- G: can update flags, append f to the mnemonic to enable this
	-- J: some kind of jump (secondary is encoded as primary)
	-- H: some kind of shift (immediate is limited to 4 bits)
	-- P: takes primary
	-- S: takes secondary
	-- T: takes tertiary
	-- D: secondary defaults to primary
	-- M: secondary defaults to tertiary, or r0 if tertiary is imm
	-- E: secondary defaults to r0
	-- X: syntactically swap secondary and tertiary
	[  "mov" ] = { traits = "GPSTM  ", code = 0x00000000 },
	[    "j" ] = { traits = "J STE  ", code = 0x01010000 },
	[   "jy" ] = { traits = "J STE  ", code = 0x00010000 },
	[   "ld" ] = { traits = " PSTE  ", code = 0x00020000 },
	[  "exh" ] = { traits = "FPSTD  ", code = 0x00030000 },
	[  "sub" ] = { traits = "FPSTDX ", code = 0x00040000, companion_code_xor = 0x00020000, companion_add_one = true },
	[  "sbb" ] = { traits = "FPSTDX ", code = 0x00050000, companion_code_xor = 0x00020000, companion_add_one = true },
	[  "add" ] = { traits = "FPSTD  ", code = 0x00060000 },
	[  "adc" ] = { traits = "FPSTD  ", code = 0x00070000 },
	[   "or" ] = { traits = "FPSTD  ", code = 0x00090000 },
	[  "xor" ] = { traits = "FPSTD  ", code = 0x00080000 },
	[   "st" ] = { traits = " PSTE  ", code = 0x000A0000 },
	[  "shl" ] = { traits = "FPSTD H", code = 0x000B0000 },
	[  "shr" ] = { traits = "FPSTD H", code = 0x000B8000 },
	[  "and" ] = { traits = "FPSTD  ", code = 0x000C0000 },
	[  "hlt" ] = { traits = "       ", code = 0x000D0000 },
	[  "mul" ] = { traits = " PST   ", code = 0x000E0000 },
	[ "mulh" ] = { traits = " PST   ", code = 0x000F0000 },
	[ "muls" ] = { traits = " PST   ", code = 0x800E0000 },
	[ "mulx" ] = { traits = " PST   ", code = 0x800F0000 },
}
mnemonic_info = transform(mnemonic_info, function(newtbl, key, value)
	if value.traits:find("F") then
		newtbl[key .. "s"] = value
		local nvalue = shallow_copy(value)
		nvalue.code = xbit32.bor(nvalue.code, 0x80000000)
		newtbl[key] = nvalue
	elseif value.traits:find("G") then
		newtbl[key] = value
		local nvalue = shallow_copy(value)
		nvalue.code = xbit32.bor(nvalue.code, 0x80000000)
		newtbl[key .. "f"] = nvalue
	else
		newtbl[key] = value
	end
end)
mnemonic_info = transform(mnemonic_info, function(newtbl, key, value)
	if value.traits:find("J") then
		for ckey, cvalue in pairs(cond_info) do
			local nvalue = shallow_copy(value)
			nvalue.code = xbit32.bor(nvalue.code, cvalue.code)
			local nkey = key .. ckey
			if nkey == "j" then
				nkey = "jmp"
			end
			newtbl[nkey] = nvalue
		end
	else
		newtbl[key] = value
	end
end)

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

	local info = mnemonic_info[mnemonic_token.value]
	local warnings_emitted = {}
	local named_ops = {}

	local code = info.code
	local named_op_index = 1
	local imm_index = 3
	if info.traits:find("X") then
		imm_index = 2
	end
	for ix_operand = 1, #operands do
		local operand = operands[ix_operand]
		if operand and operand.type == "imm" then
			local trunc_bits = 16
			if info.traits:find("H") then
				trunc_bits = 4
			end
			local trunc = 2 ^ trunc_bits
			if operand.value < 0 and operand.value >= -trunc / 2 then
				operand.value = operand.value + trunc
			end
			if operand.value >= trunc then
				operand.value = operand.value % trunc
				operand.token:blamef(printf.warn, "number truncated to %i bits", trunc_bits)
			end
			if named_op_index < imm_index then
				named_op_index = imm_index
			end
		end
		if named_op_index == 1 and not info.traits:find("P") then
			named_op_index = 2
		end
		if named_op_index == 2 and not info.traits:find("S") then
			named_op_index = 3
		end
		if named_op_index == 3 and not info.traits:find("T") then
			named_op_index = 4
		end
		named_ops[named_op_index] = operand
		named_op_index = named_op_index + 1
	end
	if info.traits:find("T") and not named_ops[3] and named_ops[2] then
		named_ops[3], named_ops[2] = named_ops[2], named_ops[3]
	end
	if info.traits:find("X") then
		if info.traits:find("T") and named_ops[3] and named_ops[3].type == "imm" then
			named_ops[3].value = xbit32.bxor(named_ops[3].value, 0xFFFF)
			if info.companion_add_one then
				named_ops[3].value = xbit32.band(named_ops[3].value + 1, 0xFFFF)
			end
			code = xbit32.bxor(code, info.companion_code_xor)
		else
			named_ops[3], named_ops[2] = named_ops[2], named_ops[3]
		end
	end

	local final_code = nop:clone():merge(code, 0)
	if final_code and info.traits:find("P") then
		if named_ops[1] then
			final_code = final_code:merge(named_ops[1].value, 25)
		else
			final_code = nil
		end
	end
	if final_code and info.traits:find("S") then
		local shift = info.traits:find("J") and 25 or 20
		if named_ops[2] then
			final_code = final_code:merge(named_ops[2].value, shift)
		elseif info.traits:find("D") and named_ops[1] then
			final_code = final_code:merge(named_ops[1].value, shift)
		elseif info.traits:find("M") and named_ops[3] then
			if named_ops[3].type == "imm" then
				final_code = final_code:merge(entities["r0"].offset, shift)
			else
				final_code = final_code:merge(named_ops[3].value, shift)
			end
		elseif info.traits:find("E") then
			final_code = final_code:merge(entities["r0"].offset, shift)
		else
			final_code = nil
		end
	end
	if final_code and info.traits:find("T") then
		if named_ops[3] then
			if named_ops[3].type == "imm" then
				final_code = final_code:merge(named_ops[3].value, 0):merge(0x40000000, 0)
			else
				final_code = final_code:merge(named_ops[3].value, 0)
			end
		elseif info.traits:find("X") and info.traits:find("D") and named_ops[1] then
			final_code = final_code:merge(named_ops[1].value, 0)
		else
			final_code = nil
		end
	end
	if named_ops[4] then
		final_code = nil
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
for mnemonic in pairs(mnemonic_info) do
	mnemonics[mnemonic] = mnemonic_desc
end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local memory_rows_str, core_count_str = assert(model:match("^R3A(..)(..)$"))
	local memory_rows = tonumber(memory_rows_str)
	local core_count = tonumber(core_count_str)
	local space_available = memory_rows * 128
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	local row_size = 128
	local row_count = space_available / row_size
	for index = 0, space_available - 1 do
		local index_x = index % row_size
		local index_y = math.floor(index / row_size)
		local opcode = opcodes[index] and opcodes[index].dwords[1] or xbit32.bor(xbit32.band(xbit32.bxor(index_y, index_x), 0xFFFF), 0x00308000)
		sim.partProperty(sim.partID(x + index_x - 41, y + index_y - 13 - row_count - core_count * 6), "ctype", opcode)
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
