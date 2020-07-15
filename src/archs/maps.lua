local config = require("config")
local opcode = require("opcode")
local detect = require("detect")

-- * TODO: figure out what the hell I was doing last time

local includes = {
	["common"] = ([==[
		%ifndef _COMMON_INCLUDED_
		%define _COMMON_INCLUDED_

		%define dw `dw'
		%define org `org'

		%endif ; _COMMON_INCLUDED_
	]==]):gsub("`([^\']+)'", function(cap)
		return config.reserved[cap]
	end)
}

local entities = {}
local nop = opcode.make(18)
local dw_bits = 18

local mnemonics = {}
-- for key in pairs(mnemonics) do
-- 	mnemonics[key] = mnemonic_desc
-- end

local function flash(model, target, opcodes)
	local x, y = detect.cpu(model, target)
	if not x then
		return
	end

	-- ?
end

return {
	includes = includes,
	dw_bits = dw_bits,
	nop = nop,
	entities = entities,
	mnemonics = mnemonics,
	flash = flash,
}
