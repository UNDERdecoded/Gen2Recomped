-- Cooperative incremental collection in otherwise unused frame time.
local Profile = require("src.core.FrameProfile")
local Budget = {}
local MAX_SECONDS = 0.0005
local _collector, _priorPause, _priorMul, _pause, _mul
local _enabled, _seconds, _canQueryRunning, _facadeStepped = false, 0, false, false

local function nonnegative(value, fallback)
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return fallback
	end
	return value
end

local function restoreTuning()
	if _collector and _priorPause ~= nil then
		_collector("setpause", _priorPause)
		_collector("setstepmul", _priorMul)
	end
	_collector, _priorPause, _priorMul, _pause, _mul = nil, nil, nil, nil, nil
end

function Budget.configure(performance, collector)
	collector = collector or collectgarbage
	if not performance.gcBudget or type(collector) ~= "function" then
		restoreTuning()
		_enabled = false
		return
	end
	if _collector ~= collector then
		restoreTuning()
	end
	local caps = performance.CAPS[performance.tier] or {}
	local pause = math.floor(nonnegative(caps.gcPause, performance.GC_PAUSE))
	local mul = math.floor(nonnegative(caps.gcStepMul, performance.GC_STEP_MUL))
	if not _collector then
		_collector = collector
		_priorPause = collector("setpause", pause)
		_priorMul = collector("setstepmul", mul)
		_canQueryRunning = pcall(collector, "isrunning")
	else
		if pause ~= _pause then
			collector("setpause", pause)
		end
		if mul ~= _mul then
			collector("setstepmul", mul)
		end
	end
	_pause, _mul = pause, mul
	_seconds = math.min(MAX_SECONDS, nonnegative(caps.gcBudgetSeconds, performance.GC_BUDGET_SECONDS))
	_enabled = true
end

function Budget.beginFrame(performance, collector)
	_facadeStepped = false
	Budget.configure(performance, collector)
end

-- An existing public compatibility method retains ownership of its frame.
-- Its call, arguments and return behavior are not replaced by idle collection.
function Budget._facadeHandled()
	_facadeStepped = true
end

function Budget.idle(timer, deadline)
	if not _enabled or _facadeStepped or _seconds <= 0 then
		return 0
	end
	local start = timer.getTime()
	local stop = math.min(deadline, start + _seconds)
	if stop <= start or (_canQueryRunning and not _collector("isrunning")) then
		return 0
	end
	local close = Profile.section("  frame pacing: gc budget")
	local steps = 0
	while timer.getTime() < stop do
		steps = steps + 1
		if _collector("step") then
			break
		end
	end
	close()
	return steps
end

return Budget
