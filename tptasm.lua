#!/usr/bin/env lua

local MAX_INCLUDE_DEPTH = 100
local MAX_EXPANSION_DEPTH = 100
local MAX_EVAL_DEPTH = 100

local RESERVED = {
	DEFINED      = "_Defined",
	DW           = "_Dw",
	IDENTITY     = "_Identity",
	LABELCONTEXT = "_Labelcontext",
	MACROUNIQUE  = "_Macrounique",
	ORG          = "_Org",
	PEERLABEL    = "_Peerlabel",
	SUPERLABEL   = "_Superlabel",
	APPENDVARARG = "_Appendvararg",
	VARARG       = "_Vararg",
	VARARGSIZE   = "_Varargsize",
}

local tpt = tpt
local env_copy = {}
for key, value in pairs(_G) do
	env_copy[key] = value
end
setfenv(1, setmetatable(env_copy, { __index = function()
	error("__index")
end, __newindex = function()
	error("__newindex")
end }))

local function get_line(up)
	local _, err = pcall(error, "@", up + 2)
	return err:match("^(.-)%s*:%s*@$")
end

local printf
do
	printf = setmetatable({
		print = print,
		print_old = print,
		log_handle = false,
		colour = false,
		err_called = false,
		silent = false
	}, { __call = function(self, ...)
		if not printf.silent then
			printf.print(string.format(...))
		end
	end })
	function printf.debug(from, first, ...)
		local things = { tostring(first) }
		for ix_thing, thing in ipairs({ ... }) do
			table.insert(things, tostring(thing))
		end
		printf((printf.colour and "[tptasm] " or "[tptasm] [DD] ") .. "[%s] %s", from, table.concat(things, "\t"))
	end
	function printf.info(format, ...)
		printf((printf.colour and "\008t[tptasm]\008w " or "[tptasm] [II] ") .. format, ...)
	end
	function printf.warn(format, ...)
		printf((printf.colour and "\008o[tptasm]\008w " or "[tptasm] [WW] ") .. format, ...)
	end
	function printf.err(format, ...)
		printf((printf.colour and "\008l[tptasm]\008w " or "[tptasm] [EE] ") .. format, ...)
		printf.err_called = true
	end
	function printf.redirect(log_path)
		local handle = type(log_path) == "string" and io.open(log_path, "w") or log_path
		if handle then
			printf.log_path = log_path
			printf.log_handle = handle
			printf.info("redirecting log to '%s'", tostring(log_path))
			printf.print = function(str)
				printf.log_handle:write(str .. "\n")
			end
		else
			printf.warn("failed to open '%s' for writing, log not redirected", tostring(printf.log_path))
		end
	end
	function printf.unredirect()
		if printf.log_handle then
			if type(printf.log_path) == "string" then
				printf.log_handle:close()
			end
			printf.log_handle = false
			printf.print = printf.print_old
			printf.info("undoing redirection of log to '%s'", tostring(printf.log_path))
		end
	end
	function printf.update_colour()
		printf.colour = tpt and not printf.log_handle
	end
	printf.update_colour()
end
local function print(...)
	printf.debug(get_line(2), ...)
end

local function failf(...)
	printf.err(...)
	error(failf)
end

local args = { ... }
xpcall(function()

	local bit32_lshift
	local bit32_rshift
	local bit32_xor
	local bit32_sub
	local bit32_add
	local bit32_div
	local bit32_mod
	local bit32_mul
	local bit32_and
	local bit32_or
	local bit32_xor
	do
		function bit32_lshift(a, b)
			if b >= 32 then
				return 0
			end
			return bit32_mul(a, 2 ^ b)
		end
		function bit32_rshift(a, b)
			if b >= 32 then
				return 0
			end
			return bit32_div(a, 2 ^ b)
		end
		function bit32_sub(a, b)
			local s = a - b
			if s < 0 then
				s = s + 0x100000000
			end
			return s
		end
		function bit32_add(a, b)
			local s = a + b
			if s >= 0x100000000 then
				s = s - 0x100000000
			end
			return s
		end
		local function divmod(a, b)
			local quo = math.floor(a / b)
			return quo, a - quo * b
		end
		function bit32_div(a, b)
			local quo, rem = divmod(a, b)
			return quo
		end
		function bit32_mod(a, b)
			local quo, rem = divmod(a, b)
			return rem
		end
		function bit32_mul(a, b)
			local ll = bit32_and(a, 0xFFFF) * bit32_and(b, 0xFFFF)
			local lh = bit32_and(bit32_and(a, 0xFFFF) * math.floor(b / 0x10000), 0xFFFF)
			local hl = bit32_and(math.floor(a / 0x10000) * bit32_and(b, 0xFFFF), 0xFFFF)
			return bit32_add(bit32_add(ll, lh * 0x10000), hl * 0x10000)
		end
		local function hasbit(a, b)
			return a % (b + b) >= b
		end
		function bit32_and(a, b)
			local curr = 1
			local out = 0
			for ix = 0, 31 do
				if hasbit(a, curr) and hasbit(b, curr) then
					out = out + curr
				end
				curr = curr * 2
			end
			return out
		end
		function bit32_or(a, b)
			local curr = 1
			local out = 0
			for ix = 0, 31 do
				if hasbit(a, curr) or hasbit(b, curr) then
					out = out + curr
				end
				curr = curr * 2
			end
			return out
		end
		function bit32_xor(a, b)
			local curr = 1
			local out = 0
			for ix = 0, 31 do
				if hasbit(a, curr) ~= hasbit(b, curr) then
					out = out + curr
				end
				curr = curr * 2
			end
			return out
		end
	end

	local make_opcode
	do
		local opcode_i = {}
		local opcode_mt = { __index = opcode_i }
		function opcode_i:clone()
			local dwords = {}
			for ix, ix_dword in ipairs(self.dwords) do
				dwords[ix] = ix_dword
			end
			return setmetatable({
				dwords = dwords
			}, opcode_mt)
		end
		function opcode_i:dump()
			return ("%08X "):rep(#self.dwords):format(unpack(self.dwords))
		end
		function opcode_i:has(shift)
			return math.floor(self.dwords[math.floor(shift / 32) + 1] / 2 ^ (shift % 32)) % 2 == 1
		end
		function opcode_i:merge(thing, shift)
			if type(thing) == "table" then
				for ix, ix_dword in ipairs(thing.dwords) do
					self:merge(ix_dword, (ix - 1) * 32 + shift)
				end
			else
				local offs = 1
				while shift >= 32 do
					offs = offs + 1
					shift = shift - 32
				end
				self.dwords[offs] = bit32_or(self.dwords[offs], thing % 2 ^ (32 - shift) * 2 ^ shift)
				thing = math.floor(thing / 2 ^ (32 - shift))
				for ix = offs + 1, #self.dwords do
					if thing == 0 then
						break
					end
					self.dwords[ix] = bit32_or(self.dwords[ix], thing % 0x100000000)
					thing = math.floor(thing / 0x100000000)
				end
			end
			return self
		end
		function make_opcode(size)
			local dwords = {}
			for ix = 1, math.ceil(size / 32) do
				dwords[ix] = 0
			end
			return setmetatable({
				dwords = dwords
			}, opcode_mt)
		end
	end

	local find_cpu
	local detect_model
	do
		local function enumerate_standard(id)
			if  sim.partProperty(id, "ctype") == 0x1864A205
			and sim.partProperty(id, "type") == elem.DEFAULT_PT_QRTZ then
				local x, y = sim.partPosition(id)
				local function ctype_of(offs)
					local cid = sim.partID(x + offs, y)
					return cid and sim.partProperty(cid, "ctype")
				end
				local id_target = ctype_of(-1)
				if id_target then
					local offs = 0
					local id_model = ""
					local checksum = 0
					local name_intact = true
					while true do
						offs = offs + 1
						local ctype = ctype_of(offs)
						if not ctype then
							name_intact = false
							break
						end
						if ctype == 0 then
							break
						end
						id_model = id_model .. string.char(ctype)
						checksum = checksum + ctype
					end
					if name_intact and ctype_of(offs + 1) == checksum then
						coroutine.yield(x, y, id_model, id_target)
						return true
					end
				end
			end
			return false
		end

		local enumerate_legacy
		do
			local function match_property(id, name, value)
				return not value or sim.partProperty(id, name) == value
			end

			function enumerate_legacy(model, conditions)
				return function(id)
					if  match_property(id, "type", conditions[1][3])
					and match_property(id, "ctype", conditions[1][4]) then
						local x, y = sim.partPosition(id)
						local ok = true
						for ix = 2, #conditions do
							local cid = sim.partID(x + conditions[ix][1], y + conditions[ix][2])
							if not cid
							or not match_property(cid, "type", conditions[ix][3])
							or not match_property(cid, "ctype", conditions[ix][4]) then
								ok = false
							end
						end
						if ok then
							coroutine.yield(x, y, model, 0)
							return true
						end
					end
					return false
				end
			end
		end

		local enumerate_micro21
		if tpt then
			enumerate_micro21 = enumerate_legacy("MICRO21", {
				{  nil, nil, elem.DEFAULT_PT_DTEC, elem.DEFAULT_PT_DSTW },
				{ -181, 292, elem.DEFAULT_PT_DMND,                false },
				{  336, 201, elem.DEFAULT_PT_DMND,                false },
				{  394,  23, elem.DEFAULT_PT_BTRY,                false },
				{  384,  85, elem.DEFAULT_PT_BTRY,                false },
				{  -13, 177, elem.DEFAULT_PT_BTRY,                false },
				{ -179, 306, elem.DEFAULT_PT_PTCT,                false },
				{ -175, 306, elem.DEFAULT_PT_PTCT,                false },
				{ -178, 309, elem.DEFAULT_PT_PTCT,                false },
				{ -174, 309, elem.DEFAULT_PT_PTCT,                false },
			})
		end

		local function enumerate_cpus()
			if not tpt then
				printf.err("not running inside TPT, can't find target")
				return
			end
			for id in sim.parts() do
				local _ = enumerate_standard(id)
				       or enumerate_micro21(id)
			end
		end

		local function cpus()
			local co = coroutine.create(enumerate_cpus)
			return function()
				if coroutine.status(co) ~= "dead" then
					local ok, x, y, id_model, id_target = coroutine.resume(co)
					if not ok then
						error(x)
					end
					return x, y, id_model, id_target
				end
			end
		end

		function find_cpu(model, target)
			for x, y, id_model, id_target in cpus() do
				if (not target or target == id_target)
				or (not model or model == id_model) then
					return x, y
				end
			end
		end

		function detect_model(target)
			for x, y, id_model, id_target in cpus() do
				if not target or target == id_target then
					return id_model
				end
			end
		end
	end

	local architectures = {}
	do
		local arch_r3 = {}
		arch_r3.includes = {
			["common"] = ([==[
				%ifndef _COMMON_INCLUDED_
				%define _COMMON_INCLUDED_
				
				%define dw `DW'
				%define org `ORG'

				%define fl 0x0708
				%define pc 0x0709
				%define _loopcontrolbase 0x070C
				%eval lc _loopcontrolbase 0 +
				%eval lf _loopcontrolbase 1 +
				%eval lt _loopcontrolbase 2 +
				%define wm 0x070F

				%macro push Thing
					mov [--sp], Thing
				%endmacro

				%macro pop Thing
					mov Thing, [sp++]
				%endmacro

				%endif ; _COMMON_INCLUDED_
			]==]):gsub("`([A-Z]+)'", function(cap)
				return RESERVED[cap]
			end)
			--[[
				%macro _loop_internal Reg, Count, Done, Loop
					mov Reg, _loopcontrolbase
					mov [Reg++], Count
					mov [Reg++], Done
					mov [Reg++], Loop
				%endmacro

				%macro loop Count, Done, Reg
				`PEERLABEL' . `MACROUNIQUE' begin:
					_loop_internal Reg, Count, Done, `PEERLABEL' `MACROUNIQUE' loop_until
				`PEERLABEL' `MACROUNIQUE' loop_until:
				`SUPERLABEL' `LABELCONTEXT':
				%endmacro
			--]] -- LOOPCONTROL
		}

		arch_r3.dw_bits = 29
		arch_r3.nop = make_opcode(32):merge(0x20000000, 0)
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
		do
			local mnemonic_to_class_code = {
				[ "nop"] = { class = "nop", code = 0x20000000 },
				[ "mov"] = { class =  "02", code = 0x20000000 },
				["call"] = { class =   "2", code = 0x211F0000 },
				[  "jn"] = { class =   "2", code = 0x22000000 },
				[ "jmp"] = { class =   "2", code = 0x22010000 },
				[ "ret"] = { class = "nop", code = 0x228100D7 },
				[ "jnb"] = { class =   "2", code = 0x22020000 },
				[ "jae"] = { class =   "2", code = 0x22020000 },
				[ "jnc"] = { class =   "2", code = 0x22020000 },
				[  "jb"] = { class =   "2", code = 0x22030000 },
				["jnae"] = { class =   "2", code = 0x22030000 },
				[  "jc"] = { class =   "2", code = 0x22030000 },
				[ "jno"] = { class =   "2", code = 0x22040000 },
				[  "jo"] = { class =   "2", code = 0x22050000 },
				[ "jne"] = { class =   "2", code = 0x22060000 },
				[ "jnz"] = { class =   "2", code = 0x22060000 },
				[  "je"] = { class =   "2", code = 0x22070000 },
				[  "jz"] = { class =   "2", code = 0x22070000 },
				[ "jns"] = { class =   "2", code = 0x22080000 },
				[  "js"] = { class =   "2", code = 0x22090000 },
				[ "jnl"] = { class =   "2", code = 0x220A0000 },
				[ "jge"] = { class =   "2", code = 0x220A0000 },
				[  "jl"] = { class =   "2", code = 0x220B0000 },
				["jnge"] = { class =   "2", code = 0x220B0000 },
				["jnbe"] = { class =   "2", code = 0x220C0000 },
				[  "ja"] = { class =   "2", code = 0x220C0000 },
				[ "jbe"] = { class =   "2", code = 0x220D0000 },
				[ "jna"] = { class =   "2", code = 0x220D0000 },
				["jnle"] = { class =   "2", code = 0x220E0000 },
				[  "jg"] = { class =   "2", code = 0x220E0000 },
				[ "jle"] = { class =   "2", code = 0x220F0000 },
				[ "jng"] = { class =   "2", code = 0x220F0000 },
				[ "hlt"] = { class = "nop", code = 0x23000000 },
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
				["tstn"] = { class =  "12", code = 0x2F000000 },
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
				["andn"] = { class = "012", code = 0x3F000000 },
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

				local opcode
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
						opcode = code
					end
				end

				if not opcode then
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
				return true, { opcode }
			end
			for mnemonic in pairs(mnemonic_to_class_code) do
				arch_r3.mnemonics[mnemonic] = mnemonic_desc
			end
		end
		function arch_r3.flash(model, target, opcodes)
			-- TODO: build R3
			for ix = 0, #opcodes do
				printf.info("OPCODE: %04X: %s", ix, opcodes[ix]:dump())
			end
		end
		architectures["R3"] = arch_r3
	end
	do
		local arch_b29k1qs60 = {}
		arch_b29k1qs60.includes = {
			["common"] = ([==[
				%ifndef _COMMON_INCLUDED_
				%define _COMMON_INCLUDED_
				
				%endif ; _COMMON_INCLUDED_
			]==]):gsub("`([A-Z]+)'", function(cap)
				return RESERVED[cap]
			end)
		}
		arch_b29k1qs60.dw_bits = 29 -- * TODO: figure out how dw even works here
		arch_b29k1qs60.nop = make_opcode(192)
			:merge(0x20000000,   0)
			:merge(0x20000000,  32)
			:merge(0x20000000,  64)
			:merge(0x20000000,  96)
			:merge(0x20000000, 128)
			:merge(0x20000000, 160)
		arch_b29k1qs60.entities = {}
		local jmem_mnemonics = {
			["mvaz"] = { code = 0x20000000, jump = false, mask = false },
			["mvjz"] = { code = 0x20000001, jump =  true, mask = false },
			["ldaz"] = { code = 0x20000002, jump = false, mask =  true },
			["ldjz"] = { code = 0x20000003, jump =  true, mask =  true },
			["staz"] = { code = 0x20000004, jump = false, mask = false },
			["stjz"] = { code = 0x20000005, jump =  true, mask = false },
			["exaz"] = { code = 0x20000006, jump = false, mask = false },
			["exjz"] = { code = 0x20000007, jump =  true, mask = false },
		}
		local mnemonic_desc = {}
		function mnemonic_desc.length()
			return true, 1 -- * RISC :)
		end
		function mnemonic_desc.emit(mnemonic_token, parameters)
			local parameter_ix = 0
			local function take_parameter(role)
				parameter_ix = parameter_ix + 1
				if not parameters[parameter_ix] then
					mnemonic_token:blamef(printf.err, "%s not specified", role)
					return false
				end
				local parameter = parameters[parameter_ix]
				if #parameter < 1 then
					parameter.before:blamef(printf.err, "no tokens in %s", role)
					return false
				end
				if #parameter > 1 then
					parameter[2]:blamef(printf.err, "excess tokens in %s", role)
					return false
				end
				if not parameter[1]:number() then
					parameter[1]:blamef(printf.err, "%s is not a number", role)
					return false
				end
				return parameter[1].parsed
			end

			local opcode = arch_b29k1qs60.nop:clone()
			local instr_desc = jmem_mnemonics[mnemonic_token.value]
			opcode:merge(instr_desc.code, 128)
			do
				local set = take_parameter("bits to set")
				if not set then
					return false
				end
				opcode:merge(set, 0)
			end
			do
				local reset = take_parameter("bits to reset")
				if not reset then
					return false
				end
				opcode:merge(reset, 32)
			end
			if instr_desc.jump then
				do
					local condition = take_parameter("jump condition")
					if not condition then
						return false
					end
					opcode:merge(condition, 64)
				end
				do
					local target = take_parameter("jump target")
					if not target then
						return false
					end
					opcode:merge(target, 96)
				end
			end
			if instr_desc.mask and not instr_desc.jump then
				do
					local mask = take_parameter("read mask")
					if not mask then
						return false
					end
					opcode:merge(mask, 64)
				end
			end
			return true, { opcode }
		end
		arch_b29k1qs60.mnemonics = {}
		for key in pairs(jmem_mnemonics) do
			arch_b29k1qs60.mnemonics[key] = mnemonic_desc
		end
		function arch_b29k1qs60.flash(model, target, opcodes)
			local x, y = find_cpu(model, target)
			if not x then
				return
			end
			local space_available = 0x100
			if #opcodes >= space_available then
				printf.err("out of space; code takes %i cells, only have %i", #opcodes + 1, space_available)
				return
			end
			for ix = 0, #opcodes do
				for iy = 1, 6 do
					sim.partProperty(sim.partID(x + ix, y + iy + 3), "ctype", opcodes[ix].dwords[iy])
				end
			end
		end
		architectures["B29K1QS60"] = arch_b29k1qs60
	end
	do
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

				%define dw `DW'
				%define org `ORG'

				%macro ifz reg
					ifn reg, 0xFF
				%endmacro

				%macro ifnz reg
					if reg, 0xFF
				%endmacro
			]==] .. macros_str .. [==[

				%endif ; _COMMON_INCLUDED_
			]==]):gsub("`([A-Z]+)'", function(cap)
				return RESERVED[cap]
			end)
		}

		arch_micro21.dw_bits = 17
		arch_micro21.nop = make_opcode(17)
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

				local opcode = make_opcode(17):merge(desc.code, 0)
				local function bind_operand(slot, operand)
					if operand.type == "imm" then
						local truncated = operand.value % 0x100
						local value = operand.value
						if value >= 0x100 then
							value = value % 0x100
							operands[ix].token:blamef(printf.warn, "number truncated to 8 bits")
						end
						opcode:merge(value, 0)
					elseif operand.type == "reg" then
						opcode:merge(operand.value, 12 - slot * 2)
					end
				end
				for ix, ix_op in ipairs(operands) do
					bind_operand(ix, ix_op)
				end
				return true, { opcode }
			end
			for mnemonic in pairs(mnemonic_to_class_code) do
				arch_micro21.mnemonics[mnemonic] = mnemonic_desc
			end
		end
		function arch_micro21.flash(model, target, opcodes)
			local x, y = find_cpu(model, target)
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
				local opcode = opcodes[iy] and opcodes[iy].dwords[1] or 0
				for ix = 0, 16 do
					local px, py = x - ix + 354, y + iy + 73
					local old_id = sim.partID(px, py)
					if old_id then
						sim.partKill(old_id)
					end
					if bit32_and(opcode, 2 ^ ix) ~= 0 then
						local new_id = sim.partCreate(-2, px, py, elem.DEFAULT_PT_ARAY)
						local colour_code = colour_codes[ix]
						if opcode == 0x1FFFF or opcode == 0x00FFF then
							colour_code = 0xFF00FFFF
						end
						if bit32_and(opcode, 0x1F000) == 0x01000 and ix < 8 then
							colour_code = 0xFF00FFFF
						end
						sim.partProperty(new_id, "dcolour", colour_code)
					end
				end
			end
		end
		architectures["MICRO21"] = arch_micro21
	end

	
	local named_args = {}
	local unnamed_args = {}
	if #args == 1 and type(args[1]) == "table" then
		for _, arg in ipairs(args[1]) do
			table.insert(unnamed_args, arg)
		end
		for key, arg in pairs(args[1]) do
			if type(key) ~= "number" then
				named_args[key] = arg
			end
		end
	else
		for ix_arg, arg in ipairs(args) do
			local key_value = type(arg) == "string" and { arg:match("^([^=]+)=(.+)$") }
			if key_value and key_value[1] then
				if named_args[key_value[1]] then
					printf.warn("argument #%i overrides earlier specification of %s", ix_arg, key_value[1])
				end
				named_args[key_value[1]] = key_value[2]
			else
				table.insert(unnamed_args, arg)
			end
		end
	end

	if named_args.silent then
		printf.silent = true
	end

	local log_path = named_args.log or unnamed_args[3]
	if log_path then
		printf.redirect(log_path)
	end

	local model_name = named_args.model or unnamed_args[4]
	if not model_name then
		model_name = detect_model()
	end
	if not model_name then
		failf("failed to detect model and no model name was passed")
	end
	local model_to_architecture = {
		["R3"] = "R3",
		["B29K1QS60"] = "B29K1QS60",
		["MICRO21"] = "MICRO21",
	}
	local architecture_name = model_to_architecture[model_name] or failf("no architecture description for model '%s'", model_name)
	local architecture = architectures[architecture_name]

	local function resolve_relative(base_with_file, relative)
		local components = {}
		local parent_depth = 0
		-- * TODO: support more prefixes (i.e. C:, eww)
		local prefix, concatenated_path = (base_with_file .. "/../" .. relative):match("^(/?)(.+)$")
		for component in concatenated_path:gmatch("[^/]+") do
			if component == ".." then
				if #components > 0 then
					components[#components] = nil
				else
					parent_depth = parent_depth + 1
				end
			elseif component ~= "." then
				table.insert(components, component)
			end
		end
		for _ = 1, parent_depth do
			table.insert(components, 1, "..")
		end
		return prefix .. table.concat(components, "/")
	end

	local function parse_parameter_list(before, expanded, first, last)
		local parameters = {}
		local parameter_buffer = {}
		local parameter_cursor = 0
		local last_comma = before
		local function flush_parameter()
			parameters[parameter_cursor] = parameter_buffer
			parameters[parameter_cursor].before = last_comma
			parameter_buffer = {}
		end
		if first <= last then
			parameter_cursor = 1
			for ix = first, last do
				if expanded[ix]:punctuator(",") then
					flush_parameter()
					last_comma = expanded[ix]
					parameter_cursor = parameter_cursor + 1
				else
					table.insert(parameter_buffer, expanded[ix])
				end
			end
			flush_parameter()
		end
		return parameters
	end

	local tokenise
	do
		local token_i = {}
		local token_mt = { __index = token_i }
		function token_i:is(type, value)
			return self.type == type and (not value or self.value == value)
		end
		function token_i:punctuator(...)
			return self:is("punctuator", ...)
		end
		function token_i:identifier(...)
			return self:is("identifier", ...)
		end
		function token_i:stringlit(...)
			return self:is("stringlit", ...)
		end
		function token_i:charlit(...)
			return self:is("charlit", ...)
		end
		function token_i:number()
			return self:is("number")
		end
		local function parse_number_base(str, base)
			local out = 0
			for ix, ch in str:gmatch("()(.)") do
				local pos = base:find(ch)
				if not pos then
					return false, ("invalid digit at position %i"):format(ix)
				end
				out = out * #base + (pos - 1)
				if out >= 0x100000000 then
					return false, "unsigned 32-bit overflow"
				end
			end
			return true, out
		end
		function token_i:parse_number()
			local str = self.value
			if str:match("^0[Xx][0-9A-Fa-f]+$") then
				return parse_number_base(str:sub(3):lower(), "0123456789abcdef")
			elseif str:match("^[0-9A-Fa-f]+[Hh]$") then
				return parse_number_base(str:sub(1, -2), "0123456789abcdef")
			elseif str:match("^0[Bb][0-1]+$") then
				return parse_number_base(str:sub(3), "01")
			elseif str:match("^0[Oo][0-7]+$") then
				return parse_number_base(str:sub(3), "01234567")
			elseif str:match("^[0-9]+$") then
				return parse_number_base(str, "0123456789")
			end
			return false, "notation not recognised"
		end
		function token_i:point(other)
			other.sline = self.sline
			other.soffs = self.soffs
			other.expanded_from = self.expanded_from
			return setmetatable(other, token_mt)
		end
		function token_i:blamef_after(report, format, ...)
			self.sline:blamef_after(report, self, format, ...)
		end
		function token_i:blamef(report, format, ...)
			report("%s:%i:%i: " .. format, self.sline.path, self.sline.line, self.soffs, ...)
			self.sline:dump_itop()
			if self.expanded_from then
				self.expanded_from:blamef(printf.info, "expanded from this")
			end
		end
		function token_i:expand_by(other)
			local clone = setmetatable({}, token_mt)
			for key, value in pairs(self) do
				clone[key] = value
			end
			clone.expanded_from = other
			return clone
		end

		local transition = {}
		local all_8bit = ""
		for ix = 0, 255 do
			all_8bit = all_8bit .. string.char(ix)
		end
		local function transitions(transition_list)
			local tbl = {}
			local function add_transition(cond, action)
				if type(cond) == "string" then
					for ch in all_8bit:gmatch(cond) do
						tbl[ch:byte()] = action
					end
				else
					tbl[cond] = action
				end
			end
			for _, ix_trans in ipairs(transition_list) do
				add_transition(ix_trans[1], ix_trans[2])
			end
			return tbl
		end

		transition.push = transitions({
			{         "'", { consume =  true, state = "charlit"    }},
			{        "\"", { consume =  true, state = "stringlit"  }},
			{     "[;\n]", { consume = false, state = "done"       }},
			{     "[0-9]", { consume =  true, state = "number"     }},
			{ "[_A-Za-z]", { consume =  true, state = "identifier" }},
			{ "[%[%]%(%)%+%-%*/%%:%?&#<>=!^~%.{}\\|@$,`]", { consume = false, state = "punctuator" }},
		})
		transition.identifier = transitions({
			{ "[_A-Za-z0-9]", { consume =  true, state = "identifier" }},
			{          false, { consume = false, state = "push"       }},
		})
		transition.number = transitions({
			{ "[_A-Za-z0-9]", { consume =  true, state = "number" }},
			{          false, { consume = false, state = "push"   }},
		})
		transition.charlit = transitions({
			{  "'", { consume = true, state = "push"         }},
			{ "\n", { error = "unfinished character literal" }},
		})
		transition.stringlit = transitions({
			{ "\"", { consume = true, state = "push"      }},
			{ "\n", { error = "unfinished string literal" }},
		})
		transition.punctuator = transitions({
			{ ".", { consume = true, state = "push" }},
		})

		local whitespace = {
			["\f"] = true,
			["\n"] = true,
			["\r"] = true,
			["\t"] = true,
			["\v"] = true,
			[" "] = true
		}

		function tokenise(sline)
			local line = sline.str .. "\n"
			local tokens = {}
			local state = "push"
			local token_begin
			local cursor = 1
			while cursor <= #line do
				local ch = line:byte(cursor)
				if state == "push" and whitespace[ch] and #tokens > 0 then
					tokens[#tokens].whitespace_follows = true
				end
				local old_state = state
				local transition_info = transition[state][ch] or transition[state][false]
				local consume = true
				if transition_info then
					if transition_info.error then
						return false, cursor, transition_info.error
					end
					state = transition_info.state
					consume = transition_info.consume
				end
				if consume then
					cursor = cursor + 1
				end
				if state == "done" then
					break
				end
				if old_state == "push" and state ~= "push" then
					token_begin = cursor
					if consume then
						token_begin = token_begin - 1
					end
				end
				if old_state ~= "push" and state == "push" then
					local token_end = cursor - 1
					table.insert(tokens, setmetatable({
						type = old_state,
						value = line:sub(token_begin, token_end),
						sline = sline,
						soffs = token_begin
					}, token_mt))
				end
			end
			if #tokens > 0 then
				tokens[#tokens].whitespace_follows = true
			end
			return true, tokens
		end
	end

	local evaluate
	do
		local operator_funcs = {
			[">="] = { params = { "number", "number" }, does = function(a, b) return (a >= b) and 1 or 0 end },
			["<="] = { params = { "number", "number" }, does = function(a, b) return (a <= b) and 1 or 0 end },
			[">" ] = { params = { "number", "number" }, does = function(a, b) return (a >  b) and 1 or 0 end },
			["<" ] = { params = { "number", "number" }, does = function(a, b) return (a <  b) and 1 or 0 end },
			["=="] = { params = { "number", "number" }, does = function(a, b) return (a == b) and 1 or 0 end },
			["~="] = { params = { "number", "number" }, does = function(a, b) return (a ~= b) and 1 or 0 end },
			["&&"] = { params = { "number", "number" }, does = function(a, b) return (a ~= 0 and b ~= 0) and 1 or 0 end },
			["||"] = { params = { "number", "number" }, does = function(a, b) return (a ~= 0 or  b ~= 0) and 1 or 0 end },
			["!" ] = { params = { "number"           }, does = function(a) return (a == 0) and 1 or 0 end },
			["~" ] = { params = { "number"           }, does = function(a) return bit32_xor(a, 0xFFFFFFFF) end },
			["<<"] = { params = { "number", "number" }, does = bit32_lshift },
			[">>"] = { params = { "number", "number" }, does = bit32_rshift },
			["-" ] = { params = { "number", "number" }, does =    bit32_sub },
			["+" ] = { params = { "number", "number" }, does =    bit32_add },
			["/" ] = { params = { "number", "number" }, does =    bit32_div },
			["%" ] = { params = { "number", "number" }, does =    bit32_mod },
			["*" ] = { params = { "number", "number" }, does =    bit32_mul },
			["&" ] = { params = { "number", "number" }, does =    bit32_and },
			["|" ] = { params = { "number", "number" }, does =     bit32_or },
			["^" ] = { params = { "number", "number" }, does =    bit32_xor },
			[RESERVED.DEFINED] = { params = { "alias" }, does = function(a) return a and 1 or 0 end },
			[RESERVED.IDENTITY] = { params = { "number" }, does = function(a) return a end },
		}
		local operators = {}
		for key in pairs(operator_funcs) do
			table.insert(operators, key)
		end
		table.sort(operators, function(a, b)
			return #a > #b
		end)

		local function evaluate_composite(composite)
			if composite.type == "number" then
				return composite.value
			end
			return composite.operator.does(function(ix)
				return evaluate_composite(composite.operands[ix])
			end)
		end

		function evaluate(tokens, cursor, last, aliases)
			local stack = {}

			local function apply_operator(operator_name)
				local operator = operator_funcs[operator_name]
				if #stack < #operator.params then
					return false, cursor, ("operator takes %i operands, %i supplied"):format(#operator.params, #stack)
				end
				local max_depth = 0
				local operands = {}
				for ix = #stack - #operator.params + 1, #stack do
					if max_depth < stack[ix].depth then
						max_depth = stack[ix].depth
					end
					table.insert(operands, stack[ix])
					stack[ix] = nil
				end
				if max_depth > MAX_EVAL_DEPTH then
					return false, cursor, "maximum evaluation depth reached"
				end
				for ix = 1, #operands do
					if operator.params[ix] == "number" then
						if operands[ix].type == "number" then
							operands[ix] = operands[ix].value
						elseif operands[ix].type == "alias" then
							local alias = operands[ix].value
							if alias then
								local ok, number
								if #alias == 1 then
									ok, number = alias[1]:parse_number()
								end
								operands[ix] = ok and number or 1
							else
								operands[ix] = 0
							end
						else
							return false, operands[ix].position, ("operand %i is %s, should be number"):format(ix, operands[ix].type)
						end
					elseif operator.params[ix] == "alias" then
						if operands[ix].type == "alias" then
							operands[ix] = operands[ix].value
						else
							return false, operands[ix].position, ("operand %i is %s, should be alias"):format(ix, operands[ix].type)
						end
					end
				end
				table.insert(stack, {
					type = "number",
					value = operator.does(unpack(operands)),
					position = cursor,
					depth = max_depth + 1
				})
			end

			while cursor <= last do
				if tokens[cursor]:number() then
					local ok, number = tokens[cursor]:parse_number()
					if not ok then
						return false, cursor, ("invalid number: %s"):format(number)
					end
					table.insert(stack, {
						type = "number",
						value = number,
						position = cursor,
						depth = 1
					})
					cursor = cursor + 1

				elseif tokens[cursor]:punctuator() then
					local found
					for _, known_operator in ipairs(operators) do
						local matches = true
						for pos, ch in known_operator:gmatch("()(.)") do
							local relative = cursor + pos - 1
							if (relative > last)
							or (pos < #known_operator and tokens[relative].whitespace_follows)
							or (not tokens[relative]:punctuator(ch)) then
								matches = false
								break
							end
						end
						if matches then
							found = known_operator
							break
						end
					end
					if not found then
						return false, cursor, "unknown operator"
					end
					apply_operator(found)
					cursor = cursor + #found

				elseif tokens[cursor]:identifier() and operator_funcs[tokens[cursor].value] then
					apply_operator(tokens[cursor].value)

				elseif tokens[cursor]:identifier() then
					table.insert(stack, {
						type = "alias",
						value = aliases[tokens[cursor].value] or false,
						position = cursor,
						depth = 1
					})
					cursor = cursor + 1

				else
					return false, cursor, "not a number, an identifier or an operator"

				end
			end

			apply_operator(RESERVED.IDENTITY)
			if #stack > 1 then
				return false, stack[2].position, "excess value"
			end
			if #stack < 1 then
				return false, 1, "no value"
			end
			return true, stack[1].value
		end
	end

	local preprocess
	do
		local source_line_i = {}
		local source_line_mt = { __index = source_line_i }
		function source_line_i:dump_itop()
			local included_from = self.itop
			while included_from do
				printf.info("  included from %s:%i", included_from.path, included_from.line)
				included_from = included_from.next
			end
		end
		function source_line_i:blamef(report, format, ...)
			report("%s:%i: " .. format, self.path, self.line, ...)
			self:dump_itop()
		end
		function source_line_i:blamef_after(report, token, format, ...)
			report("%s:%i:%i " .. format, self.path, self.line, token.soffs + #token.value, ...)
			self:dump_itop()
		end

		local macro_invocation_counter = 0
		function preprocess(path)
			local lines = {}
			local include_top = false
			local include_depth = 0

			local function preprocess_fail()
				failf("preprocessing stage failed, bailing")
			end

			local aliases = {}
			local function expand_aliases(tokens, first, last, depth)
				local expanded = {}
				for ix = first, last do
					local alias = tokens[ix]:identifier() and aliases[tokens[ix].value]
					if alias then
						if depth > MAX_EXPANSION_DEPTH then
							tokens[ix]:blamef(printf.err, "maximum expansion depth reached while expanding alias '%s'", tokens[ix].value)
							preprocess_fail()
						end
						for _, token in ipairs(expand_aliases(alias, 1, #alias, depth + 1)) do
							table.insert(expanded, token:expand_by(tokens[ix]))
						end
					else
						table.insert(expanded, tokens[ix])
					end
				end
				return expanded
			end
			local function define(identifier, tokens, first, last)
				if aliases[identifier.value] then
					identifier:blamef(printf.err, "alias '%s' is defined", identifier.value)
					preprocess_fail()
				end
				local alias = {}
				for ix = first, last do
					table.insert(alias, tokens[ix])
				end
				aliases[identifier.value] = alias
			end
			local function undef(identifier)
				if not aliases[identifier.value] then
					identifier:blamef(printf.err, "alias '%s' is not defined", identifier.value)
					preprocess_fail()
				end
				aliases[identifier.value] = nil
			end

			local macros = {}
			local defining_macro = false
			local function expand_macro(tokens, depth)
				local expanded = expand_aliases(tokens, 1, #tokens, depth + 1)
				local macro = expanded[1]:identifier() and macros[expanded[1].value]
				if macro then
					if depth > MAX_EXPANSION_DEPTH then
						expanded[1]:blamef(printf.err, "maximum expansion depth reached while expanding macro '%s'", expanded[1].value)
						preprocess_fail()
					end
					local expanded_lines = {}
					local parameters_passed = {}
					local parameter_list = parse_parameter_list(expanded[1], expanded, 2, #expanded)
					for ix, ix_param in ipairs(parameter_list) do
						parameters_passed[macro.params[ix] or false] = ix_param
					end
					if macro.vararg then
						if #macro.params > #parameter_list then
							expanded[1]:blamef(printf.err, "macro '%s' invoked with %i parameters, expects at least %i", expanded[1].value, #parameter_list, #macro.params)
							preprocess_fail()
						end
					else
						if #macro.params ~= #parameter_list then
							expanded[1]:blamef(printf.err, "macro '%s' invoked with %i parameters, expects %i", expanded[1].value, #parameter_list, #macro.params)
							preprocess_fail()
						end
					end
					macro_invocation_counter = macro_invocation_counter + 1
					parameters_passed[RESERVED.MACROUNIQUE] = { expanded[1]:point({
						type = "identifier",
						value = ("_%i_"):format(macro_invocation_counter)
					}) }
					if macro.vararg then
						local vararg_param = {}
						local appendvararg_param = {}
						if #parameter_list > #macro.params then
							table.insert(appendvararg_param, expanded[1]:point({
								type = "punctuator",
								value = ","
							}))
						end
						for ix = #macro.params + 1, #parameter_list do
							for _, ix_token in ipairs(parameter_list[ix]) do
								table.insert(vararg_param, ix_token)
								table.insert(appendvararg_param, ix_token)
							end
							if ix ~= #parameter_list then
								table.insert(vararg_param, parameter_list[ix + 1].before)
								table.insert(appendvararg_param, parameter_list[ix + 1].before)
							end
						end
						parameters_passed[RESERVED.VARARG] = vararg_param
						parameters_passed[RESERVED.APPENDVARARG] = appendvararg_param
						parameters_passed[RESERVED.VARARGSIZE] = { expanded[1]:point({
							type = "number",
							value = tostring(#parameter_list - #macro.params)
						}) }
					end
					local old_aliases = {}
					for param, value in pairs(parameters_passed) do
						old_aliases[param] = aliases[param]
						aliases[param] = value
					end
					for _, line in ipairs(macro) do
						for _, expanded_line in ipairs(expand_macro(line.tokens, depth + 1)) do
							local cloned_line = {}
							for _, token in ipairs(expanded_line) do
								table.insert(cloned_line, token:expand_by(expanded[1]))
							end
							table.insert(expanded_lines, cloned_line)
						end
					end
					for param, value in pairs(parameters_passed) do
						aliases[param] = old_aliases[param]
					end
					return expanded_lines
				else
					return { expanded }
				end
			end
			local function macro(identifier, tokens, first, last)
				if macros[identifier.value] then
					identifier:blamef(printf.err, "macro '%s' is defined", identifier.value)
					preprocess_fail()
				end
				local params = {}
				local params_assoc = {}
				local vararg = false
				for ix = first, last, 2 do
					if  ix + 2 == last
					and tokens[ix    ]:punctuator(".") and not tokens[ix    ].whitespace_follows
					and tokens[ix + 1]:punctuator(".") and not tokens[ix + 1].whitespace_follows
					and tokens[ix + 2]:punctuator(".") then
						vararg = true
						break
					end
					if not tokens[ix]:identifier() then
						tokens[ix]:blamef(printf.err, "expected parameter name")
						preprocess_fail()
					end
					if params_assoc[tokens[ix].value] then
						tokens[ix]:blamef(printf.err, "duplicate parameter")
						preprocess_fail()
					end
					params_assoc[tokens[ix].value] = true
					table.insert(params, tokens[ix].value)
					if ix == last then
						break
					end
					if not tokens[ix + 1]:punctuator(",") then
						tokens[ix + 1]:blamef(printf.err, "expected comma")
						preprocess_fail()
					end
				end
				defining_macro = {
					params = params,
					name = identifier.value,
					vararg = vararg
				}
			end
			local function endmacro()
				macros[defining_macro.name] = defining_macro
				defining_macro = false
			end
			local function unmacro(identifier)
				if not macros[identifier.value] then
					identifier:blamef(printf.err, "macro '%s' is not defined", identifier.value)
					preprocess_fail()
				end
				macros[identifier.value] = nil
			end

			local condition_stack = { {
				condition = true,
				seen_else = false,
				been_true = true,
				opened_by = false
			} }

			local function include(base_path, relative_path, lines, req)
				if include_depth > MAX_INCLUDE_DEPTH then
					req:blamef(printf.err, "maximum include depth reached while including '%s'", relative_path)
					preprocess_fail()
				end
				local path = relative_path
				local content = architecture.includes[relative_path]
				if not content then
					path = base_path and resolve_relative(base_path, relative_path) or relative_path
					local handle = io.open(path, "r")
					if not handle then
						req:blamef(printf.err, "failed to open '%s' for reading", path)
						preprocess_fail()
					end
					content = handle:read("*a")
					handle:close()
				end

				local line_number = 0
				for line in (content .. "\n"):gmatch("([^\n]*)\n") do
					line_number = line_number + 1
					local sline = setmetatable({
						path = path,
						line = line_number,
						itop = include_top,
						str = line
					}, source_line_mt)
					local ok, tokens, err = tokenise(sline)
					if not ok then
						printf.err("%s:%i:%i: %s", sline.path, sline.line, tokens, err)
						preprocess_fail()
					end
					if #tokens >= 1 and tokens[1]:punctuator("%") then
						if #tokens >= 2 and tokens[2]:identifier() then

							if tokens[2].value == "include" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected path")
										preprocess_fail()
									elseif not tokens[3]:stringlit() then
										tokens[3]:blamef(printf.err, "expected path")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									local relative_path = tokens[3].value:gsub("^\"(.*)\"$", "%1")
									include_top = {
										path = path,
										line = line_number,
										next = include_top
									}
									include_depth = include_depth + 1
									include(path, relative_path, lines, sline)
									include_depth = include_depth - 1
									include_top = include_top.next
								end

							elseif tokens[2].value == "warning" or tokens[2].value == "error" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected message")
										preprocess_fail()
									elseif not tokens[3]:stringlit() then
										tokens[3]:blamef(printf.err, "expected message")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									local err = tokens[3].value:gsub("^\"(.*)\"$", "%1")
									if tokens[2].value == "error" then
										printf.err("%s:%i: %%error: %s", path, line_number, err)
										preprocess_fail()
									else
										printf.warn("%s:%i: %%warning: %s", path, line_number, err)
									end
								end

							elseif tokens[2].value == "eval" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									local ok, result, err = evaluate(tokens, 4, #tokens, aliases)
									if not ok then
										tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
										preprocess_fail()
									end
									define(tokens[3], { tokens[3]:point({
										type = "number",
										value = tostring(result)
									}) }, 1, 1)
								end

							elseif tokens[2].value == "define" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									define(tokens[3], tokens, 4, #tokens)
								end

							elseif tokens[2].value == "undef" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									undef(tokens[3])
								end

							elseif tokens[2].value == "if" then
								local ok, result, err = evaluate(tokens, 3, #tokens, aliases)
								if not ok then
									tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
									preprocess_fail()
								end
								local evals_to_true = result ~= 0
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "ifdef" then
								if #tokens < 3 then
									sline:blamef_after(printf.err, tokens[2], "expected alias name")
									preprocess_fail()
								elseif not tokens[3]:identifier() then
									tokens[3]:blamef(printf.err, "expected alias name")
									preprocess_fail()
								end
								if #tokens > 3 then
									tokens[4]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								local evals_to_true = aliases[tokens[3].value] and true
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "ifndef" then
								if #tokens < 3 then
									sline:blamef_after(printf.err, tokens[2], "expected alias name")
									preprocess_fail()
								elseif not tokens[3]:identifier() then
									tokens[3]:blamef(printf.err, "expected alias name")
									preprocess_fail()
								end
								if #tokens > 3 then
									tokens[4]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								local evals_to_true = not aliases[tokens[3].value] and true
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "else" then
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%else")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].seen_else then
									tokens[2]:blamef(printf.err, "%%else after %%else")
									preprocess_fail()
								end
								condition_stack[#condition_stack].seen_else = true
								if condition_stack[#condition_stack].been_true then
									condition_stack[#condition_stack].condition = false
								else
									condition_stack[#condition_stack].condition = true
									condition_stack[#condition_stack].been_true = true
								end

							elseif tokens[2].value == "elif" then
								if #tokens > 2 then
									tokens[3]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%elif")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].seen_else then
									tokens[2]:blamef(printf.err, "%%elif after %%else")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].been_true then
									condition_stack[#condition_stack].condition = false
								else
									local ok, result, err = evaluate(tokens, 3, #tokens, aliases)
									if not ok then
										tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
										preprocess_fail()
									end
									local evals_to_true = result ~= 0
									condition_stack[#condition_stack].condition = evals_to_true
									condition_stack[#condition_stack].been_true = evals_to_true
								end

							elseif tokens[2].value == "endif" then
								if #tokens > 2 then
									tokens[3]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%endif")
									preprocess_fail()
								end
								condition_stack[#condition_stack] = nil

							elseif tokens[2].value == "macro" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected macro name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected macro name")
										preprocess_fail()
									end
									if defining_macro then
										tokens[2]:blamef(printf.err, "%%macro after %%macro")
										preprocess_fail()
									end
									macro(tokens[3], tokens, 4, #tokens)
								end
								
							elseif tokens[2].value == "endmacro" then
								if condition_stack[#condition_stack].condition then
									if #tokens > 2 then
										tokens[3]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									if not defining_macro then
										tokens[2]:blamef(printf.err, "unpaired %%endmacro")
										preprocess_fail()
									end
									endmacro()
								end

							elseif tokens[2].value == "unmacro" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected macro name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected macro name")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									unmacro(tokens[3])
								end

							else
								tokens[2]:blamef(printf.err, "unknown preprocessing directive")
								preprocess_fail()

							end
						end
					else
						if condition_stack[#condition_stack].condition and #tokens > 0 then
							if defining_macro then
								table.insert(defining_macro, {
									sline = sline,
									tokens = tokens
								})
							else
								for _, line in ipairs(expand_macro(tokens, 0)) do
									table.insert(lines, line)
								end
							end
						end
					end
				end
			end

			include(false, path, lines, { blamef = function(self, report, ...)
				report(...)
			end })
			if #condition_stack > 1 then
				condition_stack[#condition_stack].opened_by:blamef(printf.err, "unfinished conditional block")
				preprocess_fail()
			end

			return lines
		end
	end

	local function resolve_labels_inplace(tokens, labels)
		for ix, ix_token in ipairs(tokens) do
			if ix_token:is("label") then
				local offs = labels[ix_token.value]
				if offs then
					ix_token.type = "number"
					ix_token.value = offs
				else
					return false, ix, ix_token.value
				end
			end
		end
		return true
	end

	local function resolve_evaluations_inplace(tokens, labels)
		for ix, ix_token in ipairs(tokens) do
			if ix_token:is("evaluation") then
				local labels_ok, jx, err = resolve_labels_inplace(ix_token.value, labels)
				if labels_ok then
					local ok, result, err = evaluate(ix_token.value, 1, #ix_token.value, {})
					if ok then
						ix_token.type = "number"
						ix_token.value = tostring(result)
					else
						return false, ix, result, err
					end
				else
					return false, ix, jx, err
				end
			end
		end
		return true
	end

	local function parse_numbers_inplace(tokens)
		for ix, ix_token in ipairs(tokens) do
			if ix_token:number() then
				local ok, number = ix_token:parse_number()
				if not ok then
					return false, ix, number
				end
				ix_token.parsed = number
			elseif ix_token:charlit() then
				local number = 0
				for ch in ix_token.value:gsub("^'(.*)'$", "%1"):gmatch(".") do
					number = bit32_add(bit32_lshift(number, 8), ch:byte())
				end
				ix_token.type = "number"
				ix_token.value = tostring(number)
				ix_token.parsed = number
			end
		end
		return true
	end

	local function resolve_instructions(lines)
		local label_context = {}
		local output_pointer = 0
		local to_emit = {}
		local labels = {}

		local function emit_raw(token, values)
			to_emit[output_pointer] = {
				emit = values,
				length = #values,
				emitted_by = token,
				offset = output_pointer
			}
			to_emit[output_pointer].head = to_emit[output_pointer]
			output_pointer = output_pointer + 1
		end

		local hooks = {}
		hooks[RESERVED.ORG] = function(hook_token, parameters)
			if #parameters < 1 then
				hook_token:blamef_after(printf.err, "expected origin")
				return false
			end
			if #parameters > 1 then
				parameters[1][#parameters[1]]:blamef_after(printf.err, "excess parameters")
				return false
			end
			local org_pack = parameters[1]
			if #org_pack > 1 then
				org_pack[2]:blamef(printf.err, "excess tokens")
				return false
			end
			local org = org_pack[1]
			if not org:is("number") then
				org:blamef(printf.err, "not a number")
				return false
			end
			output_pointer = org.parsed
			return true
		end
		hooks[RESERVED.DW] = function(hook_token, parameters)
			-- * TODO: allow higher shifts, currently dw constants are truncated
			--         to 32 bits. not sure how to get around this
			for _, ix_param in ipairs(parameters) do
				if #ix_param < 1 then
					ix_param.before:blamef_after(printf.err, "no tokens")
					return false
				elseif #ix_param > 1 then
					ix_param[2]:blamef(printf.err, "excess tokens")
					return false
				end
				if ix_param[1]:number() then
					local number = ix_param[1].parsed
					if number >= 2 ^ architecture.dw_bits then
						number = number % 2 ^ architecture.dw_bits
						ix_param[1]:blamef(printf.warn, "number truncated to %i bits", architecture.dw_bits)
					end
					emit_raw(ix_param[1], { architecture.nop:clone():merge(number, 0) })
				elseif ix_param[1]:stringlit() then
					local values = {}
					for ch in ix_param[1].value:gsub("^\"(.*)\"$", "%1"):gmatch(".") do
						table.insert(values, architecture.nop:clone():merge(ch:byte(), 0))
					end
					emit_raw(ix_param[1], values)
				else
					ix_param[1]:blamef(printf.err, "expected string literal or number")
					return false
				end
			end
			return true
		end

		local known_identifiers = {}
		for key in pairs(architecture.entities) do
			known_identifiers[key] = true
		end
		for key in pairs(architecture.mnemonics) do
			known_identifiers[key] = true
		end
		for key in pairs(hooks) do
			known_identifiers[key] = true
		end
		for key, value in pairs(RESERVED) do
			known_identifiers[value] = true
		end

		for _, tokens in ipairs(lines) do
			local line_failed = false

			if not line_failed then
				local cursor = #tokens
				while cursor >= 1 do
					if tokens[cursor]:stringlit() then
						while cursor > 1 and tokens[cursor - 1]:stringlit() do
							tokens[cursor - 1] = tokens[cursor - 1]:point({
								type = "stringlit",
								value = tokens[cursor - 1].value .. tokens[cursor].value
							})
							table.remove(tokens, cursor)
							cursor = cursor - 1
						end

					elseif tokens[cursor]:charlit() then
						while cursor > 1 and tokens[cursor - 1]:charlit() do
							tokens[cursor - 1] = tokens[cursor - 1]:point({
								type = "charlit",
								value = tokens[cursor - 1].value .. tokens[cursor].value
							})
							table.remove(tokens, cursor)
							cursor = cursor - 1
						end

					elseif tokens[cursor]:identifier() and architecture.entities[tokens[cursor].value] then
						tokens[cursor] = tokens[cursor]:point({
							type = "entity",
							value = tokens[cursor].value,
							entity = architecture.entities[tokens[cursor].value]
						})

					elseif tokens[cursor]:identifier() and architecture.mnemonics[tokens[cursor].value] then
						tokens[cursor] = tokens[cursor]:point({
							type = "mnemonic",
							value = tokens[cursor].value,
							mnemonic = architecture.mnemonics[tokens[cursor].value]
						})

					elseif tokens[cursor]:identifier() and hooks[tokens[cursor].value] then
						tokens[cursor] = tokens[cursor]:point({
							type = "hook",
							value = tokens[cursor].value,
							hook = hooks[tokens[cursor].value]
						})

					elseif (tokens[cursor]:identifier() and not known_identifiers[tokens[cursor].value]) or
						   (tokens[cursor]:identifier(RESERVED.LABELCONTEXT)) then
						while cursor > 1 do
							if tokens[cursor - 1]:identifier() and not known_identifiers[tokens[cursor - 1].value] then
								tokens[cursor - 1] = tokens[cursor - 1]:point({
									type = "identifier",
									value = tokens[cursor - 1].value .. tokens[cursor].value
								})
								table.remove(tokens, cursor)
								cursor = cursor - 1

							elseif tokens[cursor - 1]:identifier(RESERVED.PEERLABEL) then
								if #label_context < 1 then
									tokens[cursor - 1]:blamef(printf.err, "peer-label reference in level %i context", #label_context - 1)
									line_failed = true
									break
								end
								tokens[cursor - 1] = tokens[cursor - 1]:point({
									type = "identifier",
									value = ("."):rep(#label_context - 1) .. tokens[cursor].value
								})
								table.remove(tokens, cursor)
								cursor = cursor - 1

							elseif tokens[cursor - 1]:identifier(RESERVED.SUPERLABEL) then
								if #label_context < 2 then
									tokens[cursor - 1]:blamef(printf.err, "super-label reference in level %i context", #label_context - 1)
									line_failed = true
									break
								end
								tokens[cursor - 1] = tokens[cursor - 1]:point({
									type = "identifier",
									value = ("."):rep(#label_context - 2) .. tokens[cursor].value
								})
								table.remove(tokens, cursor)
								cursor = cursor - 1

							elseif tokens[cursor - 1]:punctuator(".") then
								tokens[cursor - 1] = tokens[cursor - 1]:point({
									type = "identifier",
									value = "." .. tokens[cursor].value
								})
								table.remove(tokens, cursor)
								cursor = cursor - 1

							else
								break

							end
						end

						if not line_failed then
							local dots, rest = tokens[cursor].value:match("^(%.*)(.+)$")
							local level = #dots
							if level > #label_context then
								tokens[cursor]:blamef(printf.err, "level %i label declaration without preceding level %i label declaration", level, level - 1)
								line_failed = true
								break
							else
								local name_tbl = {}
								for ix = 1, level do
									table.insert(name_tbl, label_context[ix])
								end
								table.insert(name_tbl, rest)
								tokens[cursor] = tokens[cursor]:point({
									type = "label",
									value = table.concat(name_tbl, "."),
									ignore = rest == RESERVED.LABELCONTEXT,
									level = level,
									rest = rest
								})
							end
						end

					end
					cursor = cursor - 1
				end
			end

			if not line_failed then
				local cursor = 1
				while cursor <= #tokens do
					if tokens[cursor]:punctuator("{") then
						local brace_end = cursor + 1
						local last
						while brace_end <= #tokens do
							if tokens[brace_end]:punctuator("}") then
								last = brace_end
								break
							end
							brace_end = brace_end + 1
						end
						if not last then
							tokens[cursor]:blamef(printf.err, "unfinished evalation block")
							line_failed = true
							break
						end
						local eval_tokens = {}
						for ix = cursor + 1, last - 1 do
							table.insert(eval_tokens, tokens[ix])
						end
						for _ = cursor + 1, last do
							table.remove(tokens, cursor + 1)
						end
						tokens[cursor].type = "evaluation"
						tokens[cursor].value = eval_tokens
					end
					cursor = cursor + 1
				end
			end

			if not line_failed then
				if #tokens == 2 and tokens[1]:is("label") and tokens[2]:punctuator(":") then
					if tokens[1].ignore then
						for ix = tokens[1].level + 2, #label_context do
							label_context[ix] = nil
						end
					else
						for ix = tokens[1].level + 1, #label_context do
							label_context[ix] = nil
						end
						labels[tokens[1].value] = tostring(output_pointer)
						label_context[tokens[1].level + 1] = tokens[1].rest
					end

				elseif #tokens >= 1 and tokens[1]:is("mnemonic") then
					local funcs = tokens[1].mnemonic
					local parameters = parse_parameter_list(tokens[1], tokens, 2, #tokens)
					local ok, length = funcs.length(tokens[1], parameters)
					if ok then
						local overwrites = {}
						for ix = output_pointer, output_pointer + length - 1 do
							local overwritten = to_emit[ix]
							if overwritten then
								overwrites[overwritten.head] = true
							end
						end
						if next(overwrites) then
							local overwritten_count = 0
							for _ in pairs(overwrites) do
								overwritten_count = overwritten_count + 1
							end
							tokens[1]:blamef(printf.warn, "opcode emitted here (offs 0x%04X, size %i) overwrites the following %i opcodes:", output_pointer, length, overwritten_count)
							for overwritten in pairs(overwrites) do
								overwritten.emitted_by:blamef(printf.info, "opcode emitted here (offs 0x%04X, size %i)", overwritten.offset, overwritten.length)
							end
						end
						to_emit[output_pointer] = {
							emit = funcs.emit,
							parameters = parameters,
							length = length,
							emitted_by = tokens[1],
							offset = output_pointer
						}
						to_emit[output_pointer].head = to_emit[output_pointer]
						for ix = output_pointer + 1, output_pointer + length - 1 do
							to_emit[ix] = {
								head = to_emit[output_pointer]
							}
						end
						output_pointer = output_pointer + length
					else
						line_failed = true
					end

				elseif #tokens >= 1 and tokens[1]:is("hook") then
					local parameters = parse_parameter_list(tokens[1], tokens, 2, #tokens)
					for ix, ix_param in ipairs(parameters) do
						local labels_ok, ix, err = resolve_labels_inplace(ix_param, labels)
						if labels_ok then
							local evals_ok, ix, jx, err = resolve_evaluations_inplace(ix_param, labels)
							if evals_ok then
								local numbers_ok, ix, err = parse_numbers_inplace(ix_param)
								if not numbers_ok then
									ix_param[ix]:blamef(printf.err, "invalid number: %s", err)
									line_failed = true
								end
							else
								ix_param[ix].value[jx]:blamef(printf.err, "evaluation failed: %s", err)
								line_failed = true
							end
						else
							ix_param[ix]:blamef(printf.err, "failed to resolve label: %s", err)
							line_failed = true
						end
					end
					if not line_failed then
						line_failed = not tokens[1].hook(tokens[1], parameters)
					end

				else
					tokens[1]:blamef(printf.err, "expected label declaration, instruction or hook invocation")
					line_failed = true

				end
			end

			if line_failed then
				printf.err_called = true
			end
		end
		if printf.err_called then
			failf("instruction resolution stage failed, bailing")
		end

		return to_emit, labels
	end

	local emit_opcodes
	do
		function emit_opcodes(to_emit, labels)
			local opcodes = {}
			do
				local max_pointer = 0
				for _, rec in pairs(to_emit) do
					local after_end = rec.offset + rec.length
					if max_pointer < after_end then
						max_pointer = after_end
					end
				end
				for ix = 0, max_pointer - 1 do
					opcodes[ix] = architecture.nop:clone()
				end
			end
			for offset, rec in pairs(to_emit) do
				if type(rec.emit) == "function" then
					local emission_ok = true
					for ix, ix_param in ipairs(rec.parameters) do
						local labels_ok, ix, err = resolve_labels_inplace(ix_param, labels)
						if labels_ok then
							local evals_ok, ix, jx, err = resolve_evaluations_inplace(ix_param, labels)
							if evals_ok then
								local numbers_ok, ix, err = parse_numbers_inplace(ix_param)
								if not numbers_ok then
									ix_param[ix]:blamef(printf.err, "invalid number: %s", err)
									emission_ok = true
								end
							else
								ix_param[ix].value[jx]:blamef(printf.err, "evaluation failed: %s", err)
								emission_ok = false
							end
						else
							ix_param[ix]:blamef(printf.err, "failed to resolve label: %s", err)
							emission_ok = false
						end
					end
					if emission_ok then
						local emitted
						emission_ok, emitted = rec.emit(rec.emitted_by, rec.parameters)
						if emission_ok then
							for ix = 1, rec.length do
								opcodes[offset + ix - 1] = emitted[ix]
							end
						end
					end
					if not emission_ok then
						printf.err_called = true
					end

				elseif type(rec.emit) == "table" then
					for ix = 1, rec.length do
						opcodes[offset + ix - 1] = rec.emit[ix]
					end

				end
			end
			if printf.err_called then
				failf("opcode emission stage failed, bailing")
			end

			return opcodes
		end
	end

	local root_source_path = tostring(named_args.source or unnamed_args[1] or failf("no source specified"))
	local lines = preprocess(root_source_path)
	local to_emit, labels = resolve_instructions(lines)
	local opcodes = emit_opcodes(to_emit, labels)

	local target = named_args.target or unnamed_args[2]
	if type(target) == "table" then
		for ix, ix_opcode in pairs(opcodes) do
			target[ix] = ix_opcode
		end
	else
		architecture.flash(model_name, target, opcodes)
		if printf.err_called then
			failf("flashing stage failed, bailing")
		end
	end

end, function(err)

	if err ~= failf then
		-- * Dang.
		printf.err("error: %s", tostring(err))
		printf.info("%s", debug.traceback())
		printf.info("this is an assembler bug, tell LBPHacker!")
		printf.info("https://github.com/LBPHacker/tptasm")
	end

end)

printf.unredirect()
printf.info("done")
