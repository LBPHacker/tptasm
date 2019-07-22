-- yet unreleased architecture by LBPHacker

local config = require("config")
local opcode = require("opcode")
local printf = require("printf")

local arch_r3 = {}

arch_r3.includes = {
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

arch_r3.dw_bits = 29

arch_r3.nop = opcode.make(32):merge(0x20000000, 0)

arch_r3.entities = {
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

arch_r3.mnemonics = {}

local mnemonic_to_class_code = require("architectures.r3.mnemonics")
local operand_modes = require("architectures.r3.operand_modes")

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
		local code = arch_r3.nop:clone():merge(code_raw, 0):merge(mnemonic_to_class_code[mnemonic_token.value].code, 0)
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
	arch_r3.mnemonics[mnemonic] = mnemonic_desc
end

function arch_r3.flash(model, target, opcodes)
	-- TODO: build R3
	for ix = 0, #opcodes do
		printf.info("OPCODE: %04X: %s", ix, opcodes[ix]:dump())
	end
end

return arch_r3
