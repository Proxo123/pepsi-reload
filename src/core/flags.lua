local Flags = {}

function Flags.make(libraryFlags, defaults)
	local function flagVal(name, default)
		local v = libraryFlags[name]
		if type(v) == "table" and v.Value ~= nil then
			v = v.Value
		end
		if v == nil then
			return default
		end
		return v
	end

	local function flagOn(name, default)
		if default == nil then
			default = false
		end
		local v = flagVal(name, default)
		return v == true
	end

	return {
		flagVal = flagVal,
		flagOn = flagOn,
		defaults = defaults,
	}
end

return Flags
