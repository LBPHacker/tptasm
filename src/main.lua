#!/usr/bin/env lua

local new_env = {}
for key, value in pairs(getfenv(1)) do
	new_env[key] = value
end
if not new_env.tpt then
	new_env.tpt = false
end
setfenv(1, new_env)

local exit_with = 0

do
	local script_path = debug.getinfo(1).source
	assert(script_path:sub(1, 1) == "@", "something is fishy")
	script_path = script_path:sub(2)
	local slash_at
	for ix = #script_path, 1, -1 do
		if script_path:sub(ix, ix):find("[\\/]") then
			slash_at = ix
			break
		end
	end
	if slash_at then
		script_path = script_path:sub(1, slash_at - 1)
	else
		script_path = "."
	end
	local loaded = {}
	
	function require(modname)
		if not loaded[modname] then
			local try = {
				script_path .. "/" .. modname:gsub("%.", "/") .. ".lua",
				script_path .. "/" .. modname:gsub("%.", "/") .. "/init.lua",
			}
			local msg = { "no such module", "tried:" }
			for ix = 1, #try do
				local path = try[ix]
				local handle = io.open(path, "r")
				if handle then
					loaded[modname] = assert(setfenv(assert(loadstring(handle:read("*a"), "@" .. path)), getfenv(1))())
					handle:close()
					break
				end
				table.insert(msg, (" - %s"):format(path))
			end
			if not loaded[modname] then
				error(table.concat(msg, "\n"))
			end
		end
		return loaded[modname]
	end
end

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
	printf.update_colour()
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
	printf.update_colour()
end

function printf.update_colour()
	printf.colour = tpt and not printf.log_handle
end
printf.update_colour()

function printf.failf(...)
	printf.err(...)
	error(printf.failf)
end

local utility = require("utility")

function print(...)
	printf.debug(utility.get_line(2), ...)
end

-- * Environment finalised, prevent further fiddling.
setmetatable(new_env, { __index = function(_, key)
	error("__index on _G", 2)
end, __newindex = function(_, key)
	error("__newindex on _G", 2)
end })

local args = { ... }
xpcall(function()

	local detect = require("detect")
	local archs = require("archs")
	local preprocess = require("preprocess")
	local emit = require("emit")
	local resolve = require("resolve")
	local xbit32 = require("xbit32")

	local named_args, unnamed_args = utility.parse_args(args)

	local log_path = named_args.log or unnamed_args[3]
	if log_path then
		printf.redirect(log_path)
	end

	if type(named_args.anchor) == "string" then
		detect.make_anchor(named_args.anchor, named_args.anchor_dx, named_args.anchor_dy, named_args.anchor_prop, named_args.anchor_id)
		return
	end

	if named_args.silent then
		printf.silent = true
	end

	if named_args.detect then
		printf.info("listing targets")
		local counter = 0
		for x, y, model, id in detect.all_cpus() do
			printf.info(" * %s with ID %i at (%i, %i)", model, id, x, y)
			counter = counter + 1
		end
		printf.info("found %s targets", counter)
		return
	end

	local target = named_args.target or unnamed_args[2]
	local model_name = named_args.model or unnamed_args[4]

	if not model_name then
		model_name = detect.model(type(target) == "number" and target)
	end
	if not model_name then
		printf.failf("failed to detect model and no model name was passed")
	end

	local architecture_name = archs.get_name(model_name) or printf.failf("no architecture description for model '%s'", model_name)
	local architecture = archs.get_description(architecture_name)

	local root_source_path = tostring(named_args.source or unnamed_args[1] or printf.failf("no source specified"))
	local lines = preprocess(architecture, root_source_path)
	local to_emit, labels, model_restrictions = resolve.instructions(architecture, lines)

	for path, restrictions in pairs(model_restrictions) do
		local path_ok = false
		local failing_restriction_tokens = {}
		for _, restriction in ipairs(restrictions) do
			if model_name:find("^" .. restriction.value:gsub("^\"(.*)\"$", "%1") .. "$") then
				path_ok = true
			else
				failing_restriction_tokens[restriction] = true
			end
		end
		if not path_ok then
			local report_with = named_args.allow_model_mismatch and printf.warn or printf.err
			report_with("%s: unit incompatible with target model", path)
			for token in pairs(failing_restriction_tokens) do
				token:blamef(printf.info, "target model doesn't match this pattern")
			end
		end
	end
	if printf.err_called then
		printf.failf("model restriction check failed, bailing")
	end

	if named_args.export_labels then
		local handle = io.open(named_args.export_labels, "w")
		if handle then
			local sorted_labels = {}
			for name, address in pairs(labels) do
				table.insert(sorted_labels, {
					name = name,
					address = tonumber(address)
				})
			end
			table.sort(sorted_labels, function(lhs, rhs)
				if lhs.address < rhs.address then return  true end
				if lhs.address > rhs.address then return false end
				if lhs.name    < rhs.name    then return  true end
				if lhs.name    > rhs.name    then return false end
				return false
			end)
			for _, label in ipairs(sorted_labels) do
				handle:write(("%s 0x%X\n"):format(label.name, label.address))
			end
			handle:close()
		else
			printf.warn("failed to open '%s' for writing, no labels exported", tostring(named_args.export_labels))
		end
	end
	local opcodes = emit(architecture, to_emit, labels)

	if type(target) == "table" then
		for ix, ix_opcode in pairs(opcodes) do
			target[ix] = ix_opcode
		end
	elseif type(target) == "string" then
		local buf = {}
		local _, first = next(opcodes)
		if first then
			local width = #first.dwords
			for ix, ix_opcode in pairs(opcodes) do
				for ix_dword = 1, width do
					local dword = ix_opcode.dwords[ix_dword]
					buf[ix * width + ix_dword] = string.char(
						xbit32.band(              dword     , 0xFF),
						xbit32.band(xbit32.rshift(dword,  8), 0xFF),
						xbit32.band(xbit32.rshift(dword, 16), 0xFF),
						xbit32.band(xbit32.rshift(dword, 24), 0xFF)
					)
				end
			end
		end
		local handle = io.open(target, "wb")
		if handle then
			handle:write(table.concat(buf))
			handle:close()
		else
			printf.warn("failed to open '%s' for writing, no opcodes written", target)
		end
	else
		architecture.flash(model_name, target, opcodes)
		if printf.err_called then
			printf.failf("flashing stage failed, bailing")
		end
	end

end, function(err)

	if err == printf.failf then
		exit_with = 1
	else
		-- * Dang.
		printf.err("error: %s", tostring(err))
		printf.info("%s", debug.traceback())
		printf.info("this is an assembler bug, tell LBPHacker!")
		printf.info("https://github.com/LBPHacker/tptasm")
		exit_with = 2
	end

end)

printf.unredirect()
printf.info("done")
if not tpt then
	os.exit(exit_with)
end
