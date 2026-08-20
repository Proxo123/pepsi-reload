local Combat = {}

function Combat.create(ctx)
	local RS = ctx.services.RS
	local lp = ctx.lp
	local gameApi = ctx.game
	local state = ctx.state

	local fireHooks = {}
	local reloadHooks = {}
	local spreadFnOriginals = {}

	local function restoreReloadHooks()
		local stored = getgenv()._PepsiReloadHooks
		if not stored then
			return
		end
		for _, data in stored do
			if data.mod and data.original then
				data.mod.Reload = data.original
				data.mod._PepsiReloadWrapped = nil
			end
		end
		getgenv()._PepsiReloadHooks = nil
	end

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
	restoreReloadHooks()

	local remoteHandler

	local function getRemoteHandler()
		if remoteHandler then
			return remoteHandler
		end
		local ok, rh = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK.Services.RemoteHandler)
		end)
		if ok then
			remoteHandler = rh
		end
		return remoteHandler
	end

	local function instantReloadGun(p8)
		if not p8 or not p8.Equiped or p8.Reloading then
			return false
		end
		local rh = getRemoteHandler()
		local char = lp.Character
		local stats = p8.Stats
		local tool = p8.Tool
		if not rh or not char or not stats or not tool then
			return false
		end
		local ammo = tool:FindFirstChild("Ammo")
		local ammoClips = char:FindFirstChild("AmmoClips")
		if not ammo or not ammoClips then
			return false
		end
		local clipVal = ammoClips:FindFirstChild(stats.AmmoTake)
		if not clipVal then
			return false
		end

		p8.Reloading = true
		local af = gameApi.getAllFunctions()
		if af and stats.ReloadSound and p8.Handle then
			pcall(function()
				af.PlaySound(stats.ReloadSound, p8.Handle)
			end)
		end

		local ok, err = pcall(function()
			local taken = rh.InvokeServer("GetClip", stats.AmmoTake)
			local newAmmo = math.min(stats.Ammo, ammo.Value + taken)
			local clipLeft = taken - (newAmmo - ammo.Value)
			ammo.Value = newAmmo
			clipVal.Value = clipLeft
			rh.FireServer("Server_Gun", "ChangeAmmo", {
				Ammo = ammo.Value,
				[stats.AmmoTake] = clipVal.Value,
			}, tool)
		end)

		p8.Reloading = false
		if not ok then
			warn("[Pepsi Reload] Instant reload failed:", err)
			return false
		end
		return true
	end

	local function getPredictedPos(part)
		return part.Position
	end

	local function installSilentRayHook()
		if state.rayNamecallRestore or not hookmetamethod then
			return
		end
		local old
		old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
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
		local targetPos = getPredictedPos(state.silentTargetPart)
		local normal = Vector3.new(0, 1, 0)
		if u14 and u14.Handle then
			local muzzle = (u14.Handle.CFrame * CFrame.new(0, 0, 0.5)).Position
			local diff = targetPos - muzzle
			if diff.Magnitude > 0.01 then
				normal = -diff.Unit
			end
		end
		state.silentRayState = {
			part = state.silentTargetPart,
			pos = targetPos,
			normal = normal,
			count = 0,
			wallbang = ctx.flags.flagOn("Wallbang") and state.silentTargetIsBot == true,
		}
		local ok, err = pcall(original, u14, p15)
		state.silentRayState = nil
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

	local function unhookGunReloads()
		for _, data in reloadHooks do
			if data.mod and data.original then
				data.mod.Reload = data.original
				data.mod._PepsiReloadWrapped = nil
			end
		end
		table.clear(reloadHooks)
		getgenv()._PepsiReloadHooks = nil
	end

	local function hookGunReloadsOnce()
		if getgenv()._PepsiReloadHooks then
			return
		end
		local stored = {}
		local gf = RS.Modules.M3WS_FRAMEWORK.Services.GunService.GunFunctions
		for _, child in gf:GetChildren() do
			if child:IsA("ModuleScript") and not reloadHooks[child] then
				local ok, mod = pcall(require, child)
				if ok and type(mod) == "table" and type(mod.Reload) == "function" and not mod._PepsiReloadWrapped then
					local original = mod.Reload
					mod._PepsiReloadWrapped = true
					mod.Reload = function(p8, ...)
						if state.instantReloadActive then
							if instantReloadGun(p8) then
								return false
							end
							local stats = p8 and p8.Stats
							if stats and stats.ReloadTime then
								local saved = stats.ReloadTime
								stats.ReloadTime = 0
								local callOk, result = pcall(original, p8, ...)
								stats.ReloadTime = saved
								if not callOk then
									error(result)
								end
								return result
							end
						end
						return original(p8, ...)
					end
					reloadHooks[child] = { mod = mod, original = original }
					table.insert(stored, reloadHooks[child])
				end
			end
		end
		if #stored > 0 then
			getgenv()._PepsiReloadHooks = stored
		end
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
					local targetPos = getPredictedPos(state.silentTargetPart)
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
		state.silentTargetIsBot = nil
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

	local function enableInstantReload()
		if state.instantReloadActive then
			return
		end
		state.instantReloadActive = true
		hookGunReloadsOnce()
	end

	local function disableInstantReload()
		if not state.instantReloadActive then
			return
		end
		state.instantReloadActive = false
		unhookGunReloads()
	end

	local function syncInstantReloadToggle()
		local want = ctx.flags.flagOn("InstantReload")
		if want == state.instantReloadFlagState then
			return
		end
		state.instantReloadFlagState = want
		if want then
			enableInstantReload()
		else
			disableInstantReload()
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
		disableInstantReload()
		disableSilentAim()
		unhookGiveRandomSpread()
		unhookGunFires()
		unhookGunReloads()
		if state.rayNamecallRestore and hookmetamethod then
			pcall(function()
				hookmetamethod(game, "__namecall", state.rayNamecallRestore)
			end)
			state.rayNamecallRestore = nil
		end
		restoreSpreadHooks()
		state.noSpreadFlagState = false
		state.noRecoilFlagState = false
		state.instantReloadFlagState = false
		state.silentAimFlagState = false
	end

	return {
		getPredictedPos = getPredictedPos,
		syncNoSpreadToggle = syncNoSpreadToggle,
		syncSilentAimToggle = syncSilentAimToggle,
		syncNoRecoilToggle = syncNoRecoilToggle,
		syncInstantReloadToggle = syncInstantReloadToggle,
		disableAll = disableAll,
	}
end

return Combat
