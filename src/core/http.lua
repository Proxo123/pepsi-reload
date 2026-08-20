local Http = {}

function Http.create(repoBase)
	local cache = {}
	local base = repoBase

	local function import(path)
		if cache[path] then
			return cache[path]
		end
		local url = base .. path .. ".lua"
		local ok, src = pcall(game.HttpGet, game, url)
		if not ok or type(src) ~= "string" then
			error("[Pepsi Reload] HttpGet failed: " .. tostring(path))
		end
		local fn, err = loadstring(src)
		if not fn then
			error("[Pepsi Reload] loadstring failed: " .. tostring(path) .. " -> " .. tostring(err))
		end
		local mod = fn()
		cache[path] = mod
		return mod
	end

	return import
end

return Http
