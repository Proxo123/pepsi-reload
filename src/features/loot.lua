local Loot = {}

local PICKUP_HZ = 4
local PICKUP_COOLDOWN = 0.6
local MAX_PICKUPS_PER_TICK = 1
local INSTANT_RANGE = 14

local FALLBACK_AMMO = {
	["Light Ammo"] = true,
	["Medium Ammo"] = true,
	["Heavy Ammo"] = true,
	["Shells"] = true,
	["Rocket Ammo"] = true,
	["Arrow"] = true,
}

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local remoteHandler
	local ammoCaps
	local ammoNames = {}
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false
	local lootFolder

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

	local function getAmmoCaps()
		if ammoCaps then
			return ammoCaps
		end
		local ok, caps = pcall(require, RS.Modules.AmmoCaps)
		if ok then
			ammoCaps = caps
		end
		return ammoCaps
	end

	local function loadAmmoNames()
		if next(ammoNames) then
			return ammoNames
		end
		for name in FALLBACK_AMMO do
			ammoNames[name] = true
		end
		local caps = getAmmoCaps()
		if caps then
			for name in caps do
				if type(name) == "string" then
					ammoNames[name] = true
				end
			end
		end
		return ammoNames
	end

	local function getLootFolder()
		if lootFolder and lootFolder.Parent then
			return lootFolder
		end
		lootFolder = workspace:FindFirstChild("Loot")
		return lootFolder
	end

	local function getModelPosition(model)
		local part = model.PrimaryPart
			or model:FindFirstChild("Main")
			or model:FindFirstChild("Bottm")
			or model:FindFirstChildWhichIsA("BasePart")
		if part then
			return part.Position
		end
	end

	local function getLootId(model)
		local id = model:GetAttribute("ID")
		if type(id) == "string" and #id > 8 then
			return id
		end
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				id = child:GetAttribute("ID")
				if type(id) == "string" and #id > 8 then
					return id
				end
			elseif child:IsA("StringValue") and child.Name == "ID" then
				return child.Value
			end
		end
		if model.Name:match("^[%w%-]+$") and #model.Name > 20 then
			return model.Name
		end
	end

	local function isAmmoModel(model)
		if not model:IsA("Model") then
			return false
		end
		local names = loadAmmoNames()
		if names[model.Name] then
			return true
		end
		return model.Name:find("Ammo", 1, true) ~= nil
	end

	local function getPlayerRoot()
		local char = lp.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		local knocked = hum:FindFirstChild("Knocked")
		if knocked and knocked.Value then
			return
		end
		return char:FindFirstChild("HumanoidRootPart")
	end

	local function isClipFull(ammoName)
		local char = lp.Character
		local clips = char and char:FindFirstChild("AmmoClips")
		if not clips or not ammoName then
			return true
		end
		local clip = clips:FindFirstChild(ammoName)
		if not clip then
			return true
		end
		local caps = getAmmoCaps()
		local cap = caps and caps[ammoName]
		if cap and clip.Value >= cap then
			return true
		end
		return false
	end

	local function tryPickup(id)
		local now = tick()
		if pickedCooldown[id] and now - pickedCooldown[id] < PICKUP_COOLDOWN then
			return false
		end
		local rh = getRemoteHandler()
		if not rh or type(rh.InvokeServer) ~= "function" then
			return false
		end
		local ok = pcall(function()
			rh.InvokeServer("PickedUpLoot", id)
		end)
		if ok then
			pickedCooldown[id] = now
			return true
		end
		return false
	end

	local function getMaxRangeSq()
		local instant = ctx.flags.flagOn("InstantPickup")
		local far = ctx.flags.flagOn("FarPickup")
		if not instant and not far then
			return 0
		end
		local range = instant and INSTANT_RANGE or 0
		if far then
			local farRange = tonumber(ctx.flags.flagVal("PickupRange", ctx.config.DEFAULTS.PickupRange))
				or ctx.config.DEFAULTS.PickupRange
			range = math.max(range, farRange)
		end
		return range * range
	end

	local function pruneCooldowns(now)
		for id, time in pickedCooldown do
			if now - time > 10 then
				pickedCooldown[id] = nil
			end
		end
	end

	local function runPickup()
		local folder = getLootFolder()
		local root = getPlayerRoot()
		if not folder or not root then
			return
		end
		local maxRangeSq = getMaxRangeSq()
		if maxRangeSq <= 0 then
			return
		end

		local origin = root.Position
		local closestId
		local closestDistSq = maxRangeSq + 1

		for _, child in folder:GetChildren() do
			if isAmmoModel(child) and not isClipFull(child.Name) then
				local pos = getModelPosition(child)
				local id = getLootId(child)
				if pos and id and not pickedCooldown[id] then
					local delta = pos - origin
					local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
					if distSq <= maxRangeSq and distSq < closestDistSq then
						closestDistSq = distSq
						closestId = id
					end
				end
			end
		end

		if closestId then
			pruneCooldowns(tick())
			tryPickup(closestId)
		end
	end

	local function setActive(want)
		if want == active then
			return
		end
		active = want
		pickupAccum = 0
		lootFolder = nil
		if not want then
			table.clear(pickedCooldown)
		end
	end

	local function tickPickup(dt)
		local want = ctx.flags.flagOn("InstantPickup") or ctx.flags.flagOn("FarPickup")
		setActive(want)
		if not want then
			return
		end
		pickupAccum += dt
		if pickupAccum < (1 / PICKUP_HZ) then
			return
		end
		pickupAccum = 0
		runPickup()
	end

	return {
		tick = tickPickup,
	}
end

return Loot
