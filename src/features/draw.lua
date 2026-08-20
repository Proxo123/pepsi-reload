local DrawLib = Drawing or (getgenv and getgenv().Drawing)

local DrawingModule = {}

function DrawingModule.create(ctx)
	local CoreGui = ctx.services.CoreGui

	local function guiParent()
		if gethui then
			return gethui()
		end
		return CoreGui
	end

	local function drawing(class, props)
		if not DrawLib or not DrawLib.new then
			return nil
		end
		local obj
		local ok = pcall(function()
			obj = DrawLib.new(class)
		end)
		if not ok or not obj then
			return nil
		end
		for k, v in pairs(props or {}) do
			pcall(function()
				obj[k] = v
			end)
		end
		pcall(function()
			obj.Visible = false
		end)
		return obj
	end

	local function setVisible(obj, vis)
		if obj then
			pcall(function()
				obj.Visible = vis and true or false
			end)
		end
	end

	local function destroyDrawing(obj)
		if obj then
			pcall(function()
				obj.Visible = false
				obj:Remove()
			end)
		end
	end

	local function getPack(key)
		local pack = ctx.drawings[key]
		if pack then
			return pack
		end
		pack = {
			box = drawing("Square", { Filled = false, Thickness = 1, ZIndex = 2 }),
			boxOut = drawing("Square", { Filled = false, Thickness = 3, Color = Color3.new(), ZIndex = 1 }),
			tracer = drawing("Line", { Thickness = 1, ZIndex = 2 }),
			text = drawing("Text", { Center = true, Outline = true, Size = 13, Font = 2, ZIndex = 3 }),
			hp = drawing("Line", { Thickness = 2, ZIndex = 3 }),
			hpOut = drawing("Line", { Thickness = 4, Color = Color3.new(), ZIndex = 2 }),
		}
		ctx.drawings[key] = pack
		return pack
	end

	local function hidePack(pack)
		if not pack then
			return
		end
		for _, o in pairs(pack) do
			setVisible(o, false)
		end
	end

	local function clearKey(key)
		local pack = ctx.drawings[key]
		if pack then
			for _, o in pairs(pack) do
				destroyDrawing(o)
			end
			ctx.drawings[key] = nil
		end
		local hl = ctx.highlights[key]
		if hl then
			pcall(function()
				hl:Destroy()
			end)
			ctx.highlights[key] = nil
		end
	end

	local function ensureHighlight(key, char, color)
		local adornee = ctx.game.getHighlightAdornee(char)
		if not adornee or not adornee:IsDescendantOf(workspace) then
			local hl = ctx.highlights[key]
			if hl then
				hl.Enabled = false
			end
			return
		end
		local hl = ctx.highlights[key]
		if not hl or not hl.Parent then
			hl = Instance.new("Highlight")
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillTransparency = 0.62
			hl.OutlineTransparency = 0
			hl.Enabled = false
			hl.Parent = guiParent()
			ctx.highlights[key] = hl
		end
		hl.Adornee = adornee
		hl.FillColor = color
		hl.OutlineColor = color
		hl.Enabled = true
	end

	local function screenBox(headWorld, feetWorld, rootWorld)
		local camera = ctx.camera
		if not camera then
			return false
		end
		local headPos, headOn = camera:WorldToViewportPoint(headWorld)
		local feetPos, feetOn = camera:WorldToViewportPoint(feetWorld)
		local refPos
		if headOn and headPos.Z > 0 then
			refPos = headPos
		elseif feetOn and feetPos.Z > 0 then
			refPos = feetPos
		elseif rootWorld then
			local rootPos, rootOn = camera:WorldToViewportPoint(rootWorld)
			if rootOn and rootPos.Z > 0 then
				refPos = rootPos
				headPos = rootPos
				feetPos = rootPos
				headOn = true
				feetOn = true
			else
				return false
			end
		else
			return false
		end
		local h = 60
		if headOn and feetOn and headPos.Z > 0 and feetPos.Z > 0 then
			h = math.clamp(math.abs(feetPos.Y - headPos.Y), 12, 400)
		end
		local w = h * 0.55
		return true,
			refPos.X - w * 0.5,
			refPos.Y - h * 0.12,
			w,
			h,
			(headOn and headPos.Z > 0) and headPos or refPos,
			feetPos
	end

	return {
		guiParent = guiParent,
		drawing = drawing,
		setVisible = setVisible,
		destroyDrawing = destroyDrawing,
		getPack = getPack,
		hidePack = hidePack,
		clearKey = clearKey,
		ensureHighlight = ensureHighlight,
		screenBox = screenBox,
	}
end

return DrawingModule
