local Tracers = {}

function Tracers.create(ctx)
	local silentLine = ctx.draw.drawing("Line", { Thickness = 2, ZIndex = 5 })

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
		local targetPart = ctx.state.silentTargetPart
		if not targetPart or not targetPart.Parent then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local camera = ctx.camera
		if not camera or not center then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local head = targetPart.Parent:FindFirstChild("Head") or targetPart
		local targetPos = ctx.combat.getPredictedPos(head)
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
