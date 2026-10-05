-- PLATINUM'S POFFIN STIRRING, frame by frame (pokeplatinum
-- src/overlay083/ov83_0223F7F4.c), one cook. Frames are the cartridge's 30 Hz.
--
-- INPUT is the finger's movement around the pot's centre (128, 96): its
-- tangential length in pixels, positive clockwise (ApproximateArcLength), x160,
-- and where it is -- under 16 px from the centre counts half, beyond the rim
-- (8 + 64 x (1 + 0.25 x the speed past 910 / 2730)) counts nothing
-- (ov83_0223F8AC).
--
-- THE BATTER (ov83_0223F900): velocity += input x {8,7,7}[phase] / 204, then
-- friction {64,72,80}[phase] back toward zero, clamped to +-3640; the angle
-- advances CalcRadialAngle(68, velocity / 160) on a 65536 circle, and a full
-- turn in the REQUIRED direction counts one rotation.
--
-- SPILLS AND BURNS (ov83_0223FAAC): at |velocity| >= 3640 -- never in the last
-- phase -- every 30 frames is one overflow. At |velocity| <= 910 every 90
-- frames is a burn, the first of a slow stretch only a warning.
--
-- THE DIRECTION (ov83_0223FBBC) flips at random: a countdown of {150,120,90}
-- [phase] + rand(60) frames that pauses while you stir the wrong way; each
-- draw keeps the direction or switches with a bias that leans away from
-- repeating.
--
-- PHASES (ov83_0223FC58): three, each ending after 600 frames or 16 rotations.
-- The result (Gen4Poffin.cook) reads the total frames, overflows and burns.
--
-- A GROUP (2-4 cooks) stirs one pot: every cook's weighted arc is summed and
-- divided by the number of cooks (ov83_0223F900), and the frames they stir
-- TOGETHER are counted (ov83_0223FCE8, Stir.sync): the pot neither too slow
-- nor overflowing, every finger on the batter, every finger moving more than
-- 600 and within 32 px of the first cook's -- after 4 such frames in a row,
-- each one counts and sparkles. A frame that breaks the run resets it; one
-- where somebody is not moving merely pauses it. While the group is in sync
-- the direction never changes. The result takes min(10, (synced / 6) x
-- {0, 1, 5, 10}[cooks] / 10) off the smoothness (ov83_0223FFA8).

local Stir = {}

Stir.CENTER_X, Stir.CENTER_Y = 128, 96
local ACCEL = { 8, 7, 7 }
local FRICTION = { 64, 72, 80 }
local DIR_TIME = { 150, 120, 90 }
local MAX_VEL, SLOW_VEL = 3640, 910
local PHASE_FRAMES, PHASE_TURNS = 600, 16

local function trunc(x) return x >= 0 and math.floor(x) or -math.floor(-x) end
local function absi(x) return x < 0 and -x or x end

function Stir.new(random)
  local s = {
    random = random or function(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end,
    phase = 1, phaseFrames = 0, turns = 0, done = false,
    velocity = 0, angle = 0, frames = 0,
    burns = 0, spills = 0, slowFrames = 0, fastFrames = 0, warned = false,
    event = nil,                     -- "warn" | "burn" | "overflow" this frame
    dir = 0, dirBias = 2, dirCountdown = -1,
  }
  Stir.direction(s, 0)
  return s
end

-- ov83_0223F8AC: 0 full, 1 half (too near the centre), 2 nothing (off the rim)
function Stir.zone(s, x, y)
  local d = math.sqrt((x - Stir.CENTER_X) ^ 2 + (y - Stir.CENTER_Y) ^ 2)
  local over = math.max(0, absi(s.velocity) - SLOW_VEL)
  local rim = math.floor(64 * (1 + 0.25 * over / (MAX_VEL - SLOW_VEL))) + 8
  if d < 16 then return 1 elseif d > rim then return 2 end
  return 0
end

-- ApproximateArcLength (math_util.c) from (x0,y0) to (x1,y1), centre-relative,
-- x160: the step along the tangent, signed by the turn's cross product.
function Stir.arc(x0, y0, x1, y1)
  x0, y0 = x0 - Stir.CENTER_X, y0 - Stir.CENTER_Y
  x1, y1 = x1 - Stir.CENTER_X, y1 - Stir.CENTER_Y
  local cross = x0 * y1 - x1 * y0
  local len = math.sqrt(y0 * y0 + x0 * x0)
  if len == 0 then return 0 end
  local nx, ny = y0 / len, x0 / len
  local r = absi(trunc(nx * (x1 - x0) + ny * (y1 - y0)))
  if cross <= 0 then r = -r end
  return r * 160
end

-- ov83_0223FBBC
function Stir.direction(s, velocity)
  local wrong = (velocity < 0 and s.dir == 0) or (velocity > 0 and s.dir == 1)
  if wrong then return end
  if s.dirCountdown < 0 then
    local roll = s.random(65536)
    local pick = (roll % 5) <= s.dirBias and 1 or 0
    if pick == s.dir then
      if s.dir == 1 then
        if s.dirBias - 1 >= 0 then s.dirBias = s.dirBias - 1 end
      elseif s.dirBias + 1 < 5 then s.dirBias = s.dirBias + 1 end
    else
      s.dir, s.dirBias = pick, 2
    end
    s.dirCountdown = DIR_TIME[s.phase] + (roll % 60)
  end
  s.dirCountdown = s.dirCountdown - 1
end

-- One 30 Hz frame. `input` is the arc x160 already weighted by its zone
-- (Stir.weigh), or 0 with no finger down.
function Stir.weigh(s, arc, zone)
  if zone == 1 then return trunc(arc / 2) elseif zone == 2 then return 0 end
  return arc
end

-- `cooks`, for a group: { { x, y, arc, zone } }, the first the player, `arc`
-- that cook's unweighted arc this frame
function Stir.sync(s, cooks)
  s.syncStreak, s.syncFrames = s.syncStreak or 0, s.syncFrames or 0
  local speed, allOn = absi(s.velocity), true
  for _, c in ipairs(cooks) do if c.zone ~= 0 then allOn = false end end
  if speed <= SLOW_VEL or (s.phase ~= 3 and speed >= MAX_VEL) or not allOn or #cooks <= 1 then
    s.syncStreak, s.synced = 0, false
    return
  end
  s.sparkle = false
  for _, c in ipairs(cooks) do if absi(c.arc) <= 600 then return end end
  local lead = cooks[1]
  for i = 2, #cooks do
    local c = cooks[i]
    if math.sqrt((c.x - lead.x) ^ 2 + (c.y - lead.y) ^ 2) > 32 then
      s.syncStreak, s.synced = 0, false
      return
    end
  end
  if s.syncStreak < 4 then
    s.syncStreak = s.syncStreak + 1
  else
    s.syncFrames = math.min(9999 * 6, s.syncFrames + 1)
    s.synced, s.sparkle = true, true
  end
end

local SYNC_WEIGHT = { 0, 1, 5, 10 }
function Stir.syncBonus(s, cooks)
  local v = math.floor(math.floor((s.syncFrames or 0) / 6) * (SYNC_WEIGHT[cooks] or 0) / 10)
  return math.min(10, v)
end

function Stir.step(s, input, cooks)
  if s.done then return end
  s.event = nil
  -- ov83_0223FC58: the phase clock comes first
  if s.phaseFrames == PHASE_FRAMES or s.turns >= PHASE_TURNS then
    s.phase, s.phaseFrames, s.turns = s.phase + 1, 0, 0
    if s.phase > 3 then s.done = true; s.phase = 3; return end
  end
  s.phaseFrames = s.phaseFrames + 1
  s.frames = s.frames + 1

  -- ov83_0223F900
  local k = math.floor(ACCEL[s.phase] * 4096 / 204)
  local v = math.floor(trunc(input or 0) * k / 4096)
  s.velocity = s.velocity + v
  local f = FRICTION[s.phase]
  if s.velocity > 0 then s.velocity = math.max(0, s.velocity - f)
  elseif s.velocity < 0 then s.velocity = math.min(0, s.velocity + f) end
  s.velocity = math.max(-MAX_VEL, math.min(MAX_VEL, s.velocity))
  local before = s.angle % 65536
  local step = trunc(trunc(s.velocity / 160) * 0xFFFF / 427)
  s.angle = s.angle + step
  local after = s.angle % 65536
  if s.dir == 0 and s.velocity >= 0 and before > after then s.turns = s.turns + 1 end
  if s.dir == 1 and s.velocity < 0 and before < after then s.turns = s.turns + 1 end

  -- ov83_0223FAAC
  local speed = absi(s.velocity)
  if s.phase ~= 3 and speed >= MAX_VEL then
    s.fastFrames = s.fastFrames + 1
    if s.fastFrames >= 30 then
      s.spills = math.min(9999, s.spills + 1)
      s.fastFrames, s.event = 0, "overflow"
    end
    s.warned = false
  elseif speed <= SLOW_VEL then
    s.slowFrames = s.slowFrames + 1
    if s.slowFrames >= 90 then
      s.slowFrames = 0
      if not s.warned then s.event, s.warned = "warn", true
      else s.event = "burn"; s.burns = math.min(9999, s.burns + 1) end
    end
  else
    s.warned = false
  end

  if cooks then Stir.sync(s, cooks) end
  if not s.synced then Stir.direction(s, s.velocity) end
end

return Stir
