--- @since 25.2.13
-- conf_helper: A growing collection of Yazi configuration helpers.
--
-- Usage (menu):   plugin conf_helper
-- Usage (direct): plugin conf_helper -- <function_name>
--
-- Available functions:
--   y_launcher    — Install the `y` shell wrapper into your shell profile
--   yazi_file_one — Find Git's file.exe and set YAZI_FILE_ONE (Windows only)

local FUNCS = {
	{
		id    = "y_launcher",
		key   = "y",
		desc  = "y_launcher    — Install the `y` shell wrapper",
		mod   = "funcs/y_launcher",
	},
	{
		id    = "yazi_file_one",
		key   = "f",
		desc  = "yazi_file_one — Set YAZI_FILE_ONE from Git install (Windows only)",
		mod   = "funcs/yazi_file_one",
	},
}

return {
	entry = function(self, job)
		-- Direct call: plugin conf_helper -- <function_name>
		local arg = job.args and job.args[1]
		if arg then
			for _, fn in ipairs(FUNCS) do
				if fn.id == arg then
					local mod = require(fn.mod)
					return mod.run()
				end
			end
			ya.notify {
				title   = "conf_helper",
				content = "Unknown function: '" .. arg .. "'\n"
					.. "Available: " .. table.concat((function()
						local t = {}
						for _, f in ipairs(FUNCS) do table.insert(t, f.id) end
						return t
					end)(), ", "),
				level   = "error",
				timeout = 8,
			}
			return
		end

		-- Menu mode: show available functions
		local cands = {}
		for _, fn in ipairs(FUNCS) do
			table.insert(cands, { on = fn.key, desc = fn.desc })
		end
		table.insert(cands, { on = "q", desc = "quit" })

		local choice = ya.which { cands = cands, silent = false }
		if not choice then return end

		-- "q" is always the last entry
		if choice == #cands then return end

		local fn  = FUNCS[choice]
		local mod = require(fn.mod)
		mod.run()
	end,
}
