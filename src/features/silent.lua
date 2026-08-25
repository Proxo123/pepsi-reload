local Silent = {}

local ARSENAL_PLACE_ID = 286090429

function Silent.create(ctx)
	local state = ctx.state

	local function fromCaller()
		return checkcaller and checkcaller()
	end

	local function getTargetPart()
		local part = state.silentTargetPart
		if not part or not part.Parent then
			return nil
		end
		if game.PlaceId == ARSENAL_PLACE_ID then
			local char = part:FindFirstAncestorOfClass("Model")
			if char then
				local hitbox = char:FindFirstChild("Hitbox")
				if hitbox then
					return hitbox
				end
			end
		end
		return part
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

	local function handleArsenalRemote(self, method, args)
		local name = tostring(self)
		local targetPart = getTargetPart()
		if not targetPart then
			return false
		end
		local pos = targetPart.Position

		if name == "HitPart" and method == "FireServer" then
			args[1] = targetPart
			return true
		end
		if name == "Fire" and method == "FireServer" then
			args[1] = pos
			return true
		end
		if name == "Flames" and method == "FireServer" then
			args[1] = targetPart.CFrame
			args[2] = pos
			args[5] = pos
			return true
		end
		if name == "ReplicateProjectile" and method == "FireServer" then
			if type(args[1]) == "table" then
				args[1][3] = pos
				args[1][4] = pos
				args[1][10] = pos
			end
			return true
		end
		if name == "CreateProjectile" and method == "FireServer" then
			args[3] = pos
			args[4] = targetPart.CFrame
			args[10] = pos
			args[17] = pos
			args[18] = targetPart
			args[19] = pos
			return true
		end
		if name == "Trail" and method == "FireServer" then
			if type(args[1]) == "table" and type(args[1][5]) == "string" then
				args[1][2] = pos
				args[1][6] = targetPart
			end
			return true
		end
		return false
	end

	local function installHooks()
		if state.silentNamecallRestore or not hookmetamethod then
			return
		end

		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			if fromCaller() or not state.silentAimActive then
				return oldNamecall(self, ...)
			end

			local method = getnamecallmethod()
			local args = { ... }
			local targetPart = getTargetPart()

			if targetPart and self == workspace then
				local rayState = rayStateFor(targetPart)
				if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" or method == "findPartOnRay" then
					local ray = args[1]
					if typeof(ray) == "Ray" then
						local origin = ray.Origin
						local dist = ray.Direction.Magnitude
						if dist > 0.01 then
							args[1] = Ray.new(origin, (rayState.pos - origin).Unit * dist)
							return oldNamecall(self, table.unpack(args))
						end
					end
					return rayState.part, rayState.pos, rayState.normal
				end
				if method == "Raycast" then
					local origin = args[1]
					local direction = args[2]
					local params = args[3]
					if typeof(origin) ~= "Vector3" then
						origin = args[2]
						direction = args[3]
						params = args[4]
					end
					if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
						local newDir = (rayState.pos - origin).Unit * direction.Magnitude
						if typeof(args[1]) == "Vector3" then
							return oldNamecall(self, origin, newDir, params)
						end
						return oldNamecall(self, args[1], origin, newDir, params)
					end
				end
			end

			if targetPart and method == "FireServer" then
				local remoteArgs = copyArgs(args)
				if handleArsenalRemote(self, method, remoteArgs) then
					return oldNamecall(self, table.unpack(remoteArgs))
				end
			end

			return oldNamecall(self, ...)
		end))

		state.silentNamecallRestore = oldNamecall
	end

	local function refresh()
		state.silentAimActive = game.PlaceId == ARSENAL_PLACE_ID
			and ctx.flags.flagOn("SilentAim")
			and hookmetamethod ~= nil
	end

	installHooks()

	return {
		refresh = refresh,
	}
end

return Silent
