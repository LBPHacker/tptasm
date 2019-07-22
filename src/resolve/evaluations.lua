local resolve_labels = require("resolve.labels")
local evaluate = require("evaluate")

return function(tokens, labels)
	for ix, ix_token in ipairs(tokens) do
		if ix_token:is("evaluation") then
			local labels_ok, jx, err = resolve_labels(ix_token.value, labels)
			if labels_ok then
				local ok, result, err = evaluate(ix_token.value, 1, #ix_token.value, {})
				if ok then
					ix_token.type = "number"
					ix_token.value = tostring(result)
				else
					return false, ix, result, err
				end
			else
				return false, ix, jx, err
			end
		end
	end
	return true
end
