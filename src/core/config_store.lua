local ConfigStore = {}

local STORE_ROOT = "./Pepsi Lib"

local function hasFileApi()
	return isfolder and makefolder and isfile and readfile and writefile
end

function ConfigStore.autoloadPath(workspace)
	return STORE_ROOT .. "/" .. workspace .. "/_autoload.txt"
end

function ConfigStore.ensureWorkspace(workspace)
	if not hasFileApi() then
		return false
	end
	if not isfolder(STORE_ROOT) then
		makefolder(STORE_ROOT)
	end
	local dir = STORE_ROOT .. "/" .. workspace
	if not isfolder(dir) then
		makefolder(dir)
	end
	return isfolder(dir)
end

function ConfigStore.getAutoload(workspace)
	if not (hasFileApi() and workspace) then
		return nil
	end
	local path = ConfigStore.autoloadPath(workspace)
	if not isfile(path) then
		return nil
	end
	local name = readfile(path)
	if type(name) ~= "string" then
		return nil
	end
	name = name:match("^%s*(.-)%s*$")
	if not name or name == "" then
		return nil
	end
	return name
end

function ConfigStore.setAutoload(workspace, profile)
	if not (hasFileApi() and workspace and profile and profile ~= "") then
		return false
	end
	if not ConfigStore.ensureWorkspace(workspace) then
		return false
	end
	writefile(ConfigStore.autoloadPath(workspace), profile)
	return true
end

function ConfigStore.clearAutoload(workspace)
	if not (hasFileApi() and workspace) then
		return false
	end
	local path = ConfigStore.autoloadPath(workspace)
	if isfile(path) and delfile then
		delfile(path)
	end
	return true
end

function ConfigStore.profileName(library)
	if not library or not library.flags then
		return nil
	end
	local value = library.flags.ConfigProfile
	if type(value) == "table" then
		value = value.Value
	end
	if type(value) ~= "string" then
		return nil
	end
	value = value:match("^%s*(.-)%s*$")
	if not value or value == "" then
		return nil
	end
	return value
end

function ConfigStore.tryAutoload(persistence, config, library)
	if not (persistence and persistence.LoadFile and config) then
		return false
	end
	local name = ConfigStore.getAutoload(config.CONFIG_WORKSPACE)
	if not name then
		return false
	end
	local ok, err = pcall(function()
		persistence:LoadFile(name)
	end)
	if not ok then
		warn("[Pepsi Reload] Autoload failed:", err)
		return false
	end
	if library and library.Notify then
		library:Notify({ Text = "Autoloaded config: " .. name, Time = 4 })
	end
	return true
end

return ConfigStore
