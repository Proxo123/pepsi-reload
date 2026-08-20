local Game = {}

function Game.create(ctx)
	local RS = ctx.services.RS
	local lp = ctx.lp
	local squadMembers = {}
	local squadRefresh = 0

	local function isWorkspaceModel(char)
		if not char or not char.Parent then
			return false
		end
		if char.Parent == workspace then
			return true
		end
		local bots = workspace:FindFirstChild("Bots")
		return bots ~= nil and char.Parent == bots
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
		if not char then
			return
		end
		for _, tool in char:GetChildren() do
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

	local function refreshSquad()
		if tick() - squadRefresh < 1 then
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

	local function isTeammate(player)
		refreshSquad()
		return squadMembers[player] == true
	end

	local function isPlayerDead(plr)
		local info = RS:FindFirstChild("GameInfo") and RS.GameInfo:FindFirstChild("PlayerInfo")
		if not info then
			return false
		end
		local entry = info:FindFirstChild(plr.Name)
		local dead = entry and entry:FindFirstChild("Dead")
		return dead and dead.Value == true
	end

	local function resolvePlayerModel(plr)
		local ws = workspace:FindFirstChild(plr.Name)
		if ws and ws:IsA("Model") and ws:FindFirstChildOfClass("Humanoid") then
			return ws
		end
		local ch = plr.Character
		if ch and ch:IsA("Model") and ch:FindFirstChildOfClass("Humanoid") then
			return ch
		end
		local rsModel = RS:FindFirstChild(plr.Name)
		if rsModel and rsModel:IsA("Model") and rsModel:FindFirstChildOfClass("Humanoid") then
			return rsModel
		end
	end

	return {
		isWorkspaceModel = isWorkspaceModel,
		getGunService = getGunService,
		getAllFunctions = getAllFunctions,
		getGunMuzzlePos = getGunMuzzlePos,
		isTeammate = isTeammate,
		isPlayerDead = isPlayerDead,
		resolvePlayerModel = resolvePlayerModel,
	}
end

return Game
