local root = assert(os.getenv("FRAME_PACING_REPO"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Cap = require("src.core.FrameCap")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local phase, frame, deadline, last, started, cpuStarted = 1, 0, 0, 0, 0, 0
local sleeps, intervals, results = 0, {}, {}
local WINDOW, WARMUP = 120, 120
local timer = {
	getTime = love.timer.getTime,
	sleep = function(dt)
		sleeps = sleeps + 1
		love.timer.sleep(dt)
	end,
}
local _, _, mode = love.window.getMode()
local refresh = tonumber(mode.refreshrate) or 0
Cap.current = refresh > 0 and refresh or 60
local function startPhase()
	Profile.setEnabled(false)
	Cap.vsyncPacing = phase == 2
	frame, sleeps, intervals = 0, 0, {}
	deadline = timer.getTime()
end
local function finishPhase()
	local long = 0
	for _, interval in ipairs(intervals) do
		if refresh > 0 and interval > 1.5 / refresh then
			long = long + 1
		end
	end
	table.sort(intervals)
	results[phase] = {
		enabled = Cap.vsyncPacing,
		frames = WINDOW,
		seconds = timer.getTime() - started,
		medianMs = intervals[math.floor(#intervals / 2)] * 1000,
		p95Ms = intervals[math.ceil(#intervals * 0.95)] * 1000,
		maxMs = intervals[#intervals] * 1000,
		framesOver1_5Periods = long,
		extraSleepCalls = sleeps,
		processCpuMsPerFrame = (os.clock() - cpuStarted) / WINDOW * 1000,
	}
	if phase == 2 then
		if refresh > 0 and love.window.getVSync() ~= 0 then
			assert(sleeps == 0, "VSync phase still slept")
		end
		print("P1_NATIVE_RESULT " .. Json.encode({
			refresh = refresh,
			vsync = love.window.getVSync(),
			cap = Cap.current,
			os = love.system.getOS(),
			arch = jit and jit.arch or "unknown",
			renderer = love.graphics.getRendererInfo(),
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
			sleeps = 0
			Profile.setEnabled(true)
			started, last = timer.getTime(), timer.getTime()
			cpuStarted = os.clock()
		end
		love.graphics.clear(0.03, 0.04, 0.06)
		local close = Profile.section("present (GPU wait / vsync)")
		love.graphics.present()
		close()
		close = Profile.section("frame pacing: sleep")
		deadline = Cap.pace(timer, love.window, true, deadline)
		close()
		frame = frame + 1
		if frame > WARMUP then
			local now = timer.getTime()
			intervals[#intervals + 1], last = now - last, now
			Profile.frame()
		end
		if frame == WARMUP + WINDOW and finishPhase() then
			return 0
		end
	end
end
