local Loot = {}

local PICKUP_HZ = 4
local PICKUP_COOLDOWN = 0.6
local INSTANT_RANGE = 14
local MAX_RANGE = 2500

local FALLBACK_AMMO = {
	["Light Ammo"] = true,
	["Medium Ammo"] = true,
	["Heavy Ammo"] = true,
	["Shells"] = true,
	["Rocket Ammo"] = true,
	["Arrow"] = true,
}

local LOOT_AMMO_SHORT = {
	Light = "Light Ammo",
	Medium = "Medium Ammo",
	Heavy = "Heavy Ammo",
	Rocket = "Rocket Ammo",
	Shells = "Shells",
	Shotgun = "Shells",
	Arrow = "Arrow",
}

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local pickupRemote
	local ammoCaps
	local ammoNames = {}
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false
	local lootFolder

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

	local function loadAmmoNames()
		if next(ammoNames) then
			return ammoNames
		end
		for name in FALLBACK_AMMO do
			ammoNames[name] = true
		end
		for short, clip in LOOT_AMMO_SHORT do
			ammoNames[short] = true
			ammoNames[clip] = true
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

	local function getClipName(modelName)
		if LOOT_AMMO_SHORT[modelName] then
			return LOOT_AMMO_SHORT[modelName]
		end
		if loadAmmoNames()[modelName] then
			return modelName
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

	local function isWoodModel(model)
		return model:IsA("Model") and model.Name == "Wood"
	end

	local function isItemModel(model)
		if not model:IsA("Model") then
			return false
		end
		if isAmmoModel(model) or isWoodModel(model) then
			return false
		end
		return getLootId(model) ~= nil
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

	local function isInventoryFull()
		local inv = RS:FindFirstChild("PlayersInventory") and RS.PlayersInventory:FindFirstChild(lp.Name)
		if not inv then
			return false
		end
		local count = 0
		for _, child in inv:GetChildren() do
			if child:IsA("ObjectValue") and child.Value then
				count += 1
			end
		end
		return count >= 6
	end

	local function canPickupModel(model)
		if isAmmoModel(model) then
			return not isClipFull(model.Name)
		end
		if isWoodModel(model) then
			return not isWoodFull()
		end
		if isItemModel(model) then
			return not isInventoryFull()
		end
		return false
	end

	local function shouldScanModel(model)
		if isAmmoModel(model) then
			return ctx.flags.flagOn("InstantPickup") or ctx.flags.flagOn("FarPickup")
		end
		if isItemModel(model) or isWoodModel(model) then
			return ctx.flags.flagOn("PickupGuns")
		end
		return false
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

	local function isClipFull(modelName)
		local clipName = getClipName(modelName)
		if not clipName then
			return true
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

	local function tryPickup(id)
		local now = tick()
		if pickedCooldown[id] and now - pickedCooldown[id] < PICKUP_COOLDOWN then
			return false
		end
		local remote = getPickupRemote()
		if not remote then
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

	local function getMaxRangeSq()
		local instant = ctx.flags.flagOn("InstantPickup")
		local far = ctx.flags.flagOn("FarPickup")
		local guns = ctx.flags.flagOn("PickupGuns")
		if not instant and not far and not guns then
			return 0
		end
		local range = 0
		if instant or guns then
			range = math.max(range, INSTANT_RANGE)
		end
		if far or guns then
			local farRange = tonumber(ctx.flags.flagVal("PickupRange", ctx.config.DEFAULTS.PickupRange))
				or ctx.config.DEFAULTS.PickupRange
			range = math.max(range, farRange)
		end
		range = math.clamp(range, 0, MAX_RANGE)
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
			if shouldScanModel(child) and canPickupModel(child) then
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
		local want = ctx.flags.flagOn("InstantPickup")
			or ctx.flags.flagOn("FarPickup")
			or ctx.flags.flagOn("PickupGuns")
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
