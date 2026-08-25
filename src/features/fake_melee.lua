local FakeMelee = {}

local ARSENAL_PLACE_ID = 286090429
local FAKE_ATTR = "PepsiFakeMelee"
local DEFAULT_MELEE = "Saber"

function FakeMelee.create(ctx)
	local lp = ctx.lp
	local connections = {}

	local function getLockerScroll()
		local menew = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("Menew")
		local locker = menew and menew:FindFirstChild("Locker")
		local equipping = locker and locker:FindFirstChild("Equipping")
		return equipping and equipping:FindFirstChild("ScrollingFrame")
	end

	local function findTemplate(scroll)
		local preferred = scroll:FindFirstChild("Dagger")
		if preferred and preferred:IsA("GuiObject") then
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

	local function hideCountBadges(root)
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("TextLabel") and (desc.Name == "Count" or desc.Name == "CraftCount") then
				desc.Text = "x1"
				desc.Visible = true
			end
			if desc:IsA("ImageLabel") and desc.Name == "Check" then
				desc.Visible = true
			end
		end
	end

	local function setupViewport(root, meleeName)
		local viewport = root:FindFirstChild("ViewportFrame", true)
		local meleeFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Melees")
		local meleeDef = meleeFolder and meleeFolder:FindFirstChild(meleeName)
		local model = meleeDef and meleeDef:FindFirstChild("Model")
		if not viewport or not model then
			return
		end
		viewport:ClearAllChildren()
		local clone = model:Clone()
		clone.Parent = viewport
		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local pivot = clone:GetPivot()
		local size = clone:GetExtentsSize()
		local dist = math.max(size.X, size.Y, size.Z) * 1.35
		camera.CFrame = pivot * CFrame.new(0, 0, dist) * CFrame.Angles(0, math.pi, 0)
		camera.FieldOfView = 24
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
		if game.PlaceId ~= ARSENAL_PLACE_ID then
			return false
		end
		if not ctx.flags.flagOn("FakeMeleeEnabled", true) then
			return false
		end
		local scroll = getLockerScroll()
		if not scroll then
			return false
		end
		local name = meleeName()
		if scroll:FindFirstChild(name) and scroll:FindFirstChild(name):GetAttribute(FAKE_ATTR) then
			return true
		end
		if scroll:FindFirstChild(name) and not scroll:FindFirstChild(name):GetAttribute(FAKE_ATTR) then
			return false
		end
		local template = findTemplate(scroll)
		if not template then
			return false
		end
		local slot = template:Clone()
		slot.Name = name
		slot:SetAttribute(FAKE_ATTR, true)
		setLabel(slot, name)
		hideCountBadges(slot)
		setupViewport(slot, name)
		slot.Parent = scroll
		table.insert(
			connections,
			slot.MouseButton1Click:Connect(function()
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
		)
		return true
	end

	local function clear()
		removeFakeSlots(getLockerScroll())
	end

	local function watch()
		local playerGui = lp:WaitForChild("PlayerGui", 10)
		if not playerGui then
			return
		end
		table.insert(
			connections,
			playerGui.DescendantAdded:Connect(function()
				task.defer(function()
					if ctx.flags.flagOn("FakeMeleeEnabled", true) then
						inject()
					end
				end)
			end)
		)
		task.spawn(function()
			for _ = 1, 30 do
				if inject() then
					break
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
