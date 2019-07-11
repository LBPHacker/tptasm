local printf = require("printf")

local token_i = {}
local token_mt = { __index = token_i }

function token_i:is(type, value)
	return self.type == type and (not value or self.value == value)
end

function token_i:punctuator(...)
	return self:is("punctuator", ...)
end

function token_i:identifier(...)
	return self:is("identifier", ...)
end

function token_i:stringlit(...)
	return self:is("stringlit", ...)
end

function token_i:charlit(...)
	return self:is("charlit", ...)
end

function token_i:number()
	return self:is("number")
end

local function parse_number_base(str, base)
	local out = 0
	for ix, ch in str:gmatch("()(.)") do
		local pos = base:find(ch)
		if not pos then
			return false, ("invalid digit at position %i"):format(ix)
		end
		out = out * #base + (pos - 1)
		if out >= 0x100000000 then
			return false, "unsigned 32-bit overflow"
		end
	end
	return true, out
end

function token_i:parse_number()
	local str = self.value
	if str:match("^0[Xx][0-9A-Fa-f]+$") then
		return parse_number_base(str:sub(3):lower(), "0123456789abcdef")
	elseif str:match("^[0-9A-Fa-f]+[Hh]$") then
		return parse_number_base(str:sub(1, -2), "0123456789abcdef")
	elseif str:match("^0[Bb][0-1]+$") then
		return parse_number_base(str:sub(3), "01")
	elseif str:match("^0[Oo][0-7]+$") then
		return parse_number_base(str:sub(3), "01234567")
	elseif str:match("^[0-9]+$") then
		return parse_number_base(str, "0123456789")
	end
	return false, "notation not recognised"
end

function token_i:point(other)
	other.sline = self.sline
	other.soffs = self.soffs
	other.expanded_from = self.expanded_from
	return setmetatable(other, token_mt)
end

function token_i:blamef_after(report, format, ...)
	self.sline:blamef_after(report, self, format, ...)
end

function token_i:blamef(report, format, ...)
	report("%s:%i:%i: " .. format, self.sline.path, self.sline.line, self.soffs, ...)
	self.sline:dump_itop()
	if self.expanded_from then
		self.expanded_from:blamef(printf.info, "expanded from this")
	end
end

function token_i:expand_by(other)
	local clone = setmetatable({}, token_mt)
	for key, value in pairs(self) do
		clone[key] = value
	end
	clone.expanded_from = other
	return clone
end

local transition = {}
local all_8bit = ""
for ix = 0, 255 do
	all_8bit = all_8bit .. string.char(ix)
end
local function transitions(transition_list)
	local tbl = {}
	local function add_transition(cond, action)
		if type(cond) == "string" then
			for ch in all_8bit:gmatch(cond) do
				tbl[ch:byte()] = action
			end
		else
			tbl[cond] = action
		end
	end
	for _, ix_trans in ipairs(transition_list) do
		add_transition(ix_trans[1], ix_trans[2])
	end
	return tbl
end

transition.push = transitions({
	{         "'", { consume =  true, state = "charlit"    }},
	{        "\"", { consume =  true, state = "stringlit"  }},
	{     "[;\n]", { consume = false, state = "done"       }},
	{     "[0-9]", { consume =  true, state = "number"     }},
	{ "[_A-Za-z]", { consume =  true, state = "identifier" }},
	{ "[%[%]%(%)%+%-%*/%%:%?&#<>=!^~%.{}\\|@$,`]", { consume = false, state = "punctuator" }},
})
transition.identifier = transitions({
	{ "[_A-Za-z0-9]", { consume =  true, state = "identifier" }},
	{          false, { consume = false, state = "push"       }},
})
transition.number = transitions({
	{ "[_A-Za-z0-9]", { consume =  true, state = "number" }},
	{          false, { consume = false, state = "push"   }},
})
transition.charlit = transitions({
	{  "'", { consume = true, state = "push"         }},
	{ "\n", { error = "unfinished character literal" }},
})
transition.stringlit = transitions({
	{ "\"", { consume = true, state = "push"      }},
	{ "\n", { error = "unfinished string literal" }},
})
transition.punctuator = transitions({
	{ ".", { consume = true, state = "push" }},
})

local whitespace = {
	["\f"] = true,
	["\n"] = true,
	["\r"] = true,
	["\t"] = true,
	["\v"] = true,
	[" "] = true
}

return function(sline)
	local line = sline.str .. "\n"
	local tokens = {}
	local state = "push"
	local token_begin
	local cursor = 1
	while cursor <= #line do
		local ch = line:byte(cursor)
		if state == "push" and whitespace[ch] and #tokens > 0 then
			tokens[#tokens].whitespace_follows = true
		end
		local old_state = state
		local transition_info = transition[state][ch] or transition[state][false]
		local consume = true
		if transition_info then
			if transition_info.error then
				return false, cursor, transition_info.error
			end
			state = transition_info.state
			consume = transition_info.consume
		end
		if consume then
			cursor = cursor + 1
		end
		if state == "done" then
			break
		end
		if old_state == "push" and state ~= "push" then
			token_begin = cursor
			if consume then
				token_begin = token_begin - 1
			end
		end
		if old_state ~= "push" and state == "push" then
			local token_end = cursor - 1
			table.insert(tokens, setmetatable({
				type = old_state,
				value = line:sub(token_begin, token_end),
				sline = sline,
				soffs = token_begin
			}, token_mt))
		end
	end
	if #tokens > 0 then
		tokens[#tokens].whitespace_follows = true
	end
	return true, tokens
end
