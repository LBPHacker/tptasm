local config = require("config")
local printf = require("printf")
local resolve_parameters = require("resolve.parameters")
local resolve_labels = require("resolve.labels")
local resolve_evaluations = require("resolve.evaluations")
local resolve_numbers = require("resolve.numbers")

return function(architecture, lines)
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
		output_pointer = output_pointer + #values
	end

	local hooks = {}
	hooks[config.reserved.org] = function(hook_token, parameters)
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
	hooks[config.reserved.dw] = function(hook_token, parameters)
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
	for key, value in pairs(config.reserved) do
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
					   (tokens[cursor]:identifier(config.reserved.labelcontext)) then
					while cursor > 1 do
						if tokens[cursor - 1]:identifier() and not known_identifiers[tokens[cursor - 1].value] then
							tokens[cursor - 1] = tokens[cursor - 1]:point({
								type = "identifier",
								value = tokens[cursor - 1].value .. tokens[cursor].value
							})
							table.remove(tokens, cursor)
							cursor = cursor - 1

						elseif tokens[cursor - 1]:identifier(config.reserved.peerlabel) then
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

						elseif tokens[cursor - 1]:identifier(config.reserved.superlabel) then
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
								ignore = rest == config.reserved.labelcontext,
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
				local parameters = resolve_parameters(tokens[1], tokens, 2, #tokens)
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
				local parameters = resolve_parameters(tokens[1], tokens, 2, #tokens)
				for ix, ix_param in ipairs(parameters) do
					local labels_ok, ix, err = resolve_labels(ix_param, labels)
					if labels_ok then
						local evals_ok, ix, jx, err = resolve_evaluations(ix_param, labels)
						if evals_ok then
							local numbers_ok, ix, err = resolve_numbers(ix_param)
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
