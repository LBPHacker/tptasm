local function sub(a, b)
	local s = a - b
	if s < 0 then
		s = s + 0x100000000
	end
	return s
end

local function add(a, b)
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

local function div(a, b)
	local quo, rem = divmod(a, b)
	return quo
end

local function mod(a, b)
	local quo, rem = divmod(a, b)
	return rem
end

local function hasbit(a, b)
	return a % (b + b) >= b
end

local function band(a, b)
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

local function mul(a, b)
	local ll = band(a, 0xFFFF) * band(b, 0xFFFF)
	local lh = band(band(a, 0xFFFF) * math.floor(b / 0x10000), 0xFFFF)
	local hl = band(math.floor(a / 0x10000) * band(b, 0xFFFF), 0xFFFF)
	return add(add(ll, lh * 0x10000), hl * 0x10000)
end

local function bor(a, b)
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

local function bxor(a, b)
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

local function lshift(a, b)
	if b >= 32 then
		return 0
	end
	return mul(a, 2 ^ b)
end

local function rshift(a, b)
	if b >= 32 then
		return 0
	end
	return div(a, 2 ^ b)
end

return {
	bxor = bxor,
	bor = bor,
	band = band,
	sub = sub,
	add = add,
	mul = mul,
	div = div,
	mod = mod,
	rshift = rshift,
	lshift = lshift,
}
