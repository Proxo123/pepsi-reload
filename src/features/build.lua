local Build = {}

local GRID = 18
local HALF = 9
local PLACE_DELAY = 0.12

local function grid(n)
	return math.floor(n / GRID + 0.5) * GRID
end

local function snapYaw(deg)
	return math.floor(deg / 90 + 0.5) * 90
end

function Build.create(ctx)
	local RS = ctx.services.RS
	local UIS = ctx.services.UIS
	local lp = ctx.lp
	local gameApi = ctx.game

	local BuildingAssets = RS:WaitForChild("BuildingAssets")
	local HttpService = game:GetService("HttpService")
	local placeRemote = BuildingAssets:WaitForChild("PlaceBuild")

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local function getIgnore()
		local list = { lp.Character, workspace.CurrentCamera }
		local wsMe = gameApi.findWorkspacePlayerModel(lp.Name)
		if wsMe then
			table.insert(list, wsMe)
		end
		local ignore = workspace:FindFirstChild("Ignore")
		if ignore then
			table.insert(list, ignore)
		end
		return list
	end

	local function touchesTerrain(cf)
		rayParams.FilterDescendantsInstances = getIgnore()
		local hit = workspace:Raycast(cf.Position + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), rayParams)
		return hit ~= nil and hit.Instance == workspace.Terrain
	end

	local function keyFromHotkeyFlag(flagName, default)
		local f = ctx.library and ctx.library.flags and ctx.library.flags[flagName]
		if type(f) == "table" then
			if typeof(f.Value) == "EnumItem" and f.Value.EnumType == Enum.KeyCode then
				return f.Value
			end
			if type(f.Keybind) == "table" and typeof(f.Keybind.Value) == "EnumItem" then
				return f.Keybind.Value
			end
			if typeof(f.Key) == "EnumItem" then
				return f.Key
			end
		end
		return default
	end

	local function getCrosshairTarget()
		ctx.camera = workspace.CurrentCamera
		local camera = ctx.camera
		if not camera then
			return nil
		end

		local targetList = ctx.targets.collectTargets()
		local origin = camera.CFrame.Position
		local center = camera.ViewportSize * 0.5
		local fov = tonumber(ctx.flags.flagVal("BuildTargetFOV", ctx.config.DEFAULTS.BuildTargetFOV))
			or ctx.config.DEFAULTS.BuildTargetFOV
		local range = tonumber(ctx.flags.flagVal("AimRange", ctx.config.DEFAULTS.AimRange))
			or ctx.config.DEFAULTS.AimRange

		local best
		local bestScore

		for _, t in ipairs(targetList) do
			if t.player and gameApi.isTeammate(t.player) then
				continue
			end
			if t.player and gameApi.isPlayerDead(t.player) then
				continue
			end

			local part = t.aimPart or t.root
			if not part or not part.Position then
				continue
			end

			local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
			if not onScreen or screenPos.Z <= 0 then
				continue
			end

			local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
			local worldDist = (part.Position - origin).Magnitude
			if screenDist > fov or worldDist > range then
				continue
			end

			if not bestScore or screenDist < bestScore then
				best = t
				bestScore = screenDist
			end
		end

		if not best then
			return nil
		end

		local root = best.root
		if best.player and not root then
			local wsModel = gameApi.findWorkspacePlayerModel(best.player.Name)
			root = wsModel and wsModel:FindFirstChild("HumanoidRootPart") or root
		end
		if not root then
			root = best.character and best.character:FindFirstChild("HumanoidRootPart")
		end
		if not root then
			return nil
		end

		return {
			character = best.character,
			root = root,
			player = best.player,
			isBot = best.isBot,
			name = best.name,
		}
	end

	local function defaultVariant(buildType)
		local template = BuildingAssets:FindFirstChild(buildType)
		if not template then
			return "Default"
		end
		local current = template:GetAttribute("Current")
		if type(current) == "string" and current ~= "" then
			return current
		end
		return "Default"
	end

	local function placePiece(buildType, worldCFrame)
		local template = BuildingAssets:FindFirstChild(buildType)
		if not template or not template:FindFirstChild("Builds") then
			return false, "missing template"
		end

		local defaultPart = template.Builds:FindFirstChild("Default")
		if not defaultPart then
			return false, "missing default"
		end

		local guid = HttpService:GenerateGUID(false)
		local variant = defaultVariant(buildType)
		local terrainTouch = touchesTerrain(worldCFrame)

		local ok, ret1, ret2 = pcall(function()
			return placeRemote:InvokeServer(
				buildType,
				worldCFrame,
				variant,
				defaultPart.CFrame,
				guid,
				terrainTouch
			)
		end)

		if not ok then
			return false, ret1
		end

		-- Client treats first return as failure payload when truthy.
		if ret1 then
			return false, "server rejected"
		end

		return true, ret2
	end

	local function floorCFrame(x, y, z, yawDeg)
		local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
		local cf = CFrame.new(x, y, z) * rot
		return cf * (CFrame.Angles(0, math.rad(90), math.rad(90)) * CFrame.new(HALF, 0, HALF))
	end

	local function wallCFrame(x, y, z, yawDeg)
		local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
		local cf = CFrame.new(x, y, z) * rot
		return cf * (CFrame.Angles(0, math.rad(90), 0) * CFrame.new(HALF, 0, HALF))
	end

	local function coneCFrame(worldPos, yawDeg)
		local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
		local cf = CFrame.new(worldPos) * rot
		return cf * CFrame.new(0, 3, 0) * CFrame.Angles(math.pi / 2, 0, 0)
	end

	local function getYawTowardTarget(targetPos)
		ctx.camera = workspace.CurrentCamera
		local origin = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if origin then
			local look = targetPos - origin.Position
			return snapYaw(math.deg(math.atan2(-look.X, -look.Z)))
		end
		if ctx.camera then
			local _, y = ctx.camera.CFrame:ToEulerAnglesYXZ()
			return snapYaw(math.deg(y))
		end
		return 0
	end

	local function notify(text, time)
		pcall(function()
			ctx.library:Notify({ Text = text, Time = time or 4 })
		end)
		print("[Pepsi Build]", text)
	end

	local function getWood()
		local inv = RS:FindFirstChild("PlayersInventory")
		inv = inv and inv:FindFirstChild(lp.Name)
		local wood = inv and inv:FindFirstChild("Wood")
		return wood and wood.Value or 0
	end

	local busy = false

	local function runSequence(label, pieces)
		if busy then
			notify("Build already running", 2)
			return
		end
		busy = true

		local placed = 0
		local failed = 0
		local delay = tonumber(ctx.flags.flagVal("BuildPlaceDelay", PLACE_DELAY)) or PLACE_DELAY

		for _, piece in ipairs(pieces) do
			local ok = placePiece(piece.type, piece.cf)
			if ok then
				placed += 1
			else
				failed += 1
			end
			task.wait(math.clamp(delay, 0.05, 1))
		end

		notify(string.format("%s: %d placed, %d failed", label, placed, failed), 5)
		busy = false
	end

	local function boxTarget(target)
		if not ctx.flags.flagOn("BuildTestEnabled") then
			return
		end

		local root = target and target.root
		if not root then
			notify("No target under crosshair", 3)
			return
		end

		local wood = getWood()
		if wood < 30 and RS.GameInfo.InfMats.Value == false then
			notify("Low wood (" .. wood .. ") — need ~30 for full box", 4)
		end

		local center = root.Position
		local cx = grid(center.X)
		local cy = grid(center.Y)
		local cz = grid(center.Z)
		local yaw = getYawTowardTarget(center)

		local pieces = {
			{ type = "Floor", cf = floorCFrame(cx, cy, cz, yaw) },
			{ type = "Wall", cf = wallCFrame(cx, cy, cz, yaw) },
			{ type = "Wall", cf = wallCFrame(cx, cy, cz, yaw + 90) },
			{ type = "Wall", cf = wallCFrame(cx, cy, cz, yaw + 180) },
			{ type = "Wall", cf = wallCFrame(cx, cy, cz, yaw + 270) },
			{ type = "Floor", cf = floorCFrame(cx, cy + GRID, cz, yaw) },
		}

		notify("Boxing " .. target.name .. " (far test)", 3)
		task.spawn(runSequence, "Far box", pieces)
	end

	local function pyramidTarget(target)
		if not ctx.flags.flagOn("BuildTestEnabled") then
			return
		end

		local root = target and target.root
		if not root then
			notify("No target under crosshair", 3)
			return
		end

		local pos = root.Position
		local yaw = getYawTowardTarget(pos) + (tonumber(ctx.flags.flagVal("BuildPyramidYaw", 0)) or 0)
		local count = math.clamp(
			math.floor(tonumber(ctx.flags.flagVal("BuildPyramidCount", 3)) or 3),
			1,
			6
		)

		local pieces = {}
		for i = 0, count - 1 do
			local offset = Vector3.new(math.sin(i * 1.4) * 2, 3 + i * 2.5, math.cos(i * 1.4) * 2)
			table.insert(pieces, {
				type = "Cone",
				cf = coneCFrame(pos + offset, yaw + i * 37),
			})
		end

		notify("Pyramids on " .. target.name .. " (off-grid)", 3)
		task.spawn(runSequence, "Pyramid test", pieces)
	end

	local function onAction(boxKey, pyramidKey, input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if UIS:GetFocusedTextBox() then
			return
		end
		if not ctx.flags.flagOn("BuildTestEnabled") then
			return
		end

		local target = getCrosshairTarget()
		if input.KeyCode == boxKey then
			boxTarget(target)
		elseif input.KeyCode == pyramidKey then
			pyramidTarget(target)
		end
	end

	local boxKey = keyFromHotkeyFlag("BuildBoxHotkey", Enum.KeyCode.B)
	local pyramidKey = keyFromHotkeyFlag("BuildPyramidHotkey", Enum.KeyCode.N)

	table.insert(
		ctx.connections,
		UIS.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			boxKey = keyFromHotkeyFlag("BuildBoxHotkey", Enum.KeyCode.B)
			pyramidKey = keyFromHotkeyFlag("BuildPyramidHotkey", Enum.KeyCode.N)
			onAction(boxKey, pyramidKey, input)
		end)
	)

	return {
		boxTarget = boxTarget,
		pyramidTarget = pyramidTarget,
		getCrosshairTarget = getCrosshairTarget,
		placePiece = placePiece,
	}
end

return Build
