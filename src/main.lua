local Main = {}

function Main.start(import)
	local Config = import("src/core/config")
	local FlagsMod = import("src/core/flags")
	local DrawingMod = import("src/features/drawing")
	local GameMod = import("src/game/reload")
	local TargetsMod = import("src/features/targets")
	local CombatMod = import("src/features/combat")
	local AimMod = import("src/features/aim")
	local EspMod = import("src/features/esp")
	local TracersMod = import("src/features/tracers")
	local MenuMod = import("src/ui/menu")

	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local CoreGui = game:GetService("CoreGui")
	local lp = Players.LocalPlayer

	for _, step in { "PepsiReloadAim", "PepsiReloadAim_v12", "PepsiReloadAim_v13", "PepsiReloadAim_v14", "PepsiReloadAim_v15", Config.AIM_STEP } do
		pcall(function()
			RunService:UnbindFromRenderStep(step)
		end)
	end
	if getgenv()._PepsiReloadUnload then
		pcall(getgenv()._PepsiReloadUnload)
	end

	local library = loadstring(game:GetObjects(Config.LIBRARY_ID)[1].Source)("Pepsi's UI Library")
	local ctx = {
		config = Config,
		lp = lp,
		library = library,
		camera = workspace.CurrentCamera,
		drawings = {},
		highlights = {},
		connections = {},
		services = {
			Players = Players,
			RS = RS,
			RunService = RunService,
			UIS = UIS,
			CoreGui = CoreGui,
		},
		state = {
			renderWarned = false,
			aimTargetPart = nil,
			silentTargetPart = nil,
			lockedTargetKey = nil,
			silentRayState = nil,
			rayNamecallRestore = nil,
			directionSpreadRestore = nil,
			fireRecoilRestore = nil,
			noSpreadActive = false,
			noSpreadFlagState = false,
			noRecoilActive = false,
			noRecoilFlagState = false,
			silentAimActive = false,
			silentAimFlagState = false,
		},
	}

	ctx.flags = FlagsMod.make(library.flags, Config.DEFAULTS)
	ctx.game = GameMod.create(ctx)
	ctx.draw = DrawingMod.create(ctx)
	ctx.targets = TargetsMod.create(ctx)
	ctx.combat = CombatMod.create(ctx)
	ctx.aim = AimMod.create(ctx)
	ctx.esp = EspMod.create(ctx)
	ctx.tracers = TracersMod.create(ctx)
	MenuMod.create(ctx)

	local fovCircle = ctx.draw.drawing("Circle", { Filled = false, Thickness = 1, NumSides = 48, ZIndex = 4 })
	local visAccum = 0
	local VIS_INTERVAL = 1 / 30

	local function unload()
		ctx.state.aimTargetPart = nil
		ctx.state.silentTargetPart = nil
		ctx.state.lockedTargetKey = nil
		ctx.combat.disableAll()
		pcall(function()
			RunService:UnbindFromRenderStep(Config.AIM_STEP)
		end)
		for _, c in ctx.connections do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(ctx.connections)
		for k in pairs(ctx.drawings) do
			ctx.draw.clearKey(k)
		end
		for k in pairs(ctx.highlights) do
			ctx.draw.clearKey(k)
		end
		ctx.draw.destroyDrawing(fovCircle)
		if ctx.tracers then
			ctx.tracers.destroy()
		end
		pcall(function()
			library.unload()
		end)
		getgenv()._PepsiReloadUnload = nil
		getgenv()._PepsiReloadSetDefaults = nil
	end

	getgenv()._PepsiReloadUnload = unload
	getgenv()._PepsiReloadSetDefaults = function(overrides)
		for k, v in pairs(overrides or {}) do
			Config.DEFAULTS[k] = v
			local f = library.flags[k]
			if type(f) == "table" and f.Set then
				pcall(function()
					f:Set(v)
				end)
			elseif type(f) == "table" and f.Value ~= nil then
				f.Value = v
			end
		end
	end

	RunService:BindToRenderStep(Config.AIM_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		ctx.aim.applyAim()
	end)

	local function update(dt)
		if library.IsGuiValid and not library.IsGuiValid() then
			unload()
			return
		end
		ctx.combat.syncNoSpreadToggle()
		ctx.combat.syncNoRecoilToggle()
		ctx.combat.syncSilentAimToggle()
		ctx.camera = workspace.CurrentCamera
		if not ctx.camera then
			return
		end
		local vp = ctx.camera.ViewportSize
		local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
		local origin = ctx.camera.CFrame.Position
		local targetList = ctx.targets.collectTargets()
		if fovCircle then
			local show = ctx.flags.flagOn("AimEnabled") and ctx.flags.flagOn("AimShowFOV") and ctx.aim.holdRequired()
			ctx.draw.setVisible(fovCircle, show)
			if show then
				fovCircle.Position = center
				fovCircle.Radius = tonumber(ctx.flags.flagVal("AimFOV", Config.DEFAULTS.AimFOV)) or Config.DEFAULTS.AimFOV
				fovCircle.Color = ctx.flags.flagVal("AimFOVColor", Color3.new(1, 1, 1))
			end
		end
		local aimTarget = ctx.aim.getAimTarget(targetList)
		ctx.state.aimTargetPart = aimTarget and aimTarget.aimPart or nil
		local silentTarget = ctx.aim.getSilentTarget(targetList)
		ctx.state.silentTargetPart = silentTarget and silentTarget.aimPart or nil

		local seen = {}
		local needVis = ctx.flags.flagOn("ESPEnabled")
			or (ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer"))
		if needVis then
			visAccum += dt or (1 / 60)
			if visAccum >= VIS_INTERVAL then
				visAccum = 0
				if ctx.flags.flagOn("ESPEnabled") then
					seen = ctx.esp.update(targetList, origin, center, vp)
				end
				if ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer") then
					ctx.tracers.updateSilentHandTracer()
				end
			elseif ctx.flags.flagOn("ESPEnabled") then
				for _, t in ipairs(targetList) do
					seen[t.key] = true
				end
			end
		end
		for key in pairs(ctx.drawings) do
			if not seen[key] then
				ctx.draw.clearKey(key)
			end
		end
	end

	table.insert(ctx.connections, Players.PlayerRemoving:Connect(function(p)
		ctx.draw.clearKey("p" .. p.UserId)
	end))
	table.insert(
		ctx.connections,
		RunService.RenderStepped:Connect(function(dt)
			local ok, err = pcall(function()
				update(dt)
			end)
			if not ok and not ctx.state.renderWarned then
				ctx.state.renderWarned = true
				warn("[Pepsi Reload] " .. tostring(err))
			end
		end)
	)

	library:Notify({ Text = Config.VERSION .. " loaded from GitHub modules.", Time = 6 })
	print("[Pepsi Reload " .. Config.VERSION .. "] loaded")
end

return Main
