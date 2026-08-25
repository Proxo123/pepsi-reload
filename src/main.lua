local Main = {}

function Main.start(import)
	local Config = import("src/core/config")
	local FlagsMod = import("src/core/flags")
	local DrawingMod = import("src/features/draw")
	local GameMod = import("src/game/generic")
	local TargetsMod = import("src/features/targets")
	local AimMod = import("src/features/aim")
	local EspMod = import("src/features/esp")
	local FakeMeleeMod = import("src/features/fake_melee")
	local MenuMod = import("src/ui/menu")
	local ConfigStoreMod = import("src/core/config_store")

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local CoreGui = game:GetService("CoreGui")
	local lp = Players.LocalPlayer

	for _, step in {
		"PepsiReloadAim",
		"PepsiReloadAim_v12",
		"PepsiReloadAim_v13",
		"PepsiReloadAim_v14",
		"PepsiReloadAim_v15",
		"PepsiReloadAim_v16",
		"PepsiReloadAim_v17",
		"PepsiReloadAim_v18",
		"PepsiReloadAim_v49",
		"PepsiReloadAim_v50",
		Config.AIM_STEP,
	} do
		pcall(function()
			RunService:UnbindFromRenderStep(step)
		end)
	end
	if getgenv()._PepsiReloadUnload then
		pcall(getgenv()._PepsiReloadUnload)
	end

	local library = loadstring(game:GetObjects(Config.LIBRARY_ID)[1].Source)("Pepsi's UI Library")
	library.WorkspaceName = Config.CONFIG_WORKSPACE
	local ctx = {
		config = Config,
		configStore = ConfigStoreMod,
		lp = lp,
		library = library,
		camera = workspace.CurrentCamera,
		drawings = {},
		highlights = {},
		connections = {},
		services = {
			Players = Players,
			RunService = RunService,
			UIS = UIS,
			CoreGui = CoreGui,
		},
		state = {
			renderWarned = false,
			aimTargetPart = nil,
			lockedTargetKey = nil,
			cachedTargetList = {},
			lastSeenEsp = {},
		},
	}

	ctx.flags = FlagsMod.make(library.flags, Config.DEFAULTS, library)
	ctx.game = GameMod.create(ctx)
	ctx.draw = DrawingMod.create(ctx)
	ctx.targets = TargetsMod.create(ctx)
	ctx.aim = AimMod.create(ctx)
	ctx.esp = EspMod.create(ctx)
	ctx.fakeMelee = FakeMeleeMod.create(ctx)
	ctx.menu = MenuMod.create(ctx)
	ctx.flags.refresh()

	local fovCircle = ctx.draw.drawing("Circle", { Filled = false, Thickness = 1, NumSides = 48, ZIndex = 4 })
	local logicAccum = 0

	local function logicHz()
		return tonumber(ctx.flags.flagVal("TargetRefreshHz", Config.DEFAULTS.TargetRefreshHz)) or Config.DEFAULTS.TargetRefreshHz
	end

	local function needsLogic()
		return ctx.flags.flagOn("ESPEnabled") or ctx.flags.flagOn("AimEnabled")
	end

	local function needsVisuals()
		return ctx.flags.flagOn("ESPEnabled") or ctx.flags.flagOn("AimShowFOV")
	end

	local function runLogic()
		local targetList = ctx.targets.collectTargets()
		ctx.state.cachedTargetList = targetList

		local aimTarget = ctx.aim.getAimTarget(targetList)
		ctx.state.aimTargetPart = aimTarget and aimTarget.aimPart or nil
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
				fovCircle.Thickness = tonumber(ctx.flags.flagVal("AimFOVThickness", 1)) or 1
			end
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
		ctx.state.lockedTargetKey = nil
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
		if ctx.fakeMelee and ctx.fakeMelee.unload then
			ctx.fakeMelee.unload()
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
				if not needsLogic() then
					return
				end
				logicAccum += dt
				local hz = math.clamp(logicHz(), 5, 60)
				if logicAccum >= (1 / hz) then
					logicAccum = 0
					runLogic()
				end
			end)
			if not ok and not ctx.state.renderWarned then
				ctx.state.renderWarned = true
				warn("[Pepsi Hub] " .. tostring(err))
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
				warn("[Pepsi Hub] " .. tostring(err))
			end
		end)
	)

	library:Notify({ Text = Config.VERSION .. " loaded.", Time = 6 })
	print("[Pepsi Hub " .. Config.VERSION .. "] loaded")
end

return Main
