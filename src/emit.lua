local resolve = require("resolve")

return function(architecture, to_emit, labels)
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
				local labels_ok, ix, err = resolve.label_offsets(ix_param, labels, rec)
				if labels_ok then
					local evals_ok, ix, jx, err = resolve.evaluations(ix_param, labels, rec)
					if evals_ok then
						local numbers_ok, ix, err = resolve.numbers(ix_param)
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
				emission_ok, emitted = rec.emit(rec.emitted_by, rec.parameters, offset)
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
		printf.failf("opcode emission stage failed, bailing")
	end

	return opcodes
end
