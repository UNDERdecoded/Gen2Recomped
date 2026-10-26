-- Owned synthetic draw scene: no ROM, profile, asset extraction or game progress.
local F = {}
function F.new(count, options)
	local World = options and options.worldModule or require("src.world.OverworldController")
	local Game = require("src.core.Game")
	-- The normal enter lifecycle supplies this shared engine reference. The
	-- isolated rendering fixture has no map loader or save lifecycle to enter.
	for index = 1, 100 do
		local name = debug.getupvalue(World.drawWorld, index)
		if not name then
			break
		end
		if name == "Game" then
			debug.setupvalue(World.drawWorld, index, Game)
			break
		end
	end
	Game.data = { field = { overworldFx = {} }, constants = {}, sprites = {} }
	Game.save = { options = {} }
	local trace = {}
	local function mark(name, ...)
		if options and options.quiet then
			return
		end
		local row = { name, ... }
		for i = 1, #row do
			row[i] = tostring(row[i])
		end
		trace[#trace + 1] = table.concat(row, ":")
	end
	local renderer = {}
	for _, name in ipairs({ "drawBorderFill", "draw", "drawMapOnly", "drawAbove", "drawReflectionCover" }) do
		renderer[name] = function(_, ...)
			mark(name, ...)
		end
	end
	local world = setmetatable({
		camera = { x = 3, y = 5 },
		map = {
			id = "SYNTHETIC",
			renderer = renderer,
			isGrassCell = function()
				return false
			end,
		},
		neighbors = {},
		ghosts = {},
		entities = {},
		gen4Shadows = false,
		waterAnim = { x = 1, y = 1, frames = 12, total = 40 },
		ripples = { { px = 15, py = 31, clock = 0 } },
	}, { __index = World })
	for i = 1, count or 3 do
		local e = {
			px = i * 16,
			py = i * 16,
			cellX = i,
			cellY = i,
			facing = "down",
			above = i % 7 == 0,
			draw = function(self, cx, cy)
				mark("entity", self.cellX, cx, cy)
			end,
			drawReflection = function(self, cx, cy)
				mark("reflection", self.cellX, cx, cy)
			end,
		}
		world.entities[i] = e
	end
	world.player = world.entities[1]
	world.reflectionSearch = function(_, e)
		return e.cellX % 2 == 0 and { { e.cellX, e.cellY + 1 } } or nil
	end
	world.stillReflection = function()
		return false
	end
	world.reflectionRect = function(_, e)
		return e.cellX, e.cellY + 1, e.cellX + 1, e.cellY + 2
	end
	world.gen3AboveTopLayer = function(_, e)
		return e.above
	end
	world.drawRipples = function(_, cx, cy)
		mark("ripples", cx, cy)
	end
	world.drawGen3Gates = function()
		mark("gates")
	end
	world.drawGen3Flash = function()
		mark("flash")
	end
	world.drawGen3Decorate = function()
		mark("decoration")
	end
	world.placeFreeCamera = function() end
	world.reflectProbe, world.reflectProbe2 = 1, 1
	Game.renderer = {
		worldViewSize = function()
			return 160, 144
		end,
		fitScale = function()
			return 1
		end,
		setWorldOverride = function() end,
	}
	return {
		world = world,
		game = Game,
		trace = function()
			return trace
		end,
		reset = function()
			trace = {}
		end,
		mark = mark,
	}
end
return F
