local known_archs = {
	[       "R3"] = require("architectures.r3"),
	["B29K1QS60"] = require("architectures.b29k1qs60"),
	[  "MICRO21"] = require("architectures.micro21"),
	[     "PTP7"] = require("architectures.ptp7"),
}

local known_models_to_archs = {
	[       "R3"] = "R3",
	["B29K1QS60"] = "B29K1QS60",
	[  "MICRO21"] = "MICRO21",
	[    "PTP7A"] = "PTP7",
}

local architectures = {}

function architectures.get_name(model_name)
	return known_models_to_archs[model_name]
end

function architectures.get_description(architecture_name)
	return known_archs[architecture_name]
end

return architectures
