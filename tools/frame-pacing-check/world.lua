local Version = require("src.core.GameVersion")
Version.set("red")
local Renderer = require("src.render.Renderer")
local Performance = require("src.core.Performance")
local Cap = require("src.core.FrameCap")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local scene = require("tests.world_draw.fixture").new(64, { quiet = true })
local world, graphics = scene.world, love.graphics
scene.game.renderer = Renderer
Renderer:init()
world.map.renderer.drawBorderFill = function(_, cx, cy, w, h)
	graphics.setColor(0.2, 0.4, 0.5, 1)
	graphics.rectangle("fill", 0, 0, w, h)
end
world.map.renderer.draw = function()
	graphics.setColor(0.3, 0.5, 0.4, 1)
	for y = 0, 8 do
		for x = 0, 9 do
			graphics.rectangle("fill", x * 16, y * 16, 14, 14)
		end
	end
end
world.map.renderer.drawReflectionCover = function(_, cx, cy, camX, camY)
	graphics.setColor(0.2, 0.4, 0.5, 0.3)
	graphics.rectangle("fill", cx * 16 - camX, cy * 16 - camY, 16, 16)
end
for i, e in ipairs(world.entities) do
	e.px, e.py = (i % 10) * 16, math.floor(i / 10) * 16
	e.cellX, e.cellY = math.floor(e.px / 16), math.floor(e.py / 16)
	e.draw = function(actor, cx, cy)
		graphics.setColor(0.8, 0.3, 0.2, 1)
		graphics.rectangle("fill", actor.px - cx, actor.py - cy, 8, 12)
	end
	e.drawReflection = function(actor, cx, cy)
		graphics.setColor(0.8, 0.3, 0.2, 0.5)
		graphics.rectangle("fill", actor.px - cx, actor.py - cy + 16, 8, 12)
	end
end
local phase, frame, deadline, started, cpuStarted = 1, 0, 0, 0, 0
local WINDOW, WARMUP = 120, 120
local drawTotal, drawMax, protectedCalls, heapStart = 0, 0, 0, 0
local results = {}
local _, _, mode = love.window.getMode()
Cap.current = tonumber(mode.refreshrate) or 60
if Cap.current <= 0 then
	Cap.current = 60
end
Cap.vsyncPacing = true
local function draw()
	local close = Profile.section("draw: whole frame")
	Renderer:beginFrame(true)
	Renderer:beginWorldPass()
	world:drawWorld()
	Renderer:endWorldPass()
	Renderer:endFrame()
	close()
	Profile.frame()
end
local function startPhase()
	Profile.setEnabled(false)
	Performance.worldDrawHoist = phase == 2
	collectgarbage("restart")
	frame, drawTotal, drawMax = 0, 0, 0
	deadline = love.timer.getTime()
end
local function finishPhase()
	results[phase] = {
		enabled = Performance.worldDrawHoist,
		frames = WINDOW,
		seconds = love.timer.getTime() - started,
		drawMeanMs = drawTotal / WINDOW * 1000,
		drawMaxMs = drawMax * 1000,
		processCpuMsPerFrame = (os.clock() - cpuStarted) / WINDOW * 1000,
		protectedCalls = protectedCalls,
		heapGrowthKiB = collectgarbage("count") - heapStart,
	}
	collectgarbage("restart")
	if phase == 2 then
		print(
			"P4_NATIVE_RESULT "
				.. Json.encode({
					os = love.system.getOS(),
					arch = jit and jit.arch or "unknown",
					renderer = graphics.getRendererInfo(),
					refresh = mode.refreshrate,
					vsync = love.window.getVSync(),
					cap = Cap.current,
					entities = #world.entities,
					phases = results,
					scope = "Native drawWorld/entity/reflection/FX loops with synthetic 64-actor rectangles; no ROM assets or mod scene; GC stopped during each measured window",
				})
		)
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
			local original = pcall
			protectedCalls = 0
			_G.pcall = function(...)
				protectedCalls = protectedCalls + 1
				return original(...)
			end
			draw()
			_G.pcall = original
			collectgarbage("collect")
			collectgarbage("stop")
			Profile.setEnabled(true)
			heapStart = collectgarbage("count")
			started, cpuStarted = love.timer.getTime(), os.clock()
		end
		local before = love.timer.getTime()
		draw()
		if frame >= WARMUP then
			local elapsed = love.timer.getTime() - before
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
