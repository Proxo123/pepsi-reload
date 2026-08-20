local Loot = {}

local PICKUP_HZ = 3
local PICKUP_COOLDOWN = 0.5
local INSTANT_RANGE = 14
local MAX_RANGE = 2500
local PICKUP_ALL_BATCH = 25
local PICKUP_ALL_DELAY = 0.06

local LOOT_AMMO_SHORT = {
	Light = "Light Ammo",
	Medium = "Medium Ammo",
	Heavy = "Heavy Ammo",
	Rocket = "Rocket Ammo",
	Shells = "Shells",
	Shotgun = "Shells",
	Arrow = "Arrow",
}

local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x+%-"

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local pickupRemote
	local ammoCaps
	local lootTable
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false
	local pickupAllRunning = false

	local function getPickupRemote()
		if pickupRemote then
			return pickupRemote
		end
		local handler = RS.Modules.M3WS_FRAMEWORK.Services:FindFirstChild("RemoteHandler")
		if handler then
			local get = handler:FindFirstChild("Get")
			if get and get.InvokeServer then
				pickupRemote = get
				return pickupRemote
			end
		end
		local ok, rh = pcall(function()
			return require(RS.Modules.M3WS_FRAMEWORK.Services.RemoteHandler)
		end)
		if ok and rh then
			if rh.Get and rh.Get.InvokeServer then
				pickupRemote = rh.Get
			elseif rh.InvokeServer then
				pickupRemote = rh
			end
		end
		return pickupRemote
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
		if type(entry) ~= "table" then
			return false
		end
		local id = rawget(entry, "ID")
		local pos = rawget(entry, "Position")
		local typ = rawget(entry, "type")
		return type(id) == "string" and #id > 8 and typeof(pos) == "Vector3" and type(typ) == "string"
	end

	local function getLootModule()
		local loaders = {
			function()
				return require(RS.Modules.M3WS_FRAMEWORK.Modules.ClientLootSpawn)
			end,
			function()
				local ok, m3 = pcall(require, RS.Modules.M3WS_FRAMEWORK)
				if ok and m3 and m3.GetModule then
					return m3.GetModule("ClientLootSpawn")
				end
			end,
		}
		for _, loader in loaders do
			local ok, mod = pcall(loader)
			if ok and type(mod) == "table" and type(mod.AddLootDrop) == "function" then
				return mod
			end
		end
	end

	local function findLootTable()
		if lootTable then
			return lootTable
		end
		local mod = getLootModule()
		if not mod or type(mod.AddLootDrop) ~= "function" then
			return
		end
		for i = 1, 100 do
			local ok, name, value = pcall(debug.getupvalue, mod.AddLootDrop, i)
			if not ok or not name then
				break
			end
			if type(value) == "table" then
				if name == "u15" then
					lootTable = value
					return lootTable
				end
				for _, entry in value do
					if isLootEntry(entry) then
						lootTable = value
						return lootTable
					end
				end
			end
		end
		for i = 1, 100 do
			local ok, _, value = pcall(debug.getupvalue, mod.AddLootDrop, i)
			if not ok then
				break
			end
			if type(value) == "table" then
				lootTable = value
				return lootTable
			end
		end
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

	local function inferType(name, entryType)
		if entryType then
			return entryType
		end
		if name == "Wood" then
			return "Wood"
		end
		if getAmmoClipName(name) then
			return "Ammo"
		end
		return "Item"
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
		return cap and clip.Value >= cap
	end

	local function canPickup(entry)
		if entry.lootType == "Wood" and isWoodFull() then
			return false
		end
		if entry.lootType == "Ammo" then
			local clip = getAmmoClipName(entry.name) or entry.name
			if clip and isClipFull(clip) then
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

	local function collectTargets(maxRangeSq, ammoOnly)
		local root = getPlayerRoot()
		if not root then
			return {}
		end
		local origin = root.Position
		local targets = {}
		local seen = {}

		local tableRef = findLootTable()
		if tableRef then
			for _, entry in tableRef do
				if isLootEntry(entry) then
					local id = rawget(entry, "ID")
					local pos = rawget(entry, "Position")
					local name = rawget(entry, "Name") or "Loot"
					local lootType = rawget(entry, "type") or "Item"
					if id and pos and not seen[id] then
						local wrapped = { id = id, position = pos, name = name, lootType = lootType }
						if canPickup(wrapped) and (not ammoOnly or lootType == "Ammo") then
							local delta = pos - origin
							local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
							if distSq <= maxRangeSq then
								seen[id] = true
								targets[#targets + 1] = { id = id, distSq = distSq }
							end
						end
					end
				end
			end
		end

		local folder = workspace:FindFirstChild("Loot")
		if folder then
			for _, inst in folder:GetDescendants() do
				local id = inst:GetAttribute("ID")
				if not id and isUuid(inst.Name) then
					id = inst.Name
				end
				if id and not seen[id] then
					local pos
					if inst:IsA("BasePart") then
						pos = inst.Position
					elseif inst:IsA("Model") then
						local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
						pos = part and part.Position
					end
					if pos then
						local name = inst.Name
						if inst:IsA("Model") then
							name = inst.Name
						elseif inst.Parent and inst.Parent:IsA("Model") and inst.Parent.Parent == folder then
							name = inst.Parent.Name
						end
						local wrapped = {
							id = id,
							position = pos,
							name = name,
							lootType = inferType(name),
						}
						if canPickup(wrapped) and (not ammoOnly or wrapped.lootType == "Ammo") then
							local delta = pos - origin
							local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
							if distSq <= maxRangeSq then
								seen[id] = true
								targets[#targets + 1] = { id = id, distSq = distSq }
							end
						end
					end
				end
			end
		end

		table.sort(targets, function(a, b)
			return a.distSq < b.distSq
		end)
		return targets
	end

	local function tryPickup(id)
		local remote = getPickupRemote()
		if not remote then
			return false
		end
		local now = tick()
		if pickedCooldown[id] and now - pickedCooldown[id] < PICKUP_COOLDOWN then
			return false
		end
		local ok, result = pcall(function()
			return remote:InvokeServer("PickedUpLoot", id)
		end)
		if ok and result == true then
			pickedCooldown[id] = now
			return true
		end
		return false
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
			return 0, "busy"
		end
		if not getPickupRemote() then
			return 0, "api"
		end
		pickupAllRunning = true
		local tried = 0
		local okCount = 0
		local ok, err = pcall(function()
			local range = getPickupAllRange()
			local targets = collectTargets(range * range, false)
			for i = 1, math.min(#targets, PICKUP_ALL_BATCH) do
				tried += 1
				if tryPickup(targets[i].id) then
					okCount += 1
				end
				if i % 3 == 0 then
					task.wait(PICKUP_ALL_DELAY)
				end
			end
		end)
		pickupAllRunning = false
		if not ok then
			warn("[Pepsi Reload] Pickup all failed:", err)
		end
		return okCount, tried == 0 and "empty" or nil
	end

	local function setActive(want)
		if want == active then
			return
		end
		active = want
		pickupAccum = 0
		if not want then
			table.clear(pickedCooldown)
		else
			getPickupRemote()
			findLootTable()
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
