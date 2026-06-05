# conf_helper.yazi — Development Context

## Last known status

Development is moving to a local folder. This file captures the last diagnostic
state so work can continue without losing context.

---

## Bugs fixed in this session

### 1 — Exit status 1 on cancel / menu quit
**Symptom:** Plugin exited with status 1 whenever the user pressed `Esc` or `q`
in `ya.which` or `ya.confirm`.

**Root causes found:**
- `require("funcs/y_launcher")` used slash notation — Yazi's module system
  requires **dot notation**: `require("funcs.y_launcher")`. The slash caused a
  silent load failure which Yazi reported as exit status 1.
- `ya.which` returning `nil` on cancel was not handled as a clean exit — Lua
  propagated the unhandled nil as an error.

**Fix applied (main.lua):**
- Changed all `require` paths to dot notation: `"funcs.y_launcher"`,
  `"funcs.yazi_file_one"`.
- Wrapped all `require()` and `mod.run()` calls in `pcall` so any Lua error
  surfaces as a `ya.notify` error notification instead of a crash.
- `nil` return from `ya.which` (Esc) and the `"q"` candidate are now both
  treated as clean exits (`return` with no error).

---

## Known limitations / TODO

- ~~`y_launcher` Replace mode uses pattern matching~~ — **fixed**: `do_replace`
  now uses `split_lines` + `find_block_end_line` (brace counting for
  PowerShell/Bash/Zsh, keyword depth for Fish). Falls back to append when block
  boundaries cannot be determined. Comment-only lines are skipped during brace
  counting to avoid false positives.

- `yazi_file_one` session-only scope sets `$env:YAZI_FILE_ONE` inside a
  PowerShell child process, which does NOT affect the parent shell. This is
  noted in the notification but is a fundamental limitation — consider removing
  that option or replacing it with instructions to set it manually.

- No test suite. All testing has been manual. A `tests/` folder with edge-case
  scripts would be useful before publishing to `ya pkg`.

- `package.toml` still has `<your-username>` placeholder in the `repository`
  field — update before publishing.

---

## File structure

```
conf_helper.yazi/
├── main.lua                  ← entry point: menu + direct dispatch via job.args[1]
├── funcs/
│   ├── y_launcher.lua        ← installs `y` shell wrapper (all platforms + WSL1/2)
│   └── yazi_file_one.lua     ← finds Git file.exe, sets YAZI_FILE_ONE (Windows only)
├── package.toml              ← ya pkg metadata (update repository + author)
├── .gitignore
├── LICENSE                   ← MIT
├── README.md
└── context.md                ← this file
```

---

## Calling convention

| Mode        | Command                                      |
|-------------|----------------------------------------------|
| Menu picker | `plugin conf_helper`                         |
| Direct      | `plugin conf_helper -- y_launcher`           |
| Direct      | `plugin conf_helper -- yazi_file_one`        |

Keymap example (`keymap.toml`):
```toml
[[mgr.prepend_keymap]]
on   = ["<C-h>"]
run  = "plugin conf_helper"
desc = "Yazi config helpers"

[[mgr.prepend_keymap]]
on   = ["g", "y"]
run  = "plugin conf_helper -- y_launcher"
desc = "Install y shell wrapper"

[[mgr.prepend_keymap]]
on   = ["g", "f"]
run  = "plugin conf_helper -- yazi_file_one"
desc = "Set YAZI_FILE_ONE from Git"
```

---

## Adding a new function

1. Create `funcs/my_func.lua` with a `run()` entry:
```lua
local M = {}
function M.run()
    -- logic here
end
return M
```

2. Register in `main.lua` FUNCS table:
```lua
{
    id   = "my_func",
    key  = "m",
    desc = "my_func — What it does",
    mod  = "funcs.my_func",   -- dot notation, not slash
},
```

---

## Platform support matrix

| Platform         | y_launcher | yazi_file_one |
|------------------|-----------|---------------|
| Windows (PS)     | ✅        | ✅            |
| Windows (CMD)    | ✅        | ✅            |
| Linux (Bash)     | ✅        | ⚠️ not needed  |
| Linux (Zsh)      | ✅        | ⚠️ not needed  |
| Linux (Fish)     | ✅        | ⚠️ not needed  |
| macOS            | ✅        | ⚠️ not needed  |
| WSL1             | ✅        | ⚠️ not needed  |
| WSL2             | ✅        | ⚠️ not needed  |

`yazi_file_one` on non-Windows shows an informational notification and exits.
