local repo = getgenv().PEPSI_REPO
if type(repo) ~= "string" or repo == "" then
	error("[Pepsi Reload] PEPSI_REPO not set. Run loader.lua first.")
end

local ok, src = pcall(game.HttpGet, game, repo .. "src/core/http.lua")
if not ok then
	error("[Pepsi Reload] Failed to fetch http module")
end

local Http = loadstring(src)()
local import = Http.create(repo)

local okMain, errMain = pcall(function()
	import("src/main").start(import)
end)
if not okMain then
	error("[Pepsi Reload] Bootstrap failed: " .. tostring(errMain))
end

return true
