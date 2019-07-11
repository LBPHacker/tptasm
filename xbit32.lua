local xbit32 = {}

function xbit32.lshift(a, b)
	if b >= 32 then
		return 0
	end
	return xbit32.mul(a, 2 ^ b)
end

function xbit32.rshift(a, b)
	if b >= 32 then
		return 0
	end
	return xbit32.div(a, 2 ^ b)
end

function xbit32.sub(a, b)
	local s = a - b
	if s < 0 then
		s = s + 0x100000000
	end
	return s
end

function xbit32.add(a, b)
	local s = a + b
	if s >= 0x100000000 then
		s = s - 0x100000000
	end
	return s
end

local function divmod(a, b)
	local quo = math.floor(a / b)
	return quo, a - quo * b
end

function xbit32.div(a, b)
	local quo, rem = divmod(a, b)
	return quo
end

function xbit32.mod(a, b)
	local quo, rem = divmod(a, b)
	return rem
end

function xbit32.mul(a, b)
	local ll = xbit32.band(a, 0xFFFF) * xbit32.band(b, 0xFFFF)
	local lh = xbit32.band(xbit32.band(a, 0xFFFF) * math.floor(b / 0x10000), 0xFFFF)
	local hl = xbit32.band(math.floor(a / 0x10000) * xbit32.band(b, 0xFFFF), 0xFFFF)
	return xbit32.add(xbit32.add(ll, lh * 0x10000), hl * 0x10000)
end

local function hasbit(a, b)
	return a % (b + b) >= b
end

function xbit32.band(a, b)
	local curr = 1
	local out = 0
	for ix = 0, 31 do
		if hasbit(a, curr) and hasbit(b, curr) then
			out = out + curr
		end
		curr = curr * 2
	end
	return out
end

function xbit32.bor(a, b)
	local curr = 1
	local out = 0
	for ix = 0, 31 do
		if hasbit(a, curr) or hasbit(b, curr) then
			out = out + curr
		end
		curr = curr * 2
	end
	return out
end

function xbit32.bxor(a, b)
	local curr = 1
	local out = 0
	for ix = 0, 31 do
		if hasbit(a, curr) ~= hasbit(b, curr) then
			out = out + curr
		end
		curr = curr * 2
	end
	return out
end

return xbit32
