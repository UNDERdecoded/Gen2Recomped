local Cap = require("src.core.FrameCap")
local Performance = require("src.core.Performance")
local Budget = require("src.core.GCFrameBudget")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local phase, frame, deadline, started, cpuStarted = 1, 0, 0, 0, 0
local WINDOW, WARMUP = 120, 120
local results, _trash = {}, nil
local witness = { key = "retained native data", value = 2712 }
local legacySteps, idleSteps, idleTotal, idleMax, heapPeak = 0, 0, 0, 0, 0
local timer = { getTime = love.timer.getTime, sleep = love.timer.sleep }
local _, _, mode = love.window.getMode()
Cap.current = tonumber(mode.refreshrate) or 60
if Cap.current <= 0 then
	Cap.current = 60
end
Cap.vsyncPacing = true
local originalPause = collectgarbage("setpause", 120)
collectgarbage("setpause", originalPause)
local originalMul = collectgarbage("setstepmul", 300)
collectgarbage("setstepmul", originalMul)

local function resetStats()
	legacySteps, idleSteps, idleTotal, idleMax, heapPeak = 0, 0, 0, 0, 0
end
local function idle(clock, target)
	local start = clock.getTime()
	local steps = Budget.idle(clock, target)
	if steps > 0 then
		local duration = clock.getTime() - start
		idleSteps, idleTotal = idleSteps + steps, idleTotal + duration
		idleMax = math.max(idleMax, duration)
	end
end
local function startPhase()
	Profile.setEnabled(false)
	Performance.gcBudget = phase == 2
	Budget.configure(Performance)
	collectgarbage("collect")
	frame = 0
	resetStats()
	deadline = timer.getTime()
end
local function finishPhase()
	assert(witness.key == "retained native data" and witness.value == 2712)
	assert(_trash[512][2] == 512)
	results[phase] = {
		enabled = Performance.gcBudget,
		frames = WINDOW,
		seconds = timer.getTime() - started,
		processCpuMsPerFrame = (os.clock() - cpuStarted) / WINDOW * 1000,
		legacySteps = legacySteps,
		idleSteps = idleSteps,
		idleMeanMs = idleTotal / WINDOW * 1000,
		idleMaxMs = idleMax * 1000,
		heapPeakKiB = heapPeak,
	}
	if phase == 2 then
		Performance.gcBudget = false
		Budget.configure(Performance)
		local pause = collectgarbage("setpause", originalPause)
		local mul = collectgarbage("setstepmul", originalMul)
		assert(pause == originalPause and mul == originalMul, "disable did not restore GC tuning")
		print("P2_NATIVE_RESULT " .. Json.encode({
			os = love.system.getOS(),
			arch = jit and jit.arch or "unknown",
			renderer = love.graphics.getRendererInfo(),
			refresh = mode.refreshrate,
			vsync = love.window.getVSync(),
			cap = Cap.current,
			originalPause = originalPause,
			originalStepMul = originalMul,
			phases = results,
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
			resetStats()
			Profile.setEnabled(true)
			started, cpuStarted = timer.getTime(), os.clock()
		end
		Budget.beginFrame(Performance)
		local close = Profile.section("update: allocation workload")
		local rows = {}
		for index = 1, 512 do
			rows[index] = { frame, index, a = index * 2, b = index * 3 }
		end
		_trash = rows
		close()
		if not Performance.gcBudget then
			close = Profile.section("  update: gc step")
			collectgarbage("step", 1)
			legacySteps = legacySteps + 1
			close()
		end
		love.graphics.clear(0.03, 0.04, 0.06)
		close = Profile.section("present (GPU wait / vsync)")
		love.graphics.present()
		close()
		close = Profile.section("frame pacing: sleep")
		deadline = Cap.pace(timer, love.window, true, deadline, idle)
		close()
		frame = frame + 1
		if frame > WARMUP then
			heapPeak = math.max(heapPeak, collectgarbage("count"))
			Profile.frame()
		end
		if frame == WARMUP + WINDOW and finishPhase() then
			return 0
		end
	end
end
