local config = require("config")
local opcode = require("opcode")
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
		%define jnle jg
		%define jle jng
		%define jnl jge
		%define jl jnge
		%define jb jc
		%define jnb jnc
		%define test ands
		%define cmb sbbs
		%define cmp subs

		%macro nop
			jn r0
		%endmacro

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local dw_bits = 29

local nop = opcode.make(32):merge(0x20000000, 0)

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
entities["bp"] = entities["r13"]
entities["sp"] = entities["r14"]
entities["ip"] = entities["r15"]

local mnemonics = {}

local mnemonic_to_class_code = {
    [ "mov"  ] = { class = "AB", code = 0x20000000 },
    [ "and"  ] = { class = "AB", code = 0x21000000 },
    [ "or"   ] = { class = "AB", code = 0x22000000 },
    [ "xor"  ] = { class = "AB", code = 0x23000000 },
    [ "add"  ] = { class = "AB", code = 0x24000000 },
    [ "adc"  ] = { class = "AB", code = 0x25000000 },
    [ "sub"  ] = { class = "AB", code = 0x26000000 },
    [ "sbb"  ] = { class = "AB", code = 0x27000000 },
    [ "swm"  ] = { class = " B", code = 0x28000000 },
    [ "ands" ] = { class = "AB", code = 0x29000000 },
    [ "ors"  ] = { class = "AB", code = 0x2A000000 },
    [ "xors" ] = { class = "AB", code = 0x2B000000 },
    [ "adds" ] = { class = "AB", code = 0x2C000000 },
    [ "adcs" ] = { class = "AB", code = 0x2D000000 },
    [ "subs" ] = { class = "AB", code = 0x2E000000 },
    [ "sbbs" ] = { class = "AB", code = 0x2F000000 },
    [ "hlt"  ] = { class = "  ", code = 0x30000000 },
    [ "jmp"  ] = { class = " B", code = 0x31000000 },
    [ "jn"   ] = { class = " B", code = 0x31000001 },
    [ "jc"   ] = { class = " B", code = 0x31000002 },
    [ "jnc"  ] = { class = " B", code = 0x31000003 },
    [ "jo"   ] = { class = " B", code = 0x31000004 },
    [ "jno"  ] = { class = " B", code = 0x31000005 },
    [ "js"   ] = { class = " B", code = 0x31000006 },
    [ "jns"  ] = { class = " B", code = 0x31000007 },
    [ "jz"   ] = { class = " B", code = 0x31000008 },
    [ "jnz"  ] = { class = " B", code = 0x31000009 },
    [ "jng"  ] = { class = " B", code = 0x3100000A },
    [ "jg"   ] = { class = " B", code = 0x3100000B },
    [ "jnge" ] = { class = " B", code = 0x3100000C },
    [ "jge"  ] = { class = " B", code = 0x3100000D },
    [ "jbe"  ] = { class = " B", code = 0x3100000E },
    [ "jnbe" ] = { class = " B", code = 0x3100000F },
    [ "rol"  ] = { class = "AB", code = 0x32000000 },
    [ "ror"  ] = { class = "AB", code = 0x33000000 },
    [ "shl"  ] = { class = "AB", code = 0x34000000 },
    [ "shr"  ] = { class = "AB", code = 0x35000000 },
    [ "scl"  ] = { class = "AB", code = 0x36000000 },
    [ "scr"  ] = { class = "AB", code = 0x37000000 },
    [ "bump" ] = { class = "A ", code = 0x38000000 },
    [ "wait" ] = { class = "A ", code = 0x39000000 },
    [ "send" ] = { class = "AB", code = 0x3A000000 },
    [ "recv" ] = { class = "AB", code = 0x3B000000 },
    [ "push" ] = { class = " B", code = 0x3C000000 },
    [ "pop"  ] = { class = "A ", code = 0x3D000000 },
    [ "call" ] = { class = " B", code = 0x3E000000 },
    [ "ret"  ] = { class = "  ", code = 0x3F000000 },
}
local class_to_mode = {
    ["  "] = {
        { ops = {                               }, code = 0x00000000 },
    },
    ["A "] = {
        { ops = {  "reg@0"                      }, code = 0x00000000 },
        { ops = { "[reg@0]"                     }, code = 0x00400000 },
        { ops = { "[reg@16+reg@0]"              }, code = 0x00C00000 },
        { ops = { "[reg@16-reg@0]"              }, code = 0x00C08000 },
        { ops = { "[imm16@4]"                   }, code = 0x00500000 },
        { ops = { "[imm11@4+reg@16]"            }, code = 0x00D00000 },
        { ops = { "[reg@16+imm11@4]"            }, code = 0x00D00000 },
        { ops = { "[reg@16-imm11@4]"            }, code = 0x00D08000 },
    },
    [" B"] = {
        { ops = {  "reg@4"                      }, code = 0x00000000 },
        { ops = { "[reg@4]"                     }, code = 0x00100000 },
        { ops = { "[reg@16+reg@4]"              }, code = 0x00900000 },
        { ops = { "[reg@16-reg@4]"              }, code = 0x00908000 },
        { ops = {  "imm16@4"                    }, code = 0x00200000 },
        { ops = { "[imm16@4]"                   }, code = 0x00300000 },
        { ops = { "[imm11@4+reg@16]"            }, code = 0x00B00000 },
        { ops = { "[reg@16+imm11@4]"            }, code = 0x00B00000 },
        { ops = { "[reg@16-imm11@4]"            }, code = 0x00B08000 },
    },
    ["AB"] = {
        { ops = {  "reg@0" ,  "reg@4"           }, code = 0x00000000 },
        { ops = {  "reg@0" , "[reg@4]"          }, code = 0x00100000 },
        { ops = {  "reg@0" , "[reg@16+reg@4]"   }, code = 0x00900000 },
        { ops = {  "reg@0" , "[reg@16-reg@4]"   }, code = 0x00908000 },
        { ops = {  "reg@0" ,  "imm16@4"         }, code = 0x00200000 },
        { ops = {  "reg@0" , "[imm16@4]"        }, code = 0x00300000 },
        { ops = {  "reg@0" , "[imm11@4+reg@16]" }, code = 0x00B00000 },
        { ops = {  "reg@0" , "[reg@16+imm11@4]" }, code = 0x00B00000 },
        { ops = {  "reg@0" , "[reg@16-imm11@4]" }, code = 0x00B08000 },
        { ops = { "[reg@0]",            "reg@4" }, code = 0x00400000 },
        { ops = { "[reg@16+reg@0]",     "reg@4" }, code = 0x00C00000 },
        { ops = { "[reg@16-reg@0]",     "reg@4" }, code = 0x00C08000 },
        { ops = { "[imm16@4]",          "reg@0" }, code = 0x00500000 },
        { ops = { "[imm11@4+reg@16]",   "reg@0" }, code = 0x00D00000 },
        { ops = { "[reg@16+imm11@4]",   "reg@0" }, code = 0x00D00000 },
        { ops = { "[reg@16-imm11@4]",   "reg@0" }, code = 0x00D08000 },
        { ops = { "[reg@0]",          "imm16@4" }, code = 0x00600000 },
        { ops = { "[reg@16+reg@0]",   "imm11@4" }, code = 0x00E00000 },
        { ops = { "[reg@16-reg@0]",   "imm11@4" }, code = 0x00E08000 },
        { ops = { "[imm16@4]",         "imm4@0" }, code = 0x00700000 },
        { ops = { "[imm11@4+reg@16]",  "imm4@0" }, code = 0x00F00000 },
        { ops = { "[reg@16+imm11@4]",  "imm4@0" }, code = 0x00F00000 },
        { ops = { "[reg@16-imm11@4]",  "imm4@0" }, code = 0x00F08000 },
    },
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

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "[reg]",
				value = ix_param[2].entity.offset,
			})

		elseif #ix_param == 3
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:number()
		   and ix_param[3]:punctuator("]") then
			table.insert(operands, {
				type = "[imm]",
				value = ix_param[2].parsed,
				token = ix_param[2],
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("+")
		   and ix_param[4]:is("entity") and ix_param[4].entity.type == "register"
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg+reg]",
				base = ix_param[2].entity.offset,
				value = ix_param[4].entity.offset,
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("-")
		   and ix_param[4]:is("entity") and ix_param[4].entity.type == "register"
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg-reg]",
				base = ix_param[2].entity.offset,
				value = ix_param[4].entity.offset,
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:number()
		   and ix_param[3]:punctuator("+")
		   and ix_param[4]:is("entity") and ix_param[4].entity.type == "register"
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg+imm]",
				base = ix_param[4].entity.offset,
				value = ix_param[2].parsed,
				token = ix_param[2],
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("+")
		   and ix_param[4]:number()
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg+imm]",
				base = ix_param[2].entity.offset,
				value = ix_param[4].parsed,
				token = ix_param[4],
			})

		elseif #ix_param == 5
		   and ix_param[1]:punctuator("[")
		   and ix_param[2]:is("entity") and ix_param[2].entity.type == "register"
		   and ix_param[3]:punctuator("-")
		   and ix_param[4]:number()
		   and ix_param[5]:punctuator("]") then
			table.insert(operands, {
				type = "[reg-imm]",
				base = ix_param[2].entity.offset,
				value = ix_param[4].parsed,
				token = ix_param[4],
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
	if #class_code.class:gsub("[^AB]", "") == #operands then
		local modes = class_to_mode[class_code.class]
		for m = 1, #modes do
			local ops = modes[m].ops
			local ok = true
			for i = 1, #operands do
				if operands[i].type ~= ops[i]:gsub("[0-9@]", "") then
					ok = false
					break
				end
			end
			if ok then
				final_code = opcode.make(32):merge(class_code.code, 0):merge(modes[m].code, 0)
				for i = 1, #operands do
					local next_type = operands[i].type:gmatch("[a-z]+")
					local comp = 0
					for shift in ops[i]:gmatch("[0-9@]+") do
						comp = comp + 1
						local comp_type = next_type()
						local width = 4
						local value = operands[i].value
						if comp == 1 and operands[i].base then
							value = operands[i].base
						end
						if comp_type == "imm" then
							width, shift = shift:match("^([0-9]+)@([0-9]+)$")
							width = tonumber(width)
							shift = tonumber(shift)
						else
							shift = tonumber(shift:sub(2))
						end
						if value >= 2 ^ width then
							value = value % 2 ^ width
							operands[i].token:blamef(printf.warn, "number truncated to " .. width .. " bits")
						end
						final_code:merge(value, shift)
					end
				end
			end
		end
	end

	local hardware_bugs = false
	if mnemonic_token.value == "bump" and operands[1].type:find("^%[") then
		hardware_bugs = true
	end
	if mnemonic_token.value == "send" and operands[1].type:find("^%[") then
		hardware_bugs = true
	end
	if hardware_bugs then
		mnemonic_token:blamef(printf.err, "refusing to assemble due to hardware bugs, consult the manual")
		return false
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

local supported_models = {
	[ "R216K2A" ] = { ram_x = 70, ram_y =  -99, ram_width = 128, ram_height = 16 },
	[ "R216K4A" ] = { ram_x = 70, ram_y = -115, ram_width = 128, ram_height = 32 },
	[ "R216K8B" ] = { ram_x = 70, ram_y = -147, ram_width = 128, ram_height = 64 },
}
local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	local model_data = supported_models[model]
	local space_available = model_data.ram_width * model_data.ram_height
	if #opcodes >= space_available then
		printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
		return
	end

	for row = 0, model_data.ram_height - 1 do
		local skipped = 0
		for column = 0, model_data.ram_width - 1 do
			while true do
				local id = sim.partID(x + model_data.ram_x - column - skipped, y + row + model_data.ram_y)
				if id and sim.partProperty(id, "type") ~= elem.DEFAULT_PT_FILT then
					id = nil
				end
				if id then
					local index = row * model_data.ram_width + column
					local opcode = opcodes[index] and opcodes[index].dwords[1] or nop.dwords[1]
					sim.partProperty(id, "ctype", opcode)
					break
				end
				if skipped > 0 then
					printf.err("RAM layout sanity check failed")
					return
				end
				skipped = 1
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
