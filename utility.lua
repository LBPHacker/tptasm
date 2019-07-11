local utility = {}

function utility.strict()
	local env_copy = {}
	for key, value in pairs(_G) do
		env_copy[key] = value
	end
	setfenv(1, setmetatable(env_copy, { __index = function()
		error("__index")
	end, __newindex = function()
		error("__newindex")
	end }))
end

function utility.get_line(up)
	local _, err = pcall(error, "@", up + 2)
	return err:match("^(.-)%s*:%s*@$")
end

function utility.parse_args(args)
	local named_args = {}
	local unnamed_args = {}
	if #args == 1 and type(args[1]) == "table" then
		for _, arg in ipairs(args[1]) do
			table.insert(unnamed_args, arg)
		end
		for key, arg in pairs(args[1]) do
			if type(key) ~= "number" then
				named_args[key] = arg
			end
		end
	else
		for ix_arg, arg in ipairs(args) do
			local key_value = type(arg) == "string" and { arg:match("^([^=]+)=(.+)$") }
			if key_value and key_value[1] then
				if named_args[key_value[1]] then
					printf.warn("argument #%i overrides earlier specification of %s", ix_arg, key_value[1])
				end
				named_args[key_value[1]] = key_value[2]
			else
				table.insert(unnamed_args, arg)
			end
		end
	end
	return named_args, unnamed_args
end

function utility.resolve_relative(base_with_file, relative)
	local components = {}
	local parent_depth = 0
	-- * TODO: support more prefixes (i.e. C:, eww)
	local prefix, concatenated_path = (base_with_file .. "/../" .. relative):match("^(/?)(.+)$")
	for component in concatenated_path:gmatch("[^/]+") do
		if component == ".." then
			if #components > 0 then
				components[#components] = nil
			else
				parent_depth = parent_depth + 1
			end
		elseif component ~= "." then
			table.insert(components, component)
		end
	end
	for _ = 1, parent_depth do
		table.insert(components, 1, "..")
	end
	return prefix .. table.concat(components, "/")
end

return utility
