local printf
do
	printf = setmetatable({
		print = print,
		print_old = print,
		log_handle = false,
		colour = false,
		err_called = false,
		silent = false
	}, { __call = function(self, ...)
		if not printf.silent then
			printf.print(string.format(...))
		end
	end })
	function printf.debug(from, first, ...)
		local things = { tostring(first) }
		for ix_thing, thing in ipairs({ ... }) do
			table.insert(things, tostring(thing))
		end
		printf((printf.colour and "[tptasm] " or "[tptasm] [DD] ") .. "[%s] %s", from, table.concat(things, "\t"))
	end
	function printf.info(format, ...)
		printf((printf.colour and "\008t[tptasm]\008w " or "[tptasm] [II] ") .. format, ...)
	end
	function printf.warn(format, ...)
		printf((printf.colour and "\008o[tptasm]\008w " or "[tptasm] [WW] ") .. format, ...)
	end
	function printf.err(format, ...)
		printf((printf.colour and "\008l[tptasm]\008w " or "[tptasm] [EE] ") .. format, ...)
		printf.err_called = true
	end
	function printf.redirect(log_path)
		local handle = type(log_path) == "string" and io.open(log_path, "w") or log_path
		if handle then
			printf.log_path = log_path
			printf.log_handle = handle
			printf.info("redirecting log to '%s'", tostring(log_path))
			printf.print = function(str)
				printf.log_handle:write(str .. "\n")
			end
		else
			printf.warn("failed to open '%s' for writing, log not redirected", tostring(printf.log_path))
		end
	end
	function printf.unredirect()
		if printf.log_handle then
			if type(printf.log_path) == "string" then
				printf.log_handle:close()
			end
			printf.log_handle = false
			printf.print = printf.print_old
			printf.info("undoing redirection of log to '%s'", tostring(printf.log_path))
		end
	end
	function printf.update_colour()
		printf.colour = tpt and not printf.log_handle
	end
	printf.update_colour()

	function printf.failf(...)
		printf.err(...)
		error(printf.failf)
	end
end

return printf
