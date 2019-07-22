local xbit32 = require("xbit32")
local config = require("config")

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
	["~" ] = { params = { "number"           }, does = function(a) return xbit32.bxor(a, 0xFFFFFFFF) end },
	["<<"] = { params = { "number", "number" }, does = xbit32.lshift },
	[">>"] = { params = { "number", "number" }, does = xbit32.rshift },
	["-" ] = { params = { "number", "number" }, does =    xbit32.sub },
	["+" ] = { params = { "number", "number" }, does =    xbit32.add },
	["/" ] = { params = { "number", "number" }, does =    xbit32.div },
	["%" ] = { params = { "number", "number" }, does =    xbit32.mod },
	["*" ] = { params = { "number", "number" }, does =    xbit32.mul },
	["&" ] = { params = { "number", "number" }, does =   xbit32.band },
	["|" ] = { params = { "number", "number" }, does =    xbit32.bor },
	["^" ] = { params = { "number", "number" }, does =   xbit32.bxor },
	[config.reserved.defined] = { params = { "alias" }, does = function(a) return a and 1 or 0 end },
	[config.reserved.identity] = { params = { "number" }, does = function(a) return a end },
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

return function(tokens, cursor, last, aliases)
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
		if max_depth > config.max_depth.eval then
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

	apply_operator(config.reserved.identity)
	if #stack > 1 then
		return false, stack[2].position, "excess value"
	end
	if #stack < 1 then
		return false, 1, "no value"
	end
	return true, stack[1].value
end
