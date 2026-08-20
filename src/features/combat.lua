local Combat = {}

local WALLBANG_BACKTRACK_TTL = 0.45

function Combat.create(ctx)
	local RS = ctx.services.RS
	local lp = ctx.lp
	local gameApi = ctx.game
	local state = ctx.state

	local fireHooks = {}
	local spreadFnOriginals = {}
	local wallbangBacktrack = {}

	local function restoreSpreadHooks()
		local stored = getgenv()._PepsiSpreadOriginals
		if not stored or not hookfunction then
			return
		end
		for fn, orig in stored do
			pcall(function()
				hookfunction(fn, orig)
			end)
		end
		getgenv()._PepsiSpreadOriginals = nil
		getgenv()._PepsiSpreadHooked = nil
	end

	local function restoreFireHooks()
		local stored = getgenv()._PepsiFireHooks
		if not stored then
			return
		end
		for _, data in stored do
			if data.mod and data.original then
				data.mod.Fire = data.original
				data.mod._PepsiFireWrapped = nil
			end
		end
		getgenv()._PepsiFireHooks = nil
	end

	restoreSpreadHooks()
	restoreFireHooks()

	local function getCharacterModel(part)
		local model = part
		while model and model ~= workspace do
			if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
				return model
			end
			model = model.Parent
		end
	end

	local function readServerPos(char)
		if not char then
			return
		end
		local serverPos = char:GetAttribute("ServerPos")
		if typeof(serverPos) == "Vector3" then
			return serverPos
		end
	end

	local function wallbangMode()
		return ctx.flags.flagVal("WallbangMode", "Full")
	end

	local function wallbangUses(flag)
		if not ctx.flags.flagOn("Wallbang") then
			return false
		end
		local mode = wallbangMode()
		if mode == "Full" then
			return true
		end
		return mode == flag
	end

	local function isPlayerCharacter(char)
		if not char then
			return false
		end
		local plr = game:GetService("Players"):GetPlayerFromCharacter(char)
		return plr ~= nil and plr ~= lp
	end

	local function getPredictedPos(part, opts)
		if not part or not part.Position then
			return
		end
		local pos = part.Position
		if not ctx.flags.flagOn("Wallbang") then
			return pos
		end
		local char = (opts and opts.character) or getCharacterModel(part)
		if wallbangUses("Backtrack") and opts and opts.useBacktrack and opts.backtrackKey then
			local cached = wallbangBacktrack[opts.backtrackKey]
			if cached and tick() - cached.time <= WALLBANG_BACKTRACK_TTL then
				return cached.pos
			end
		end
		local serverPos = readServerPos(char)
		if serverPos then
			pos = serverPos
		end
		return pos
	end

	local function recordWallbangVisible(key, pos)
		if key and pos and ctx.flags.flagOn("Wallbang") and wallbangUses("Backtrack") then
			wallbangBacktrack[key] = { pos = pos, time = tick() }
		end
	end

	local function hasWallbangBacktrack(key)
		local cached = wallbangBacktrack[key]
		return cached ~= nil and tick() - cached.time <= WALLBANG_BACKTRACK_TTL
	end

	local function shouldSuppressServerPos(part)
		if not ctx.flags.flagOn("Wallbang") or not wallbangUses("No ServerPos") then
			return false
		end
		local char = getCharacterModel(part)
		return isPlayerCharacter(char)
	end

	local function installFireServerHook()
		if state.fireServerRestore then
			return
		end
		local ok, rh = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK.Services.RemoteHandler)
		end)
		if not ok or type(rh) ~= "table" or type(rh.FireServer) ~= "function" then
			return
		end
		local original = rh.FireServer
		rh.FireServer = function(service, action, ...)
			local args = { ... }
			if state.wallbangSuppressServerPos and service == "Server_Gun" and action == "Fire" and #args >= 12 then
				args[12] = nil
			end
			return original(service, action, table.unpack(args))
		end
		state.fireServerRestore = { mod = rh, original = original }
	end

	local function restoreFireServerHook()
		if not state.fireServerRestore then
			return
		end
		state.fireServerRestore.mod.FireServer = state.fireServerRestore.original
		state.fireServerRestore = nil
	end

	local function installSilentRayHook()
		if state.rayNamecallRestore or not hookmetamethod then
			return
		end
		local old
		old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if state.wallbangSuppressServerPos and method == "GetAttribute" then
				local attr = select(1, ...)
				if attr == "ServerPos" then
					local char = state.silentTargetChar
					if char and (self == char or (state.silentTargetPart and self == state.silentTargetPart.Parent)) then
						return nil
					end
				end
			end
			if state.silentRayState and self == workspace then
				if method == "FindPartOnRayWithIgnoreList" then
					state.silentRayState.count = (state.silentRayState.count or 0) + 1
					local redirect = state.silentRayState.wallbang or state.silentRayState.count == 1
					if redirect then
						return state.silentRayState.part, state.silentRayState.pos, state.silentRayState.normal
					end
				elseif method == "Raycast" and state.silentRayState.wallbang then
					local args = { ... }
					local origin = args[1]
					local direction = args[2]
					if typeof(origin) ~= "Vector3" then
						origin = args[2]
						direction = args[3]
					end
					if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
						local hitDist = (state.silentRayState.pos - origin).Magnitude
						local maxDist = direction.Magnitude
						if hitDist <= maxDist then
							return {
								Instance = state.silentRayState.part,
								Position = state.silentRayState.pos,
								Normal = state.silentRayState.normal,
								Material = Enum.Material.Plastic,
								Distance = hitDist,
							}
						end
					end
				end
			end
			return old(self, ...)
		end))
		state.rayNamecallRestore = old
	end

	local function fireWithSilentRay(original, u14, p15)
		local rayOpts = {
			character = state.silentTargetChar,
			backtrackKey = state.silentTargetKey,
			useBacktrack = ctx.flags.flagOn("Wallbang") and wallbangUses("Backtrack"),
		}
		local targetPos = getPredictedPos(state.silentTargetPart, rayOpts)
		local normal = Vector3.new(0, 1, 0)
		if u14 and u14.Handle and targetPos then
			local muzzle = (u14.Handle.CFrame * CFrame.new(0, 0, 0.5)).Position
			local diff = targetPos - muzzle
			if diff.Magnitude > 0.01 then
				normal = -diff.Unit
			end
		end
		state.wallbangSuppressServerPos = shouldSuppressServerPos(state.silentTargetPart)
		state.silentRayState = {
			part = state.silentTargetPart,
			pos = targetPos,
			normal = normal,
			count = 0,
			wallbang = ctx.flags.flagOn("Wallbang"),
		}
		local ok, err = pcall(original, u14, p15)
		state.silentRayState = nil
		state.wallbangSuppressServerPos = false
		if not ok then
			error(err)
		end
	end

	local function zeroSpreadValues()
		local pgi = RS:FindFirstChild("PlayerGunInfo") and RS.PlayerGunInfo:FindFirstChild(lp.Name)
		if not pgi then
			return
		end
		local spread = pgi:FindFirstChild("Spread")
		local added = pgi:FindFirstChild("Added")
		if spread then
			spread.Value = 0
		end
		if added then
			added.Value = 0
		end
	end

	local function hookGunFiresOnce()
		if getgenv()._PepsiFireHooks then
			return
		end
		local stored = {}
		local gf = RS.Modules.M3WS_FRAMEWORK.Services.GunService.GunFunctions
		for _, child in gf:GetChildren() do
			if child:IsA("ModuleScript") and not fireHooks[child] then
				local ok, mod = pcall(require, child)
				if ok and type(mod) == "table" and type(mod.Fire) == "function" and not mod._PepsiFireWrapped then
					local original = mod.Fire
					mod._PepsiFireWrapped = true
					mod.Fire = function(u14, p15)
						if state.noSpreadActive or state.silentAimActive then
							zeroSpreadValues()
						end
						if state.silentAimActive and state.silentTargetPart and state.silentTargetPart.Parent then
							fireWithSilentRay(original, u14, p15)
							return
						end
						return original(u14, p15)
					end
					fireHooks[child] = { mod = mod, original = original }
					table.insert(stored, fireHooks[child])
				end
			end
		end
		if #stored > 0 then
			getgenv()._PepsiFireHooks = stored
		end
	end

	local function unhookGunFires()
		for _, data in fireHooks do
			if data.mod and data.original then
				data.mod.Fire = data.original
				data.mod._PepsiFireWrapped = nil
			end
		end
		table.clear(fireHooks)
		getgenv()._PepsiFireHooks = nil
	end

	local function refreshDirectionSpreadHook()
		local af = gameApi.getAllFunctions()
		if not af then
			return
		end
		if state.silentAimActive or state.noSpreadActive then
			if not state.directionSpreadRestore then
				state.directionSpreadRestore = af.GiveDirectionSpread
			end
			af.GiveDirectionSpread = function(dir, ...)
				if state.silentAimActive and state.silentTargetPart and state.silentTargetPart.Parent then
					local targetPos = getPredictedPos(state.silentTargetPart, {
						character = state.silentTargetChar,
						backtrackKey = state.silentTargetKey,
						useBacktrack = ctx.flags.flagOn("Wallbang") and wallbangUses("Backtrack"),
					})
					local origin = gameApi.getGunMuzzlePos()
					if not origin then
						ctx.camera = workspace.CurrentCamera
						origin = ctx.camera and ctx.camera.CFrame.Position
					end
					if origin then
						local newDir = targetPos - origin
						if newDir.Magnitude > 0.01 then
							return newDir.Unit
						end
					end
				end
				if state.noSpreadActive then
					return dir
				end
				return state.directionSpreadRestore(dir, ...)
			end
		elseif state.directionSpreadRestore then
			af.GiveDirectionSpread = state.directionSpreadRestore
			state.directionSpreadRestore = nil
		end
	end

	local function unhookGiveRandomSpread()
		local stored = getgenv()._PepsiSpreadOriginals or spreadFnOriginals
		if hookfunction and stored then
			for fn, orig in stored do
				pcall(function()
					hookfunction(fn, orig)
				end)
			end
		end
		table.clear(spreadFnOriginals)
		getgenv()._PepsiSpreadOriginals = nil
		getgenv()._PepsiSpreadHooked = nil
	end

	local function hookGiveRandomSpreadOnce()
		if getgenv()._PepsiSpreadHooked or next(spreadFnOriginals) then
			return
		end
		for _, fn in getgc(true) do
			if type(fn) == "function" then
				local ok, name = pcall(debug.info, fn, "n")
				if ok and name == "GiveRandomSpread" and not spreadFnOriginals[fn] then
					local original = fn
					spreadFnOriginals[fn] = original
					if hookfunction then
						hookfunction(fn, function(spread, ...)
							if state.silentAimActive and state.silentTargetPart and state.silentTargetPart.Parent then
								return 0, 0, 0
							end
							if state.noSpreadActive then
								return 0, 0, 0
							end
							return original(spread, ...)
						end)
					end
				end
			end
		end
		if next(spreadFnOriginals) then
			getgenv()._PepsiSpreadOriginals = spreadFnOriginals
			getgenv()._PepsiSpreadHooked = true
		end
	end

	local function enableNoSpread()
		if state.noSpreadActive then
			return
		end
		state.noSpreadActive = true
		refreshDirectionSpreadHook()
		hookGunFiresOnce()
		hookGiveRandomSpreadOnce()
	end

	local function disableNoSpread()
		if not state.noSpreadActive then
			return
		end
		state.noSpreadActive = false
		if not state.silentAimActive then
			unhookGunFires()
			unhookGiveRandomSpread()
		end
		refreshDirectionSpreadHook()
	end

	local function syncNoSpreadToggle()
		local want = ctx.flags.flagOn("NoSpread")
		if want == state.noSpreadFlagState then
			return
		end
		state.noSpreadFlagState = want
		if want then
			enableNoSpread()
		else
			disableNoSpread()
		end
	end

	local function enableSilentAim()
		if state.silentAimActive then
			return
		end
		state.silentAimActive = true
		installSilentRayHook()
		installFireServerHook()
		hookGiveRandomSpreadOnce()
		refreshDirectionSpreadHook()
		hookGunFiresOnce()
	end

	local function disableSilentAim()
		if not state.silentAimActive then
			return
		end
		state.silentAimActive = false
		state.silentTargetPart = nil
		if not state.noSpreadActive then
			unhookGunFires()
			unhookGiveRandomSpread()
		end
		refreshDirectionSpreadHook()
	end

	local function syncSilentAimToggle()
		local want = ctx.flags.flagOn("SilentAim")
		if want == state.silentAimFlagState then
			return
		end
		state.silentAimFlagState = want
		if want then
			enableSilentAim()
		else
			disableSilentAim()
		end
	end

	local function enableNoRecoil()
		if state.noRecoilActive then
			return
		end
		local GS = gameApi.getGunService()
		if GS and type(GS.FireRecoil) == "function" and not state.fireRecoilRestore then
			state.fireRecoilRestore = GS.FireRecoil
			GS.FireRecoil = function() end
			state.noRecoilActive = true
		end
	end

	local function disableNoRecoil()
		if not state.fireRecoilRestore then
			return
		end
		local GS = gameApi.getGunService()
		if GS then
			GS.FireRecoil = state.fireRecoilRestore
		end
		state.fireRecoilRestore = nil
		state.noRecoilActive = false
	end

	local function syncNoRecoilToggle()
		local want = ctx.flags.flagOn("NoRecoil")
		if want == state.noRecoilFlagState then
			return
		end
		state.noRecoilFlagState = want
		if want then
			enableNoRecoil()
		else
			disableNoRecoil()
		end
	end

	local function disableAll()
		disableNoSpread()
		disableNoRecoil()
		disableSilentAim()
		unhookGiveRandomSpread()
		unhookGunFires()
		restoreFireServerHook()
		table.clear(wallbangBacktrack)
		if state.rayNamecallRestore and hookmetamethod then
			pcall(function()
				hookmetamethod(game, "__namecall", state.rayNamecallRestore)
			end)
			state.rayNamecallRestore = nil
		end
		restoreSpreadHooks()
		state.noSpreadFlagState = false
		state.noRecoilFlagState = false
		state.silentAimFlagState = false
	end

	return {
		getPredictedPos = getPredictedPos,
		recordWallbangVisible = recordWallbangVisible,
		hasWallbangBacktrack = hasWallbangBacktrack,
		syncNoSpreadToggle = syncNoSpreadToggle,
		syncSilentAimToggle = syncSilentAimToggle,
		syncNoRecoilToggle = syncNoRecoilToggle,
		disableAll = disableAll,
	}
end

return Combat
