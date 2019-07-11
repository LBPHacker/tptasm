local printf = require("printf")

local detect = {}

local function enumerate_standard(id)
	if  sim.partProperty(id, "ctype") == 0x1864A205
	and sim.partProperty(id, "type") == elem.DEFAULT_PT_QRTZ then
		local x, y = sim.partPosition(id)
		local function ctype_of(offs)
			local cid = sim.partID(x + offs, y)
			return cid and sim.partProperty(cid, "ctype")
		end
		local id_target = ctype_of(-1)
		if id_target then
			local offs = 0
			local id_model = ""
			local checksum = 0
			local name_intact = true
			while true do
				offs = offs + 1
				local ctype = ctype_of(offs)
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
			if name_intact and ctype_of(offs + 1) == checksum then
				coroutine.yield(x, y, id_model, id_target)
				return true
			end
		end
	end
	return false
end

local enumerate_legacy
do
	local function match_property(id, name, value)
		return not value or sim.partProperty(id, name) == value
	end

	function enumerate_legacy(model, conditions)
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
end

local enumerate_micro21
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
end

local function enumerate_cpus()
	if not tpt then
		printf.err("not running inside TPT, can't find target")
		return
	end
	for id in sim.parts() do
		local _ = enumerate_standard(id)
		       or enumerate_micro21(id)
	end
end

local function cpus()
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

function detect.cpu(model, target)
	for x, y, id_model, id_target in cpus() do
		if (not target or target == id_target)
		or (not model or model == id_model) then
			return x, y
		end
	end
end

function detect.model(target)
	for x, y, id_model, id_target in cpus() do
		if not target or target == id_target then
			return id_model
		end
	end
end

return detect
