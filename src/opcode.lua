local xbit32 = require("xbit32")

local opcode = {}

local opcode_i = {}
local opcode_mt = { __index = opcode_i }

function opcode_i:clone()
	local dwords = {}
	for ix, ix_dword in ipairs(self.dwords) do
		dwords[ix] = ix_dword
	end
	return setmetatable({
		dwords = dwords
	}, opcode_mt)
end

function opcode_i:dump()
	return ("%08X "):rep(#self.dwords):format(unpack(self.dwords))
end

function opcode_i:has(shift)
	return math.floor(self.dwords[math.floor(shift / 32) + 1] / 2 ^ (shift % 32)) % 2 == 1
end

function opcode_i:merge(thing, shift)
	if type(thing) == "table" then
		for ix, ix_dword in ipairs(thing.dwords) do
			self:merge(ix_dword, (ix - 1) * 32 + shift)
		end
	else
		local offs = 1
		while shift >= 32 do
			offs = offs + 1
			shift = shift - 32
		end
		self.dwords[offs] = xbit32.bor(self.dwords[offs], thing % 2 ^ (32 - shift) * 2 ^ shift)
		thing = math.floor(thing / 2 ^ (32 - shift))
		for ix = offs + 1, #self.dwords do
			if thing == 0 then
				break
			end
			self.dwords[ix] = xbit32.bor(self.dwords[ix], thing % 0x100000000)
			thing = math.floor(thing / 0x100000000)
		end
	end
	return self
end

function opcode.make(size)
	local dwords = {}
	for ix = 1, math.ceil(size / 32) do
		dwords[ix] = 0
	end
	return setmetatable({
		dwords = dwords
	}, opcode_mt)
end

return opcode
