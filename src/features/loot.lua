local Loot = {}

local PICKUP_HZ = 3
local PICKUP_COOLDOWN = 0.55
local INSTANT_RANGE = 14
local INDEX_REFRESH = 10
local PICKUP_ALL_BATCH = 30
local PICKUP_ALL_DELAY = 0.05
local MAX_RANGE = 2500

local LOOT_AMMO_SHORT = {
	Light = "Light Ammo",
	Medium = "Medium Ammo",
	Heavy = "Heavy Ammo",
	Rocket = "Rocket Ammo",
	Shells = "Shells",
	Shotgun = "Shells",
	Arrow = "Arrow",
	Wood = "Wood",
}

local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x+%-"

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local remoteHandler
	local clientLootSpawn
	local ammoCaps
	local lootIndex = {}
	local pickedCooldown = {}
	local pickupAccum = 0
	local indexAccum = 0
	local active = false
	local lootFolder
	local pickupAllRunning = false
	local childAddedConn

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

	local function getClientLootSpawn()
		if clientLootSpawn then
			return clientLootSpawn
		end
		local ok, mod = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK.Modules.ClientLootSpawn)
		end)
		if ok then
			clientLootSpawn = mod
		end
		return clientLootSpawn
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

	local function getLootFolder()
		if lootFolder and lootFolder.Parent then
			return lootFolder
		end
		lootFolder = workspace:FindFirstChild("Loot")
		return lootFolder
	end

	local function isUuid(text)
		return type(text) == "string" and #text > 20 and text:match(UUID_PATTERN) ~= nil
	end

	local function getAmmoClipName(name)
		if not name then
			return
		end
		if LOOT_AMMO_SHORT[name] then
			return LOOT_AMMO_SHORT[name]
		end
		if name:find("Ammo", 1, true) or name == "Shells" or name == "Arrow" then
			return name
		end
	end

	local function inferLootType(name)
		if name == "Wood" then
			return "Wood"
		end
		if getAmmoClipName(name) then
			return "Ammo"
		end
		return "Item"
	end

	local function getInstancePosition(inst)
		if inst:IsA("BasePart") then
			return inst.Position
		end
		if inst:IsA("Model") then
			local part = inst.PrimaryPart
				or inst:FindFirstChild("Main")
				or inst:FindFirstChild("Bottm")
				or inst:FindFirstChildWhichIsA("BasePart")
			if part then
				return part.Position
			end
		end
	end

	local function upsertLoot(id, name, lootType, position)
		if not isUuid(id) or not position then
			return
		end
		local existing = lootIndex[id]
		if existing then
			existing.name = name or existing.name
			existing.lootType = lootType or existing.lootType
			existing.position = position
			return
		end
		lootIndex[id] = {
			id = id,
			name = name or "Loot",
			lootType = lootType or "Item",
			position = position,
		}
	end

	local function registerInstance(inst)
		if not inst then
			return
		end
		local id = inst:GetAttribute("ID")
		local name = inst.Name
		local pos = getInstancePosition(inst)

		if inst:IsA("BasePart") and not id then
			local parent = inst.Parent
			if parent and parent:IsA("Model") and parent.Parent == getLootFolder() then
				id = parent:GetAttribute("ID")
				name = parent.Name
				pos = getInstancePosition(parent) or pos
			elseif isUuid(inst.Name) then
				id = inst.Name
			end
		end

		if not id and isUuid(name) then
			id = name
		end

		if id and pos then
			upsertLoot(id, name, inferLootType(name), pos)
		end
	end

	local function ingestLootTable(data)
		if type(data) ~= "table" then
			return
		end
		for key, entry in data do
			if type(entry) == "table" then
				local id = entry.ID or entry.Id or (isUuid(key) and key)
				local pos = entry.Position or entry.Pos
				local name = entry.Name or entry.Gun or entry.Item
				local lootType = entry.type or entry.Type or inferLootType(name)
				if id and typeof(pos) == "Vector3" then
					upsertLoot(id, name, lootType, pos)
				end
			elseif isUuid(key) and typeof(entry) == "Vector3" then
				upsertLoot(key, key, "Item", entry)
			end
		end
	end

	local function refreshFromGameModule()
		local cls = getClientLootSpawn()
		if not cls or type(cls.GetItemByID) ~= "function" then
			return
		end
		for id, entry in lootIndex do
			local model = cls.GetItemByID(id)
			if model then
				local pos = getInstancePosition(model)
				if pos then
					entry.position = pos
					if model.Name and model.Name ~= "PhysicsBall" then
						entry.name = model.Name
						entry.lootType = inferLootType(model.Name)
					end
				end
			end
		end
	end

	local function refreshLootIndex(force)
		indexAccum += force and INDEX_REFRESH or 0
		if not force and indexAccum < INDEX_REFRESH then
			return
		end
		indexAccum = 0

		local rh = getRemoteHandler()
		if rh and type(rh.InvokeServer) == "function" then
			pcall(function()
				ingestLootTable(rh.InvokeServer("GiveRawData"))
			end)
		end

		local folder = getLootFolder()
		if folder then
			for _, child in folder:GetChildren() do
				registerInstance(child)
			end
		end

		refreshFromGameModule()
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

	local function canPickupLoot(entry)
		if entry.lootType == "Wood" and isWoodFull() then
			return false
		end
		if entry.lootType == "Ammo" then
			local clipName = getAmmoClipName(entry.name)
			if clipName and isClipFull(clipName) then
				return false
			end
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
			lootIndex[id] = nil
			return true
		end
		return false
	end

	local function collectTargets(maxRangeSq, ammoOnly)
		refreshLootIndex(false)
		local root = getPlayerRoot()
		if not root then
			return {}
		end
		local origin = root.Position
		local targets = {}
		for _, entry in lootIndex do
			if canPickupLoot(entry) and (not ammoOnly or entry.lootType == "Ammo") then
				local pos = entry.position
				if pos then
					local delta = pos - origin
					local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
					if distSq <= maxRangeSq then
						targets[#targets + 1] = { id = entry.id, distSq = distSq }
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
			tryPickup(targets[1].id)
		end
	end

	local function pickupAll()
		if pickupAllRunning then
			return 0
		end
		pickupAllRunning = true
		local tried = 0
		local ok, err = pcall(function()
			refreshLootIndex(true)
			local range = getPickupAllRange()
			local targets = collectTargets(range * range, false)
			for i = 1, math.min(#targets, PICKUP_ALL_BATCH) do
				tryPickup(targets[i].id)
				tried += 1
				if i % 3 == 0 then
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
		indexAccum = INDEX_REFRESH
		lootFolder = nil
		if not want then
			table.clear(pickedCooldown)
			if childAddedConn then
				childAddedConn:Disconnect()
				childAddedConn = nil
			end
			return
		end
		refreshLootIndex(true)
		local folder = getLootFolder()
		if folder and not childAddedConn then
			childAddedConn = folder.ChildAdded:Connect(function(child)
				task.defer(registerInstance, child)
			end)
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
