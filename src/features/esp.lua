local Esp = {}

function Esp.create(ctx)
	local draw = ctx.draw

	local function liveWorld(t)
		local char = t.character
		local root = t.root
		if char then
			local liveRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
			if liveRoot then
				root = liveRoot
			end
		end
		if not root then
			return t.headWorld, t.feetWorld, t.root and t.root.Position
		end
		local head = char and char:FindFirstChild("Head")
		local headWorld
		if head and (head.Position - root.Position).Magnitude <= 50 then
			headWorld = head.Position
		else
			headWorld = root.Position + Vector3.new(0, 2.8, 0)
		end
		local feetWorld = root.Position - Vector3.new(0, 3.2, 0)
		return headWorld, feetWorld, root.Position
	end

	local function update(targetList, origin, center, vp)
		if not ctx.flags.flagOn("ESPEnabled") then
			return {}
		end
		local seen = {}
		local maxDist = tonumber(ctx.flags.flagVal("ESPMaxDistance", ctx.config.DEFAULTS.ESPMaxDistance))
			or ctx.config.DEFAULTS.ESPMaxDistance
		for _, t in ipairs(targetList) do
			seen[t.key] = true
			local show = true
			if t.player and not ctx.flags.flagOn("ShowPlayers") then
				show = false
			end
			if t.isBot and not ctx.flags.flagOn("ShowBots") then
				show = false
			end
			local pack = draw.getPack(t.key)
			local color = ctx.targets.getColor(t)
			if show then
				local headWorld, feetWorld, rootPos = liveWorld(t)
				if not rootPos or (rootPos - origin).Magnitude > maxDist then
					show = false
				else
				local okBox, x, y, w, h, labelPos, feetPos = draw.screenBox(headWorld, feetWorld, rootPos)
				local boxVis = ctx.flags.flagOn("ESPBoxes") and okBox == true
				draw.setVisible(pack.box, boxVis)
				draw.setVisible(pack.boxOut, boxVis)
				if boxVis and pack.box and pack.boxOut then
					pack.box.Color = color
					pack.box.Position = Vector2.new(x, y)
					pack.box.Size = Vector2.new(w, h)
					pack.boxOut.Position = Vector2.new(x, y)
					pack.boxOut.Size = Vector2.new(w, h)
				end
				local tracerVis = ctx.flags.flagOn("ESPTracers") and feetPos and feetPos.Z > 0
				draw.setVisible(pack.tracer, tracerVis)
				if tracerVis and pack.tracer then
					pack.tracer.Color = color
					pack.tracer.From = Vector2.new(center.X, vp.Y)
					pack.tracer.To = Vector2.new(feetPos.X, feetPos.Y)
				end
				local textVis = (ctx.flags.flagOn("ESPNames") or ctx.flags.flagOn("ESPDistance")) and labelPos and labelPos.Z > 0
				draw.setVisible(pack.text, textVis)
				if textVis and pack.text then
					local label = ctx.flags.flagOn("ESPNames") and t.name or ""
					if ctx.flags.flagOn("ESPDistance") then
						label = label .. (label ~= "" and "\n" or "") .. string.format("[%d]", (rootPos - origin).Magnitude)
					end
					pack.text.Text = label
					pack.text.Color = color
					pack.text.Position = Vector2.new(labelPos.X, labelPos.Y - 16)
				end
				local hpVis = ctx.flags.flagOn("ESPHealth") and boxVis
				draw.setVisible(pack.hp, hpVis)
				draw.setVisible(pack.hpOut, hpVis)
				if hpVis and pack.hp and pack.hpOut then
					local hum = t.character and t.character:FindFirstChildOfClass("Humanoid") or t.hum
					local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					local barX, bottom, top = x - 4, y + h, y + h * (1 - hp)
					pack.hpOut.From = Vector2.new(barX, y)
					pack.hpOut.To = Vector2.new(barX, bottom)
					pack.hp.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 40)
					pack.hp.From = Vector2.new(barX, bottom)
					pack.hp.To = Vector2.new(barX, top)
				end
				if ctx.flags.flagOn("ESPChams") then
					draw.ensureHighlight(t.key, t.character, color)
				elseif ctx.highlights[t.key] then
					ctx.highlights[t.key].Enabled = false
				end
				end
			else
				draw.hidePack(pack)
				if ctx.highlights[t.key] then
					ctx.highlights[t.key].Enabled = false
				end
			end
		end
		return seen
	end

	return { update = update }
end

return Esp
