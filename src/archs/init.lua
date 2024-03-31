local known_archs = {
	[   "A728D28" ] = require("archs.a728d28"  ),
	[ "B29K1QS60" ] = require("archs.b29k1qs60"),
	[  "I8M7D28S" ] = require("archs.i8m7d28s" ),
	[      "MAPS" ] = require("archs.maps"     ),
	[   "MICRO21" ] = require("archs.micro21"  ),
	[      "PTP7" ] = require("archs.ptp7"     ),
	[        "R2" ] = require("archs.r2"       ),
	[        "R3" ] = require("archs.r3"       ),
	[ "Armatoste" ] = require("archs.armatoste"),
}
local function get_description(architecture_name)
	return known_archs[architecture_name]
end

local known_models_to_archs = {
	[  "A728D280" ] = "A728D28",   -- * "A7-28D28 Microcomputer" by Sam_Hayzen, id:2460726
	[  "A728D28A" ] = "A728D28",   -- * "A7-28D28 Microcomputer" by Sam_Hayzen, id:2460726
	[ "B29K1QS60" ] = "B29K1QS60", -- * "B29K1QS60" by unnick, id:2435570
	[  "I8M7D28S" ] = "I8M7D28S",  -- * "Guardian I8M7D28S" by Sam_Hayzen, id:2473628
	[      "MAPS" ] = "MAPS",      -- * "Computer (mapS)" by drakide, id:975033
	[   "MICRO21" ] = "MICRO21",   -- * "Micro Computer v2.1" by RockerM4NHUN, id:1599945
	[     "PTP7A" ] = "PTP7",      -- * "PTP7" by unnick, id:2458644
	[   "R216K2A" ] = "R2",        -- * "R216K2A" by LBPHacker, id:2303519
	[   "R216K4A" ] = "R2",        -- * "R216K4A" by LBPHacker, id:2305835
	[   "R216K8B" ] = "R2",        -- * "R216K8B" by LBPHacker, id:2342633
	[ "Armatoste" ] = "Armatoste", -- * yet unreleased architecture by DanielUbTb
}
for core_count = 1, 99 do
	for addr_bits = 11, 13 do
		known_models_to_archs[("R3A%s%02i"):format(string.char(addr_bits + 64), core_count)] = "R3" -- * yet unreleased architecture by LBPHacker
	end
end

local function get_name(model_name)
	return known_models_to_archs[model_name]
end

return {
	get_description = get_description,
	get_name = get_name,
}
