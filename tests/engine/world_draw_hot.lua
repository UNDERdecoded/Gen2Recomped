local T = require("tests.harness")
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Performance = require("src.core.Performance")
local World = require("src.world.OverworldController")
local Fixture = require("tests.world_draw.fixture")
local originalPcall = pcall
for _, version in ipairs({ "red", "gold", "emerald", "platinum" }) do
	Version.set(version)
	local f = Fixture.new(32)
	local world = f.world
	Performance.worldDrawHoist = false
	world:drawWorld()
	f.reset()
	local beforeCalls = 0
	_G.pcall = function(...)
		beforeCalls = beforeCalls + 1
		return originalPcall(...)
	end
	world:drawWorld()
	_G.pcall = originalPcall
	local before = f.trace()
	f.reset()
	Performance.worldDrawHoist = true
	local afterCalls = 0
	_G.pcall = function(...)
		afterCalls = afterCalls + 1
		return originalPcall(...)
	end
	world:drawWorld()
	_G.pcall = originalPcall
	T.same(f.trace(), before, version .. " keeps tile/reflection/entity/top-layer/FX draw order and coordinates")
	T.check(beforeCalls > afterCalls, version .. " reduces protected calls for the entity pass")
	T.eq(afterCalls, 1, version .. " has one protected ordinary entity loop")
	local list, cover = world._worldReflectors, world._worldCover
	world:drawWorld()
	T.eq(world._worldReflectors, list, "reflector list is private and reused")
	T.eq(world._worldCover, cover, "parallel cover columns are private and reused")
	world.entities = { world.player }
	world.ripples = {}
	world:drawWorld()
	T.eq(list.n, 0, "shrinking frame clears reflector count")
	T.eq(list[1], nil, "shrinking frame releases stale entity references")
end
Version.set("red")
local f = Fixture.new(3)
local world = f.world
local retained = {}
world.rippleCells = function(self, out, seen)
	retained[#retained + 1] = out
	T.check(out ~= self._worldCover, "public replacement never receives a private pool")
	return World.rippleCells(self, out, seen)
end
world:drawWorld()
world:drawWorld()
T.check(retained[1] ~= retained[2], "public ripple wrapper keeps fresh cell records")
T.check(retained[1][1] ~= retained[2][1], "public cell pairs remain detached")
local ended = 0
world.map.renderer.gen4Ground = {
	rise = function()
		return 0
	end,
	billboardDepth = function()
		return nil
	end,
	beginSprites = function()
		return true
	end,
	endSprites = function()
		ended = ended + 1
	end,
}
world.player.draw = function()
	error("synthetic entity failure")
end
local ok, err = pcall(World.drawWorld, world)
T.eq(ok, false, "entity errors are propagated")
T.check(tostring(err):find("synthetic entity failure", 1, true) ~= nil, "original entity error remains visible")
T.eq(ended, 1, "sprite depth pass closes exactly once on failure")
-- Nested cover drawing must not overwrite the outer borrowed columns.
local nested = false
local visited = {}
world.rippleCells = World.rippleCells
world.map.renderer.drawReflectionCover = function(_, cx, cy)
	visited[#visited + 1] = cx .. ":" .. cy
	if not nested then
		nested = true
		world:_worldReflectionCover({}, 0, { drawReflectionCover = function() end }, world.camera, 0)
	end
end
world:_worldReflectionCover({ world.entities[2] }, 1, world.map.renderer, world.camera, 0)
T.same(
	visited,
	{ "2:3", "3:3", "2:4", "3:4", "0:1", "1:1", "0:2", "1:2" },
	"nested cover work cannot clobber the outer columns"
)
-- A pipeline may retain its no-argument FX callbacks after a later frame.
local P = require("src.render.Pipelines")
local saved =
	{ worldPipeline = P.worldPipeline, drawWorld = P.drawWorld, worldPresent = P.worldPresent, level = P.level }
local frames = {}
P.worldPipeline = function()
	return "synthetic", {}
end
P.drawWorld = function(_, ctx)
	frames[#frames + 1] = ctx
	return {}
end
P.worldPresent = function(canvas)
	return canvas
end
P.level = function()
	return 1
end
local scene = Fixture.new(2)
scene.world:drawWorld()
scene.world.camera = { x = 67, y = 5 }
scene.world:drawWorld()
T.check(frames[1] ~= frames[2] and frames[1].fx ~= frames[2].fx, "public pipeline frames and FX tables remain detached")
T.check(frames[1].fx.water ~= frames[2].fx.water, "public FX callbacks keep their own frame binding")
local positions = {}
local rectangle = love.graphics.rectangle
love.graphics.rectangle = function(_, x)
	positions[#positions + 1] = x
end
frames[1].fx.water()
local oldX = positions[1]
positions = {}
frames[2].fx.water()
T.eq(oldX - positions[1], 64, "retained zero-argument callback keeps the original camera")
love.graphics.rectangle = rectangle
for name, value in pairs(saved) do
	P[name] = value
end
T.finish("world draw hot paths")
