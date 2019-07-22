#!/usr/bin/env lua

-- WRANGLE SAFE MODULES HERE

local pconf = {}
do
	pconf.pathsep, pconf.dirsep, pconf.wildcard = package.config:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n")
	local basedir = assert(debug.getinfo(1)).source:sub(2):match(("^(.+)%s[^%s]+$"):format(pconf.pathsep, pconf.pathsep))
	pconf.package_path_old = package.path
	package.path = basedir .. "/?.lua" .. pconf.dirsep .. package.path
	package.path = basedir .. "/?/init.lua" .. pconf.dirsep .. package.path
end

local config = require("config")
local utility = require("utility")

tpt = tpt or false
utility.strict()

local printf = require("printf")
local print_old = print
function print(...)
	printf.debug(utility.get_line(2), ...)
end

local args = { ... }
xpcall(function()

	-- WRANGLE UNSAFE MODULES HERE

	local detect = require("detect")
	local architectures = require("architectures")
	local preprocess = require("preprocess")
	local emit = require("emit")
	local resolve_instructions = require("resolve.instructions")

	local named_args, unnamed_args = utility.parse_args(args)

	if named_args.flatten then
		printf.info("invoked flattening mode, exiting")
		return
	end

	if type(named_args.anchor) == "string" then
		detect.make_anchor(named_args.anchor)
		return
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
		model_name = detect.model()
	end
	if not model_name then
		printf.failf("failed to detect model and no model name was passed")
	end

	local architecture_name = architectures.get_name(model_name) or printf.failf("no architecture description for model '%s'", model_name)
	local architecture = architectures.get_description(architecture_name)

	local root_source_path = tostring(named_args.source or unnamed_args[1] or printf.failf("no source specified"))
	local lines = preprocess(architecture, root_source_path)
	local to_emit, labels = resolve_instructions(architecture, lines)
	local opcodes = emit(architecture, to_emit, labels)

	local target = named_args.target or unnamed_args[2]
	if type(target) == "table" then
		for ix, ix_opcode in pairs(opcodes) do
			target[ix] = ix_opcode
		end
	else
		architecture.flash(model_name, target, opcodes)
		if printf.err_called then
			printf.failf("flashing stage failed, bailing")
		end
	end

end, function(err)

	if err ~= printf.failf then
		-- * Dang.
		printf.err("error: %s", tostring(err))
		printf.info("%s", debug.traceback())
		printf.info("this is an assembler bug, tell LBPHacker!")
		printf.info("https://github.com/LBPHacker/tptasm")
	end

end)

package.path = pconf.package_path_old
print = print_old

printf.unredirect()
printf.info("done")
