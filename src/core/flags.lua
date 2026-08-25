local Flags = {}

function Flags.make(libraryFlags, defaults, library)
	local toggleCache = {}
	local toggleCacheTime = 0
	local TOGGLE_CACHE_TTL = 0.1

	local function readToggle(toggle, flagName)
		if type(toggle) ~= "table" or not toggle.Options then
			return
		end
		if toggle.Options.Value ~= nil then
			toggleCache[flagName] = toggle.Options.Value
		end
	end

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

		if type(library.flags) == "table" then
			for flagName, value in pairs(library.flags) do
				if type(value) == "table" then
					readToggle(value, flagName)
				elseif value ~= nil then
					toggleCache[flagName] = value
				end
			end
		end

		if type(library.objects) == "table" then
			for _, obj in ipairs(library.objects) do
				if type(obj) == "table" then
					local flagName = obj.Flag or (obj.Options and obj.Options.Flag)
					if type(flagName) == "string" then
						readToggle(obj, flagName)
					end
					if type(obj.Flags) == "table" then
						for name, toggle in pairs(obj.Flags) do
							readToggle(toggle, name)
						end
					end
				end
			end
		end
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
		refresh = refreshToggleCache,
	}
end

return Flags
