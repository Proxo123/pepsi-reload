--[[
  Pepsi Reload — GitHub loader (paste into your executor)

  1. Push this repo to GitHub
  2. Set REPO below to your raw.githubusercontent.com URL
  3. Execute this script (or save as auto-exec)
]]

if getgenv()._PepsiReloadUnload then
	pcall(getgenv()._PepsiReloadUnload)
end

-- Pinned commit so Roblox HttpGet does not serve stale branch cache
local COMMIT = "6b76045"
local REPO = "https://raw.githubusercontent.com/Proxo123/pepsi-reload/" .. COMMIT .. "/"

getgenv().PEPSI_REPO = REPO
getgenv().PEPSI_CACHE_BUST = "v22b"

local ok, err = pcall(function()
	loadstring(game:HttpGet(REPO .. "src/bootstrap.lua"))()
end)

if not ok then
	warn("[Pepsi Reload] Loader failed:", err)
end
