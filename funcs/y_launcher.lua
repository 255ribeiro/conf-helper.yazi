-- funcs/y_launcher.lua
-- Detects the running shell and installs the `y` shell wrapper into the
-- appropriate profile file. Supports PowerShell, Bash, Zsh, Fish, CMD,
-- WSL1, and WSL2.

local WRAPPERS = {
	powershell = {
		name        = "PowerShell",
		profile_env = "USERPROFILE",
		profile_sub = { "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1" },
		marker      = "function y {",
		content     = [[
function y {
    $tmp = (New-TemporaryFile).FullName
    yazi.exe @args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if ($cwd -and $cwd -ne $PWD.Path -and (Test-Path -LiteralPath $cwd -PathType Container)) {
        Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
    }
    Remove-Item -Path $tmp
}
]],
	},
	bash = {
		name        = "Bash",
		profile_env = "HOME",
		profile_sub = { ".bashrc" },
		marker      = "function y()",
		content     = [[
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}
]],
	},
	zsh = {
		name        = "Zsh",
		profile_env = "HOME",
		profile_sub = { ".zshrc" },
		marker      = "function y()",
		content     = [[
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}
]],
	},
	fish = {
		name        = "Fish",
		profile_env = "HOME",
		profile_sub = { ".config", "fish", "config.fish" },
		marker      = "function y",
		content     = [[
function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	command yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
		builtin cd -- "$cwd"
	end
	command rm -f -- "$tmp"
end
]],
	},
	cmd = {
		name    = "CMD",
		marker  = "yazi.exe %*",
		content = [[@echo off
set tmpfile=%TEMP%\yazi-cwd.%random%
yazi.exe %* --cwd-file="%tmpfile%"
if not exist "%tmpfile%" exit /b 0
set /p cwd=<"%tmpfile%"
if not "%cwd%"=="" if exist "%cwd%\" (
    cd /d "%cwd%"
)
del "%tmpfile%"
]],
	},
}

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function unix_env(name)
	local out = Command("sh"):arg("-c"):arg("printf '%s' \"$" .. name .. "\"")
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if out and out.stdout ~= "" then return out.stdout:match("^%s*(.-)%s*$") end
	return nil
end

local function win_env(name)
	local ps = ya.target_os() == "windows" and "powershell" or "powershell.exe"
	local out = Command(ps)
		:arg("-NoProfile"):arg("-Command"):arg("$env:" .. name)
		:stdout(Command.PIPED):stderr(Command.NULL):output()
	if out and out.stdout ~= "" then return out.stdout:match("^%s*(.-)%s*$") end
	return nil
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local c = f:read("*a"); f:close(); return c
end

local function write_file(path, content, append)
	local f = io.open(path, append and "a" or "w")
	if not f then return false end
	f:write(content); f:close(); return true
end

local function ensure_parent(path, is_win)
	if is_win then
		local parent = path:match("(.+)\\[^\\]+$")
		if not parent then return end
		local ps = ya.target_os() == "windows" and "powershell" or "powershell.exe"
		Command(ps):arg("-NoProfile"):arg("-Command")
			:arg(string.format('[System.IO.Directory]::CreateDirectory("%s") | Out-Null', parent))
			:status()
	else
		local parent = path:match("(.+)/[^/]+$")
		if parent then fs.create("dir_all", Url(parent)) end
	end
end

-- ─── line-level block helpers ────────────────────────────────────────────────

local function split_lines(content)
	local result = {}
	local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
	local pos = 1
	while pos <= #normalized do
		local nl = normalized:find("\n", pos, true)
		if nl then
			table.insert(result, normalized:sub(pos, nl - 1))
			pos = nl + 1
		else
			table.insert(result, normalized:sub(pos))
			break
		end
	end
	return result
end

-- Returns the line index where the block starting at start_idx ends.
-- For brace-delimited shells (powershell/bash/zsh) it counts { }.
-- For fish it counts function/if/while/for/begin/switch vs end keywords.
-- Comment-only lines (starting with #) are skipped for brace counting.
local function find_block_end_line(lines, start_idx, shell_key)
	if shell_key == "powershell" or shell_key == "bash" or shell_key == "zsh" then
		local depth = 0
		for i = start_idx, #lines do
			local line = lines[i]
			if not line:match("^%s*#") then
				for ci = 1, #line do
					local c = line:sub(ci, ci)
					if c == "{" then
						depth = depth + 1
					elseif c == "}" then
						depth = depth - 1
						if depth == 0 then return i end
					end
				end
			end
		end
	elseif shell_key == "fish" then
		local depth = 0
		for i = start_idx, #lines do
			local t = lines[i]:match("^%s*(%S.*)")
			if t then
				if t:match("^function%s") or t:match("^if%s") or
				   t:match("^while%s")    or t:match("^for%s") or
				   t:match("^begin%s*$")  or t:match("^switch%s") then
					depth = depth + 1
				elseif t:match("^end%s*$") then
					depth = depth - 1
					if depth == 0 then return i end
				end
			end
		end
	end
	return nil
end

-- ─── WSL detection ───────────────────────────────────────────────────────────

local function wsl_version()
	if ya.target_os() ~= "linux" then return nil end
	local distro = unix_env("WSL_DISTRO_NAME")
	if not distro or distro == "" then return nil end
	local f = io.open("/proc/version", "r")
	if f then
		local ver = f:read("*a"):lower(); f:close()
		if ver:find("wsl2") then return "wsl2" end
		if ver:find("microsoft") then return "wsl1" end
	end
	return "wsl1"
end

-- ─── shell + path detection ──────────────────────────────────────────────────

local function detect_shell(is_wsl)
	if not is_wsl and ya.target_os() == "windows" then
		local psmp = win_env("PSModulePath")
		if psmp and psmp ~= "" then return "powershell" end
		return "cmd"
	end
	local sp = unix_env("SHELL") or ""
	if sp:find("zsh")  then return "zsh"  end
	if sp:find("fish") then return "fish" end
	if sp:find("bash") then return "bash" end
	if unix_env("ZSH_VERSION")  then return "zsh"  end
	if unix_env("FISH_VERSION") then return "fish" end
	return "bash"
end

local function get_profile_path(shell_key, is_wsl)
	local cfg = WRAPPERS[shell_key]
	if shell_key == "cmd" then
		local home    = win_env("USERPROFILE") or "C:\\Users\\Default"
		local bin_dir = home .. "\\bin"
		fs.create("dir_all", Url(bin_dir))
		return bin_dir .. "\\y.bat", true
	end
	if ya.target_os() == "windows" and not is_wsl then
		local base  = win_env(cfg.profile_env) or "C:\\Users\\Default"
		local parts = { base }
		for _, p in ipairs(cfg.profile_sub) do table.insert(parts, p) end
		local path = table.concat(parts, "\\")
		ensure_parent(path, true)
		return path, true
	end
	local base  = unix_env(cfg.profile_env) or os.getenv("HOME") or "~"
	local parts = { base }
	for _, p in ipairs(cfg.profile_sub) do table.insert(parts, p) end
	local path = table.concat(parts, "/")
	ensure_parent(path, false)
	return path, false
end

-- ─── file I/O actions ────────────────────────────────────────────────────────

local function show_file(path)
	local permit = ui.hide()
	local pager  = ya.target_os() == "windows" and "more" or "less"
	Command(pager):arg(path)
		:stdin(Command.INHERIT):stdout(Command.INHERIT):stderr(Command.INHERIT):status()
	permit:drop()
end

local function write_wrapper(path, content, append)
	local ok = write_file(path, "\n" .. content, append)
	ya.notify {
		title   = "y_launcher",
		content = ok
			and ((append and "Appended `y` to " or "Created ") .. path)
			or  ("Failed to write to " .. path),
		level   = ok and "info" or "error",
		timeout = 6,
	}
end

local function do_replace(path, existing, shell_key, cfg)
	-- CMD bat files have no reliable block structure; always append.
	if shell_key == "cmd" then
		local ok = write_file(path, existing .. "\n" .. cfg.content, false)
		ya.notify {
			title   = "y_launcher",
			content = ok and ("Appended `y` to " .. path) or ("Failed to write " .. path),
			level   = ok and "info" or "error",
			timeout = 5,
		}
		return
	end

	local lines     = split_lines(existing)
	local start_idx = nil
	for i, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		-- Skip comment lines so a marker in a comment doesn't match.
		local is_comment = trimmed:match("^#") ~= nil
		if not is_comment then
			local pos = line:find(cfg.marker, 1, true)
			if pos then
				-- For fish, guard against 'function yellow' matching 'function y'.
				if shell_key == "fish" then
					local after = line:sub(pos + #cfg.marker)
					if after == "" or after:match("^%s") then
						start_idx = i; break
					end
				else
					start_idx = i; break
				end
			end
		end
	end

	local new_content
	if start_idx then
		local end_idx = find_block_end_line(lines, start_idx, shell_key)
		if end_idx then
			local new_wrapper = split_lines(cfg.content)
			while new_wrapper[1] == "" do table.remove(new_wrapper, 1) end
			while #new_wrapper > 0 and new_wrapper[#new_wrapper] == "" do
				table.remove(new_wrapper)
			end
			local parts = {}
			for i = 1, start_idx - 1      do table.insert(parts, lines[i])       end
			for _, l   in ipairs(new_wrapper) do table.insert(parts, l)           end
			for i = end_idx + 1, #lines    do table.insert(parts, lines[i])       end
			new_content = table.concat(parts, "\n")
			if new_content:sub(-1) ~= "\n" then new_content = new_content .. "\n" end
		end
	end

	-- Fallback: append when block boundaries could not be found.
	if not new_content then
		new_content = existing .. "\n" .. cfg.content
	end

	local ok = write_file(path, new_content, false)
	ya.notify {
		title   = "y_launcher",
		content = ok and ("Replaced `y` in " .. path) or ("Failed to write " .. path),
		level   = ok and "info" or "error",
		timeout = 5,
	}
end

-- ─── public entry ─────────────────────────────────────────────────────────────

local M = {}

function M.run()
	local wsl        = wsl_version()
	local is_wsl     = wsl ~= nil
	local shell_key  = detect_shell(is_wsl)
	local cfg        = WRAPPERS[shell_key]
	local path, _    = get_profile_path(shell_key, is_wsl)

	local env_label
	if wsl then
		env_label = string.format("WSL%s (%s) → %s",
			wsl:sub(4), unix_env("WSL_DISTRO_NAME") or "?", cfg.name)
	else
		env_label = cfg.name
	end

	ya.notify {
		title   = "y_launcher",
		content = string.format("Shell: %s\nProfile: %s", env_label, path),
		level   = "info",
		timeout = 5,
	}

	local existing = read_file(path)
	local has_func = existing and existing:find(cfg.marker, 1, true)

	-- Case 1: profile missing → offer to create
	if not existing then
		local ok = ya.confirm {
			pos   = { "center", w = 62, h = 9 },
			title = "y_launcher — Create file?",
			body  = string.format("No profile found at:\n%s\n\nCreate it with the `y` wrapper?", path),
		}
		if ok then write_wrapper(path, cfg.content, false) end
		return
	end

	-- Case 2: profile exists but no `y` → offer to append
	if not has_func then
		local ok = ya.confirm {
			pos   = { "center", w = 62, h = 9 },
			title = "y_launcher — Append wrapper?",
			body  = string.format("Profile found:\n%s\n\nNo `y` function detected. Append it?", path),
		}
		if ok then write_wrapper(path, cfg.content, true) end
		return
	end

	-- Case 3: `y` already present → menu
	local choice = ya.which {
		cands = {
			{ on = "i", desc = "Ignore  (do nothing)" },
			{ on = "r", desc = "Replace existing `y` function" },
			{ on = "a", desc = "Append  another `y` block anyway" },
			{ on = "s", desc = "Show    the profile file" },
		},
	}
	if not choice then return end

	if     choice == 1 then
		ya.notify { title = "y_launcher", content = "No changes made.", level = "info", timeout = 3 }
	elseif choice == 2 then do_replace(path, existing, shell_key, cfg)
	elseif choice == 3 then write_wrapper(path, cfg.content, true)
	elseif choice == 4 then show_file(path)
	end
end

return M
