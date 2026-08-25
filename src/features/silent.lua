local Silent = {}

local ARSENAL_PLACE_ID = 286090429

function Silent.create(ctx)
	local RS = game:GetService("ReplicatedStorage")
	local state = ctx.state
	local hitRemote = RS:FindFirstChild("HitPart")

	local function active()
		return game.PlaceId == ARSENAL_PLACE_ID
			and ctx.flags.flagOn("SilentAim")
			and hitRemote ~= nil
			and hookmetamethod ~= nil
	end

	local function getTargetPart()
		local part = state.silentTargetPart
		if part and part.Parent then
			return part
		end
	end

	local function rayStateFor(part)
		ctx.camera = workspace.CurrentCamera
		local pos = part.Position
		local origin = ctx.camera and ctx.camera.CFrame.Position or pos
		local diff = pos - origin
		local normal = diff.Magnitude > 0.01 and -diff.Unit or Vector3.new(0, 1, 0)
		return {
			part = part,
			pos = pos,
			normal = normal,
		}
	end

	local function copyArgs(args)
		local out = {}
		for i = 1, #args do
			out[i] = args[i]
		end
		return out
	end

	local function rewriteHitArgs(args, part, pos)
		local newArgs = copyArgs(args)
		local replacedPart = false
		local replacedPos = false
		for i, a in ipairs(newArgs) do
			if not replacedPart and typeof(a) == "Instance" and a:IsA("BasePart") then
				newArgs[i] = part
				replacedPart = true
			elseif not replacedPos and typeof(a) == "Vector3" then
				newArgs[i] = pos
				replacedPos = true
			end
		end
		if not replacedPart then
			table.insert(newArgs, 1, part)
		end
		if not replacedPos then
			table.insert(newArgs, 2, pos)
		end
		return newArgs
	end

	local function redirectRay(method, args, rayState)
		if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" then
			return rayState.part, rayState.pos, rayState.normal
		end
		if method == "Raycast" then
			local origin = args[1]
			local direction = args[2]
			if typeof(origin) ~= "Vector3" then
				origin = args[2]
				direction = args[3]
			end
			if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
				local hitDist = (rayState.pos - origin).Magnitude
				if hitDist <= direction.Magnitude then
					return {
						Instance = rayState.part,
						Position = rayState.pos,
						Normal = rayState.normal,
						Material = Enum.Material.Plastic,
						Distance = hitDist,
					}
				end
			end
		end
	end

	local function installHook()
		if state.silentNamecallRestore or not hookmetamethod or not hitRemote then
			return
		end
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if active() then
				local targetPart = getTargetPart()
				if targetPart then
					if self == hitRemote and method == "FireServer" then
						local rayState = rayStateFor(targetPart)
						state.silentRayState = rayState
						local newArgs = rewriteHitArgs({ ... }, targetPart, rayState.pos)
						local results = { oldNamecall(self, table.unpack(newArgs)) }
						state.silentRayState = nil
						return table.unpack(results)
					end
					if state.silentRayState and self == workspace then
						local redirected = redirectRay(method, { ... }, state.silentRayState)
						if redirected ~= nil then
							return redirected
						end
					end
				end
			end
			return oldNamecall(self, ...)
		end))
		state.silentNamecallRestore = oldNamecall
	end

	local function refresh()
		state.silentAimActive = active()
	end

	installHook()

	return {
		refresh = refresh,
	}
end

return Silent
