local printf  = require("tptasm.printf")
local utility = require("tptasm.utility")

local function run(...)
	local exit_with = 0

	local args = { ... }
	if _G.tpt and select("#", ...) == 0 then
		_G.tptasm = run
		return exit_with
	end

	printf.update_colour()
	local old_print = print
	function print(...)
		printf.debug(utility.get_line(2), ...)
	end

	xpcall(function()

		local detect = require("tptasm.detect")
		local archs = require("tptasm.archs")
		local preprocess = require("tptasm.preprocess")
		local emit = require("tptasm.emit")
		local resolve = require("tptasm.resolve")
		local xbit32 = require("tptasm.xbit32")

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
	print = old_print
	if not _G.tpt then
		os.exit(exit_with)
	end
	return exit_with
end

return {
	run = run,
}
