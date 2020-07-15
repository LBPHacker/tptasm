local known_archs = {
	[        "R3" ] = require("archs.r3"       ), -- * yet unreleased architecture by LBPHacker
	[ "B29K1QS60" ] = require("archs.b29k1qs60"), -- * "B29K1QS60" by unnick, id:2435570
	[   "MICRO21" ] = require("archs.micro21"  ), -- * "Micro Computer v2.1" by RockerM4NHUN, id:1599945
	[      "PTP7" ] = require("archs.ptp7"     ), -- * "PTP7" by unnick, id:2458644
	[   "A728D28" ] = require("archs.a728d28"  ), -- * "A7-28D28 Microcomputer" by Sam_Hayzen, id:2460726
	[  "I8M7D28S" ] = require("archs.i8m7d28s" ), -- * "Guardian I8M7D28S" by Sam_Hayzen, id:2473628
	[      "MAPS" ] = require("archs.maps"     ), -- * "Computer (mapS)" by drakide, id:975033
}

local known_models_to_archs = {
	[        "R3" ] = "R3",
	[ "B29K1QS60" ] = "B29K1QS60",
	[   "MICRO21" ] = "MICRO21",
	[     "PTP7A" ] = "PTP7",
	[  "A728D280" ] = "A728D28",
	[  "A728D28A" ] = "A728D28",
	[  "I8M7D28S" ] = "I8M7D28S",
	-- [      "MAPS" ] = "MAPS", -- * incomplete, don't use
}

local function get_name(model_name)
	return known_models_to_archs[model_name]
end

local function get_description(architecture_name)
	return known_archs[architecture_name]
end

return {
	get_name = get_name,
	get_description = get_description,
}
