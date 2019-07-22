return function(tokens, labels)
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
