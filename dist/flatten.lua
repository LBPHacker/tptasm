#!/usr/bin/env lua

local TPTASM_PATH_IN = "../src/tptasm.lua"
local TPTASM_PATH_OUT = "tptasm.lua"

local pconf = {}
pconf.dirsep, pconf.pathsep, pconf.wildcard = package.config:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n")

local function escape_lua_regex(str)
	return (str:gsub("[%$%%%(%)%*%+%-%.%?%[%]%^]", "%%%1"))
end

local wrangle = {}
local wrangle_safe = {
	["config"] = true,
	["utility"] = true,
	["printf"] = true,
}
table.insert(package.loaders, 1, function(name)
	local name_to_path = name:gsub("%.", escape_lua_regex(pconf.dirsep))
	for path in package.path:gsub(escape_lua_regex(pconf.wildcard), escape_lua_regex(name_to_path)):gmatch("[^" .. escape_lua_regex(pconf.pathsep) .. "]+") do
		local handle = io.open(path, "r")
		if handle then
			local content = handle:read("*a")
			handle:close()
			local func, err = loadstring(content, "=" .. path)
			if not func then
				error(err)
			end
			local ok, ret = pcall(func)
			if not ok then
				error(ret)
			end
			table.insert(wrangle, {
				name = name,
				content = content
			})
			return function()
				return ret
			end
		end
	end
	print(package.path)
	error(("failed to wrangle module '%s'"):format(name))
end)

local content, hashbang
do
	local handle = assert(io.open(TPTASM_PATH_IN, "r"), "you're probably in the wrong directory")
	content = handle:read("*a"):gsub("^#![^\n]*\n", function(cap)
		hashbang = cap
		return ""
	end)
	handle:close()
end

assert(loadstring(content, "=" .. TPTASM_PATH_IN))({ flatten = true }) -- wrangle!

do
	local handle = assert(io.open(TPTASM_PATH_OUT, "w"), "D:")
	handle:write(hashbang .. [[

local preload = {}
local function require(name)
	return preload[name]
end
		]] .. content:gsub("WRANGLE SAFE MODULES HERE", function()
		local parts = { "DISTRIBUTION VERSION" }
		for _, wr in ipairs(wrangle) do
			if wrangle_safe[wr.name] then
				table.insert(parts, ([[
preload[%q] = (function()
	%s
end)()
				]]):format(wr.name, wr.content:gsub("\n", "\n\t")))
			end
		end
		return table.concat(parts, "\n")
	end):gsub("WRANGLE UNSAFE MODULES HERE", function()
		local parts = { "DISTRIBUTION VERSION" }
		for _, wr in ipairs(wrangle) do
			if not wrangle_safe[wr.name] then
				table.insert(parts, ([[
	preload[%q] = (function()
		%s
	end)()
				]]):format(wr.name, wr.content:gsub("\n", "\n\t\t")))
			end
		end
		return table.concat(parts, "\n")
	end))
	handle:close()
end
