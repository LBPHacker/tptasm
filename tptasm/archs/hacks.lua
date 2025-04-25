local printf = require("tptasm.printf")

local function pig(mnemonic_token_hax, parameters_hax, mnemonics)
	local sub_instructions = {}

	local tokens = { mnemonic_token_hax }
	for _, parameter in ipairs(parameters_hax) do
		for _, token in ipairs(parameter) do
			table.insert(tokens, token)
		end
	end

	while tokens[1] do
		local mnemonic_token = tokens[1]
		table.remove(tokens, 1)

		local instr_desc = mnemonics[mnemonic_token.value]
		if not instr_desc then
			mnemonic_token:blamef(printf.err, "unknown mnemonic")
			return false
		end

		local wants_operands = tonumber(instr_desc.class:sub(1, 1))
		local operand
		do
			local operand_list = {}
			while tokens[1] and not tokens[1]:punctuator("|") do
				table.insert(operand_list, tokens[1])
				table.remove(tokens, 1)
			end
			if tokens[1] and tokens[1]:punctuator("|") then
				table.remove(tokens, 1)
			end

			if #operand_list > wants_operands then
				operand_list[wants_operands + 1]:blamef(printf.err, "excess operands")
				return false
			end
			if #operand_list < wants_operands then
				if #operand_list == 0 then
					mnemonic_token:blamef_after(printf.err, "insufficient operands")
				else
					operand_list[#operand_list]:blamef_after(printf.err, "insufficient operands")
				end
				return false
			end
			operand = operand_list[1]
		end

		if operand then
			local expect_class = "X"
			if operand:number() then
				expect_class = "I"
			end
			if operand:is("entity") then
				expect_class = "R"
			end
			if not instr_desc.class:find(expect_class) then -- * it can only be a register
				mnemonic_token:blamef(printf.err, "no variant of '%s' exists that takes a %s operand '%s'", mnemonic_token.value, operand.type, operand.value)
				return false
			end
		end

		table.insert(sub_instructions, {
			instr_desc = instr_desc,
			mnemonic_token = mnemonic_token,
			operand = operand
		})
	end

	return sub_instructions
end

return {
	pig = pig, -- * Aka piped instruction groups. (Stupid way to say that multiple instructions exist on the same source line and are delimited by '|'.)
}
