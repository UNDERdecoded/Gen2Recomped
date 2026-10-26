return function(mod)
	mod.exports.npc = function(...)
		return mod.world:npc(...)
	end
	mod.exports.sample = function(mapId, ref, appearance)
		local h = assert(mod.world:npc(mapId, ref))
		assert(h:placeAt(1, 1, "right"))
		local allowed = h:canStep("right")
		assert(h:setPassable(true))
		assert(h:stepNow("right"))
		local moving = h:isMoving()
		assert(h:placeAt(3, 4, "up"))
		assert(h:setPassable(false))
		assert(h:setAppearance(appearance))
		local x, y = h:position()
		return { x = x, y = y, allowed = allowed, moving = moving, stopped = not h:isMoving() }
	end
end
