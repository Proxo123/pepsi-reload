local Loot = {}

local PICKUP_HZ = 4
local PICKUP_COOLDOWN = 0.6
local GAME_PICKUP_RANGE = 14
local API_RETRY = 5
local PICKUP_ALL_BATCH = 12
local PICKUP_ALL_DELAY = 0.08

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local ammoCaps
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false
	local pickupAllRunning = false
	local pickUpFn
	local lootTable
	local apiLookupAt = 0

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
		if type(entry) ~= "table" then
			return false
		end
		local id = rawget(entry, "ID")
		local pos = rawget(entry, "Position")
		local typ = rawget(entry, "type")
		return type(id) == "string"
			and #id > 8
			and typeof(pos) == "Vector3"
			and type(typ) == "string"
	end

	local function ensurePickupApi()
		if pickUpFn and lootTable then
			return true
		end
		local now = tick()
		if now - apiLookupAt < API_RETRY then
			return false
		end
		apiLookupAt = now

		local bestTable
		local bestCount = 0
		for _, value in getgc(true) do
			if type(value) == "table" then
				local count = 0
				for _, entry in value do
					if isLootEntry(entry) then
						count += 1
					end
				end
				if count > bestCount then
					bestTable = value
					bestCount = count
				end
			end
		end
		if bestCount > 0 then
			lootTable = bestTable
		end

		for _, fn in getgc(true) do
			if type(fn) == "function" then
				for i = 1, 80 do
					local ok, name, val = pcall(debug.getupvalue, fn, i)
					if not ok or not name then
						break
					end
					if name == "u83" and type(val) == "function" then
						pickUpFn = val
						break
					end
				end
				if pickUpFn then
					break
				end
			end
		end

		return pickUpFn ~= nil and lootTable ~= nil
	end

	local function isWoodFull()
		local inv = RS:FindFirstChild("PlayersInventory") and RS.PlayersInventory:FindFirstChild(lp.Name)
		local cap = RS:FindFirstChild("GameInfo") and RS.GameInfo:FindFirstChild("WoodCap")
		if not inv or not cap then
			return false
		end
		local wood = inv:FindFirstChild("Wood")
		return wood and wood.Value >= cap.Value
	end

	local function isClipFull(clipName)
		if not clipName then
			return false
		end
		local char = lp.Character
		local clips = char and char:FindFirstChild("AmmoClips")
		if not clips then
			return true
		end
		local clip = clips:FindFirstChild(clipName)
		if not clip then
			return true
		end
		local caps = getAmmoCaps()
		local cap = caps and caps[clipName]
		if cap and clip.Value >= cap then
			return true
		end
		return false
	end

	local function canPickupEntry(entry)
		if not isLootEntry(entry) then
			return false
		end
		if rawget(entry, "OPEN") == true then
			return false
		end
		local typ = rawget(entry, "type")
		if typ == "Wood" and isWoodFull() then
			return false
		end
		if typ == "Ammo" then
			local clipName = rawget(entry, "Name")
			if clipName and isClipFull(clipName) then
				return false
			end
		end
		local ball = rawget(entry, "Ball")
		if ball and not ball.Parent then
			return false
		end
		return true
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

	local function getPickupRange()
		local instant = ctx.flags.flagOn("InstantPickup")
		local far = ctx.flags.flagOn("FarPickup")
		local range = 0
		if instant then
			range = GAME_PICKUP_RANGE
		end
		if far then
			local farRange = tonumber(ctx.flags.flagVal("PickupRange", ctx.config.DEFAULTS.PickupRange))
				or ctx.config.DEFAULTS.PickupRange
			range = math.max(range, farRange)
		end
		return math.min(range, GAME_PICKUP_RANGE)
	end

	local function getPickupAllRange()
		local allRange = tonumber(ctx.flags.flagVal("PickupAllRange", ctx.config.DEFAULTS.PickupAllRange))
			or ctx.config.DEFAULTS.PickupAllRange
		return math.min(allRange, GAME_PICKUP_RANGE)
	end

	local function tryPickupEntry(entry)
		if not ensurePickupApi() or not pickUpFn then
			return false
		end
		local id = rawget(entry, "ID")
		if not id then
			return false
		end
		local now = tick()
		if pickedCooldown[id] and now - pickedCooldown[id] < PICKUP_COOLDOWN then
			return false
		end
		local ok = pcall(pickUpFn, entry, true)
		if ok then
			pickedCooldown[id] = now
			return true
		end
		return false
	end

	local function collectTargets(maxRangeSq, ammoOnly)
		if not ensurePickupApi() or not lootTable then
			return {}
		end
		local root = getPlayerRoot()
		if not root then
			return {}
		end
		local origin = root.Position
		local targets = {}
		for _, entry in lootTable do
			if canPickupEntry(entry) and (not ammoOnly or rawget(entry, "type") == "Ammo") then
				local pos = rawget(entry, "Position")
				if pos then
					local delta = pos - origin
					local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
					if distSq <= maxRangeSq then
						targets[#targets + 1] = { entry = entry, distSq = distSq }
					end
				end
			end
		end
		table.sort(targets, function(a, b)
			return a.distSq < b.distSq
		end)
		return targets
	end

	local function runPickup()
		local range = getPickupRange()
		if range <= 0 then
			return
		end
		local targets = collectTargets(range * range, true)
		if targets[1] then
			tryPickupEntry(targets[1].entry)
		end
	end

	local function pickupAll()
		if pickupAllRunning then
			return 0
		end
		pickupAllRunning = true
		local tried = 0
		local ok, err = pcall(function()
			local range = getPickupAllRange()
			local targets = collectTargets(range * range, false)
			for i = 1, math.min(#targets, PICKUP_ALL_BATCH) do
				tryPickupEntry(targets[i].entry)
				tried += 1
				if i % 2 == 0 then
					task.wait(PICKUP_ALL_DELAY)
				end
			end
		end)
		pickupAllRunning = false
		if not ok then
			warn("[Pepsi Reload] Pickup all failed:", err)
		end
		return tried
	end

	local function setActive(want)
		if want == active then
			return
		end
		active = want
		pickupAccum = 0
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
		pickupAll = pickupAll,
	}
end

return Loot
