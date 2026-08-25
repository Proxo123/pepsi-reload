local Build = {}

local GRID = 18
local HALF = 9
local DEFAULT_WALL_COUNT = 10

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

	local buildingAssets
	local placeRemote

	local function getBuildingAssets()
		if buildingAssets == nil then
			buildingAssets = RS:FindFirstChild("BuildingAssets")
		end
		return buildingAssets
	end

	local function getPlaceRemote()
		if placeRemote == nil then
			local assets = getBuildingAssets()
			placeRemote = assets and assets:FindFirstChild("PlaceBuild") or false
		end
		return placeRemote ~= false and placeRemote or nil
	end

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
		local assets = getBuildingAssets()
		if not assets then
			return "Default"
		end
		local template = assets:FindFirstChild(buildType)
		if not template then
			return "Default"
		end
		local current = template:GetAttribute("Current")
		if type(current) == "string" and current ~= "" then
			return current
		end
		return "Default"
	end

	local function preparePreview(preview, buildType, worldCFrame, guid, variant)
		preview.Parent = workspace.Builds
		preview:SetAttribute("Current", variant)
		preview:PivotTo(worldCFrame)
		preview:SetAttribute("ID", guid)

		local cfVal = Instance.new("CFrameValue")
		cfVal.Name = "CF"
		cfVal.Value = worldCFrame
		cfVal.Parent = preview

		local ogVal = Instance.new("CFrameValue")
		ogVal.Name = "OGCF"
		ogVal.Value = preview.Builds.Default.CFrame
		ogVal.Parent = preview

		local defaultPart = preview.Builds:FindFirstChild("Default")
		if defaultPart then
			defaultPart.Transparency = 0
		end

		for _, desc in preview:GetDescendants() do
			if desc.Name == "Main" then
				desc:Destroy()
			elseif desc:IsA("BasePart") and desc.Name ~= buildType then
				desc.CanCollide = false
			end
		end
	end

	local function placePiece(buildType, worldCFrame)
		local assets = getBuildingAssets()
		local remote = getPlaceRemote()
		if not assets or not remote then
			return false
		end

		local template = assets:FindFirstChild(buildType)
		if not template or not template:FindFirstChild("Builds") then
			return false
		end

		local defaultPart = template.Builds:FindFirstChild("Default")
		if not defaultPart then
			return false
		end

		local preview = template:Clone()
		local guid = HttpService:GenerateGUID(false)
		local variant = defaultVariant(buildType)
		local defaultCF = defaultPart.CFrame

		preparePreview(preview, buildType, worldCFrame, guid, variant)

		local ok, ret1 = pcall(function()
			return remote:InvokeServer(
				buildType,
				worldCFrame,
				variant,
				defaultCF,
				guid,
				touchesTerrain(worldCFrame)
			)
		end)

		if not ok then
			preview:Destroy()
			return false
		end

		if ret1 then
			preview:Destroy()
			return false
		end

		-- Keep the client preview. Destroying it immediately can break BuildServer.
		return true
	end

	local function wallCFrame(x, y, z, yawDeg)
		local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
		local cf = CFrame.new(x, y, z) * rot
		return cf * (CFrame.Angles(0, math.rad(90), 0) * CFrame.new(HALF, 0, HALF))
	end

	local function coneCFrame(worldPos, yawDeg, pitchOffset)
		local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
		local cf = CFrame.new(worldPos) * rot
		cf = cf * CFrame.new(0, 3 + (pitchOffset or 0), 0)
		return cf * CFrame.Angles(math.pi / 2, 0, 0)
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

		for _, piece in ipairs(pieces) do
			if placePiece(piece.type, piece.cf) then
				placed += 1
			else
				failed += 1
			end
		end

		notify(string.format("%s: %d placed, %d failed", label, placed, failed), 5)
		busy = false
	end

	local function wallSpamTarget(target)
		if not ctx.flags.flagOn("BuildTestEnabled") then
			return
		end

		local root = target and target.root
		if not root then
			notify("No target under crosshair", 3)
			return
		end

		local wood = getWood()
		local wallCount = math.clamp(
			math.floor(tonumber(ctx.flags.flagVal("BuildWallCount", DEFAULT_WALL_COUNT)) or DEFAULT_WALL_COUNT),
			4,
			24
		)
		if wood < wallCount * 5 and RS:FindFirstChild("GameInfo") and RS.GameInfo:FindFirstChild("InfMats") and RS.GameInfo.InfMats.Value == false then
			notify("Low wood (" .. wood .. ") — need ~" .. wallCount * 5, 4)
		end

		local center = root.Position
		local baseY = grid(center.Y)
		local yaw = getYawTowardTarget(center)
		local pieces = {}

		for i = 0, wallCount - 1 do
			local angle = yaw + (360 / wallCount) * i
			local rad = math.rad(angle)
			local offset = Vector3.new(math.sin(rad) * GRID, 0, math.cos(rad) * GRID)
			local wx = center.X + offset.X
			local wz = center.Z + offset.Z
			local wy = baseY + (i % 2) * GRID
			table.insert(pieces, {
				type = "Wall",
				cf = wallCFrame(wx, wy, wz, angle + 90),
			})
		end

		notify("Wall spam on " .. target.name .. " x" .. wallCount, 3)
		task.spawn(runSequence, "Wall spam", pieces)
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
			math.floor(tonumber(ctx.flags.flagVal("BuildPyramidCount", 5)) or 5),
			1,
			12
		)

		local pieces = {}
		for i = 0, count - 1 do
			local spin = math.rad(i * 47 + yaw)
			local offset = Vector3.new(math.sin(spin) * (2 + i * 0.8), 2 + i * 3, math.cos(spin) * (2 + i * 0.8))
			table.insert(pieces, {
				type = "Cone",
				cf = coneCFrame(pos + offset, yaw + i * 29, i * 0.5),
			})
		end

		notify("Pyramids on " .. target.name .. " x" .. count, 3)
		task.spawn(runSequence, "Pyramid spam", pieces)
	end

	local function onAction(wallKey, pyramidKey, input)
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
		if input.KeyCode == wallKey then
			wallSpamTarget(target)
		elseif input.KeyCode == pyramidKey then
			pyramidTarget(target)
		end
	end

	table.insert(
		ctx.connections,
		UIS.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local wallKey = keyFromHotkeyFlag("BuildWallHotkey", Enum.KeyCode.B)
			local pyramidKey = keyFromHotkeyFlag("BuildPyramidHotkey", Enum.KeyCode.N)
			onAction(wallKey, pyramidKey, input)
		end)
	)

	return {
		wallSpamTarget = wallSpamTarget,
		pyramidTarget = pyramidTarget,
		getCrosshairTarget = getCrosshairTarget,
		placePiece = placePiece,
	}
end

return Build
