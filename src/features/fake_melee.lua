local FakeMelee = {}

local ARSENAL_PLACE_ID = 286090429
local FAKE_ATTR = "PepsiFakeMelee"
local DEFAULT_MELEE = "Saber"
local INJECT_COOLDOWN = 2

function FakeMelee.create(ctx)
	local lp = ctx.lp
	local connections = {}
	local injecting = false
	local lastInject = 0
	local scrollWatchBound = false

	local function getLockerScroll()
		local playerGui = lp:FindFirstChild("PlayerGui")
		local menew = playerGui and playerGui:FindFirstChild("Menew")
		local locker = menew and menew:FindFirstChild("Locker")
		local equipping = locker and locker:FindFirstChild("Equipping")
		return equipping and equipping:FindFirstChild("ScrollingFrame")
	end

	local function findTemplate(scroll)
		local preferred = scroll:FindFirstChild("Dagger")
		if preferred and preferred:IsA("GuiObject") and not preferred:GetAttribute(FAKE_ATTR) then
			return preferred
		end
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("ImageButton") and child.Name ~= "AAAShuffle" and not child:GetAttribute(FAKE_ATTR) then
				return child
			end
		end
	end

	local function setLabel(root, text)
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("TextLabel") and desc.Name == "TextLabel" then
				desc.Text = text
			end
		end
	end

	local function removeFakeSlots(scroll)
		if not scroll then
			return
		end
		for _, child in ipairs(scroll:GetChildren()) do
			if child:GetAttribute(FAKE_ATTR) then
				child:Destroy()
			end
		end
	end

	local function meleeName()
		local name = ctx.flags.flagVal("FakeMeleeName", DEFAULT_MELEE)
		if type(name) ~= "string" or name == "" then
			return DEFAULT_MELEE
		end
		return name
	end

	local function inject()
		if injecting then
			return false
		end
		if tick() - lastInject < INJECT_COOLDOWN then
			return false
		end
		if game.PlaceId ~= ARSENAL_PLACE_ID then
			return false
		end
		if not ctx.flags.flagOn("FakeMeleeEnabled", false) then
			return false
		end

		local scroll = getLockerScroll()
		if not scroll then
			return false
		end

		local name = meleeName()
		local existing = scroll:FindFirstChild(name)
		if existing then
			return existing:GetAttribute(FAKE_ATTR) == true
		end

		local template = findTemplate(scroll)
		if not template then
			return false
		end

		injecting = true
		local ok, result = pcall(function()
			local slot = template:Clone()
			slot.Name = name
			slot:SetAttribute(FAKE_ATTR, true)
			setLabel(slot, name)
			slot.Parent = scroll
			slot.MouseButton1Click:Connect(function()
				pcall(function()
					local dataMelee = lp:FindFirstChild("Data") and lp.Data:FindFirstChild("Melee")
					if dataMelee and dataMelee:IsA("StringValue") then
						dataMelee.Value = name
					end
					local menew = lp.PlayerGui:FindFirstChild("Menew")
					local locker = menew and menew:FindFirstChild("Locker")
					local slots = locker and locker:FindFirstChild("Slots")
					local slotsMelee = slots and slots:FindFirstChild("Melees")
					if slotsMelee then
						local tip = slotsMelee:FindFirstChild("ToolTip")
						if tip and tip:IsA("StringValue") then
							tip.Value = name
						end
					end
				end)
			end)
			return true
		end)
		injecting = false
		lastInject = tick()
		return ok and result == true
	end

	local function clear()
		removeFakeSlots(getLockerScroll())
		lastInject = 0
	end

	local function bindScrollWatch(scroll)
		if scrollWatchBound or not scroll then
			return
		end
		scrollWatchBound = true
		table.insert(
			connections,
			scroll.ChildRemoved:Connect(function(child)
				if child:GetAttribute(FAKE_ATTR) then
					lastInject = 0
					task.delay(INJECT_COOLDOWN, function()
						if ctx.flags.flagOn("FakeMeleeEnabled", false) then
							inject()
						end
					end)
				end
			end)
		)
	end

	local function watch()
		task.spawn(function()
			for _ = 1, 20 do
				local scroll = getLockerScroll()
				if scroll then
					bindScrollWatch(scroll)
					if ctx.flags.flagOn("FakeMeleeEnabled", false) then
						inject()
					end
					return
				end
				task.wait(1)
			end
		end)
	end

	watch()

	return {
		inject = inject,
		clear = clear,
		unload = function()
			clear()
			scrollWatchBound = false
			for _, conn in ipairs(connections) do
				pcall(function()
					conn:Disconnect()
				end)
			end
			table.clear(connections)
		end,
	}
end

return FakeMelee
