local Aim = {}

function Aim.create(ctx)
	local UIS = ctx.services.UIS
	local state = ctx.state
	local targetsApi = ctx.targets
	local combat = ctx.combat

	local function holdRequired()
		local mode = ctx.flags.flagVal("AimMode", "Mouse2 Held")
		if mode == "Always" then
			return true
		end
		if not UIS or type(UIS.IsMouseButtonPressed) ~= "function" then
			return false
		end
		if mode == "Mouse1 Held" then
			return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		end
		return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	end

	local function partAlive(part)
		return part and part.Position
	end

	local function screenScore(part, origin, center, fov, range)
		if not partAlive(part) then
			return
		end
		local pos, onScreen = ctx.camera:WorldToViewportPoint(part.Position)
		if not onScreen or pos.Z <= 0 then
			return
		end
		local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
		local worldDist = (part.Position - origin).Magnitude
		if screenDist > fov or worldDist > range then
			return
		end
		return screenDist
	end

	local function targetScore(t, origin, center, fov, range)
		local score = screenScore(t.aimPart, origin, center, fov, range)
		if not score then
			return
		end
		if ctx.flags.flagOn("AimWallCheck") and not targetsApi.visible(origin, t.aimPart.Position, t.character, t.key) then
			return
		end
		return score
	end

	local function getAimTarget(targetList)
		if not ctx.flags.flagOn("AimEnabled") then
			state.lockedTargetKey = nil
			return
		end
		if UIS:GetFocusedTextBox() then
			return
		end
		if isrbxactive and not isrbxactive() then
			return
		end
		if not holdRequired() then
			state.lockedTargetKey = nil
			return
		end
		ctx.camera = workspace.CurrentCamera
		if not ctx.camera then
			return
		end
		local origin = ctx.camera.CFrame.Position
		local range = tonumber(ctx.flags.flagVal("AimRange", ctx.config.DEFAULTS.AimRange)) or ctx.config.DEFAULTS.AimRange
		local fov = tonumber(ctx.flags.flagVal("AimFOV", ctx.config.DEFAULTS.AimFOV)) or ctx.config.DEFAULTS.AimFOV
		local center = ctx.camera.ViewportSize * 0.5
		local stickyFov = fov * 1.35
		local wallCheck = ctx.flags.flagOn("AimWallCheck")

		if state.lockedTargetKey then
			for _, t in ipairs(targetList) do
				if t.key == state.lockedTargetKey and targetsApi.isValidAimTarget(t) then
					local part = t.aimPart
					local score = screenScore(part, origin, center, stickyFov, range)
					if score and (not wallCheck or targetsApi.visible(origin, part.Position, t.character, t.key)) then
						return t
					end
				end
			end
			state.lockedTargetKey = nil
		end

		local best, bestDist
		for _, t in ipairs(targetList) do
			if targetsApi.isValidAimTarget(t) then
				local score = screenScore(t.aimPart, origin, center, fov, range)
				if score and (not bestDist or score < bestDist) then
					best = t
					bestDist = score
				end
			end
		end
		if best and wallCheck and not targetsApi.visible(origin, best.aimPart.Position, best.character, best.key) then
			best = nil
		end
		if best then
			state.lockedTargetKey = best.key
		end
		return best
	end

	local function targetScoreSilent(t, origin, center, screenFov, angleFov, range)
		local part = t.aimPart
		if not partAlive(part) then
			return
		end
		local targetPos = combat.getPredictedPos(part)
		local worldDist = (targetPos - origin).Magnitude
		if worldDist > range then
			return
		end
		local pos, onScreen = ctx.camera:WorldToViewportPoint(targetPos)
		if onScreen and pos.Z > 0 then
			local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
			if screenDist <= screenFov then
				return screenDist
			end
		end
		local dir = (targetPos - origin).Unit
		local angle = math.deg(math.acos(math.clamp(ctx.camera.CFrame.LookVector:Dot(dir), -1, 1)))
		if angle <= angleFov then
			return 10000 + angle * 10 + worldDist * 0.01
		end
	end

	local function getSilentTarget(targetList)
		if not ctx.flags.flagOn("SilentAim") then
			return
		end
		if UIS:GetFocusedTextBox() then
			return
		end
		if isrbxactive and not isrbxactive() then
			return
		end
		ctx.camera = workspace.CurrentCamera
		if not ctx.camera then
			return
		end
		local origin = ctx.camera.CFrame.Position
		local range = tonumber(ctx.flags.flagVal("AimRange", ctx.config.DEFAULTS.AimRange)) or ctx.config.DEFAULTS.AimRange
		local screenFov = tonumber(ctx.flags.flagVal("SilentFOV", ctx.config.DEFAULTS.SilentFOV)) or ctx.config.DEFAULTS.SilentFOV
		local angleFov = tonumber(ctx.flags.flagVal("SilentAngleFOV", ctx.config.DEFAULTS.SilentAngleFOV))
			or ctx.config.DEFAULTS.SilentAngleFOV
		local center = ctx.camera.ViewportSize * 0.5
		local wallCheck = ctx.flags.flagOn("AimWallCheck")
		local best, bestDist
		for _, t in ipairs(targetList) do
			if targetsApi.isValidAimTarget(t) then
				local score = targetScoreSilent(t, origin, center, screenFov, angleFov, range)
				if score and (not bestDist or score < bestDist) then
					best = t
					bestDist = score
				end
			end
		end
		if best and wallCheck then
			local targetPos = combat.getPredictedPos(best.aimPart)
			if not targetsApi.visible(origin, targetPos, best.character, best.key) then
				return
			end
		end
		return best
	end

	local function applyAim()
		if not ctx.flags.flagOn("AimEnabled") or not holdRequired() then
			return
		end
		if not state.aimTargetPart or not partAlive(state.aimTargetPart) then
			return
		end
		ctx.camera = workspace.CurrentCamera
		if not ctx.camera then
			return
		end
		local targetPos = combat.getPredictedPos(state.aimTargetPart)
		local goal = CFrame.lookAt(ctx.camera.CFrame.Position, targetPos)
		local strength = math.clamp(
			tonumber(ctx.flags.flagVal("AimSmoothness", ctx.config.DEFAULTS.AimSmoothness)) or ctx.config.DEFAULTS.AimSmoothness,
			0.05,
			1
		)
		if strength >= 0.995 then
			ctx.camera.CFrame = goal
			return
		end
		local dir = (targetPos - ctx.camera.CFrame.Position).Unit
		local misalign = 1 - math.clamp(ctx.camera.CFrame.LookVector:Dot(dir), -1, 1)
		ctx.camera.CFrame = ctx.camera.CFrame:Lerp(goal, math.clamp(strength + misalign * (1 - strength), strength, 1))
	end

	return {
		holdRequired = holdRequired,
		getAimTarget = getAimTarget,
		getSilentTarget = getSilentTarget,
		applyAim = applyAim,
	}
end

return Aim
