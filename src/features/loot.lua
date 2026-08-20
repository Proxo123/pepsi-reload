local Loot = {}

local PICKUP_HZ = 6
local PICKUP_COOLDOWN = 0.45
local MAX_PICKUPS_PER_TICK = 2
local INSTANT_RANGE = 14
local LOOT_TABLE_RETRY = 3
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

	local function readEntry(entry, key)
		if type(entry) ~= "table" then
			return
		end
		return rawget(entry, key)
	end

	local function isAmmoEntry(entry)
		if type(entry) ~= "table" then
			return false
		end
		local id = rawget(entry, "ID")
		local pos = rawget(entry, "Position")
		local lootType = rawget(entry, "type")
		return type(id) == "string"
			and #id > 8
			and typeof(pos) == "Vector3"
			and lootType == "Ammo"
	end

	local function scanLootTableOnce()
		local best
		local bestAmmo = 0
		for _, value in getgc(true) do
			if type(value) == "table" then
				local ammoCount = 0
				for _, entry in value do
					if isAmmoEntry(entry) then
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
		for id, entry in lootTable do
			if isAmmoEntry(entry) then
				if not readEntry(entry, "Ignore") and not readEntry(entry, "OPEN") then
					local ball = readEntry(entry, "Ball")
					if not ball or ball.Parent then
						ammoIndex[#ammoIndex + 1] = entry
					end
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
		if readEntry(entry, "Chest") or readEntry(entry, "AmmoBox") or readEntry(entry, "AirDrop") then
			return false
		end
		local name = readEntry(entry, "Name")
		if not name or fullClips[name] then
			return false
		end
		return true
	end

	local function tryPickup(entry, lootTable)
		local id = readEntry(entry, "ID")
		if not id then
			return false
		end
		local now = tick()
		if pickedCooldown[id] and now - pickedCooldown[id] < PICKUP_COOLDOWN then
			return false
		end
		local rh = getRemoteHandler()
		if not rh or type(rh.InvokeServer) ~= "function" then
			return false
		end

		local ok = pcall(function()
			if lootTable then
				lootTable[id] = nil
			end
			local ball = readEntry(entry, "Ball")
			if ball and ball.Parent then
				ball:Destroy()
			end
			rh.InvokeServer("PickedUpLoot", id)
		end)

		if ok then
			pickedCooldown[id] = now
			for i = #ammoIndex, 1, -1 do
				if readEntry(ammoIndex[i], "ID") == id then
					table.remove(ammoIndex, i)
				end
			end
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
				local pos = readEntry(entry, "Position")
				if typeof(pos) == "Vector3" then
					local delta = pos - origin
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
		end

		local now = tick()
		pruneCooldowns(now)
		for i = 1, bestCount do
			tryPickup(best[i].entry, lootTable)
		end
	end

	local function setActive(want)
		if want == active then
			return
		end
		active = want
		pickupAccum = 0
		if want then
			lootTableCache = nil
			lootLookupFailedAt = 0
			ammoIndexTime = 0
			table.clear(ammoIndex)
		else
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
