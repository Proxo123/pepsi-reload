local Menu = {}

function Menu.create(ctx)
	local defaults = ctx.config.DEFAULTS
	local version = ctx.config.VERSION
	local ConfigStore = ctx.configStore

	local window = ctx.library:CreateWindow({
		Name = "Pepsi Hub",
		Themeable = { Info = version, Credit = true },
	})

	local aimTab = window:CreateTab({ Name = "Aimbot" })
	local espTab = window:CreateTab({ Name = "ESP" })
	local colorTab = window:CreateTab({ Name = "Colors" })
	local settingsTab = window:CreateTab({ Name = "Settings" })

	local aimMain = aimTab:CreateSection({ Name = "Aimbot", Side = "Left" })
	local aimSet = aimTab:CreateSection({ Name = "Tuning", Side = "Right" })

	local espMain = espTab:CreateSection({ Name = "ESP", Side = "Left" })
	local espSet = espTab:CreateSection({ Name = "Display", Side = "Right" })

	local colSec = colorTab:CreateSection({ Name = "Colors", Side = "Left" })
	local configSec = settingsTab:CreateSection({ Name = "Configs", Side = "Left" })
	local miscSec = settingsTab:CreateSection({ Name = "Arsenal", Side = "Right" })
	local autoloadSec = settingsTab:CreateSection({ Name = "Autoload", Side = "Right" })

	aimMain:AddToggle({ Name = "Enabled", Flag = "AimEnabled", Value = false })
	aimMain:AddToggle({ Name = "Team Check", Flag = "AimTeamCheck", Value = false })
	aimMain:AddToggle({ Name = "Wall Check", Flag = "AimWallCheck", Value = true })
	aimMain:AddToggle({ Name = "Sticky Target", Flag = "AimSticky", Value = true })
	aimMain:AddToggle({ Name = "Show FOV", Flag = "AimShowFOV", Value = true })
	aimMain:AddDropdown({
		Name = "Activation",
		Flag = "AimMode",
		Value = "Mouse2 Held",
		List = { "Mouse2 Held", "Mouse1 Held", "Always" },
	})
	aimMain:AddDropdown({
		Name = "Target Part",
		Flag = "AimPart",
		Value = "Head",
		List = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Random" },
	})
	aimMain:AddDropdown({
		Name = "Priority",
		Flag = "AimPriority",
		Value = "Crosshair",
		List = { "Crosshair", "Distance" },
	})

	aimSet:AddSlider({
		Name = "Smoothness",
		Flag = "AimSmoothness",
		Value = defaults.AimSmoothness,
		Min = 0.05,
		Max = 1,
		Precise = 2,
		Textbox = true,
	})
	aimSet:AddSlider({ Name = "FOV", Flag = "AimFOV", Value = defaults.AimFOV, Min = 10, Max = 800, Textbox = true })
	aimSet:AddSlider({ Name = "Range", Flag = "AimRange", Value = defaults.AimRange, Min = 50, Max = 5000, Textbox = true })
	aimSet:AddSlider({ Name = "FOV Thickness", Flag = "AimFOVThickness", Value = 1, Min = 1, Max = 4, Textbox = true })

	espMain:AddToggle({
		Name = "Enabled",
		Flag = "ESPEnabled",
		Value = false,
		Keybind = { Value = Enum.KeyCode.U, Mode = "Toggle" },
	})
	espMain:AddToggle({ Name = "Team Check", Flag = "ESPTeamCheck", Value = false })
	espMain:AddToggle({ Name = "Players", Flag = "ShowPlayers", Value = true })
	espMain:AddToggle({ Name = "NPCs", Flag = "ShowNPCs", Value = false })
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
		Min = 50,
		Max = 10000,
		Textbox = true,
	})
	espSet:AddSlider({
		Name = "Text Size",
		Flag = "ESPTextSize",
		Value = defaults.ESPTextSize,
		Min = 10,
		Max = 24,
		Textbox = true,
	})
	espSet:AddSlider({
		Name = "Box Thickness",
		Flag = "ESPBoxThickness",
		Value = defaults.ESPBoxThickness,
		Min = 1,
		Max = 4,
		Textbox = true,
	})
	espSet:AddDropdown({
		Name = "Tracer Origin",
		Flag = "ESPTracerOrigin",
		Value = "Bottom",
		List = { "Bottom", "Center", "Top", "Mouse" },
	})

	miscSec:AddToggle({
		Name = "Fake Saber In Melee Locker",
		Flag = "FakeMeleeEnabled",
		Value = true,
		Callback = function(enabled)
			if not ctx.fakeMelee then
				return
			end
			if enabled then
				ctx.fakeMelee.inject()
			else
				ctx.fakeMelee.clear()
			end
		end,
	})

	colSec:AddColorpicker({ Name = "Players", Flag = "PlayerColor", Value = Color3.fromRGB(255, 70, 70) })
	colSec:AddColorpicker({ Name = "NPCs", Flag = "NPCColor", Value = Color3.fromRGB(255, 170, 50) })
	colSec:AddColorpicker({ Name = "Team", Flag = "TeamColor", Value = Color3.fromRGB(80, 220, 120) })
	colSec:AddColorpicker({ Name = "FOV Circle", Flag = "AimFOVColor", Value = Color3.fromRGB(255, 255, 255) })

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
		window:CreateDesigner({ Credit = true, Info = version })
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
