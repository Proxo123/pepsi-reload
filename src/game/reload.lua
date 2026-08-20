local Game = {}

function Game.create(ctx)
	local RS = ctx.services.RS
	local Players = ctx.services.Players
	local lp = ctx.lp
	local squadMembers = {}
	local squadRefresh = 0
	local teamMembers = {}
	local teamRefresh = 0
	local wsModelCache = {}
	local wsCacheTime = 0
	local WS_CACHE_TTL = 0.4

	local function refreshWorkspaceCache()
		local now = tick()
		if now - wsCacheTime < WS_CACHE_TTL then
			return
		end
		wsCacheTime = now
		table.clear(wsModelCache)
		for _, child in workspace:GetChildren() do
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
				wsModelCache[child.Name] = child
			end
		end
	end

	local function findWorkspacePlayerModel(name)
		if not name then
			return
		end
		refreshWorkspaceCache()
		return wsModelCache[name]
	end

	local function isLobbyPosition(pos)
		if not pos then
			return true
		end
		return math.abs(pos.X) < 3 and math.abs(pos.Z) < 3 and pos.Y > 85
	end

	local function isWorkspaceModel(char)
		if not char then
			return false
		end
		local parent = char.Parent
		if parent == workspace then
			return true
		end
		if parent then
			local bots = workspace:FindFirstChild("Bots")
			if bots and char:IsDescendantOf(bots) then
				return true
			end
			if char:IsDescendantOf(workspace) then
				return true
			end
		end
		refreshWorkspaceCache()
		return wsModelCache[char.Name] ~= nil
	end

	local function getHighlightAdornee(char)
		if not char then
			return
		end
		local parent = char.Parent
		if parent == workspace or (parent and char:IsDescendantOf(workspace)) then
			return char
		end
		return findWorkspacePlayerModel(char.Name) or char
	end

	local function getGunService()
		local ok, M3WS = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK)
		end)
		if ok and M3WS then
			return M3WS.GetService("GunService")
		end
	end

	local function getAllFunctions()
		local ok, mod = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK.Services.GunService.AllFunctions)
		end)
		if ok then
			return mod
		end
	end

	local function getGunMuzzlePos()
		local char = lp.Character
		local wsChar = findWorkspacePlayerModel(lp.Name)
		for _, source in { char, wsChar } do
			if source then
				for _, tool in source:GetChildren() do
					if tool:IsA("Tool") then
						local handle = tool:FindFirstChild("Handle")
						if not handle and tool:FindFirstChild("MGP") then
							handle = tool.MGP:FindFirstChild("Body")
						end
						if handle and (tool:FindFirstChild("GunMain") or tool:FindFirstChild("Level")) then
							return (handle.CFrame * CFrame.new(0, 0, 0.5)).Position
						end
					end
				end
			end
		end
	end

	local function getTracerOrigin()
		local muzzle = getGunMuzzlePos()
		if muzzle then
			return muzzle
		end
		for _, source in { lp.Character, findWorkspacePlayerModel(lp.Name) } do
			if source then
				local hand = source:FindFirstChild("RightHand") or source:FindFirstChild("Right Arm")
				if hand then
					return hand.Position
				end
				local root = source:FindFirstChild("HumanoidRootPart")
				if root and not isLobbyPosition(root.Position) then
					return root.Position + Vector3.new(1.2, 0.5, 0)
				end
			end
		end
	end

	local function refreshSquad()
		if tick() - squadRefresh < 1.5 then
			return
		end
		squadRefresh = tick()
		table.clear(squadMembers)
		local squads = RS:FindFirstChild("Squads")
		if not squads then
			return
		end
		local myFolder
		for _, squad in squads:GetChildren() do
			local pf = squad:FindFirstChild("Players")
			if pf then
				for _, obj in pf:GetChildren() do
					if obj:IsA("ObjectValue") and obj.Value == lp then
						myFolder = pf
						break
					end
				end
			end
			if myFolder then
				break
			end
		end
		if myFolder then
			for _, obj in myFolder:GetChildren() do
				if obj:IsA("ObjectValue") and obj.Value and obj.Value:IsA("Player") then
					squadMembers[obj.Value] = true
				end
			end
		end
	end

	local function refreshTeam()
		if tick() - teamRefresh < 1.5 then
			return
		end
		teamRefresh = tick()
		table.clear(teamMembers)
		local teamInfo = RS:FindFirstChild("GameInfo") and RS.GameInfo:FindFirstChild("TeamInfo")
		if not teamInfo then
			return
		end
		local myTeam
		for _, teamFolder in teamInfo:GetChildren() do
			local pf = teamFolder:FindFirstChild("Players")
			if pf then
				for _, obj in pf:GetChildren() do
					local plr
					if obj:IsA("ObjectValue") and obj.Value and obj.Value:IsA("Player") then
						plr = obj.Value
					elseif obj:IsA("StringValue") then
						plr = Players:FindFirstChild(obj.Value)
					end
					if plr == lp then
						myTeam = teamFolder
						break
					end
				end
			end
			if myTeam then
				break
			end
		end
		if not myTeam then
			return
		end
		local pf = myTeam:FindFirstChild("Players")
		if not pf then
			return
		end
		for _, obj in pf:GetChildren() do
			local plr
			if obj:IsA("ObjectValue") and obj.Value and obj.Value:IsA("Player") then
				plr = obj.Value
			elseif obj:IsA("StringValue") then
				plr = Players:FindFirstChild(obj.Value)
			end
			if plr and plr:IsA("Player") then
				teamMembers[plr] = true
			end
		end
	end

	local teammateCache = {}
	local teammateCacheTime = 0

	local function isTeammate(player)
		local now = tick()
		if now - teammateCacheTime > 1.5 then
			teammateCacheTime = now
			table.clear(teammateCache)
			refreshSquad()
			refreshTeam()
			for plr in squadMembers do
				teammateCache[plr] = true
			end
			for plr in teamMembers do
				teammateCache[plr] = true
			end
		end
		return teammateCache[player] == true
	end

	local deadCache = {}
	local deadCacheTime = 0

	local function isPlayerDead(plr)
		local now = tick()
		if now - deadCacheTime > 0.5 then
			deadCacheTime = now
			table.clear(deadCache)
			local info = RS:FindFirstChild("GameInfo") and RS.GameInfo:FindFirstChild("PlayerInfo")
			if info then
				for _, entry in info:GetChildren() do
					local dead = entry:FindFirstChild("Dead")
					deadCache[entry.Name] = dead and dead.Value == true
				end
			end
		end
		return deadCache[plr.Name] == true
	end

	local function pickBestModel(plr, char)
		local ws = findWorkspacePlayerModel(plr.Name)
		if ws and ws:IsA("Model") then
			local wsHum = ws:FindFirstChildOfClass("Humanoid")
			local chHum = char and char:FindFirstChildOfClass("Humanoid")
			if wsHum and (not chHum or wsHum.Health > chHum.Health or chHum.Health <= 0) then
				return ws
			end
		end
		if char and char:IsA("Model") and char:FindFirstChildOfClass("Humanoid") then
			return char
		end
		return ws
	end

	local function resolvePlayerModel(plr)
		return pickBestModel(plr, plr.Character)
	end

	local function invalidateCaches()
		wsCacheTime = 0
		deadCacheTime = 0
		teammateCacheTime = 0
	end

	return {
		findWorkspacePlayerModel = findWorkspacePlayerModel,
		isLobbyPosition = isLobbyPosition,
		isWorkspaceModel = isWorkspaceModel,
		getHighlightAdornee = getHighlightAdornee,
		getGunService = getGunService,
		getAllFunctions = getAllFunctions,
		getGunMuzzlePos = getGunMuzzlePos,
		getTracerOrigin = getTracerOrigin,
		isTeammate = isTeammate,
		isPlayerDead = isPlayerDead,
		resolvePlayerModel = resolvePlayerModel,
		pickBestModel = pickBestModel,
		invalidateCaches = invalidateCaches,
	}
end

return Game
