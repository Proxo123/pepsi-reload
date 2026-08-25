local Flags = {}

function Flags.make(libraryFlags, defaults, library)
	local toggleCache = {}
	local toggleCacheTime = 0
	local TOGGLE_CACHE_TTL = 0.05

	local function refreshToggleCache()
		local now = tick()
		if now - toggleCacheTime < TOGGLE_CACHE_TTL then
			return
		end
		toggleCacheTime = now
		table.clear(toggleCache)
		if not library then
			return
		end
		local function walk(node, depth)
			if depth > 16 or type(node) ~= "table" then
				return
			end
			local flags = node.Flags
			if type(flags) == "table" then
				for flagName, toggle in pairs(flags) do
					if type(toggle) == "table" and toggle.Options and toggle.Options.Value ~= nil then
						toggleCache[flagName] = toggle.Options.Value
					end
				end
			end
			for _, child in pairs(node) do
				walk(child, depth + 1)
			end
		end
		walk(library, 0)
	end

	local function resolveFlag(name)
		local v = libraryFlags[name]
		if type(v) == "table" then
			if v.Value ~= nil then
				return v.Value
			end
			if v.Options and v.Options.Value ~= nil then
				return v.Options.Value
			end
		end
		if v ~= nil then
			return v
		end
		refreshToggleCache()
		return toggleCache[name]
	end

	local function flagVal(name, default)
		local v = resolveFlag(name)
		if v == nil then
			return default
		end
		return v
	end

	local function flagOn(name, default)
		if default == nil then
			default = false
		end
		local v = resolveFlag(name)
		if v == nil then
			return default
		end
		return v == true
	end

	local function teamCheckOn(kind)
		if kind == "esp" then
			return flagOn("ESPTeamCheck") or flagOn("TeamCheck")
		end
		return flagOn("AimTeamCheck") or flagOn("TeamCheck")
	end

	return {
		flagVal = flagVal,
		flagOn = flagOn,
		teamCheckOn = teamCheckOn,
		defaults = defaults,
	}
end

return Flags
