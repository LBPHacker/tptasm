local xbit32 = require("xbit32")

local function enumerate_standard(id)
	if  sim.partProperty(id, "ctype") == 0x1864A205
	and sim.partProperty(id, "type") == elem.DEFAULT_PT_QRTZ then
		local x, y = sim.partPosition(id)
		local dxdyprop = sim.partProperty(id, "tmp2")
		local dx   = xbit32.band(              dxdyprop,      0xF)
		local dy   = xbit32.band(xbit32.rshift(dxdyprop, 4),  0xF)
		local prop = xbit32.band(xbit32.rshift(dxdyprop, 8), 0x1F)
		if dx == 0 and dy == 0 then
			dx = 1
		end
		if math.abs(dx) > 1 or math.abs(dy) > 1 then -- * Garbage.
			dy = 0
			dx = 1
		end
		if prop == 0 then
			prop = sim.FIELD_CTYPE
		end
		local function prop_of(offs)
			local cid = sim.partID(x + offs * dx, y + offs * dy)
			return cid and sim.partProperty(cid, prop)
		end
		local id_target = prop_of(-1)
		if id_target then
			local offs = 0
			local id_model = ""
			local checksum = 0
			local name_intact = true
			while true do
				offs = offs + 1
				local ctype = prop_of(offs)
				if not ctype then
					name_intact = false
					break
				end
				if ctype == 0 then
					break
				end
				id_model = id_model .. string.char(ctype)
				checksum = checksum + ctype
			end
			if name_intact and prop_of(offs + 1) == checksum then
				coroutine.yield(x, y, id_model, id_target)
				return true
			end
		end
	end
	return false
end

local function enumerate_nope()
	-- * nothing, it's a placeholder and it just fails
end

local function match_property(id, name, value)
	return not value or sim.partProperty(id, name) == value
end

local function enumerate_legacy(model, conditions)
	return function(id)
		if  match_property(id, "type", conditions[1][3])
		and match_property(id, "ctype", conditions[1][4]) then
			local x, y = sim.partPosition(id)
			local ok = true
			for ix = 2, #conditions do
				local cid = sim.partID(x + conditions[ix][1], y + conditions[ix][2])
				if not cid
				or not match_property(cid, "type", conditions[ix][3])
				or not match_property(cid, "ctype", conditions[ix][4]) then
					ok = false
				end
			end
			if ok then
				coroutine.yield(x, y, model, 0)
				return true
			end
		end
		return false
	end
end

local enumerate_micro21 = enumerate_nope
local enumerate_maps = enumerate_nope
if tpt then
	enumerate_micro21 = enumerate_legacy("MICRO21", {
		{  nil, nil, elem.DEFAULT_PT_DTEC, elem.DEFAULT_PT_DSTW },
		{ -181, 292, elem.DEFAULT_PT_DMND,                false },
		{  336, 201, elem.DEFAULT_PT_DMND,                false },
		{  394,  23, elem.DEFAULT_PT_BTRY,                false },
		{  384,  85, elem.DEFAULT_PT_BTRY,                false },
		{  -13, 177, elem.DEFAULT_PT_BTRY,                false },
		{ -179, 306, elem.DEFAULT_PT_PTCT,                false },
		{ -175, 306, elem.DEFAULT_PT_PTCT,                false },
		{ -178, 309, elem.DEFAULT_PT_PTCT,                false },
		{ -174, 309, elem.DEFAULT_PT_PTCT,                false },
	})
	enumerate_maps = enumerate_legacy("MAPS", {
		{  nil, nil, elem.DEFAULT_PT_SWCH, false },
		{  -28,  -2, elem.DEFAULT_PT_ARAY, false },
		{  137, -27, elem.DEFAULT_PT_DLAY, false },
		{   67, -11, elem.DEFAULT_PT_INST, false },
		{   49,  19, elem.DEFAULT_PT_FILT, false },
		{  -12,  34, elem.DEFAULT_PT_INWR, false },
		{   90,   3, elem.DEFAULT_PT_ARAY, false },
		{   94, -42, elem.DEFAULT_PT_INSL, false },
		{  124,  12, elem.DEFAULT_PT_SWCH, false },
		{  113,  11, elem.DEFAULT_PT_METL, false },
	})
end

local function enumerate_cpus()
	if not tpt then
		printf.err("not running inside TPT, can't find target")
		return
	end
	for id in sim.parts() do
		local _ = enumerate_standard(id)
		       or enumerate_micro21(id)
		       or enumerate_maps(id)
	end
end

local function all_cpus()
	local co = coroutine.create(enumerate_cpus)
	return function()
		if coroutine.status(co) ~= "dead" then
			local ok, x, y, id_model, id_target = coroutine.resume(co)
			if not ok then
				error(x)
			end
			return x, y, id_model, id_target
		end
	end
end

local function detect_filter(filter)
	local candidates = {}
	for x, y, model, id in all_cpus() do
		if filter(x, y, model, id) then
			table.insert(candidates, {
				x = x,
				y = y,
				model = model,
				id = id
			})
		end
	end
	if tpt then
		local mx, my = sim.adjustCoords(tpt.mousex, tpt.mousey)
		for _, candidate in ipairs(candidates) do
			if candidate.x == mx and candidate.y == my then
				candidates = { candidate }
				break
			end
		end
	end
	if candidates[1] then
		return candidates[1]
	end
end

local function cpu(model_in, target_in)
	local candidate = detect_filter(function(x, y, model, id)
		return (not target_in or target_in == id   )
		   and (not  model_in or  model_in == model)
	end)
	if candidate then
		return candidate.x, candidate.y
	end
end

local function model(target_in)
	local candidate = detect_filter(function(x, y, model, id)
		return (not target_in or target_in == id)
	end)
	if candidate then
		return candidate.model
	end
end

local function make_anchor(model, dxstr, dystr, propname, leetid)
	if not tpt then
		printf.err("not running inside TPT, can't spawn anchor")
		return
	end
	local prop = sim["FIELD_" .. tostring(propname or "ctype"):upper()]
	if not prop then
		printf.err("invalid property")
		return
	end
	local dx = tonumber(dxstr or "1")
	if dx ~= math.floor(dx) or dx >= 8 or dx < -8 then
		printf.err("invalid dx")
		return
	end
	if dx < 0 then
		dx = dx + 16
	end
	local dy = tonumber(dystr or "0")
	if dy ~= math.floor(dy) or dy >= 8 or dy < -8 then
		printf.err("invalid dy")
		return
	end
	if dy < 0 then
		dy = dy + 16
	end
	local x, y = sim.adjustCoords(tpt.mousex, tpt.mousey)
	local function spawn(offs, ty)
		local px = x + offs * dx
		local py = y + offs * dy
		local id = sim.partID(px, py) or sim.partCreate(-2, px, py, ty)
		return id
	end
	sim.partProperty(spawn(-1, elem.DEFAULT_PT_FILT), prop, leetid or 1337)
	local anchor = spawn(0, elem.DEFAULT_PT_QRTZ)
	sim.partProperty(anchor, "tmp2", dx + dy * 0x10 + prop * 0x100)
	sim.partProperty(anchor, "ctype", 0x1864A205)
	local checksum = 0
	for ix = 1, #model do
		local byte = model:byte(ix)
		sim.partProperty(spawn(ix, elem.DEFAULT_PT_FILT), prop, byte)
		checksum = checksum + byte
	end
	spawn(#model + 1, elem.DEFAULT_PT_FILT)
	sim.partProperty(spawn(#model + 2, elem.DEFAULT_PT_FILT), prop, checksum)
end

return {
	all_cpus = all_cpus,
	cpu = cpu,
	model = model,
	make_anchor = make_anchor,
}
