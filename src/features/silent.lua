local Silent = {}

local ARSENAL_PLACE_ID = 286090429

local REMOTE_NAMES = {
	HitPart = true,
	Trail = true,
	CreateProjectile = true,
	Flames = true,
	Fire = true,
	ReplicateProjectile = true,
}

function Silent.create(ctx)
	local state = ctx.state
	local hookBusy = false

	local function isActive()
		return state.silentAimActive
	end

	local function fromExecutor()
		return checkcaller and checkcaller()
	end

	local function getHitbox()
		local part = state.silentTargetPart
		if not part or not part.Parent then
			return nil
		end
		if part.Name == "Hitbox" then
			return part
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

	local function rayHitFor(part)
		local pos = part.Position
		ctx.camera = workspace.CurrentCamera
		local origin = ctx.camera and ctx.camera.CFrame.Position or pos
		local diff = pos - origin
		local normal = diff.Magnitude > 0.01 and -diff.Unit or Vector3.new(0, 1, 0)
		return part, pos, normal
	end

	local function copyArgs(args)
		local out = {}
		for i = 1, #args do
			out[i] = args[i]
		end
		return out
	end

	local function patchRemoteArgs(name, args, hitbox)
		local pos = hitbox.Position
		if name == "HitPart" then
			args[1] = hitbox
			return true
		end
		if name == "Fire" then
			args[1] = pos
			return true
		end
		if name == "Flames" then
			args[1] = hitbox.CFrame
			args[2] = pos
			args[5] = pos
			return true
		end
		if name == "ReplicateProjectile" then
			if type(args[1]) == "table" then
				args[1][3] = pos
				args[1][4] = pos
				args[1][10] = pos
			end
			return true
		end
		if name == "CreateProjectile" then
			args[3] = pos
			args[4] = hitbox.CFrame
			args[10] = pos
			args[17] = pos
			args[18] = hitbox
			args[19] = pos
			return true
		end
		if name == "Trail" then
			if type(args[1]) == "table" and type(args[1][5]) == "string" then
				args[1][2] = pos
				args[1][6] = hitbox
			end
			return true
		end
		return false
	end

	local function installHooks()
		if state.silentHooksInstalled or not hookmetamethod then
			return
		end

		local mouse = ctx.lp:GetMouse()
		local oldNamecall
		local oldIndex

		oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			if hookBusy or fromExecutor() or not isActive() then
				return oldNamecall(self, ...)
			end

			local method = getnamecallmethod()
			local args = { ... }
			local hitbox = getHitbox()

			if method == "FireServer" and hitbox then
				local name = tostring(self)
				if REMOTE_NAMES[name] then
					local remoteArgs = copyArgs(args)
					if patchRemoteArgs(name, remoteArgs, hitbox) then
						hookBusy = true
						local ok, result = pcall(function()
							return self.FireServer(self, table.unpack(remoteArgs))
						end)
						hookBusy = false
						if ok then
							return result
						end
					end
				end
			end

			if hitbox and self == workspace then
				if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" or method == "findPartOnRay" then
					return rayHitFor(hitbox)
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
						local newDir = (hitbox.Position - origin).Unit * direction.Magnitude
						hookBusy = true
						local ok, result = pcall(function()
							if typeof(args[1]) == "Vector3" then
								return oldNamecall(self, origin, newDir, params)
							end
							return oldNamecall(self, args[1], origin, newDir, params)
						end)
						hookBusy = false
						if ok then
							return result
						end
					end
				end
			end

			return oldNamecall(self, ...)
		end))

		if mouse then
			oldIndex = hookmetamethod(game, "__index", newcclosure(function(obj, index)
				if hookBusy or fromExecutor() or not isActive() or obj ~= mouse then
					return oldIndex(obj, index)
				end
				local target = getHitbox()
				if not target then
					return oldIndex(obj, index)
				end
				if index == "Target" or index == "target" then
					return target
				end
				if index == "Hit" or index == "hit" then
					return target.CFrame
				end
				return oldIndex(obj, index)
			end))
		end

		state.silentNamecallRestore = oldNamecall
		state.silentIndexRestore = oldIndex
		state.silentHooksInstalled = true
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
