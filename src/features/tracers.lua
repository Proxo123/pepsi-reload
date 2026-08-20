local Tracers = {}

function Tracers.create(ctx)
	local silentLine = ctx.draw.drawing("Line", { Thickness = 2, ZIndex = 5 })

	local function resolveHead(part, character)
		if character then
			local head = character:FindFirstChild("Head")
			if head then
				return head
			end
		end
		if part and part.Name == "Head" then
			return part
		end
		if part and part.Parent then
			local head = part.Parent:FindFirstChild("Head")
			if head then
				return head
			end
		end
		return part
	end

	local function updateSilentTracer(center)
		if not silentLine then
			return
		end
		local show = ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer")
		if not show then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		if not center then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local head = ctx.state.silentTargetHead or resolveHead(ctx.state.silentTargetPart, ctx.state.silentTargetChar)
		if not head then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local camera = ctx.camera
		if not camera then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local targetPos = head.Position
		local toPos, toOn = camera:WorldToViewportPoint(targetPos)
		if not toOn or toPos.Z <= 0 then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		silentLine.From = center
		silentLine.To = Vector2.new(toPos.X, toPos.Y)
		silentLine.Color = ctx.flags.flagVal("SilentTracerColor", Color3.fromRGB(255, 80, 255))
		ctx.draw.setVisible(silentLine, true)
	end

	local function destroy()
		ctx.draw.destroyDrawing(silentLine)
	end

	return {
		updateSilentTracer = updateSilentTracer,
		destroy = destroy,
	}
end

return Tracers
