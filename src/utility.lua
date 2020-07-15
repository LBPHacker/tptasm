local function get_line(up)
	local _, err = pcall(error, "@", up + 2)
	return err:match("^(.-)%s*:%s*@$")
end

local function parse_args(args)
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
		local max_arg = 0
		for key in pairs(args) do
			max_arg = key
		end
		local unnamed_counter = 0
		for ix_arg = 1, max_arg do
			local arg = args[ix_arg]
			local key_value = type(arg) == "string" and { arg:match("^([^=]+)=(.+)$") }
			if key_value and key_value[1] then
				if named_args[key_value[1]] then
					printf.warn("argument #%i overrides earlier specification of %s", ix_arg, key_value[1])
				end
				named_args[key_value[1]] = key_value[2]
			else
				unnamed_counter = unnamed_counter + 1
				unnamed_args[unnamed_counter] = arg
			end
		end
	end
	return named_args, unnamed_args
end

local function resolve_relative(base_with_file, relative)
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

local function utf8_each(str)
	local cursor = 0
	return function()
		if cursor >= #str then
			return
		end
		cursor = cursor + 1
		local head = str:byte(cursor)
		if head < 0x80 then
			return cursor, cursor, head
		end
		if head < 0xE0 and cursor + 1 <= #str then
			local cont1 = str:byte(cursor + 1, cursor + 1)
			cursor = cursor + 1
			return cursor - 1, cursor, head % 0x20 * 0x40 + cont1 % 0x40
		end
		if head < 0xF0 and cursor + 2 <= #str then
			local cont1, cont2 = str:byte(cursor + 1, cursor + 2)
			cursor = cursor + 2
			return cursor - 2, cursor, head % 0x10 * 0x1000 + cont1 % 0x40 * 0x40 + cont2 % 0x40
		end
		if head < 0xF8 and cursor + 3 <= #str then
			local cont1, cont2, cont3 = str:byte(cursor + 1, cursor + 3)
			cursor = cursor + 3
			return cursor - 3, cursor, head % 0x08 * 0x40000 + cont1 % 0x40 * 0x1000 + cont2 % 0x40 * 0x40 + cont3 % 0x40
		end
	end
end

return {
	utility = utility,
	parse_args = parse_args,
	resolve_relative = resolve_relative,
	utf8_each = utf8_each,
}
