local Targets = {}

function Targets.create(ctx)
	local Players = ctx.services.Players
	local lp = ctx.lp
	local gameApi = ctx.game

	local function getAimPart(char, root, head, isBot)
		if ctx.flags.flagVal("AimPart", "Head") == "Torso" then
			return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or root
		end
		if head and root then
			if isBot or gameApi.isWorkspaceModel(char) then
				if (head.Position - root.Position).Magnitude <= 50 then
					return head
				end
			end
		end
		if head and not isBot and gameApi.isWorkspaceModel(char) and (head.Position - root.Position).Magnitude <= 3 then
			return head
		end
		return root
	end

	local function getLogicalParts(char, isBot, plr)
		if not char then
			return
		end
		if not isBot and plr then
			char = gameApi.pickBestModel(plr, char) or char
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart
		if not hum or hum.Health <= 0 or not root then
			return
		end
		if not isBot and gameApi.isLobbyPosition(root.Position) then
			return
		end
		local head = char:FindFirstChild("Head")
		local hiddenPlayer = not isBot and not gameApi.isWorkspaceModel(char)
		local split = hiddenPlayer or not head
		if not split and head and root and (head.Position - root.Position).Magnitude > 3 then
			split = true
		end
		local headWorld = split and (root.Position + Vector3.new(0, 2.8, 0)) or head.Position
		local feetWorld = root.Position - Vector3.new(0, 3.2, 0)
		return hum, root, getAimPart(char, root, head, isBot), headWorld, feetWorld, char
	end

	local function addPlayerTarget(list, seenPlayers, plr, char)
		if not plr or plr == lp or seenPlayers[plr.UserId] or gameApi.isPlayerDead(plr) then
			return
		end
		local hum, root, aimPart, headWorld, feetWorld, bestChar = getLogicalParts(char, false, plr)
		if not hum then
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
			name = plr.Name,
			isBot = false,
		})
	end

	local function rayIgnore()
		local camera = ctx.camera
		local t = { lp.Character, camera }
		local wsMe = gameApi.findWorkspacePlayerModel(lp.Name)
		if wsMe then
			table.insert(t, wsMe)
		end
		local ig = workspace:FindFirstChild("Ignore")
		if ig then
			table.insert(t, ig)
		end
		return t
	end

	local function visible(origin, worldPos, char)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = rayIgnore()
		params.IgnoreWater = true
		local result = workspace:Raycast(origin, worldPos - origin, params)
		if not result then
			return true
		end
		local adornee = char and (gameApi.getHighlightAdornee(char) or char) or char
		return result.Instance and adornee and result.Instance:IsDescendantOf(adornee)
	end

	local function getColor(target)
		if target.player and gameApi.isTeammate(target.player) then
			return ctx.flags.flagVal("SquadColor", Color3.fromRGB(80, 220, 120))
		end
		if target.isBot then
			return ctx.flags.flagVal("BotColor", Color3.fromRGB(255, 170, 50))
		end
		return ctx.flags.flagVal("PlayerColor", Color3.fromRGB(255, 70, 70))
	end

	local function collectTargets()
		local list = {}
		if not (ctx.flags.flagOn("ESPEnabled") or ctx.flags.flagOn("AimEnabled") or ctx.flags.flagOn("SilentAim")) then
			return list
		end
		local seenPlayers = {}
		local wantPlayers = ctx.flags.flagOn("ShowPlayers") or ctx.flags.flagOn("AimEnabled") or ctx.flags.flagOn("SilentAim")
		if wantPlayers then
			for _, model in workspace:GetChildren() do
				if model:IsA("Model") then
					local plr = Players:FindFirstChild(model.Name)
					if plr then
						addPlayerTarget(list, seenPlayers, plr, model)
					end
				end
			end
			for _, plr in Players:GetPlayers() do
				if not seenPlayers[plr.UserId] then
					addPlayerTarget(list, seenPlayers, plr, gameApi.resolvePlayerModel(plr))
				end
			end
		end
		if ctx.flags.flagOn("ShowBots") or ctx.flags.flagOn("AimEnabled") or ctx.flags.flagOn("SilentAim") then
			local bots = workspace:FindFirstChild("Bots")
			if bots then
				for _, model in bots:GetChildren() do
					if model:IsA("Model") then
						local hum, root, aimPart, headWorld, feetWorld, bestChar = getLogicalParts(model, true)
						if hum then
							table.insert(list, {
								key = "b" .. model.Name,
								character = bestChar or model,
								hum = hum,
								root = root,
								aimPart = aimPart,
								headWorld = headWorld,
								feetWorld = feetWorld,
								name = model.Name .. " [BOT]",
								isBot = true,
							})
						end
					end
				end
			end
		end
		return list
	end

	local function isValidAimTarget(t)
		if t.player and ctx.flags.flagOn("SquadCheck") and gameApi.isTeammate(t.player) then
			return false
		end
		if t.player and not ctx.flags.flagOn("ShowPlayers") and not ctx.flags.flagOn("SilentAim") and not ctx.flags.flagOn("AimEnabled") then
			return false
		end
		if t.isBot and not ctx.flags.flagOn("ShowBots") and not ctx.flags.flagOn("SilentAim") and not ctx.flags.flagOn("AimEnabled") then
			return false
		end
		if t.player and gameApi.isPlayerDead(t.player) then
			return false
		end
		return true
	end

	return {
		visible = visible,
		getColor = getColor,
		collectTargets = collectTargets,
		isValidAimTarget = isValidAimTarget,
	}
end

return Targets
