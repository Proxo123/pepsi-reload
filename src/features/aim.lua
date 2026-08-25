local Aim = {}

function Aim.create(ctx)
	local UIS = ctx.services.UIS
	local state = ctx.state
	local targetsApi = ctx.targets

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

	local function getPredictedPos(part)
		if not partAlive(part) then
			return
		end
		if not ctx.flags.flagOn("AimPrediction") then
			return part.Position
		end
		local lead = tonumber(ctx.flags.flagVal("AimPredictionLead", ctx.config.DEFAULTS.AimPredictionLead))
			or ctx.config.DEFAULTS.AimPredictionLead
		local vel = part.AssemblyLinearVelocity
		if vel.Magnitude < 0.05 then
			return part.Position
		end
		return part.Position + vel * lead
	end

	local function screenScore(part, origin, center, fov, range)
		if not partAlive(part) then
			return
		end
		local targetPos = getPredictedPos(part)
		local pos, onScreen = ctx.camera:WorldToViewportPoint(targetPos)
		if not onScreen or pos.Z <= 0 then
			return
		end
		local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
		local worldDist = (targetPos - origin).Magnitude
		if screenDist > fov or worldDist > range then
			return
		end
		local priority = ctx.flags.flagVal("AimPriority", "Crosshair")
		if priority == "Distance" then
			return worldDist
		end
		return screenDist
	end

	local function targetPassesWallCheck(t, origin)
		if not ctx.flags.flagOn("AimWallCheck") then
			return true
		end
		local targetPos = getPredictedPos(t.aimPart)
		return targetsApi.visible(origin, targetPos, t.character, t.key)
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
		local sticky = ctx.flags.flagOn("AimSticky")

		if sticky and state.lockedTargetKey then
			for _, t in ipairs(targetList) do
				if t.key == state.lockedTargetKey and targetsApi.isValidAimTarget(t) then
					local part = t.aimPart
					local score = screenScore(part, origin, center, stickyFov, range)
					if score and targetPassesWallCheck(t, origin) then
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
		if best and not targetPassesWallCheck(best, origin) then
			best = nil
		end
		if best and sticky then
			state.lockedTargetKey = best.key
		elseif not sticky then
			state.lockedTargetKey = nil
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
		local targetPos = getPredictedPos(state.aimTargetPart)
		if not targetPos then
			return
		end
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
		applyAim = applyAim,
	}
end

return Aim
