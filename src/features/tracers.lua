local Tracers = {}

function Tracers.create(ctx)
	local silentLine = ctx.draw.drawing("Line", { Thickness = 2, ZIndex = 5 })

	local function updateSilentHandTracer()
		if not silentLine then
			return
		end
		local show = ctx.flags.flagOn("SilentAim") and ctx.flags.flagOn("SilentHandTracer")
		if not show then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local targetPart = ctx.state.silentTargetPart
		if not targetPart or not targetPart.Parent then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local origin = ctx.game.getTracerOrigin()
		if not origin then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local camera = ctx.camera
		if not camera then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		local targetPos = ctx.combat.getPredictedPos(targetPart)
		local fromPos, fromOn = camera:WorldToViewportPoint(origin)
		local toPos, toOn = camera:WorldToViewportPoint(targetPos)
		if not fromOn or fromPos.Z <= 0 or not toOn or toPos.Z <= 0 then
			ctx.draw.setVisible(silentLine, false)
			return
		end
		silentLine.From = Vector2.new(fromPos.X, fromPos.Y)
		silentLine.To = Vector2.new(toPos.X, toPos.Y)
		silentLine.Color = ctx.flags.flagVal("SilentTracerColor", Color3.fromRGB(255, 80, 255))
		ctx.draw.setVisible(silentLine, true)
	end

	local function destroy()
		ctx.draw.destroyDrawing(silentLine)
	end

	return {
		updateSilentHandTracer = updateSilentHandTracer,
		destroy = destroy,
	}
end

return Tracers
