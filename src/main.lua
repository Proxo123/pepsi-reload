local Main = {}

function Main.start(import)
	local Config = import("src/core/config")
	local FlagsMod = import("src/core/flags")
	local DrawingMod = import("src/features/draw")
	local GameMod = import("src/game/reload")
	local TargetsMod = import("src/features/targets")
	local CombatMod = import("src/features/combat")
	local AimMod = import("src/features/aim")
	local EspMod = import("src/features/esp")
	local TracersMod = import("src/features/tracers")
	local BuildMod = import("src/features/build")
	local MenuMod = import("src/ui/menu")

	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local CoreGui = game:GetService("CoreGui")
	local lp = Players.LocalPlayer

	for _, step in { "PepsiReloadAim", "PepsiReloadAim_v12", "PepsiReloadAim_v13", "PepsiReloadAim_v14", "PepsiReloadAim_v15", "PepsiReloadAim_v16", "PepsiReloadAim_v17", "PepsiReloadAim_v18", Config.AIM_STEP } do
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
			silentTargetHead = nil,
			silentTargetChar = nil,
			lockedTargetKey = nil,
			directionSpreadRestore = nil,
			fireRecoilRestore = nil,
			noSpreadActive = false,
			noSpreadFlagState = false,
			noRecoilActive = false,
			noRecoilFlagState = false,
			silentAimActive = false,
			silentAimFlagState = false,
			cachedTargetList = {},
			lastSeenEsp = {},
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
	ctx.build = BuildMod.create(ctx)
	MenuMod.create(ctx)

	local fovCircle = ctx.draw.drawing("Circle", { Filled = false, Thickness = 1, NumSides = 48, ZIndex = 4 })
	local logicAccum = 0
	local LOGIC_HZ = 30

	local function needsLogic()
		return ctx.flags.flagOn("ESPEnabled")
			or ctx.flags.flagOn("AimEnabled")
			or ctx.flags.flagOn("SilentAim")
			or ctx.flags.flagOn("NoSpread")
			or ctx.flags.flagOn("NoRecoil")
			or ctx.flags.flagOn("InstantReload")
	end

	local function needsVisuals()
		return ctx.flags.flagOn("ESPEnabled")
			or ctx.flags.flagOn("AimShowFOV")
			or (ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer"))
	end

	local function runLogic()
		local targetList = ctx.targets.collectTargets()
		ctx.state.cachedTargetList = targetList

		local aimTarget = ctx.aim.getAimTarget(targetList)
		ctx.state.aimTargetPart = aimTarget and aimTarget.aimPart or nil

		local silentTarget = ctx.aim.getSilentTarget(targetList)
		ctx.state.silentTargetPart = silentTarget and silentTarget.aimPart or nil
		ctx.state.silentTargetChar = silentTarget and silentTarget.character or nil
		ctx.state.silentTargetIsBot = silentTarget and silentTarget.isBot or nil
		if silentTarget then
			ctx.state.silentTargetHead = silentTarget.character and silentTarget.character:FindFirstChild("Head")
				or silentTarget.aimPart
		else
			ctx.state.silentTargetHead = nil
			ctx.state.silentTargetChar = nil
		end
	end

	local function runVisuals()
		ctx.camera = workspace.CurrentCamera
		if not ctx.camera then
			return
		end
		local vp = ctx.camera.ViewportSize
		local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
		local origin = ctx.camera.CFrame.Position

		if fovCircle then
			local show = ctx.flags.flagOn("AimEnabled") and ctx.flags.flagOn("AimShowFOV") and ctx.aim.holdRequired()
			ctx.draw.setVisible(fovCircle, show)
			if show then
				fovCircle.Position = center
				fovCircle.Radius = tonumber(ctx.flags.flagVal("AimFOV", Config.DEFAULTS.AimFOV)) or Config.DEFAULTS.AimFOV
				fovCircle.Color = ctx.flags.flagVal("AimFOVColor", Color3.new(1, 1, 1))
			end
		end

		if ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer") then
			ctx.tracers.updateSilentTracer(center)
		elseif ctx.tracers then
			ctx.tracers.updateSilentTracer(nil)
		end

		if ctx.flags.flagOn("ESPEnabled") then
			local targetList = ctx.state.cachedTargetList
			if #targetList == 0 then
				targetList = ctx.targets.collectTargets()
				ctx.state.cachedTargetList = targetList
			end
			ctx.state.lastSeenEsp = ctx.esp.update(targetList, origin, center, vp)
			for key, pack in pairs(ctx.drawings) do
				if not ctx.state.lastSeenEsp[key] then
					ctx.draw.hidePack(pack)
					local hl = ctx.highlights[key]
					if hl then
						hl.Enabled = false
					end
				end
			end
		else
			for _, pack in pairs(ctx.drawings) do
				ctx.draw.hidePack(pack)
			end
			for _, hl in pairs(ctx.highlights) do
				hl.Enabled = false
			end
			ctx.state.lastSeenEsp = {}
		end
	end

	local function unload()
		ctx.state.aimTargetPart = nil
		ctx.state.silentTargetPart = nil
		ctx.state.silentTargetHead = nil
		ctx.state.silentTargetChar = nil
		ctx.state.silentTargetIsBot = nil
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

	table.insert(ctx.connections, Players.PlayerRemoving:Connect(function(p)
		ctx.draw.clearKey("p" .. p.UserId)
	end))
	table.insert(
		ctx.connections,
		RunService.Heartbeat:Connect(function(dt)
			local ok, err = pcall(function()
				if library.IsGuiValid and not library.IsGuiValid() then
					unload()
					return
				end
				ctx.combat.syncNoSpreadToggle()
				ctx.combat.syncNoRecoilToggle()
				ctx.combat.syncInstantReloadToggle()
				ctx.combat.syncSilentAimToggle()
				if not needsLogic() then
					return
				end
				logicAccum += dt
				if logicAccum >= (1 / LOGIC_HZ) then
					logicAccum = 0
					runLogic()
				end
			end)
			if not ok and not ctx.state.renderWarned then
				ctx.state.renderWarned = true
				warn("[Pepsi Reload] " .. tostring(err))
			end
		end)
	)
	table.insert(
		ctx.connections,
		RunService.RenderStepped:Connect(function()
			local ok, err = pcall(function()
				if library.IsGuiValid and not library.IsGuiValid() then
					return
				end
				if not needsVisuals() then
					if fovCircle then
						ctx.draw.setVisible(fovCircle, false)
					end
					return
				end
				runVisuals()
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
