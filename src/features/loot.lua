local Loot = {}

local PICKUP_HZ = 3
local PICKUP_COOLDOWN = 0.55
local INSTANT_RANGE = 14
local MAX_RANGE = 2500
local PICKUP_ALL_BATCH = 20
local PICKUP_ALL_DELAY = 0.12
local API_RETRY = 0.75

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
	local lootModule
	local getCurrentItemFn
	local u18Index
	local pickupKey
	local apiReady = false
	local apiLookupAt = 0
	local gcScanned = false

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
		return type(id) == "string" and #id > 8 and typeof(pos) == "Vector3" and type(typ) == "string"
	end

	local function countLootEntries(tbl)
		if type(tbl) ~= "table" then
			return 0
		end
		local count = 0
		for _, entry in tbl do
			if isLootEntry(entry) then
				count += 1
			end
		end
		return count
	end

	local function isRemoteHandler(tbl)
		return type(tbl) == "table" and type(tbl.InvokeServer) == "function" and type(tbl.FireServer) == "function"
	end

	local function getLootModule()
		if lootModule then
			return lootModule
		end
		local loaders = {
			function()
				return require(RS.Modules.M3WS_FRAMEWORK.Modules.ClientLootSpawn)
			end,
			function()
				local ok, m3 = pcall(require, RS.Modules.M3WS_FRAMEWORK)
				if ok and m3 and type(m3.GetModule) == "function" then
					return m3.GetModule("ClientLootSpawn")
				end
			end,
		}
		for _, loader in loaders do
			local ok, mod = pcall(loader)
			if ok and type(mod) == "table" and type(mod.AddLootDrop) == "function" then
				lootModule = mod
				if type(mod.GetCurrentItem) == "function" then
					getCurrentItemFn = mod.GetCurrentItem
				end
				return mod
			end
		end
	end

	local function findLootTable(mod)
		local bestTable
		local bestScore = -1
		local scan = { mod.AddLootDrop, mod.GetItemByID, mod.GetCurrentItem }
		for _, fn in scan do
			if type(fn) ~= "function" then
				continue
			end
			for i = 1, 100 do
				local ok, name, value = pcall(debug.getupvalue, fn, i)
				if not ok or not name then
					break
				end
				if type(value) == "table" then
					local score = countLootEntries(value)
					if name == "u15" then
						return value
					end
					if score > bestScore then
						bestScore = score
						bestTable = value
					end
				end
			end
		end
		if bestTable then
			return bestTable
		end
		for i = 1, 100 do
			local ok, name, value = pcall(debug.getupvalue, mod.AddLootDrop, i)
			if not ok or not name then
				break
			end
			if type(value) == "table" then
				return value
			end
		end
	end

	local function findPickUpFn(tableRef)
		if not tableRef or type(getgc) ~= "function" then
			return
		end
		local bestFn
		local bestScore = -1
		for _, fn in getgc(true) do
			if type(fn) ~= "function" then
				continue
			end
			local hasLoot = false
			local hasRemote = false
			local hasBool = false
			for i = 1, 100 do
				local ok, _, value = pcall(debug.getupvalue, fn, i)
				if not ok then
					break
				end
				if value == tableRef then
					hasLoot = true
				end
				if isRemoteHandler(value) then
					hasRemote = true
				end
				if type(value) == "boolean" then
					hasBool = true
				end
			end
			if hasLoot and hasRemote then
				local score = hasBool and 2 or 1
				if score > bestScore then
					bestScore = score
					bestFn = fn
				end
			end
		end
		return bestFn
	end

	local function cacheU18Index()
		if u18Index or not getCurrentItemFn then
			return
		end
		for i = 1, 20 do
			local ok, _, value = pcall(debug.getupvalue, getCurrentItemFn, i)
			if not ok then
				break
			end
			if value == nil or type(value) == "table" then
				u18Index = i
				return
			end
		end
		u18Index = 1
	end

	local function cachePickupKey()
		if pickupKey then
			return
		end
		local ok, key = pcall(function()
			return Enum.KeyCode[lp:WaitForChild("Settings"):WaitForChild("Pick Up").Value]
		end)
		if ok and key then
			pickupKey = key
		else
			pickupKey = Enum.KeyCode.E
		end
	end

	local function pressPickupKey()
		cachePickupKey()
		local vim = game:GetService("VirtualInputManager")
		pcall(function()
			vim:SendKeyEvent(true, pickupKey, false, game)
			task.wait(0.04)
			vim:SendKeyEvent(false, pickupKey, false, game)
		end)
	end

	local function canUsePickup()
		return lootTable ~= nil and (pickUpFn ~= nil or (getCurrentItemFn ~= nil and u18Index ~= nil))
	end

	local function resolvePickupApi(force)
		if apiReady and canUsePickup() then
			return true
		end
		local now = tick()
		if not force and now - apiLookupAt < API_RETRY then
			return canUsePickup()
		end
		apiLookupAt = now

		local mod = getLootModule()
		if mod and not lootTable then
			lootTable = findLootTable(mod)
		end

		if lootTable and not pickUpFn and not gcScanned and type(getgc) == "function" then
			gcScanned = true
			pickUpFn = findPickUpFn(lootTable)
		end

		cacheU18Index()
		cachePickupKey()

		apiReady = canUsePickup()
		return apiReady
	end

	task.spawn(function()
		for _ = 1, 40 do
			if resolvePickupApi(true) then
				break
			end
			task.wait(1.5)
		end
	end)

	local function unlockPickup()
		if not pickUpFn then
			return
		end
		for i = 1, 100 do
			local ok, name, value = pcall(debug.getupvalue, pickUpFn, i)
			if not ok or not name then
				break
			end
			if type(value) == "boolean" and value == false then
				pcall(debug.setupvalue, pickUpFn, i, true)
			end
		end
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

	local function getAutoRange()
		local range = 0
		if ctx.flags.flagOn("InstantPickup") then
			range = math.max(range, INSTANT_RANGE)
		end
		if ctx.flags.flagOn("FarPickup") then
			local farRange = tonumber(ctx.flags.flagVal("PickupRange", ctx.config.DEFAULTS.PickupRange))
				or ctx.config.DEFAULTS.PickupRange
			range = math.max(range, farRange)
		end
		return math.clamp(range, 0, MAX_RANGE)
	end

	local function getPickupAllRange()
		local allRange = tonumber(ctx.flags.flagVal("PickupAllRange", ctx.config.DEFAULTS.PickupAllRange))
			or ctx.config.DEFAULTS.PickupAllRange
		return math.clamp(allRange, INSTANT_RANGE, MAX_RANGE)
	end

	local function invokePickup(entry)
		unlockPickup()
		if pickUpFn then
			return pcall(pickUpFn, entry, true)
		end
		if getCurrentItemFn and u18Index then
			local ok = pcall(debug.setupvalue, getCurrentItemFn, u18Index, entry)
			if ok then
				pressPickupKey()
				return true
			end
		end
		return false
	end

	local function tryPickupEntry(entry)
		if not resolvePickupApi(true) then
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
		local ok = invokePickup(entry)
		if ok then
			pickedCooldown[id] = now
			return true
		end
		unlockPickup()
		return false
	end

	local function collectTargets(maxRangeSq, ammoOnly)
		if not resolvePickupApi(true) or not lootTable then
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
		local range = getAutoRange()
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
			return 0, "busy"
		end
		for _ = 1, 20 do
			if resolvePickupApi(true) then
				break
			end
			task.wait(0.5)
		end
		if not canUsePickup() then
			return 0, "api"
		end
		pickupAllRunning = true
		local tried = 0
		local ok, err = pcall(function()
			unlockPickup()
			local range = getPickupAllRange()
			local targets = collectTargets(range * range, false)
			for i = 1, math.min(#targets, PICKUP_ALL_BATCH) do
				tryPickupEntry(targets[i].entry)
				tried += 1
				task.wait(PICKUP_ALL_DELAY)
			end
			unlockPickup()
		end)
		pickupAllRunning = false
		if not ok then
			warn("[Pepsi Reload] Pickup all failed:", err)
			unlockPickup()
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
			unlockPickup()
		else
			resolvePickupApi(true)
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
