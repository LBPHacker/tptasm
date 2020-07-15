local config = require("config")
local opcode = require("opcode")

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_
		
		%define dw `dw'
		%define org `org'

		%define mem_fl 0x0708
		%define mem_pc 0x0709
		%define mem_li 0x070A
		%define mem_lo 0x070B
		%define mem_lc 0x070C
		%define mem_lf 0x070D
		%define mem_lt 0x070E
		%define mem_wm 0x070F
		%define mem_mc 0x0710

		%define t0 [sp-16]
		%define t1 [sp-15]
		%define t2 [sp-14]
		%define t3 [sp-13]
		%define t4 [sp-12]
		%define t5 [sp-11]
		%define t6 [sp-10]
		%define t7 [sp-9]
		%define t8 [sp-8]
		%define t9 [sp-7]
		%define t10 [sp-6]
		%define t11 [sp-5]
		%define t12 [sp-4]
		%define t13 [sp-3]
		%define t14 [sp-2]
		%define t15 [sp-1]
		%define s0 [sp+0]
		%define s1 [sp+1]
		%define s2 [sp+2]
		%define s3 [sp+3]
		%define s4 [sp+4]
		%define s5 [sp+5]
		%define s6 [sp+6]
		%define s7 [sp+7]
		%define s8 [sp+8]
		%define s9 [sp+9]
		%define s10 [sp+10]
		%define s11 [sp+11]
		%define s12 [sp+12]
		%define s13 [sp+13]
		%define s14 [sp+14]
		%define s15 [sp+15]

		%macro push Thing
			mov [--sp], Thing
		%endmacro

		%macro pop Thing
			mov Thing, [sp++]
		%endmacro

		%macro loop Reg, Count, Loop, Done
			mov Reg, 0x070C
			mov [Reg++], Count
			mov [Reg++], Done
			mov [Reg++], Loop
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 29

local nop = opcode.make(32):merge(0x20000000, 0)

local entities = {
	["r0"] = { type = "register", offset = 0 },
	["r1"] = { type = "register", offset = 1 },
	["r2"] = { type = "register", offset = 2 },
	["r3"] = { type = "register", offset = 3 },
	["r4"] = { type = "register", offset = 4 },
	["r5"] = { type = "register", offset = 5 },
	["r6"] = { type = "register", offset = 6 },
	["r7"] = { type = "register", offset = 7 },
	["sp"] = { type = "register", offset = 7 },
	["lo"] = { type = "last_output" },
}

local mnemonics = {}

local mnemonic_to_class_code = {
	[  "jn"] = { class =   "2", code = 0x20000000 },
	[ "jmp"] = { class =   "2", code = 0x20010000 },
	[ "ret"] = { class = "nop", code = 0x208100D7 },
	[ "jnb"] = { class =   "2", code = 0x20020000 },
	[ "jae"] = { class =   "2", code = 0x20020000 },
	[ "jnc"] = { class =   "2", code = 0x20020000 },
	[  "jb"] = { class =   "2", code = 0x20030000 },
	["jnae"] = { class =   "2", code = 0x20030000 },
	[  "jc"] = { class =   "2", code = 0x20030000 },
	[ "jno"] = { class =   "2", code = 0x20040000 },
	[  "jo"] = { class =   "2", code = 0x20050000 },
	[ "jne"] = { class =   "2", code = 0x20060000 },
	[ "jnz"] = { class =   "2", code = 0x20060000 },
	[  "je"] = { class =   "2", code = 0x20070000 },
	[  "jz"] = { class =   "2", code = 0x20070000 },
	[ "jns"] = { class =   "2", code = 0x20080000 },
	[  "js"] = { class =   "2", code = 0x20090000 },
	[ "jnl"] = { class =   "2", code = 0x200A0000 },
	[ "jge"] = { class =   "2", code = 0x200A0000 },
	[  "jl"] = { class =   "2", code = 0x200B0000 },
	["jnge"] = { class =   "2", code = 0x200B0000 },
	["jnbe"] = { class =   "2", code = 0x200C0000 },
	[  "ja"] = { class =   "2", code = 0x200C0000 },
	[ "jbe"] = { class =   "2", code = 0x200D0000 },
	[ "jna"] = { class =   "2", code = 0x200D0000 },
	["jnle"] = { class =   "2", code = 0x200E0000 },
	[  "jg"] = { class =   "2", code = 0x200E0000 },
	[ "jle"] = { class =   "2", code = 0x200F0000 },
	[ "jng"] = { class =   "2", code = 0x200F0000 },
	[ "hlt"] = { class = "nop", code = 0x21000000 },
	[ "nop"] = { class = "nop", code = 0x20000000 },
	[ "mov"] = { class =  "02", code = 0x22000000 },
	["call"] = { class =   "2", code = 0x231F0000 },
	[ "bsf"] = { class =  "02", code = 0x24000000 },
	[ "bsr"] = { class =  "02", code = 0x25000000 },
	[ "zsf"] = { class =  "02", code = 0x26000000 },
	[ "zsr"] = { class =  "02", code = 0x27000000 },
	["maks"] = { class =  "12", code = 0x28000000 },
	["exts"] = { class =  "12", code = 0x29000000 },
	["scls"] = { class =  "12", code = 0x2A000000 },
	["scrs"] = { class =  "12", code = 0x2B000000 },
	[ "cmp"] = { class =  "12", code = 0x2C000000 },
	["cmpc"] = { class =  "12", code = 0x2D000000 },
	["test"] = { class =  "12", code = 0x2E000000 },
	["op0f"] = { class = "nop", code = 0x2F000000 },
	["mak1"] = { class = "012", code = 0x30000000 },
	["ext1"] = { class = "012", code = 0x31000000 },
	[ "rol"] = { class = "012", code = 0x32000000 },
	[ "ror"] = { class = "012", code = 0x33000000 },
	[ "add"] = { class = "012", code = 0x34000000 },
	[ "adc"] = { class = "012", code = 0x35000000 },
	[ "xor"] = { class = "012", code = 0x36000000 },
	[  "or"] = { class = "012", code = 0x37000000 },
	[ "mak"] = { class = "012", code = 0x38000000 },
	[ "ext"] = { class = "012", code = 0x39000000 },
	[ "scl"] = { class = "012", code = 0x3A000000 },
	[ "scr"] = { class = "012", code = 0x3B000000 },
	[ "sub"] = { class = "012", code = 0x3C000000 },
	[ "sbb"] = { class = "012", code = 0x3D000000 },
	[ "and"] = { class = "012", code = 0x3E000000 },
	[ "pml"] = { class = "012", code = 0x3F000000 },
}
local operand_modes = {
	{ "nop", {                                                                     }, false, false, 0x00000000 },
	{   "2", { {  "creg",      0 }                                                 }, false, false, 0x00800000 },
	{   "2", { { "[imm]", 13,  0 }                                                 }, false, false, 0x00804000 },
	{   "2", { {   "imm", 16,  0 }                                                 }, false, false, 0x00C00000 },
	{  "02", { { "[imm]", 13,  0 }, {  "creg",        16 }                         }, false, false, 0x00006000 },
	{  "02", { {  "creg",     16 }, { "[imm]", 13,     0 }                         }, false, false, 0x00804000 },
	{  "02", { {  "creg",     16 }, {   "imm", 16,     0 }                         }, false, false, 0x00C00000 },
	{  "02", { {  "creg",     16 }, {  "creg",         0 }                         }, false, false, 0x00800000 },
	{ "012", { { "[imm]", 13,  0 }, {  "creg",        16 }                         }, false, false, 0x00006000 },
	{ "012", { {  "creg",     16 }, { "[imm]", 13,     0 }                         }, false, false, 0x00804000 },
	{ "012", { {  "creg",     16 }, {   "imm", 16,     0 }                         }, false, false, 0x00C00000 },
	{ "012", { {  "creg",     16,                      8 }, {  "creg",         0 } }, false, false, 0x00800000 },
	{ "012", { {  "creg",     16 }, {  "creg",         8 }, {  "creg",         0 } }, false, false, 0x00800000 },
	{ "012", { {  "creg",     16 }, {  "creg",        -1 }, {   "imm", 16,     0 } },  true, false, 0x00C00000 },
	{ "012", { {  "creg",     16 }, {  "creg",         8 }, { "immsx",  8, 0, 14 } }, false, false, 0x00808000 },
	{ "012", { {  "creg",     16 }, {   "imm", 16,     0 }, {  "creg",        -1 } }, false,  true, 0x00400000 },
	{ "012", { {  "creg",     16 }, { "immsx",  8, 0, 14 }, {  "creg",         8 } }, false, false, 0x00008000 },
	{ "012", { {  "creg",     16 }, {  "creg",        -1 }, { "[imm]", 13,     0 } },  true, false, 0x00804000 },
	{ "012", { {  "creg",     16 }, { "[imm]", 13,     0 }, {  "creg",        -1 } }, false,  true, 0x00004000 },
	{ "012", { { "[imm]", 13,  0 }, {  "creg",        16 }, { "[imm]", 13,    -1 } }, false,  true, 0x00806000 },
	{ "012", { { "[imm]", 13,  0 }, { "[imm]", 13,    -1 }, {  "creg",        16 } },  true, false, 0x00006000 },
	{  "12", { { "[imm]", 13,  0 }, {  "creg",        16 }                         }, false, false, 0x00006000 },
	{  "12", { {  "creg",     16 }, { "[imm]", 13,     0 }                         }, false, false, 0x00804000 },
	{  "12", { {  "creg",     16 }, {   "imm", 16,     0 }                         }, false, false, 0x00C00000 },
	{  "12", { {  "creg",      8 }, {  "creg",         0 }                         }, false, false, 0x00800000 },
}

local mnemonic_desc = {}
function mnemonic_desc.length()
	return true, 1 -- * RISC :)
end

function mnemonic_desc.emit(mnemonic_token, parameters)
	local operands = {}
	for ix, ix_param in ipairs(parameters) do
		if #ix_param == 1
		   and ix_param[1]:is("entity") and ix_param[1].entity.type == "last_output" then
			table.insert(operands, {
				type = "lo"
			})

		elseif #ix_param == 1
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

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register" and ix_param[2].entity.offset == 7
		   and ix_param[4]:number()
		   and (
		   		(ix_param[3]:punctuator("+") and ix_param[4].parsed <  16) or
		   		(ix_param[3]:punctuator("-") and ix_param[4].parsed <= 16)
		       )
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[sp+s5]",
				value = ix_param[3]:punctuator("-") and (0x20 - ix_param[4].parsed) or ix_param[4].parsed
			})

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register" and ix_param[2].entity.offset == 7
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "[sp+s5]",
				value = 0
			})

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "[reg]",
				value = ix_param[2].entity.offset
			})

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:number()
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "[imm]",
				value = ix_param[2].parsed,
				token = ix_param[2]
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("+")
		   and ix_param[4]:punctuator("+")
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg++]",
				value = ix_param[2].entity.offset
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:punctuator("-")
		   and ix_param[3]:punctuator("-")
		   and ix_param[4]:is("entity") and ix_param[4].entity.type == "register"
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[--reg]",
				value = ix_param[4].entity.offset
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
	local max_score = -math.huge
	local warnings_emitted
	for _, ix_operand_mode in ipairs(operand_modes) do
		local class, takes, check12, check13, code_raw = unpack(ix_operand_mode)
		local code = nop:clone():merge(code_raw, 0):merge(mnemonic_to_class_code[mnemonic_token.value].code, 0)
		local score = 0
		local warnings = {}
		local check123 = {}
		local viable = true
		if class ~= mnemonic_to_class_code[mnemonic_token.value].class then
			viable = false
		end
		if viable then
			if #takes ~= #operands then
				viable = false
			end
		end
		if viable then
			for ix, ix_takes in ipairs(takes) do
				if ix_takes[1] == "creg" and operands[ix].type == "reg" then
					local creg = operands[ix].value
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif ix_takes[1] == "creg" and operands[ix].type == "[reg]" then
					local creg = 0x08 + operands[ix].value
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif ix_takes[1] == "creg" and operands[ix].type == "[reg++]" then
					local creg = 0x10 + operands[ix].value
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif ix_takes[1] == "creg" and operands[ix].type == "[--reg]" then
					local creg = 0x18 + operands[ix].value
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif ix_takes[1] == "creg" and operands[ix].type == "[sp+s5]" then
					local creg = 0x20 + operands[ix].value
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif ix_takes[1] == "creg" and operands[ix].type == "lo" then
					local creg = 0x0F
					if ix_takes[2] ~= -1 then
						code:merge(creg, ix_takes[2])
						if ix_takes[3] then
							code:merge(creg, ix_takes[3])
						end
					end
					table.insert(check123, ("creg %i"):format(creg))

				elseif (ix_takes[1] == "imm" and operands[ix].type == "imm") or
				       (ix_takes[1] == "[imm]" and operands[ix].type == "[imm]") then
					local imm = operands[ix].value
					local trunc = 2 ^ ix_takes[2]
					if imm >= trunc then
						imm = imm % trunc
						table.insert(warnings, { operands[ix].token, "number truncated to %i bits", ix_takes[2] })
						score = score - 1
					end
					if ix_takes[3] ~= -1 then
						code:merge(imm, ix_takes[3])
					end
					table.insert(check123, ("imm %i"):format(imm))

				elseif ix_takes[1] == "immsx" and operands[ix].type == "imm" then
					local imm = operands[ix].value
					local trunc = 2 ^ (ix_takes[2] + 1)
					if imm >= trunc then
						imm = imm % trunc
						table.insert(warnings, { operands[ix].token, "number truncated to %i bits", ix_takes[2] })
						score = score - 1
					end
					local sign = math.floor(imm / 2 ^ ix_takes[2])
					imm = imm % 2 ^ ix_takes[2]
					if ix_takes[3] ~= -1 then
						code:merge(imm, ix_takes[3])
						code:merge(sign, ix_takes[4])
					end
					table.insert(check123, ("immsx %i %i"):format(imm, sign))

				else
					viable = false

				end
			end
		end
		if viable and check12 and check123[1] ~= check123[2] then
			viable = false
		end
		if viable and check13 and check123[1] ~= check123[3] then
			viable = false
		end
		if viable and max_score < score then
			max_score = score
			warnings_emitted = warnings
			final_code = code
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
	for _, ix_warning in ipairs(warnings_emitted) do
		ix_warning[1]:blamef(printf.warn, unpack(ix_warning, 2))
	end
	return true, { final_code }
end
for mnemonic in pairs(mnemonic_to_class_code) do
	mnemonics[mnemonic] = mnemonic_desc
end

local function flash(model, target, opcodes)
	-- * TODO: build R3

	for ix = 0, #opcodes do
		printf.info("OPCODE: %04X: %s", ix, opcodes[ix]:dump())
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
