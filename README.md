# conf-helper.yazi

A growing collection of Yazi configuration helpers, bundled as a single plugin with a function menu.

## Functions

| Function         | Description                                               | Platform     |
|------------------|-----------------------------------------------------------|--------------|
| `y_launcher`     | Install the `y` shell wrapper into your shell profile     | All          |
| `yazi_file_one`  | Find Git's `file.exe` and set `YAZI_FILE_ONE`             | Windows only |

---

## Installation

**Via `ya pkg` (recommended):**
```sh
ya pkg add 255ribeio/conf-helper
```

**Manual:**

Copy the plugin folder to your Yazi plugins directory:

| Platform | Path |
|----------|------|
| Windows  | `%AppData%\yazi\config\plugins\conf-helper.yazi\` |
| Linux / macOS | `~/.config/yazi/plugins/conf-helper.yazi/` |
| WSL      | `~/.config/yazi/plugins/conf-helper.yazi/` |

---

## Usage

### Menu mode

Open the function picker inside Yazi:

```toml
# keymap.toml
[[mgr.prepend_keymap]]
on   = ["<C-h>"]
run  = "plugin conf-helper"
desc = "Yazi config helpers"
```

Press the bound key → a menu appears listing all available functions.

### Direct mode (bypass the menu)

Call a specific function directly by passing its name as an argument:

```toml
# keymap.toml
[[mgr.prepend_keymap]]
on   = ["g", "y"]
run  = "plugin conf-helper -- y_launcher"
desc = "Install y shell wrapper"

[[mgr.prepend_keymap]]
on   = ["g", "f"]
run  = "plugin conf-helper -- yazi_file_one"
desc = "Set YAZI_FILE_ONE from Git"
```

You can also call functions from the Yazi command prompt (`:`):

```
plugin conf-helper -- y_launcher
plugin conf-helper -- yazi_file_one
```

---

## Functions

### `y_launcher`

Detects your current shell and installs the `y` wrapper function into the appropriate profile file.

**Supported shells:**

| Shell      | Profile file |
|------------|--------------|
| PowerShell | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` |
| Bash       | `~/.bashrc` |
| Zsh        | `~/.zshrc` |
| Fish       | `~/.config/fish/config.fish` |
| CMD        | `~/bin/y.bat` |

**WSL1 / WSL2:** Fully supported. The plugin detects the WSL version and distro name, skips the `$PSModulePath` leak from Windows, and installs the correct Linux shell wrapper.

**Behaviour:**
- Profile missing → offers to create it
- Profile exists, no `y` → offers to append the wrapper
- `y` already present → shows a menu: **Ignore / Replace / Append / Show**

**After installation**, use `y` instead of `yazi`:

```sh
y           # open Yazi
# navigate...
q           # quit AND cd to the current directory
Q           # quit WITHOUT changing directory
```

---

### `yazi_file_one`

Searches for Git's bundled `file.exe` (required by Yazi on Windows for MIME-type detection) and sets the `YAZI_FILE_ONE` environment variable.

**Windows only.** On Linux and macOS, `file` is a native system binary that Yazi finds automatically — no environment variable is needed. Running this function on non-Windows will show an informational message and exit.

**Search order:**

1. `git --exec-path` (walks up to find `usr\bin\file.exe`)
2. Windows Registry (`HKLM:\SOFTWARE\GitForWindows`)
3. Known install paths (`C:\Program Files\Git\...`)
4. Scoop (`%USERPROFILE%\scoop\apps\git\current\...`)
5. `where git` (fallback)

**Scope options (asked at runtime):**

| Option | Description |
|--------|-------------|
| User (recommended) | Permanent, current user only, no Admin required |
| System-wide | Permanent, all users, requires Administrator |
| Session only | Active terminal only, not persistent |

After setting, restart your terminal for the variable to take effect.

---

## Adding more functions

The plugin is designed to grow. To add a new function:

1. Create `funcs/my_func.lua` with a `run()` entry point:

```lua
local M = {}
function M.run()
    -- your logic here
end
return M
```

2. Register it in `main.lua`'s `FUNCS` table:

```lua
{
    id   = "my_func",
    key  = "m",           -- key shown in the menu
    desc = "my_func — What it does",
    mod  = "funcs/my_func",
},
```

That's it — it will appear in the menu automatically and support direct calls via `plugin conf-helper -- my_func`.

---

## Publishing

Update `package.toml` with your GitHub username and run:

```sh
ya pkg publish
```

Users can then install with:

```sh
ya pkg add 255ribeiro/conf-helper
```

---

## License

MIT
