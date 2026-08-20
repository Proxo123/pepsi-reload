# pepsi-reload

Modular Pepsi menu for **Reload BR** — loaded via GitHub `HttpGet` + `loadstring`.

## Quick start

1. **Fork / clone** this repo and push to GitHub (must be **public** for free raw URLs).
2. Edit `loader.lua` and `src/core/config.lua` — replace `YOUR_GITHUB_USERNAME` with your GitHub username.
3. In your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/pepsi-reload/main/loader.lua"))()
```

## Project layout

```
loader.lua              # Tiny entry (~20 lines) — only file you need to execute
src/
  bootstrap.lua         # Fetches modules and starts main
  main.lua              # Wires modules, update loop, unload
  core/
    config.lua          # Version, defaults, repo URL
    http.lua            # GitHub module loader (import shim)
    flags.lua           # Menu flag helpers
  game/
    reload.lua          # Reload-specific game API (guns, squad, models)
  features/
    drawing.lua         # ESP drawing helpers
    targets.lua         # Target collection + visibility
    combat.lua          # No spread / silent / recoil hooks
    aim.lua             # Aimbot + silent target selection
    esp.lua             # ESP render pass
  ui/
    menu.lua            # Pepsi UI tabs/sections
```

## Controls

| Key | Action |
|-----|--------|
| RightShift | Open menu |
| U | Toggle ESP |
| RMB hold | Visible aimbot (default) |

Unload: `getgenv()._PepsiReloadUnload()`

## Publish to GitHub

```powershell
cd C:\Users\ilove\Projects\pepsi-reload
git init -b main
git add -A
git commit -m "Initial modular Pepsi Reload loader"
gh repo create pepsi-reload --public --source=. --remote=origin --push
```

Then update `REPO` in `loader.lua` and push again.

## Local dev (Potassium)

Until GitHub is live, you can still test the monolith at `C:\Users\ilove\pepsi_v11.lua`, or deploy modules via chunked `HttpGet` simulation using your repo URL after first push.
