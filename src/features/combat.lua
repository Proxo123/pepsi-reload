local Combat = {}

function Combat.create(ctx)
	local RS = ctx.services.RS
	local lp = ctx.lp
	local gameApi = ctx.game
	local state = ctx.state

	local fireHooks = {}

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

	local function uninstallSilentRayHook()
		if state.silentRayRestore and hookfunction then
			pcall(function()
				hookfunction(workspace.FindPartOnRayWithIgnoreList, state.silentRayRestore)
			end)
		end
		state.silentRayRestore = nil
		state.silentRayHooked = false
		state.inSilentFire = false
		state.silentRayIndex = 0
	end

	local function installSilentRayHook()
		if state.silentRayHooked or not hookfunction then
			return
		end
		local original
		local ok, hooked = pcall(function()
			original = hookfunction(workspace.FindPartOnRayWithIgnoreList, function(self, ray, ignoreList, ...)
				if state.inSilentFire and state.silentTargetPart then
					state.silentRayIndex = (state.silentRayIndex or 0) + 1
					if state.silentRayIndex == 1 then
						local part = state.silentTargetPart
						if part and part.Position then
							return part, part.Position, Vector3.new(0, 1, 0)
						end
					end
				end
				return original(self, ray, ignoreList, ...)
			end)
			return original
		end)
		if ok and hooked then
			state.silentRayRestore = hooked
			state.silentRayHooked = true
		end
	end

	restoreSpreadHooks()
	restoreFireHooks()
	uninstallSilentRayHook()

	local function getPredictedPos(part)
		return part.Position
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
						local useSilent = state.silentAimActive and state.silentTargetPart and state.silentTargetPart.Position
						if state.noSpreadActive or useSilent then
							zeroSpreadValues()
						end
						if useSilent then
							state.inSilentFire = true
							state.silentRayIndex = 0
						end
						local okFire, result = pcall(original, u14, p15)
						state.inSilentFire = false
						state.silentRayIndex = 0
						if not okFire then
							error(result)
						end
						return result
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
				if state.silentAimActive and state.silentTargetPart and state.silentTargetPart.Position then
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

	local function enableNoSpread()
		if state.noSpreadActive then
			return
		end
		state.noSpreadActive = true
		refreshDirectionSpreadHook()
		hookGunFiresOnce()
	end

	local function disableNoSpread()
		if not state.noSpreadActive then
			return
		end
		state.noSpreadActive = false
		if not state.silentAimActive then
			unhookGunFires()
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
		refreshDirectionSpreadHook()
		installSilentRayHook()
		hookGunFiresOnce()
	end

	local function disableSilentAim()
		if not state.silentAimActive then
			return
		end
		state.silentAimActive = false
		state.silentTargetPart = nil
		uninstallSilentRayHook()
		if not state.noSpreadActive then
			unhookGunFires()
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
		unhookGunFires()
		uninstallSilentRayHook()
		restoreSpreadHooks()
		state.noSpreadFlagState = false
		state.noRecoilFlagState = false
		state.silentAimFlagState = false
	end

	return {
		getPredictedPos = getPredictedPos,
		syncNoSpreadToggle = syncNoSpreadToggle,
		syncSilentAimToggle = syncSilentAimToggle,
		syncNoRecoilToggle = syncNoRecoilToggle,
		disableAll = disableAll,
	}
end

return Combat
