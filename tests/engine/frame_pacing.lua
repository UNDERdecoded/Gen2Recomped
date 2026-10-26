local T = require("tests.harness")
local Cap = require("src.core.FrameCap")
local function clock(start)
	local now, sleeps, total = start or 0, 0, 0
	return {
		getTime = function()
			return now
		end,
		sleep = function(dt)
			now = now + dt
			sleeps = sleeps + 1
			total = total + dt
		end,
		advance = function(dt)
			now = now + dt
		end,
		sleeps = function()
			return sleeps, total
		end,
	}
end
local function window(sync, rate)
	local calls = 0
	return {
		getVSync = function()
			return sync
		end,
		getMode = function()
			calls = calls + 1
			return 320, 240, { refreshrate = rate }
		end,
		modeCalls = function()
			return calls
		end,
		set = function(s, r)
			sync, rate = s, r
		end,
	}
end
Cap.current = 60
T.eq(Cap.vsyncPacing, true, "P1 switch defaults on")
for _, sync in ipairs({ 1, -1, 2 }) do
	local timer, w = clock(), window(sync, 60)
	local nextFrame = 0
	for _ = 1, 60 do
		timer.advance(1 / 60)
		nextFrame = Cap.pace(timer, w, true, nextFrame)
	end
	T.eq(timer.sleeps(), 0, "active VSync at the cap receives no additional sleep")
	T.eq(w.modeCalls(), 1, "display flags are not allocated each frame")
end
for _, case in ipairs({
	{ sync = 0, rate = 60, presented = true },
	{ sync = 1, rate = 144, presented = true },
	{ sync = 1, rate = 0, presented = true },
	{ sync = 1, rate = 60, presented = false },
}) do
	local timer, w = clock(), window(case.sync, case.rate)
	local deadline = Cap.pace(timer, w, case.presented, 0)
	T.check(timer.sleeps() > 0, "software cap remains for disabled/unknown/faster/unpresented cases")
	T.check(math.abs(deadline - 1 / 60) < 1e-9, "software deadline remains one frame ahead")
end
local timer, w = clock(), window(1, 60)
Cap.vsyncPacing = false
Cap.pace(timer, w, true, 0)
T.check(timer.sleeps() > 0, "P1 switch restores software pacing")
T.eq(w.modeCalls(), 0, "disabled P1 does not query display flags")
Cap.vsyncPacing = true
timer, w = clock(), window(1, 60)
local deadline = Cap.pace(timer, w, true, 0)
w.set(0, 60)
deadline = Cap.pace(timer, w, true, deadline)
T.check(math.abs(deadline - 1 / 60) < 1e-9, "turning VSync off resumes the carried software deadline")
timer.advance(1)
deadline = Cap.pace(timer, w, true, deadline)
T.eq(deadline, timer.getTime(), "stalls re-anchor instead of accumulating catch-up frames")
deadline = Cap.pace(timer, w, true, deadline)
T.eq(deadline, timer.getTime(), "software pacing resumes after a stall")
timer, w = clock(), window(1, 60)
Cap.pace(timer, w, true, 0)
w.set(1, 144)
timer.advance(1.01)
deadline = Cap.pace(timer, w, true, timer.getTime())
T.check(timer.sleeps() > 0, "display rate changes refresh the software-cap decision")
T.eq(w.modeCalls(), 2, "display sample refresh is bounded")
timer = clock()
Cap.pace(timer, nil, true, 0)
T.check(timer.sleeps() > 0, "headless provider absence retains the software cap")

-- Execute the actual run-loop body with native present/timer boundaries
-- substituted, so a correct helper wired to the wrong loop still fails.
local file = assert(io.open("main.lua", "r"))
local source = file:read("*a")
file:close()
local start = assert(source:find("function love.run()", 1, true))
for _, active in ipairs({ true, false }) do
	local fake = clock()
	fake.step = function()
		return 1 / 60
	end
	local presents = 0
	local noop = function() end
	local env = {
		love = {
			timer = fake,
			window = window(1, 60),
			graphics = {
				isActive = function()
					return active
				end,
				origin = noop,
				clear = noop,
				getBackgroundColor = function()
					return 0, 0, 0, 1
				end,
				present = function()
					presents = presents + 1
					fake.advance(1 / 60 - 0.001)
				end,
			},
		},
		BootTrace = { mark = noop, frame = noop },
		Frames = { tick = noop },
		FrameProfile = {
			section = function()
				return noop
			end,
		},
		WindowFrame = {
			draw = function(fn)
				fn()
			end,
		},
		GraphicsStack = { drain = noop },
		pacingEnabled = function()
			return true
		end,
		lastLogFlush = 0,
	}
	setmetatable(env, { __index = _G })
	local chunk
	if setfenv then
		chunk = assert(loadstring(source:sub(start), "@main.lua:love.run"))
		setfenv(chunk, env)
	else
		chunk = assert(load(source:sub(start), "@main.lua:love.run", "t", env))
	end
	chunk()
	env.love.run()()
	T.eq(presents, active and 1 or 0, "actual main loop presents only active graphics")
	T.eq(fake.sleeps() > 0, not active, "actual main loop bypasses sleep only after native presentation")
end
T.finish()
