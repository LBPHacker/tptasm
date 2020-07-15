local config = {
	max_depth = {
		include = 100,
		expansion = 100,
		eval = 100
	},
	reserved = {
		appendvararg = "_Appendvararg",
		defined      = "_Defined",
		dw           = "_Dw",
		identity     = "_Identity",
		labelcontext = "_Labelcontext",
		litmap       = "_Litmap",
		macrounique  = "_Macrounique",
		model        = "_Model",
		org          = "_Org",
		peerlabel    = "_Peerlabel",
		superlabel   = "_Superlabel",
		vararg       = "_Vararg",
		varargsize   = "_Varargsize",
	},
	litmap = {}
}
for ix = 0, 127 do
	config.litmap[ix] = ix
end

return config
