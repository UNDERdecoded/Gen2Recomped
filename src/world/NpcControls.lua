-- Original contribution by Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared native actor operations. Facades retain their own admission policy.
local Collision = require("src.world.Collision")
local copy = require("src.mods.Merge").deepCopy
local C = {}
function C.isMoving(actor)
	return not not actor.moving
end
function C.canStep(actor, map, peers, direction)
	return not not Collision.canMove(map, peers or {}, actor, direction)
end
function C.stepNow(actor, direction)
	if actor.moving then
		return nil, "already moving"
	end
	actor.facing = direction
	actor.targetX, actor.targetY = Collision.target(actor.cellX, actor.cellY, direction)
	actor.moving, actor.progress = true, 0
	return true
end
function C.placeAt(actor, x, y, facing)
	actor.moving, actor.marching, actor.progress = false, false, 0
	actor.targetX, actor.targetY = nil, nil
	actor.cellX, actor.cellY, actor.px, actor.py = x, y, x * 16, y * 16
	if facing then
		actor.facing = facing
	end
	return true
end
function C.setPassable(actor, passable)
	actor.passable = passable
	return true
end
function C.setAppearance(actor, game, id, req)
	if not (game.data and game.data.sprites and game.data.sprites[id]) then
		return nil, "unknown sprite: " .. tostring(id)
	end
	-- Resolve first, then commit. A renderer failure cannot half-change a live
	-- actor or its imported template. This is the existing API-3 native path.
	local proxy = { id = actor.id, def = copy(actor.def) }
	proxy.def.sprite = id
	proxy.def.graphicsId, proxy.def.graphics, proxy.def.graphicsVar, proxy.def.varSprite = nil, nil, nil, nil
	local nativeNpc = (req or require)("src.world.NPC")
	nativeNpc.refreshSprite(proxy, game.data)
	actor.def, actor.sprite, actor.appearance = proxy.def, proxy.sprite, id
	actor.big = proxy.sprite and proxy.sprite.big or false
	return true
end
return C
