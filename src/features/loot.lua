local Loot = {}

local PICKUP_COOLDOWN = 0.4
local MAX_PICKUPS_PER_TICK = 4
local INSTANT_RANGE = 14

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local remoteHandler
	local ammoCaps
	local lootTableCache
	local lootTableTime = 0
	local pickedCooldown = {}

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

	local function isLootEntry(entry)
		return type(entry) == "table"
			and type(entry.ID) == "string"
			and #entry.ID > 8
			and typeof(entry.Position) == "Vector3"
			and type(entry.type) == "string"
	end

	local function findLootTable()
		local now = tick()
		if lootTableCache and now - lootTableTime < 1.5 then
			return lootTableCache
		end
		local best
		local bestAmmo = 0
		for _, value in getgc(true) do
			if type(value) == "table" and not getmetatable(value) then
				local ammoCount = 0
				for _, entry in value do
					if isLootEntry(entry) and entry.type == "Ammo" then
						ammoCount += 1
					end
				end
				if ammoCount > bestAmmo then
					best = value
					bestAmmo = ammoCount
				end
			end
		end
		lootTableCache = bestAmmo > 0 and best or nil
		lootTableTime = now
		return lootTableCache
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

	local function canPickupAmmo(entry)
		if entry.type ~= "Ammo" or entry.Ignore or entry.OPEN then
			return false
		end
		if entry.Chest or entry.AmmoBox or entry.AirDrop then
			return false
		end
		if entry.Ball and not entry.Ball.Parent then
			return false
		end
		local char = lp.Character
		if not char then
			return false
		end
		local clips = char:FindFirstChild("AmmoClips")
		if not clips or not entry.Name then
			return false
		end
		local clip = clips:FindFirstChild(entry.Name)
		if not clip then
			return false
		end
		local caps = getAmmoCaps()
		if caps and caps[entry.Name] and clip.Value >= caps[entry.Name] then
			return false
		end
		return true
	end

	local function tryPickup(entry)
		local id = entry.ID
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

	local function getMaxRange()
		local instant = ctx.flags.flagOn("InstantPickup")
		local far = ctx.flags.flagOn("FarPickup")
		if not instant and not far then
			return 0
		end
		local range = 0
		if instant then
			range = INSTANT_RANGE
		end
		if far then
			local farRange = tonumber(ctx.flags.flagVal("PickupRange", ctx.config.DEFAULTS.PickupRange))
				or ctx.config.DEFAULTS.PickupRange
			range = math.max(range, farRange)
		end
		return range
	end

	local function tickPickup()
		if not ctx.flags.flagOn("InstantPickup") and not ctx.flags.flagOn("FarPickup") then
			return
		end
		local root = getPlayerRoot()
		if not root then
			return
		end
		local lootTable = findLootTable()
		if not lootTable then
			return
		end
		local maxRange = getMaxRange()
		if maxRange <= 0 then
			return
		end
		local origin = root.Position
		local candidates = {}
		for _, entry in lootTable do
			if canPickupAmmo(entry) then
				local dist = (entry.Position - origin).Magnitude
				if dist <= maxRange then
					table.insert(candidates, { dist = dist, entry = entry })
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.dist < b.dist
		end)
		local picked = 0
		for _, item in candidates do
			if picked >= MAX_PICKUPS_PER_TICK then
				break
			end
			if tryPickup(item.entry) then
				picked += 1
			end
		end
	end

	return {
		tick = tickPickup,
	}
end

return Loot
