import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[1]
override_paths = [
    "src/core/config.lua",
    "src/core/config_store.lua",
    "src/main.lua",
    "src/ui/menu.lua",
]
overrides = {}
for rel in override_paths:
    key = rel.replace(".lua", "").replace("\\", "/")
    overrides[key] = (root / rel).read_text(encoding="utf-8")

repo = "https://raw.githubusercontent.com/Proxo123/pepsi-reload/main/"
loader = f"""if getgenv()._PepsiReloadUnload then
\tpcall(getgenv()._PepsiReloadUnload)
end

getgenv().PEPSI_CACHE_BUST = "v50-local"
local REPO = "{repo}"
local HttpService = game:GetService("HttpService")
local OVERRIDES = HttpService:JSONDecode([[{json.dumps(overrides)}]])

local function makeImport(base)
\tlocal cache = {{}}
\treturn function(path)
\t\tif cache[path] then
\t\t\treturn cache[path]
\t\tend
\t\tlocal src = OVERRIDES[path]
\t\tif not src then
\t\t\tlocal url = base .. path .. ".lua?cb=" .. tostring(getgenv().PEPSI_CACHE_BUST)
\t\t\tlocal ok, fetched = pcall(game.HttpGet, game, url)
\t\t\tif not ok or type(fetched) ~= "string" then
\t\t\t\terror("[Pepsi Reload] HttpGet failed: " .. tostring(path))
\t\t\tend
\t\t\tsrc = fetched
\t\tend
\t\tlocal fn, err = loadstring(src)
\t\tif not fn then
\t\t\terror("[Pepsi Reload] loadstring failed: " .. tostring(path) .. " -> " .. tostring(err))
\t\tend
\t\tlocal mod = fn()
\t\tcache[path] = mod
\t\treturn mod
\tend
end

local ok, err = pcall(function()
\tmakeImport(REPO)("src/main").start(makeImport(REPO))
end)
if not ok then
\twarn("[Pepsi Reload] Loader failed:", err)
end
"""

out = root / ".potassium_bundle.lua"
out.write_text(loader, encoding="utf-8")
print(out)
print("bytes", out.stat().st_size)
