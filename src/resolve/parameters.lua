return function(before, expanded, first, last)
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
