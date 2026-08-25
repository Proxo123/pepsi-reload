local Targets = {}

function Targets.create(ctx)
	local Players = ctx.services.Players
	local lp = ctx.lp
	local gameApi = ctx.game

	local cachedTargets = {}
	local cacheTime = 0
	local TARGET_CACHE_TTL = 0.05

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local rayIgnoreList = {}
	local rayIgnoreTime = 0
	local visCache = {}
	local visCacheTime = {}
	local VIS_CACHE_TTL = 0.35

	local function resolveAimPart(char, root, head, isNpc, wsKnown)
		local choice = ctx.flags.flagVal("AimPart", "Head")
		if choice == "HumanoidRootPart" then
			return root
		end
		if choice == "UpperTorso" or choice == "Torso" then
			return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or root
		end
		if choice == "LowerTorso" then
			return char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso") or root
		end
		if choice == "Random" then
			local parts = { head, root }
			for _, name in { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" } do
				local part = char:FindFirstChild(name)
				if part then
					table.insert(parts, part)
				end
			end
			return parts[math.random(1, #parts)] or root
		end
		if head and root then
			if isNpc or wsKnown then
				if (head.Position - root.Position).Magnitude <= 50 then
					return head
				end
			end
		end
		if head and not isNpc and wsKnown and (head.Position - root.Position).Magnitude <= 3 then
			return head
		end
		return head or root
	end

	local function getLogicalParts(char, isNpc, plr, wsModel)
		if not char then
			return
		end
		if not isNpc and plr then
			char = wsModel or gameApi.pickBestModel(plr, char) or char
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart
		if not hum or not root then
			return
		end
		local head = char:FindFirstChild("Head")
		if not gameApi.isCharacterViable(hum, root, head) then
			return
		end
		if not isNpc and gameApi.isLobbyPosition(root.Position) then
			return
		end
		local wsKnown = isNpc or char.Parent == workspace or wsModel == char
		local split = (not isNpc and not wsKnown) or not head
		if not split and head and root and (head.Position - root.Position).Magnitude > 3 then
			split = true
		end
		local headWorld = split and (root.Position + Vector3.new(0, 2.8, 0)) or head.Position
		local feetWorld = root.Position - Vector3.new(0, 3.2, 0)
		return hum, root, resolveAimPart(char, root, head, isNpc, wsKnown), headWorld, feetWorld, char
	end

	local function addPlayerTarget(list, seenPlayers, plr, char, wsModel)
		if not plr or plr == lp or seenPlayers[plr.UserId] then
			return
		end
		local hum, root, aimPart, headWorld, feetWorld, bestChar = getLogicalParts(char, false, plr, wsModel)
		if not hum or gameApi.isPlayerDead(plr, hum) then
			return
		end
		seenPlayers[plr.UserId] = true
		table.insert(list, {
			key = "p" .. plr.UserId,
			player = plr,
			character = bestChar or char,
			hum = hum,
			root = root,
			aimPart = aimPart,
			headWorld = headWorld,
			feetWorld = feetWorld,
			name = plr.DisplayName ~= "" and plr.DisplayName or plr.Name,
			isBot = false,
		})
	end

	local function getRayIgnore()
		local now = tick()
		if now - rayIgnoreTime < 0.75 then
			return rayIgnoreList
		end
		rayIgnoreTime = now
		table.clear(rayIgnoreList)
		local camera = ctx.camera
		if lp.Character then
			table.insert(rayIgnoreList, lp.Character)
		end
		if camera then
			table.insert(rayIgnoreList, camera)
		end
		local wsMe = gameApi.findWorkspacePlayerModel(lp.Name)
		if wsMe then
			table.insert(rayIgnoreList, wsMe)
		end
		local ignoreName = gameApi.getRayIgnoreFolderName()
		if ignoreName then
			local ig = workspace:FindFirstChild(ignoreName)
			if ig then
				table.insert(rayIgnoreList, ig)
			end
		end
		return rayIgnoreList
	end

	local function visible(origin, worldPos, char, cacheKey)
		if cacheKey and visCache[cacheKey] ~= nil and tick() - (visCacheTime[cacheKey] or 0) < VIS_CACHE_TTL then
			return visCache[cacheKey]
		end
		rayParams.FilterDescendantsInstances = getRayIgnore()
		local result = workspace:Raycast(origin, worldPos - origin, rayParams)
		local ok
		if not result then
			ok = true
		elseif not char then
			ok = false
		else
			local adornee = char.Parent == workspace and char or gameApi.getHighlightAdornee(char)
			ok = result.Instance and adornee and result.Instance:IsDescendantOf(adornee)
		end
		if cacheKey then
			visCache[cacheKey] = ok
			visCacheTime[cacheKey] = tick()
		end
		return ok
	end

	local function getColor(target)
		if target.player and gameApi.isTeammate(target.player) then
			return ctx.flags.flagVal("TeamColor", Color3.fromRGB(80, 220, 120))
		end
		if target.isBot then
			return ctx.flags.flagVal("NPCColor", Color3.fromRGB(255, 170, 50))
		end
		return ctx.flags.flagVal("PlayerColor", Color3.fromRGB(255, 70, 70))
	end

	local function addNpcTargets(list)
		if not ctx.flags.flagOn("ShowNPCs") then
			return
		end
		for _, folderName in ipairs(gameApi.getNpcFolders()) do
			local folder = workspace:FindFirstChild(folderName)
			if folder then
				for _, model in folder:GetChildren() do
					if model:IsA("Model") then
						local hum, root, aimPart, headWorld, feetWorld, bestChar = getLogicalParts(model, true)
						if hum then
							table.insert(list, {
								key = "n" .. folderName .. "_" .. model.Name,
								character = bestChar or model,
								hum = hum,
								root = root,
								aimPart = aimPart,
								headWorld = headWorld,
								feetWorld = feetWorld,
								name = model.Name,
								isBot = true,
							})
						end
					end
				end
			end
		end
	end

	local function rebuildTargets()
		local list = {}
		if not (ctx.flags.flagOn("ESPEnabled") or ctx.flags.flagOn("AimEnabled")) then
			return list
		end
		local seenPlayers = {}
		local wantPlayers = ctx.flags.flagOn("ShowPlayers") or ctx.flags.flagOn("AimEnabled")
		if wantPlayers then
			for _, plr in Players:GetPlayers() do
				if plr ~= lp then
					local wsModel = gameApi.findWorkspacePlayerModel(plr.Name)
					local char = wsModel or plr.Character
					addPlayerTarget(list, seenPlayers, plr, char, wsModel)
				end
			end
		end
		addNpcTargets(list)
		return list
	end

	local function collectTargets()
		local now = tick()
		if now - cacheTime < TARGET_CACHE_TTL then
			return cachedTargets
		end
		cacheTime = now
		cachedTargets = rebuildTargets()
		return cachedTargets
	end

	local function invalidateTargetCache()
		cacheTime = 0
	end

	local function refreshTarget(t)
		if not t or not t.character then
			return false
		end
		local char = t.character
		local hum = char:FindFirstChildOfClass("Humanoid") or t.hum
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or t.root
		local head = char:FindFirstChild("Head")
		if not hum or not root then
			return false
		end
		t.hum = hum
		t.root = root
		if t.player and gameApi.isPlayerDead(t.player, hum) then
			return false
		end
		if not gameApi.isCharacterViable(hum, root, head) then
			return false
		end
		t.aimPart = resolveAimPart(char, root, head, t.isBot, char.Parent == workspace)
		return true
	end

	local function isValidAimTarget(t)
		if not refreshTarget(t) then
			return false
		end
		if t.player and ctx.flags.flagOn("AimTeamCheck") and gameApi.isTeammate(t.player) then
			return false
		end
		if t.player and not ctx.flags.flagOn("ShowPlayers") and not ctx.flags.flagOn("AimEnabled") then
			return false
		end
		if t.isBot and not ctx.flags.flagOn("ShowNPCs") and not ctx.flags.flagOn("AimEnabled") then
			return false
		end
		if t.player and gameApi.isPlayerDead(t.player, t.hum) then
			return false
		end
		return true
	end

	local function shouldShowEsp(t)
		if t.player and ctx.flags.flagOn("ESPTeamCheck") and gameApi.isTeammate(t.player) then
			return false
		end
		if not refreshTarget(t) then
			return false
		end
		return true
	end

	table.insert(ctx.connections or {}, Players.PlayerAdded:Connect(invalidateTargetCache))
	table.insert(ctx.connections or {}, Players.PlayerRemoving:Connect(invalidateTargetCache))

	return {
		visible = visible,
		getColor = getColor,
		collectTargets = collectTargets,
		invalidateTargetCache = invalidateTargetCache,
		isValidAimTarget = isValidAimTarget,
		shouldShowEsp = shouldShowEsp,
		refreshTarget = refreshTarget,
	}
end

return Targets
