local Loot = {}

local PICKUP_HZ = 6
local PICKUP_COOLDOWN = 0.45
local MAX_PICKUPS_PER_TICK = 2
local INSTANT_RANGE = 14
local LOOT_TABLE_RETRY = 12
local AMMO_INDEX_REFRESH = 4

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local remoteHandler
	local ammoCaps
	local lootTableCache
	local lootLookupFailedAt = 0
	local ammoIndex = {}
	local ammoIndexTime = 0
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false

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
			and entry.type == "Ammo"
	end

	local function scanLootTableOnce()
		local best
		local bestAmmo = 0
		for _, value in getgc(true) do
			if type(value) == "table" and not getmetatable(value) then
				local ammoCount = 0
				for _, entry in value do
					if isLootEntry(entry) then
						ammoCount += 1
					end
				end
				if ammoCount > bestAmmo then
					best = value
					bestAmmo = ammoCount
				end
			end
		end
		return bestAmmo > 0 and best or nil
	end

	local function getLootTable()
		if lootTableCache then
			return lootTableCache
		end
		local now = tick()
		if now - lootLookupFailedAt < LOOT_TABLE_RETRY then
			return
		end
		lootTableCache = scanLootTableOnce()
		lootLookupFailedAt = now
		ammoIndexTime = 0
		return lootTableCache
	end

	local function refreshAmmoIndex(lootTable)
		table.clear(ammoIndex)
		for _, entry in lootTable do
			if isLootEntry(entry) and not entry.Ignore and not entry.OPEN then
				if not entry.Ball or entry.Ball.Parent then
					ammoIndex[#ammoIndex + 1] = entry
				end
			end
		end
		ammoIndexTime = tick()
	end

	local function getAmmoIndex(lootTable)
		local now = tick()
		if #ammoIndex == 0 or now - ammoIndexTime >= AMMO_INDEX_REFRESH then
			refreshAmmoIndex(lootTable)
		end
		return ammoIndex
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

	local function getClipState()
		local char = lp.Character
		local clips = char and char:FindFirstChild("AmmoClips")
		if not clips then
			return
		end
		local caps = getAmmoCaps()
		local full = {}
		for _, clip in clips:GetChildren() do
			if clip:IsA("ValueBase") then
				local cap = caps and caps[clip.Name]
				if cap and clip.Value >= cap then
					full[clip.Name] = true
				end
			end
		end
		return full
	end

	local function canPickupAmmo(entry, fullClips)
		if entry.Chest or entry.AmmoBox or entry.AirDrop then
			return false
		end
		if not entry.Name or fullClips[entry.Name] then
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
			if now - time > 8 then
				pickedCooldown[id] = nil
			end
		end
	end

	local function runPickup()
		local root = getPlayerRoot()
		if not root then
			return
		end
		local lootTable = getLootTable()
		if not lootTable then
			return
		end
		local maxRangeSq = getMaxRangeSq()
		if maxRangeSq <= 0 then
			return
		end

		local origin = root.Position
		local fullClips = getClipState()
		if not fullClips then
			return
		end

		local entries = getAmmoIndex(lootTable)
		local best = {}
		local bestCount = 0

		for i = 1, #entries do
			local entry = entries[i]
			if canPickupAmmo(entry, fullClips) then
				local delta = entry.Position - origin
				local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
				if distSq <= maxRangeSq then
					if bestCount < MAX_PICKUPS_PER_TICK then
						bestCount += 1
						best[bestCount] = { distSq = distSq, entry = entry }
					else
						local worstIdx = 1
						local worstDist = best[1].distSq
						for j = 2, bestCount do
							if best[j].distSq > worstDist then
								worstDist = best[j].distSq
								worstIdx = j
							end
						end
						if distSq < worstDist then
							best[worstIdx] = { distSq = distSq, entry = entry }
						end
					end
				end
			end
		end

		local now = tick()
		pruneCooldowns(now)
		for i = 1, bestCount do
			tryPickup(best[i].entry)
		end
	end

	local function setActive(want)
		if want == active then
			return
		end
		active = want
		pickupAccum = 0
		if not want then
			lootTableCache = nil
			ammoIndexTime = 0
			table.clear(ammoIndex)
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
