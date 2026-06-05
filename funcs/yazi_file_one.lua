-- funcs/yazi_file_one.lua
-- Finds Git's bundled file.exe and sets YAZI_FILE_ONE.
-- Windows only. On Linux/macOS the `file` command is a native system binary
-- that Yazi finds automatically — no env var needed.
--
-- Flow:
--   YAZI_FILE_ONE not set → search → pick scope → set
--   YAZI_FILE_ONE already set → show status → Skip / Update / View
--     Update → search → if different path found, confirm → pick scope → set

local M = {}

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function win_env(name)
	local out = Command("powershell")
		:arg("-NoProfile"):arg("-Command"):arg("$env:" .. name)
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if out and out.stdout ~= "" then return out.stdout:match("^%s*(.-)%s*$") end
	return nil
end

local function ps_run(cmd)
	local out = Command("powershell")
		:arg("-NoProfile"):arg("-Command"):arg(cmd)
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if out and out.stdout ~= "" then return out.stdout:match("^%s*(.-)%s*$") end
	return nil
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then f:close(); return true end
	return false
end

-- ─── Git search strategies ───────────────────────────────────────────────────

-- 1. Ask `git.exe --exec-path` and walk up to find usr\bin\file.exe
local function find_via_git_cmd()
	local out = Command("git"):arg("--exec-path")
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if not out or out.stdout == "" then return nil end
	local base = out.stdout:match("^%s*(.-)%s*$")
	for _ = 1, 6 do
		local candidate = base .. "\\usr\\bin\\file.exe"
		if file_exists(candidate) then return candidate end
		base = base:match("(.+)\\[^\\]+$") or ""
		if base == "" then break end
	end
	return nil
end

-- 2. Windows Registry: HKLM\SOFTWARE\GitForWindows → InstallPath
local function find_via_registry()
	local path = ps_run(
		"(Get-ItemProperty 'HKLM:\\SOFTWARE\\GitForWindows' -ErrorAction SilentlyContinue).InstallPath")
	if not path or path == "" then return nil end
	local candidate = path .. "\\usr\\bin\\file.exe"
	if file_exists(candidate) then return candidate end
	return nil
end

-- 3. Well-known default install locations
local function find_via_known_paths()
	local drive = win_env("SYSTEMDRIVE") or "C:"
	local candidates = {
		"C:\\Program Files\\Git\\usr\\bin\\file.exe",
		"C:\\Program Files (x86)\\Git\\usr\\bin\\file.exe",
		drive .. "\\Program Files\\Git\\usr\\bin\\file.exe",
	}
	for _, p in ipairs(candidates) do
		if file_exists(p) then return p end
	end
	return nil
end

-- 4. Scoop: %USERPROFILE%\scoop\apps\git\current\usr\bin\file.exe
local function find_via_scoop()
	local home = win_env("USERPROFILE")
	if not home then return nil end
	local p = home .. "\\scoop\\apps\\git\\current\\usr\\bin\\file.exe"
	if file_exists(p) then return p end
	return nil
end

-- 5. `where git` → walk up (last resort)
local function find_via_where()
	local out = Command("where"):arg("git")
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if not out or out.stdout == "" then return nil end
	local git_path = out.stdout:match("^%s*(.-)%s*$")
	local base = git_path:match("(.+)\\[^\\]+$") or ""
	base = base:match("(.+)\\[^\\]+$") or ""
	local candidate = base .. "\\usr\\bin\\file.exe"
	if file_exists(candidate) then return candidate end
	return nil
end

local FINDERS = {
	{ name = "git --exec-path", fn = find_via_git_cmd    },
	{ name = "registry",        fn = find_via_registry   },
	{ name = "known paths",     fn = find_via_known_paths },
	{ name = "scoop",           fn = find_via_scoop      },
	{ name = "where git",       fn = find_via_where      },
}

-- ─── env var setters ─────────────────────────────────────────────────────────

local function set_permanent_user(value)
	ps_run(string.format(
		'[Environment]::SetEnvironmentVariable("YAZI_FILE_ONE", "%s", "User")', value))
end

local function set_permanent_machine(value)
	ps_run(string.format(
		'[Environment]::SetEnvironmentVariable("YAZI_FILE_ONE", "%s", "Machine")', value))
end

local function set_session_only(value)
	ps_run(string.format('$env:YAZI_FILE_ONE = "%s"', value))
end

local function verify_set(expected)
	local actual = ps_run('[Environment]::GetEnvironmentVariable("YAZI_FILE_ONE", "User")')
	return actual == expected
end

-- ─── shared helpers ──────────────────────────────────────────────────────────

local function search_file_exe()
	for _, finder in ipairs(FINDERS) do
		local result = finder.fn()
		if result then return result, finder.name end
	end
	return nil, nil
end

-- Presents scope picker and performs the set
local function pick_scope_and_set(found_path, found_by)
	local choice = ya.which {
		cands = {
			{ on = "u", desc = "Set for current user (recommended)" },
			{ on = "m", desc = "Set system-wide (requires Admin)" },
			{ on = "s", desc = "Session only (not permanent)" },
			{ on = "q", desc = "Cancel" },
		},
	}
	if not choice or choice == 4 then return end

	ya.notify {
		title   = "yazi_file_one",
		content = string.format("Setting:\n%s\n(found via: %s)", found_path, found_by),
		level   = "info",
		timeout = 4,
	}

	if choice == 1 then
		set_permanent_user(found_path)
		local ok = verify_set(found_path)
		ya.notify {
			title   = "yazi_file_one",
			content = ok
				and ("Set for current user:\n" .. found_path .. "\n\nRestart terminal to apply.")
				or  "Failed to set. Try running Yazi as Administrator.",
			level   = ok and "info" or "error",
			timeout = 8,
		}

	elseif choice == 2 then
		set_permanent_machine(found_path)
		local actual = ps_run('[Environment]::GetEnvironmentVariable("YAZI_FILE_ONE", "Machine")')
		local ok = actual == found_path
		ya.notify {
			title   = "yazi_file_one",
			content = ok
				and ("Set system-wide:\n" .. found_path .. "\n\nRestart terminal to apply.")
				or  "Failed to set system-wide. Run Yazi as Administrator.",
			level   = ok and "info" or "warn",
			timeout = 8,
		}

	elseif choice == 3 then
		set_session_only(found_path)
		ya.notify {
			title   = "yazi_file_one",
			content = "Set for this session only:\n" .. found_path
				.. "\n\nWill NOT persist after closing the terminal.\n"
				.. 'Rerun and choose "user" to make it permanent.',
			level   = "warn",
			timeout = 10,
		}
	end
end

-- ─── public entry ─────────────────────────────────────────────────────────────

function M.run()
	-- Not useful on non-Windows
	if ya.target_os() ~= "windows" then
		ya.notify {
			title   = "yazi_file_one",
			content = "Not needed on Linux/macOS.\n"
				.. "`file` is a native system command Yazi finds automatically.\n"
				.. "YAZI_FILE_ONE is only required on Windows.",
			level   = "warn",
			timeout = 8,
		}
		return
	end

	local current = win_env("YAZI_FILE_ONE")

	-- ── Already set: show status + Skip / Update / View ──────────────────────
	if current and current ~= "" then
		local file_ok = file_exists(current)

		ya.notify {
			title   = "yazi_file_one",
			content = file_ok
				and ("Already set and file exists:\n" .. current)
				or  ("Set but file NOT found at:\n" .. current
					.. "\n\nGit may have been uninstalled or moved."),
			level   = file_ok and "info" or "warn",
			timeout = 6,
		}

		local action = ya.which {
			cands = {
				{ on = "s", desc = "Skip    (keep current value)" },
				{ on = "u", desc = "Update  (search for new path and set)" },
				{ on = "v", desc = "View    (show full current value)" },
			},
		}
		if not action or action == 1 then return end

		-- View
		if action == 3 then
			ya.notify {
				title   = "yazi_file_one",
				content = "YAZI_FILE_ONE =\n" .. current
					.. "\n\nFile " .. (file_ok and "exists ✓" or "NOT found ✗"),
				level   = file_ok and "info" or "warn",
				timeout = 12,
			}
			return
		end

		-- Update: search for a (possibly new) path
		ya.notify {
			title   = "yazi_file_one",
			content = "Searching for Git's file.exe...",
			level   = "info",
			timeout = 3,
		}

		local found_path, found_by = search_file_exe()

		if not found_path then
			ya.notify {
				title   = "yazi_file_one",
				content = "Could not find Git's file.exe.\n\n"
					.. "Make sure Git for Windows is installed.\n"
					.. "Download: https://git-scm.com/download/win",
				level   = "error",
				timeout = 10,
			}
			return
		end

		-- Same path, already working → nothing to do
		if found_path == current and file_ok then
			ya.notify {
				title   = "yazi_file_one",
				content = "Already pointing to the correct path:\n" .. found_path
					.. "\n\nNo update needed.",
				level   = "info",
				timeout = 6,
			}
			return
		end

		-- Confirm before overwriting (new path or broken path being fixed)
		local label = found_path == current
			and "(same path, but was missing — file now found)"
			or  string.format("found via: %s", found_by)

		local confirmed = ya.confirm {
			pos   = { "center", w = 66, h = 10 },
			title = "yazi_file_one — Update?",
			body  = string.format(
				"Current:\n  %s\n\nNew path (%s):\n  %s\n\nReplace?",
				current, label, found_path),
		}
		if not confirmed then return end

		pick_scope_and_set(found_path, found_by)
		return
	end

	-- ── Not set yet: fresh install flow ──────────────────────────────────────
	ya.notify {
		title   = "yazi_file_one",
		content = "YAZI_FILE_ONE is not set.\nSearching for Git's file.exe...",
		level   = "info",
		timeout = 3,
	}

	local found_path, found_by = search_file_exe()

	if not found_path then
		ya.notify {
			title   = "yazi_file_one",
			content = "Could not find Git's file.exe.\n\n"
				.. "Make sure Git for Windows is installed.\n"
				.. "Download: https://git-scm.com/download/win",
			level   = "error",
			timeout = 10,
		}
		return
	end

	pick_scope_and_set(found_path, found_by)
end

return M
