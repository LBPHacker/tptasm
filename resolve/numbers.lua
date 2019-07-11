local xbit32 = require("xbit32")

return function(tokens)
	for ix, ix_token in ipairs(tokens) do
		if ix_token:number() then
			local ok, number = ix_token:parse_number()
			if not ok then
				return false, ix, number
			end
			ix_token.parsed = number
		elseif ix_token:charlit() then
			local number = 0
			for ch in ix_token.value:gsub("^'(.*)'$", "%1"):gmatch(".") do
				number = xbit32.add(xbit32.lshift(number, 8), ch:byte())
			end
			ix_token.type = "number"
			ix_token.value = tostring(number)
			ix_token.parsed = number
		end
	end
	return true
end
