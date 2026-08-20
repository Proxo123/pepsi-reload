local Menu = {}

function Menu.create(ctx)
	local defaults = ctx.config.DEFAULTS
	local version = ctx.config.VERSION

	local window = ctx.library:CreateWindow({
		Name = "Pepsi Reload",
		Themeable = { Info = "Reload BR " .. version, Credit = true },
	})
	local aimTab = window:CreateTab({ Name = "Aimbot" })
	local visTab = window:CreateTab({ Name = "Visuals" })
	local aimSec = aimTab:CreateSection({ Name = "Aimbot", Side = "Left" })
	local aimSet = aimTab:CreateSection({ Name = "Settings", Side = "Right" })
	local espSec = visTab:CreateSection({ Name = "ESP", Side = "Left" })
	local colSec = visTab:CreateSection({ Name = "Colors", Side = "Right" })

	aimSec:AddToggle({ Name = "Enabled", Flag = "AimEnabled", Value = true })
	aimSec:AddToggle({ Name = "No Spread", Flag = "NoSpread", Value = false })
	aimSec:AddToggle({ Name = "No Recoil", Flag = "NoRecoil", Value = false })
	aimSec:AddToggle({ Name = "Silent Aim", Flag = "SilentAim", Value = false })
	aimSec:AddToggle({ Name = "Squad Check", Flag = "SquadCheck", Value = true })
	aimSec:AddToggle({ Name = "Wall Check", Flag = "AimWallCheck", Value = true })
	aimSec:AddToggle({ Name = "Show FOV", Flag = "AimShowFOV", Value = true })
	aimSec:AddDropdown({
		Name = "Activation",
		Flag = "AimMode",
		Value = "Mouse2 Held",
		List = { "Mouse2 Held", "Mouse1 Held", "Always" },
	})
	aimSec:AddDropdown({ Name = "Target Part", Flag = "AimPart", Value = "Head", List = { "Head", "Torso" } })

	aimSet:AddSlider({
		Name = "Lock Strength",
		Flag = "AimSmoothness",
		Value = defaults.AimSmoothness,
		Min = 0.05,
		Max = 1,
		Precise = 2,
		Textbox = true,
	})
	aimSet:AddSlider({
		Name = "Prediction",
		Flag = "AimPrediction",
		Value = defaults.AimPrediction,
		Min = 0,
		Max = 0.35,
		Precise = 2,
		Textbox = true,
	})
	aimSet:AddSlider({ Name = "FOV", Flag = "AimFOV", Value = defaults.AimFOV, Min = 10, Max = 500, Textbox = true })
	aimSet:AddSlider({
		Name = "Silent FOV",
		Flag = "SilentFOV",
		Value = defaults.SilentFOV,
		Min = 50,
		Max = 1200,
		Textbox = true,
	})
	aimSet:AddSlider({
		Name = "Silent Angle",
		Flag = "SilentAngleFOV",
		Value = defaults.SilentAngleFOV,
		Min = 5,
		Max = 90,
		Textbox = true,
	})
	aimSet:AddSlider({ Name = "Range", Flag = "AimRange", Value = defaults.AimRange, Min = 50, Max = 2500, Textbox = true })

	espSec:AddToggle({
		Name = "Enabled",
		Flag = "ESPEnabled",
		Value = true,
		Keybind = { Value = Enum.KeyCode.U, Mode = "Toggle" },
	})
	espSec:AddToggle({ Name = "Players", Flag = "ShowPlayers", Value = true })
	espSec:AddToggle({ Name = "Bots", Flag = "ShowBots", Value = true })
	espSec:AddToggle({ Name = "Boxes", Flag = "ESPBoxes", Value = true })
	espSec:AddToggle({ Name = "Names", Flag = "ESPNames", Value = true })
	espSec:AddToggle({ Name = "Distance", Flag = "ESPDistance", Value = true })
	espSec:AddToggle({ Name = "Health", Flag = "ESPHealth", Value = true })
	espSec:AddToggle({ Name = "Tracers", Flag = "ESPTracers", Value = false })
	espSec:AddToggle({ Name = "Chams", Flag = "ESPChams", Value = true })
	espSec:AddSlider({
		Name = "Max Distance",
		Flag = "ESPMaxDistance",
		Value = defaults.ESPMaxDistance,
		Min = 100,
		Max = 5000,
		Textbox = true,
	})

	colSec:AddColorpicker({ Name = "Players", Flag = "PlayerColor", Value = Color3.fromRGB(255, 70, 70) })
	colSec:AddColorpicker({ Name = "Bots", Flag = "BotColor", Value = Color3.fromRGB(255, 170, 50) })
	colSec:AddColorpicker({ Name = "Squad", Flag = "SquadColor", Value = Color3.fromRGB(80, 220, 120) })
	colSec:AddColorpicker({ Name = "FOV Circle", Flag = "AimFOVColor", Value = Color3.fromRGB(255, 255, 255) })

	pcall(function()
		window:CreateDesigner({ Credit = true, Info = "Reload " .. version })
	end)

	return window
end

return Menu
