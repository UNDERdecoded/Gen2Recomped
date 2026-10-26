-- Render frame-rate cap.  With a driver control panel forcing
-- vsync off, the 160x144 game is trivially cheap and love.run will present
-- thousands of frames a second; over hours that cooks the graphics driver
-- until a restart, and it wastes power whenever the window is left open in
-- the background.  A hard cap bounds the present rate.  Render-only: game
-- logic is fixed-step off dt (src/core/FixedStep.lua), so pacing present()
-- changes nothing about timing, audio, or determinism.
--
-- Persisted as save.options.fpsCap; applied from OptionsMenu and on boot
-- via Game:applyOptions.  main.lua's love.run reads FrameCap.current each
-- frame for its sleep budget.  The module never touches love.timer itself,
-- so it stays safe under the headless test stub.

local FrameCap = {}

-- Selectable steps: the normal framerate stops between the floor and the
-- ceiling.  STEPS[1] == MIN and STEPS[#STEPS] == MAX, so the nearest-step
-- snap in normalize doubles as the clamp.  Cycling past the last wraps.
FrameCap.STEPS = { 30, 40, 50, 60, 75, 90, 100, 120, 144, 160 }
FrameCap.MIN = 30
FrameCap.MAX = 160
FrameCap.DEFAULT = 60

-- The live cap the run loop paces to.  Defaults so the launcher and the
-- save editor are paced before any save applies its stored option.
FrameCap.current = FrameCap.DEFAULT

-- P1 rollback switch. Each frame still falls back to software pacing when
-- there was no present, VSync is off, or the display rate is unavailable.
FrameCap.vsyncPacing = true
local _refreshWindow, _refreshVsync, _refreshAt, _refreshRate
local REFRESH_POLL_SECONDS = 1

local function presentationPaces(window, now)
  if not (window and window.getVSync and window.getMode) then return false end
  local vsync = window.getVSync()
  if type(vsync) ~= "number" or vsync == 0 then
    _refreshVsync = vsync
    return false
  end
  -- getMode returns a new flags table: sample it once a second rather than
  -- allocate one each frame. Provider/VSync changes invalidate the sample;
  -- display-rate changes are observed on the next periodic sample.
  if window ~= _refreshWindow or vsync ~= _refreshVsync or not _refreshAt
      or now < _refreshAt or now - _refreshAt >= REFRESH_POLL_SECONDS then
    local _, _, flags = window.getMode()
    local rate = type(flags) == "table" and tonumber(flags.refreshrate)
    _refreshWindow, _refreshVsync, _refreshAt = window, vsync, now
    _refreshRate = rate and rate > 0 and rate < math.huge and rate or nil
  end
  return _refreshRate ~= nil and FrameCap.current >= _refreshRate
end

-- The run loop owns the deadline and passes back the returned value. Keeping
-- the original fallback here lets tests exercise the real pacing operation.
function FrameCap.pace(timer, window, presented, nextFrame)
  local now = timer.getTime()
  if FrameCap.vsyncPacing and presented and presentationPaces(window, now) then
    return now
  end
  local budget = 1 / FrameCap.current
  nextFrame = nextFrame + budget
  if now - nextFrame > budget then nextFrame = now end
  while true do
    local remaining = nextFrame - timer.getTime()
    if remaining <= 0 then break end
    timer.sleep(remaining < 0.001 and remaining or 0.001)
  end
  return nextFrame
end

-- Nearest valid step for an arbitrary value (a hand-edited options.lua or
-- an old save with no fpsCap key), so a bad number degrades to something
-- sane; nil / non-numbers fall back to the default.  A value below MIN or
-- above MAX snaps to that end, since MIN/MAX are the first/last steps.
function FrameCap.normalize(value)
  value = tonumber(value)
  if not value then return FrameCap.DEFAULT end
  local best, bestDiff = FrameCap.DEFAULT, math.huge
  for _, step in ipairs(FrameCap.STEPS) do
    local diff = math.abs(step - value)
    if diff < bestDiff then best, bestDiff = step, diff end
  end
  return best
end

-- plain numeric text for the options row (e.g. "60")
function FrameCap.label(value)
  return tostring(FrameCap.normalize(value))
end

-- cycle to the next/previous step, wrapping (the options row idiom)
function FrameCap.cycle(value, dir)
  local steps = FrameCap.STEPS
  local snapped = FrameCap.normalize(value)
  local cur = 1
  for i, step in ipairs(steps) do
    if step == snapped then cur = i break end
  end
  local nextIdx = (cur - 1 + (dir or 1)) % #steps + 1
  return steps[nextIdx]
end

-- Store the chosen cap as the live value the run loop paces to.  Never
-- touches love.timer, so it is safe headless -- the loop just reads the
-- number back.  Returns the normalized value it stored.
function FrameCap.apply(value)
  FrameCap.current = FrameCap.normalize(value)
  return FrameCap.current
end

function FrameCap.applyOptions(opts)
  FrameCap.apply(opts and opts.fpsCap)
end

return FrameCap
