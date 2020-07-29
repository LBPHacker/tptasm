local config = require("config")
local evaluate = require("evaluate")
local resolve = require("resolve")
local tokenise = require("tokenise")
local utility = require("utility")

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

return function(architecture, path)
	local macro_invocation_counter = 0
	local lines = {}
	local include_top = false
	local include_depth = 0

	local function preprocess_fail()
		printf.failf("preprocessing stage failed, bailing")
	end

	local aliases = {}
	local function expand_aliases(tokens, first, last, depth)
		local expanded = {}
		for ix = first, last do
			local alias = tokens[ix]:identifier() and aliases[tokens[ix].value]
			if alias then
				if depth > config.max_depth.expansion then
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
			if depth > config.max_depth.expansion then
				expanded[1]:blamef(printf.err, "maximum expansion depth reached while expanding macro '%s'", expanded[1].value)
				preprocess_fail()
			end
			local expanded_lines = {}
			local parameters_passed = {}
			local parameter_list = resolve.parameters(expanded[1], expanded, 2, #expanded)
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
			parameters_passed[config.reserved.macrounique] = { expanded[1]:point({
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
				parameters_passed[config.reserved.vararg] = vararg_param
				parameters_passed[config.reserved.appendvararg] = appendvararg_param
				parameters_passed[config.reserved.varargsize] = { expanded[1]:point({
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
		if include_depth > config.max_depth.include then
			req:blamef(printf.err, "maximum include depth reached while including '%s'", relative_path)
			preprocess_fail()
		end
		local path = relative_path
		local content = architecture.includes[relative_path]
		if not content then
			path = base_path and utility.resolve_relative(base_path, relative_path) or relative_path
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
								tokens[2]:blamef(printf.err, "%%error: %s", err)
								preprocess_fail()
							else
								tokens[2]:blamef(printf.warn, "%%warning: %s", err)
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
