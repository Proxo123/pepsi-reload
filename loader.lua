--[[
  Pepsi Reload — paste into your executor:

  loadstring(game:HttpGet("https://raw.githubusercontent.com/Proxo123/pepsi-reload/0af559d/loader.lua"))()

  Pin changes each release so Roblox HttpGet does not serve a stale loader cache.
]]

if getgenv()._PepsiReloadUnload then
	pcall(getgenv()._PepsiReloadUnload)
end

-- Pinned commit so Roblox HttpGet does not serve stale branch cache
local COMMIT = "77586e6"
local REPO = "https://raw.githubusercontent.com/Proxo123/pepsi-reload/" .. COMMIT .. "/"

getgenv().PEPSI_REPO = REPO
getgenv().PEPSI_CACHE_BUST = "v54"

local ok, err = pcall(function()
	loadstring(game:HttpGet(REPO .. "src/bootstrap.lua"))()
end)

if not ok then
	warn("[Pepsi Reload] Loader failed:", err)
end
