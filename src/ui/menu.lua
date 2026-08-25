local Menu = {}

function Menu.create(ctx)
	local defaults = ctx.config.DEFAULTS
	local version = ctx.config.VERSION
	local ConfigStore = ctx.configStore

	local window = ctx.library:CreateWindow({
		Name = "Pepsi Reload",
		Themeable = { Info = "Reload " .. version, Credit = true },
	})

	local aimTab = window:CreateTab({ Name = "Aimbot" })
	local silentTab = window:CreateTab({ Name = "Silent" })
	local combatTab = window:CreateTab({ Name = "Combat" })
	local buildTab = window:CreateTab({ Name = "Build" })
	local espTab = window:CreateTab({ Name = "ESP" })
	local colorTab = window:CreateTab({ Name = "Colors" })

	local aimMain = aimTab:CreateSection({ Name = "Aimbot", Side = "Left" })
	local aimSet = aimTab:CreateSection({ Name = "Settings", Side = "Right" })

	local silentMain = silentTab:CreateSection({ Name = "Silent Aim", Side = "Left" })
	local silentSet = silentTab:CreateSection({ Name = "Settings", Side = "Right" })

	local combatSec = combatTab:CreateSection({ Name = "Gun Mods", Side = "Left" })

	local buildSec = buildTab:CreateSection({ Name = "Build Tests", Side = "Left" })
	local buildSet = buildTab:CreateSection({ Name = "Settings", Side = "Right" })

	local espMain = espTab:CreateSection({ Name = "ESP", Side = "Left" })
	local espSet = espTab:CreateSection({ Name = "Settings", Side = "Right" })

	local colSec = colorTab:CreateSection({ Name = "Colors", Side = "Left" })

	aimMain:AddToggle({ Name = "Enabled", Flag = "AimEnabled", Value = true })
	aimMain:AddToggle({ Name = "Squad Check", Flag = "SquadCheck", Value = true })
	aimMain:AddToggle({ Name = "Wall Check", Flag = "AimWallCheck", Value = true })
	aimMain:AddToggle({ Name = "Show FOV", Flag = "AimShowFOV", Value = true })
	aimMain:AddDropdown({
		Name = "Activation",
		Flag = "AimMode",
		Value = "Mouse2 Held",
		List = { "Mouse2 Held", "Mouse1 Held", "Always" },
	})
	aimMain:AddDropdown({ Name = "Target Part", Flag = "AimPart", Value = "Head", List = { "Head", "Torso" } })

	aimSet:AddSlider({
		Name = "Lock Strength",
		Flag = "AimSmoothness",
		Value = defaults.AimSmoothness,
		Min = 0.05,
		Max = 1,
		Precise = 2,
		Textbox = true,
	})
	aimSet:AddSlider({ Name = "FOV", Flag = "AimFOV", Value = defaults.AimFOV, Min = 10, Max = 500, Textbox = true })
	aimSet:AddSlider({ Name = "Range", Flag = "AimRange", Value = defaults.AimRange, Min = 50, Max = 2500, Textbox = true })

	silentMain:AddToggle({ Name = "Enabled", Flag = "SilentAim", Value = false })
	silentMain:AddToggle({ Name = "Target Tracer", Flag = "SilentHandTracer", Value = false })
	silentMain:AddToggle({ Name = "Wallbang (Bots)", Flag = "Wallbang", Value = false })

	silentSet:AddSlider({
		Name = "Silent FOV",
		Flag = "SilentFOV",
		Value = defaults.SilentFOV,
		Min = 50,
		Max = 1200,
		Textbox = true,
	})
	silentSet:AddSlider({
		Name = "Silent Angle",
		Flag = "SilentAngleFOV",
		Value = defaults.SilentAngleFOV,
		Min = 5,
		Max = 90,
		Textbox = true,
	})

	combatSec:AddToggle({ Name = "No Spread", Flag = "NoSpread", Value = false })
	combatSec:AddToggle({ Name = "No Recoil", Flag = "NoRecoil", Value = false })
	combatSec:AddToggle({ Name = "Instant Reload", Flag = "InstantReload", Value = false })

	buildSec:AddToggle({ Name = "Build Tests Enabled", Flag = "BuildTestEnabled", Value = false })
	buildSec:AddToggle({
		Name = "Wall Spam (crosshair)",
		Flag = "BuildWallHotkey",
		Value = false,
		Keybind = { Value = Enum.KeyCode.B, Mode = "Press" },
	})
	buildSec:AddToggle({
		Name = "Pyramid Spam (off-grid)",
		Flag = "BuildPyramidHotkey",
		Value = false,
		Keybind = { Value = Enum.KeyCode.N, Mode = "Press" },
	})

	buildSet:AddSlider({
		Name = "Target FOV",
		Flag = "BuildTargetFOV",
		Value = defaults.BuildTargetFOV,
		Min = 50,
		Max = 600,
		Textbox = true,
	})
	buildSet:AddSlider({
		Name = "Wall Count",
		Flag = "BuildWallCount",
		Value = defaults.BuildWallCount,
		Min = 4,
		Max = 24,
		Textbox = true,
	})
	buildSet:AddSlider({
		Name = "Pyramid Count",
		Flag = "BuildPyramidCount",
		Value = defaults.BuildPyramidCount,
		Min = 1,
		Max = 12,
		Textbox = true,
	})
	buildSet:AddSlider({
		Name = "Pyramid Yaw Offset",
		Flag = "BuildPyramidYaw",
		Value = defaults.BuildPyramidYaw,
		Min = -180,
		Max = 180,
		Textbox = true,
	})

	espMain:AddToggle({
		Name = "Enabled",
		Flag = "ESPEnabled",
		Value = true,
		Keybind = { Value = Enum.KeyCode.U, Mode = "Toggle" },
	})
	espMain:AddToggle({ Name = "Players", Flag = "ShowPlayers", Value = true })
	espMain:AddToggle({ Name = "Bots", Flag = "ShowBots", Value = true })
	espMain:AddToggle({ Name = "Boxes", Flag = "ESPBoxes", Value = true })
	espMain:AddToggle({ Name = "Names", Flag = "ESPNames", Value = true })
	espMain:AddToggle({ Name = "Distance", Flag = "ESPDistance", Value = true })
	espMain:AddToggle({ Name = "Health", Flag = "ESPHealth", Value = true })
	espMain:AddToggle({ Name = "Tracers", Flag = "ESPTracers", Value = false })
	espMain:AddToggle({ Name = "Chams", Flag = "ESPChams", Value = false })

	espSet:AddSlider({
		Name = "Max Distance",
		Flag = "ESPMaxDistance",
		Value = defaults.ESPMaxDistance,
		Min = 100,
		Max = 5000,
		Textbox = true,
	})

	colSec:AddColorpicker({ Name = "Players", Flag = "PlayerColor", Value = Color3.fromRGB(255, 70, 70) })
	colSec:AddColorpicker({ Name = "Bots", Flag = "BotColor", Value = Color3.fromRGB(255, 170, 50) })
	colSec:AddColorpicker({ Name = "Squad / Team", Flag = "SquadColor", Value = Color3.fromRGB(80, 220, 120) })
	colSec:AddColorpicker({ Name = "FOV Circle", Flag = "AimFOVColor", Value = Color3.fromRGB(255, 255, 255) })
	colSec:AddColorpicker({ Name = "Silent Tracer", Flag = "SilentTracerColor", Value = Color3.fromRGB(255, 80, 255) })

	local settingsTab = window:CreateTab({ Name = "Settings" })
	local configSec = settingsTab:CreateSection({ Name = "Configs", Side = "Left" })
	local autoloadSec = settingsTab:CreateSection({ Name = "Autoload", Side = "Right" })

	local workspaceName = ctx.config.CONFIG_WORKSPACE
	local defaultProfile = ctx.config.DEFAULT_CONFIG
	local autoloadProfile = ConfigStore.getAutoload(workspaceName)

	local persistence = configSec:AddPersistence({
		Name = "Config Name",
		Flag = "ConfigProfile",
		Workspace = workspaceName,
		Suffix = "Config",
		Flags = true,
		Value = autoloadProfile or defaultProfile,
	})

	autoloadSec:AddToggle({
		Name = "Autoload On Startup",
		Flag = "ConfigAutoloadEnabled",
		Value = autoloadProfile ~= nil,
		Callback = function(enabled)
			if enabled then
				local profile = ConfigStore.profileName(ctx.library) or defaultProfile
				if ConfigStore.setAutoload(workspaceName, profile) then
					ctx.library:Notify({ Text = "Autoload set to: " .. profile, Time = 4 })
				end
			else
				ConfigStore.clearAutoload(workspaceName)
				ctx.library:Notify({ Text = "Autoload disabled.", Time = 3 })
			end
		end,
	})

	autoloadSec:AddButton({
		Name = "Use Current As Autoload",
		Callback = function()
			local profile = ConfigStore.profileName(ctx.library) or defaultProfile
			if ConfigStore.setAutoload(workspaceName, profile) then
				local flag = ctx.library.flags.ConfigAutoloadEnabled
				if type(flag) == "table" and flag.Set then
					flag:Set(true)
				end
				ctx.library:Notify({ Text = "Autoload set to: " .. profile, Time = 4 })
			end
		end,
	})

	pcall(function()
		window:CreateDesigner({ Credit = true, Info = "Reload " .. version })
	end)

	task.defer(function()
		ConfigStore.tryAutoload(persistence, ctx.config, ctx.library)
	end)

	return {
		window = window,
		persistence = persistence,
	}
end

return Menu
