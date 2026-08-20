local Loot = {}

local PICKUP_HZ = 4
local PICKUP_COOLDOWN = 0.6
local MAX_PICKUPS_PER_TICK = 1
local INSTANT_RANGE = 14
local PICKUP_ALL_BATCH = 35
local PICKUP_ALL_DELAY = 0.04

local LOOT_AMMO_SHORT = {
	Light = "Light Ammo",
	Medium = "Medium Ammo",
	Heavy = "Heavy Ammo",
	Rocket = "Rocket Ammo",
	Shells = "Shells",
	Arrow = "Arrow",
}

function Loot.create(ctx)
	local lp = ctx.lp
	local RS = ctx.services.RS

	local remoteHandler
	local ammoCaps
	local pickedCooldown = {}
	local pickupAccum = 0
	local active = false
	local lootFolder
	local pickupAllRunning = false

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
		if not model then
			return
		end
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
	end

	local function getAmmoClipName(modelName)
		if LOOT_AMMO_SHORT[modelName] then
			return LOOT_AMMO_SHORT[modelName]
		end
		if modelName:find("Ammo", 1, true) then
			return modelName
		end
	end

	local function isAmmoModel(model)
		if not model:IsA("Model") then
			return false
		end
		return getAmmoClipName(model.Name) ~= nil
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

	local function canPickupModel(model)
		if not model:IsA("Model") then
			return false
		end
		if model:GetAttribute("OPEN") == true then
			return false
		end
		if model.Name == "Wood" and isWoodFull() then
			return false
		end
		local clipName = getAmmoClipName(model.Name)
		if clipName and isClipFull(clipName) then
			return false
		end
		return getLootId(model) ~= nil
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

	local function getPickupAllRange()
		return tonumber(ctx.flags.flagVal("PickupAllRange", ctx.config.DEFAULTS.PickupAllRange))
			or ctx.config.DEFAULTS.PickupAllRange
	end

	local function collectTargets(maxRangeSq, ammoOnly)
		local folder = getLootFolder()
		local root = getPlayerRoot()
		if not folder or not root then
			return {}
		end
		local origin = root.Position
		local targets = {}
		for _, child in folder:GetChildren() do
			if canPickupModel(child) and (not ammoOnly or isAmmoModel(child)) then
				local pos = getModelPosition(child)
				local id = getLootId(child)
				if pos and id then
					local delta = pos - origin
					local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
					if distSq <= maxRangeSq then
						targets[#targets + 1] = { id = id, distSq = distSq }
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
		local maxRangeSq = getMaxRangeSq()
		if maxRangeSq <= 0 then
			return
		end
		local targets = collectTargets(maxRangeSq, true)
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
			local range = getPickupAllRange()
			local targets = collectTargets(range * range, false)
			for i = 1, math.min(#targets, PICKUP_ALL_BATCH) do
				tryPickup(targets[i].id)
				tried += 1
				if i % 4 == 0 then
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
		pickupAll = pickupAll,
	}
end

return Loot
