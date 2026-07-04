local printf = require("tptasm.printf")
local config = require("tptasm.config")
local opcode = require("tptasm.opcode")
local xbit32 = require("tptasm.xbit32")
local detect = require("tptasm.detect")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%define db `dw'
		%define org `org'

		%macro dh thing
			db { thing 0xFF & }, { thing 8 >> 0xFF & }
		%endmacro

		%macro dw thing
			db { thing 0xFF & }, { thing 8 >> 0xFF & }, { thing 16 >> 0xFF & }, { thing 24 >> 0xFF & }
		%endmacro

		%define zero x0
		%define ra   x1
		%define sp   x2
		%define gp   x3
		%define tp   x4
		%define t0   x5
		%define t1   x6
		%define t2   x7
		%define s0   x8
		%define fp   x8
		%define s1   x9
		%define a0   x10
		%define a1   x11
		%define a2   x12
		%define a3   x13
		%define a4   x14
		%define a5   x15
		%define a6   x16
		%define a7   x17
		%define s2   x18
		%define s3   x19
		%define s4   x20
		%define s5   x21
		%define s6   x22
		%define s7   x23
		%define s8   x24
		%define s9   x25
		%define s10  x26
		%define s11  x27
		%define t3   x28
		%define t4   x29
		%define t5   x30
		%define t6   x31

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 8

local nop = opcode.make(8)

local entities = {}
for i = 0, 31 do
	entities["x" .. i] = { type = "register", offset = i }
end

local mnemonics = {}

local mnemonic_info = {
	[ "lb"        ] = { traits = "I", code = 0x00000000 },
	[ "lh"        ] = { traits = "I", code = 0x00001000 },
	[ "lw"        ] = { traits = "I", code = 0x00002000 },
	[ "lbu"       ] = { traits = "I", code = 0x00004000 },
	[ "lhu"       ] = { traits = "I", code = 0x00005000 },
	[ "fence"     ] = { traits = "N", code = 0x00000004 },
	[ "fence_i"   ] = { traits = "N", code = 0x00001004 },
	[ "addi"      ] = { traits = "I", code = 0x00000010 },
	[ "add"       ] = { traits = "R", code = 0x00000030 },
	[ "sub"       ] = { traits = "R", code = 0x40000030 },
	[ "slli"      ] = { traits = "A", code = 0x00001010 },
	[ "srli"      ] = { traits = "A", code = 0x00005010 },
	[ "srai"      ] = { traits = "A", code = 0x40005010 },
	[ "sll"       ] = { traits = "R", code = 0x00001030 },
	[ "srl"       ] = { traits = "R", code = 0x00005030 },
	[ "sra"       ] = { traits = "R", code = 0x40005030 },
	[ "slti"      ] = { traits = "I", code = 0x00002010 },
	[ "sltiu"     ] = { traits = "I", code = 0x00003010 },
	[ "slt"       ] = { traits = "R", code = 0x00002030 },
	[ "sltu"      ] = { traits = "R", code = 0x00003030 },
	[ "xori"      ] = { traits = "I", code = 0x00004010 },
	[ "ori"       ] = { traits = "I", code = 0x00006010 },
	[ "andi"      ] = { traits = "I", code = 0x00007010 },
	[ "xor"       ] = { traits = "R", code = 0x00004030 },
	[ "or"        ] = { traits = "R", code = 0x00006030 },
	[ "and"       ] = { traits = "R", code = 0x00007030 },
	[ "auipc"     ] = { traits = "U", code = 0x00000014 },
	[ "lui"       ] = { traits = "U", code = 0x00000034 },
	[ "sb"        ] = { traits = "S", code = 0x00000020 },
	[ "sh"        ] = { traits = "S", code = 0x00001020 },
	[ "sw"        ] = { traits = "S", code = 0x00002020 },
	[ "mul"       ] = { traits = "R", code = 0x02000030 },
	[ "mulh"      ] = { traits = "R", code = 0x02001030 },
	[ "mulhsu"    ] = { traits = "R", code = 0x02002030 },
	[ "mulhu"     ] = { traits = "R", code = 0x02003030 },
	[ "czero_eqz" ] = { traits = "R", code = 0x06000030 },
	[ "czero_nez" ] = { traits = "R", code = 0x06002030 },
	[ "beq"       ] = { traits = "B", code = 0x00000040 },
	[ "bne"       ] = { traits = "B", code = 0x00001040 },
	[ "blt"       ] = { traits = "B", code = 0x00004040 },
	[ "bge"       ] = { traits = "B", code = 0x00005040 },
	[ "bltu"      ] = { traits = "B", code = 0x00006040 },
	[ "bgeu"      ] = { traits = "B", code = 0x00007040 },
	[ "jalr"      ] = { traits = "I", code = 0x00000044 },
	[ "jal"       ] = { traits = "J", code = 0x00000048 },
	[ "ecall"     ] = { traits = "N", code = 0x00000050 },
	[ "ebreak"    ] = { traits = "N", code = 0x00100050 },
}

local mnemonic_desc = {}
function mnemonic_desc.length()
	return true, 4 -- * RISC :)
end

function mnemonic_desc.emit(mnemonic_token, parameters)
	local operands = {}
	local mnemonic = mnemonic_token.value

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

	local info = mnemonic_info[mnemonic]
	local warnings_emitted = {}
	local named_ops = {}

	local function get_imm(operand, trunc_bits, clear_bits, signed)
		local trunc = xbit32.lshift(1, trunc_bits)
		local value = operand.value
		if signed and value < 0 and value >= -trunc / 2 then
			value = value + trunc
		end
		if value >= trunc or value < 0 then
			value = value % trunc
			operand.token:blamef(printf.warn, "number truncated to %i bits", trunc_bits)
		end
		if xbit32.band(value, clear_bits) ~= 0 then
			local mask = xbit32.bxor(0xFFFFFFFF, clear_bits)
			operand.token:blamef(printf.warn, "number masked with 0x%08X", mask)
			value = xbit32.band(value, mask)
		end
		return value
	end
	local function get_bits(imm, hi, lo)
		return xbit32.band(xbit32.rshift(imm, lo), xbit32.lshift(1, hi - lo + 1) - 1)
	end

	local final_code
	if info.traits == "N" and #operands == 0 then
		final_code = opcode.make(32):merge(info.code, 0)
	elseif info.traits == "J" and #operands == 2 and operands[1].type == "reg" and operands[2].type == "imm" then
		local rd = operands[1].value
		local s21 = get_imm(operands[2], 21, 0x00000001, true)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(rd, 7)
		                            :merge(get_bits(s21, 19, 12), 12)
		                            :merge(get_bits(s21, 11, 11), 20)
		                            :merge(get_bits(s21, 10,  1), 21)
		                            :merge(get_bits(s21, 20, 20), 31)
	elseif info.traits == "I" and #operands == 3 and operands[1].type == "reg" and operands[2].type == "reg" and operands[3].type == "imm" then
		local rd = operands[1].value
		local rs1 = operands[2].value
		local s12 = get_imm(operands[3], 12, 0x00000000, true)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(rd, 7)
		                            :merge(rs1, 15)
		                            :merge(s12, 20)
	elseif info.traits == "B" and #operands == 3 and operands[1].type == "reg" and operands[2].type == "reg" and operands[3].type == "imm" then
		local rs1 = operands[1].value
		local rs2 = operands[2].value
		local s13 = get_imm(operands[3], 13, 0x00000001, true)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(get_bits(s13, 11, 11), 7)
		                            :merge(get_bits(s13,  4,  1), 8)
		                            :merge(rs1, 15)
		                            :merge(rs2, 20)
		                            :merge(get_bits(s13, 10,  5), 25)
		                            :merge(get_bits(s13, 12, 12), 31)
	elseif info.traits == "R" and #operands == 3 and operands[1].type == "reg" and operands[2].type == "reg" and operands[3].type == "reg" then
		local rd = operands[1].value
		local rs1 = operands[2].value
		local rs2 = operands[3].value
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(rd, 7)
		                            :merge(rs1, 15)
		                            :merge(rs2, 20)
	elseif info.traits == "S" and #operands == 3 and operands[1].type == "reg" and operands[2].type == "reg" and operands[3].type == "imm" then
		local rs2 = operands[1].value
		local rs1 = operands[2].value
		local s12 = get_imm(operands[3], 12, 0x00000000, true)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(get_bits(s12,  4, 0), 7)
		                            :merge(rs1, 15)
		                            :merge(rs2, 20)
		                            :merge(get_bits(s12, 11, 5), 25)
	elseif info.traits == "U" and #operands == 2 and operands[1].type == "reg" and operands[2].type == "imm" then
		local rd = operands[1].value
		local u20 = get_imm(operands[2], 20, 0x00000000, false)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(rd, 7)
		                            :merge(u20, 12)
	elseif info.traits == "A" and #operands == 3 and operands[1].type == "reg" and operands[2].type == "reg" and operands[3].type == "imm" then
		local rd = operands[1].value
		local rs1 = operands[2].value
		local amt = get_imm(operands[3], 5, 0x00000000, false)
		final_code = opcode.make(32):merge(info.code, 0)
		                            :merge(rd, 7)
		                            :merge(rs1, 15)
		                            :merge(amt, 20)
	end

	if not final_code then
		local operands_repr = {}
		for _, ix_oper in ipairs(operands) do
			table.insert(operands_repr, ix_oper.type)
		end
		mnemonic_token:blamef(printf.err, "no variant of %s exists that takes '%s' operands", mnemonic, table.concat(operands_repr, ", "))
		return false
	end
	return true, {
		opcode.make(8):merge(xbit32.band(              final_code.dwords[1]     , 0xFF), 0),
		opcode.make(8):merge(xbit32.band(xbit32.rshift(final_code.dwords[1],  8), 0xFF), 0),
		opcode.make(8):merge(xbit32.band(xbit32.rshift(final_code.dwords[1], 16), 0xFF), 0),
		opcode.make(8):merge(xbit32.band(xbit32.rshift(final_code.dwords[1], 24), 0xFF), 0),
	}
end
for mnemonic in pairs(mnemonic_info) do
	mnemonics[mnemonic] = mnemonic_desc
end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local core_count_str, memory_rows_str = assert(model:match("^R4A(..)(..)M?$"))
	local memory_rows = tonumber(memory_rows_str)
	local core_count = tonumber(core_count_str)
	local space_available = memory_rows * 512
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i bytes, only have %i", #opcodes + 1, space_available)
		return
	end

	local row_size = 128
	for index = 0, space_available - 1, 4 do
		local index_x = index / 4 % row_size
		local index_y = math.floor(index / 4 / row_size)
		local data = opcode.make(32):merge(opcodes[index    ] and opcodes[index    ].dwords[1] or 0,  0)
		                            :merge(opcodes[index + 1] and opcodes[index + 1].dwords[1] or 0,  8)
		                            :merge(opcodes[index + 2] and opcodes[index + 2].dwords[1] or 0, 16)
		                            :merge(opcodes[index + 3] and opcodes[index + 3].dwords[1] or 0, 24)
		local i = sim.partID(x + (index_x % 64) * 2 + math.floor(index_x / 64) + 28, y - index_y - 18 - core_count * 16)
		local bray = xbit32.band(data.dwords[1], 1) ~= 0
		sim.partProperty(i, "type" , bray and elem.DEFAULT_PT_BRAY or elem.DEFAULT_PT_FILT)
		sim.partProperty(i, "life" , bray and     988 or 4)
		sim.partProperty(i, "tmp"  , bray and       1 or 0)
		sim.partProperty(i, "ctype", xbit32.bor(xbit32.band(data.dwords[1], 0xFFFFFFFE), 1))
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
