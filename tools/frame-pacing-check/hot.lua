local Version = require("src.core.GameVersion")
Version.set("red")
local Game = require("src.core.Game")
local Renderer = require("src.render.Renderer")
local Stack = require("src.core.StateStack")
local Performance = require("src.core.Performance")
local Cap = require("src.core.FrameCap")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local graphics = love.graphics
Game.data = require("tests.modkit.fixtures").fresh()
Game.save = { version = "red", options = {}, player = {}, modData = {} }
Game.overworld = {}
Game.stack = setmetatable(
	{
		states = {
			{
				draw = function()
					graphics.setColor(0.2, 0.4, 0.6, 1)
					graphics.rectangle("fill", 16, 16, 96, 80)
					graphics.setColor(1, 1, 1, 1)
				end,
			},
		},
	},
	{ __index = Stack }
)
Renderer:init()
local phase, frame, deadline, started, cpuStarted = 1, 0, 0, 0, 0
local WINDOW, WARMUP = 120, 120
local drawTotal, drawMax, requireCalls, requires = 0, 0, 0, {}
local results = {}
local _, _, mode = love.window.getMode()
Cap.current = tonumber(mode.refreshrate) or 60
if Cap.current <= 0 then
	Cap.current = 60
end
Cap.vsyncPacing = true

local function countRequires()
	local original = require
	requireCalls, requires = 0, {}
	_G.require = function(name, ...)
		requireCalls = requireCalls + 1
		requires[name] = (requires[name] or 0) + 1
		return original(name, ...)
	end
	local ok, err = pcall(Game.draw, Game)
	_G.require = original
	assert(ok, err)
end
local function startPhase()
	Profile.setEnabled(false)
	Performance.hotPathHoist = phase == 2
	frame, drawTotal, drawMax = 0, 0, 0
	deadline = love.timer.getTime()
end
local function finishPhase()
	results[phase] = {
		enabled = Performance.hotPathHoist,
		frames = WINDOW,
		seconds = love.timer.getTime() - started,
		drawMeanMs = drawTotal / WINDOW * 1000,
		drawMaxMs = drawMax * 1000,
		processCpuMsPerFrame = (os.clock() - cpuStarted) / WINDOW * 1000,
		requireCalls = requireCalls,
		requires = requires,
	}
	if phase == 2 then
		print("P3_NATIVE_RESULT " .. Json.encode({
			os = love.system.getOS(),
			arch = jit and jit.arch or "unknown",
			renderer = graphics.getRendererInfo(),
			refresh = mode.refreshrate,
			vsync = love.window.getVSync(),
			cap = Cap.current,
			phases = results,
			scope = "Native Game:draw and real canvas composition over owned synthetic content, no world/battle/mod scene",
		}))
		return true
	end
	phase = 2
	startPhase()
end
function love.run()
	startPhase()
	return function()
		love.event.pump()
		for name in love.event.poll() do
			if name == "quit" then
				return 1
			end
		end
		if frame == WARMUP then
			countRequires()
			Profile.setEnabled(true)
			started, cpuStarted = love.timer.getTime(), os.clock()
		end
		local start = love.timer.getTime()
		Game:draw()
		if frame >= WARMUP then
			local elapsed = love.timer.getTime() - start
			drawTotal, drawMax = drawTotal + elapsed, math.max(drawMax, elapsed)
		end
		local close = Profile.section("present (GPU wait / vsync)")
		graphics.present()
		close()
		deadline = Cap.pace(love.timer, love.window, true, deadline)
		frame = frame + 1
		if frame == WARMUP + WINDOW and finishPhase() then
			return 0
		end
	end
end
