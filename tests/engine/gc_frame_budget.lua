local T = require("tests.harness")
local Performance = require("src.core.Performance")
local Budget = require("src.core.GCFrameBudget")
local Cap = require("src.core.FrameCap")

local function setup(cost)
	local state = { now = 0, pause = 200, mul = 200, steps = 0, running = true, stepArgs = {}, sleeps = 0 }
	local timer = {
		getTime = function()
			return state.now
		end,
		sleep = function(dt)
			state.now = state.now + dt
			state.sleeps = state.sleeps + 1
		end,
	}
	local function collector(command, ...)
		local value = (...)
		if command == "setpause" then
			local old = state.pause
			state.pause = value
			return old
		end
		if command == "setstepmul" then
			local old = state.mul
			state.mul = value
			return old
		end
		if command == "isrunning" then
			return state.running
		end
		assert(command == "step", "unexpected collector command")
		state.steps = state.steps + 1
		state.stepArgs[#state.stepArgs + 1] = select("#", ...)
		state.now = state.now + (cost or 0.0001)
		return state.completeAt and state.steps >= state.completeAt or false
	end
	return state, timer, collector
end
T.eq(Performance.gcBudget, true, "P2 defaults on")
T.eq(Performance.GC_PAUSE, 120, "requested collector pause")
T.eq(Performance.GC_STEP_MUL, 300, "requested collector step multiplier")
for _, tier in ipairs({ "high", "balanced", "low" }) do
	T.eq(Performance.CAPS[tier].gcBudgetSeconds, 0.0005, "tier carries the default idle budget")
end
local state, timer, gc = setup()
Performance.tier = "high"
Budget.beginFrame(Performance, gc)
T.eq(state.pause, 120, "frame applies requested pause")
T.eq(state.mul, 300, "frame applies requested step multiplier")
local steps = Budget.idle(timer, 0.01)
T.eq(steps, 5, "idle work stops at the half-millisecond budget")
for _, n in ipairs(state.stepArgs) do
	T.eq(n, 0, "incremental step has no fixed kilobyte argument")
end
local before = state.steps
T.eq(Budget.idle(timer, state.now), 0, "no collector work starts at an exhausted deadline")
T.eq(state.steps, before, "expired deadline leaves collector untouched")
state, timer, gc = setup()
Budget.beginFrame(Performance, gc)
T.eq(Budget.idle(timer, 0.00025), 3, "shorter deadline bounds started steps")
T.check(state.now <= 0.00035, "indivisible work can overshoot by at most one tested step")
state, timer, gc = setup()
state.completeAt = 2
Budget.beginFrame(Performance, gc)
T.eq(Budget.idle(timer, 0.01), 2, "completed cycle does not immediately start another cycle")
state.running = false
T.eq(Budget.idle(timer, 0.01), 0, "a stopped collector is not restarted")
state.running = true
Budget._facadeHandled()
T.eq(Budget.idle(timer, 0.01), 0, "existing public GC delegation retains its frame")
Budget.beginFrame(Performance, gc)
T.check(Budget.idle(timer, 0.01) > 0, "next frame resets compatibility delegation ownership")
Performance.gcBudget = false
Budget.beginFrame(Performance, gc)
T.eq(state.pause, 200, "disable restores previous collector pause")
T.eq(state.mul, 200, "disable restores previous step multiplier")
T.eq(Budget.idle(timer, 0.01), 0, "disabled P2 does no idle collector work")
Performance.gcBudget = true
local caps = Performance.CAPS.low
local oldPause, oldMul, oldSeconds = caps.gcPause, caps.gcStepMul, caps.gcBudgetSeconds
caps.gcPause, caps.gcStepMul, caps.gcBudgetSeconds = 140, 250, 0.0002
Performance.tier = "low"
state, timer, gc = setup()
Budget.beginFrame(Performance, gc)
T.eq(state.pause, 140, "tier-specific pause is respected")
T.eq(state.mul, 250, "tier-specific step multiplier is respected")
T.eq(Budget.idle(timer, 0.01), 2, "tier can reduce the idle budget")
caps.gcBudgetSeconds = 0.01
Budget.beginFrame(Performance, gc)
before = state.steps
Budget.idle(timer, state.now + 0.1)
T.check(state.steps - before <= 6, "tier override cannot exceed the half-millisecond ceiling")
caps.gcPause, caps.gcStepMul, caps.gcBudgetSeconds = oldPause, oldMul, oldSeconds
Performance.tier = "high"
state, timer, gc = setup()
Budget.beginFrame(Performance, gc)
Cap.current, Cap.vsyncPacing = 60, false
local deadline = Cap.pace(timer, nil, false, 0, Budget.idle)
T.eq(state.steps, 5, "actual software pacing performs bounded GC before sleeping")
T.check(state.sleeps > 0, "software pacing sleeps after collection")
T.check(math.abs(deadline - 1 / 60) < 1e-9, "collection does not move the software deadline")
state, timer, gc = setup()
Budget.beginFrame(Performance, gc)
Cap.vsyncPacing = true
local window = {
	getVSync = function()
		return 1
	end,
	getMode = function()
		return 320, 180, { refreshrate = 60 }
	end,
}
state.now = 1 / 60 - 0.0003
Cap.pace(timer, window, true, 0, Budget.idle)
T.check(state.steps > 0 and state.steps <= 4, "VSync uses only actual remaining deadline time")
T.eq(state.sleeps, 0, "VSync receives no extra sleep after collection")
state, timer, gc = setup()
Budget.beginFrame(Performance, gc)
state.now = 1 / 60 + 0.001
Cap.pace(timer, window, true, 0, Budget.idle)
T.eq(state.steps, 0, "late VSync present receives no invented idle budget")
Performance.gcBudget = false
Budget.configure(Performance, gc)
Performance.gcBudget = true
T.finish()
