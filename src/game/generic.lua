local Game = {}

function Game.create(ctx)
	local Players = ctx.services.Players
	local lp = ctx.lp

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
		if not ctx.flags.flagOn("UseWorkspaceModels") then
			return
		end
		for _, child in workspace:GetChildren() do
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
				wsModelCache[child.Name] = child
			end
		end
	end

	local function findWorkspacePlayerModel(name)
		if not name or not ctx.flags.flagOn("UseWorkspaceModels") then
			return nil
		end
		refreshWorkspaceCache()
		return wsModelCache[name]
	end

	local function isLobbyPosition(pos)
		if not ctx.flags.flagOn("FilterLobbySpawn") then
			return false
		end
		if not pos then
			return true
		end
		local minY = tonumber(ctx.flags.flagVal("LobbyMinY", ctx.config.DEFAULTS.LobbyMinY)) or ctx.config.DEFAULTS.LobbyMinY
		return math.abs(pos.X) < 3 and math.abs(pos.Z) < 3 and pos.Y > minY
	end

	local function getHighlightAdornee(char)
		if not char then
			return nil
		end
		local parent = char.Parent
		if parent == workspace or (parent and char:IsDescendantOf(workspace)) then
			return char
		end
		return findWorkspacePlayerModel(char.Name) or char
	end

	local function getLocalRootY()
		local char = lp.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		return root and root.Position.Y
	end

	local function isCharacterViable(hum, root, head)
		if not hum or not root then
			return false
		end
		if hum.Health <= 0 then
			return false
		end
		local state = hum:GetState()
		if state == Enum.HumanoidStateType.Dead then
			return false
		end
		local localY = getLocalRootY()
		if localY then
			local drop = tonumber(ctx.flags.flagVal("DeadDropThreshold", ctx.config.DEFAULTS.DeadDropThreshold))
				or ctx.config.DEFAULTS.DeadDropThreshold
			if root.Position.Y < localY - drop then
				return false
			end
		end
		if head then
			local maxSep = tonumber(ctx.flags.flagVal("MaxPartSeparation", ctx.config.DEFAULTS.MaxPartSeparation))
				or ctx.config.DEFAULTS.MaxPartSeparation
			if (head.Position - root.Position).Magnitude > maxSep then
				return false
			end
		end
		return true
	end

	local function isTeammate(player)
		if not player or player == lp then
			return true
		end
		return lp.Team ~= nil and player.Team == lp.Team
	end

	local function isPlayerDead(plr, hum)
		if hum and hum.Health <= 0 then
			return true
		end
		if not plr then
			return hum == nil
		end
		if not plr.Parent then
			return true
		end
		local char = plr.Character
		if not char then
			return false
		end
		local charHum = char:FindFirstChildOfClass("Humanoid")
		return charHum ~= nil and charHum.Health <= 0
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

	local function getNpcFolders()
		local raw = ctx.flags.flagVal("NPCFolders", "")
		if type(raw) ~= "string" or raw == "" then
			return {}
		end
		local folders = {}
		for entry in string.gmatch(raw, "[^,]+") do
			local name = entry:match("^%s*(.-)%s*$")
			if name ~= "" then
				table.insert(folders, name)
			end
		end
		return folders
	end

	local function getRayIgnoreFolderName()
		local name = ctx.flags.flagVal("RayIgnoreFolder", "Ignore")
		if type(name) ~= "string" or name == "" then
			return nil
		end
		return name
	end

	return {
		findWorkspacePlayerModel = findWorkspacePlayerModel,
		isLobbyPosition = isLobbyPosition,
		getHighlightAdornee = getHighlightAdornee,
		isTeammate = isTeammate,
		isPlayerDead = isPlayerDead,
		pickBestModel = pickBestModel,
		getNpcFolders = getNpcFolders,
		getRayIgnoreFolderName = getRayIgnoreFolderName,
		isCharacterViable = isCharacterViable,
		invalidateCaches = function()
			wsCacheTime = 0
		end,
	}
end

return Game
