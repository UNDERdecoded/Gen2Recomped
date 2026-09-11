-- Emerald's procedural front-pic animations.
--
-- PicAnim (next door) plays Crystal's FRAME animations: two pictures swapped
-- back and forth.  This is the other half, and on Gen 3 it is the half that
-- carries the motion.  Every species picks one routine out of
-- sMonAnimFunctions -- squash, hop, rotate, slide, glow -- and that routine
-- moves the SPRITE, not its pixels.  The import side reads the pick and the
-- delay before it starts (RomExtractorGen3:extractMonAnims) and leaves:
--
--   constants.gen3MonAnim.anims[SPECIES] = {
--     anim  = "V_JUMPS_H_JUMPS",   -- the sMonAnimFunctions entry
--     id    = 6,                   -- its index, for the record
--     delay = 0,                   -- 60Hz frames to wait first
--   }
--
-- The routines are written here as pure functions of `t` in 0..1 over the
-- animation's own length, each returning the sprite transform for that
-- instant.  The hardware ones are hand-written sprite callbacks that step a
-- counter, but every one of them traces a shape -- a sine, a decaying shake,
-- a pair of hops -- and the shape is what the eye reads.  The families here
-- ARE the cartridge's families: pret builds all 87 out of the same handful
-- of helpers with different amplitudes, speeds and repeat counts, and those
-- are the parameters below.
--
-- Emerald plays this ONCE, when the mon appears (and again on the summary
-- page).  It does not loop; a mon that bounced forever would be a different
-- game.  So the player runs to its end and then sits still, exactly like
-- PicAnim.

local MonAnim = {}
MonAnim.__index = MonAnim

local sin, cos, pi, abs, floor = math.sin, math.cos, math.pi, math.abs, math.floor

-- ---------------------------------------------------------------------------
-- the shapes
--
-- Each returns dx, dy (sprite pixels), sx, sy (scale), rot (radians),
-- alpha, and optionally a tint {r, g, b, strength}.  `t` runs 0..1.
-- ---------------------------------------------------------------------------

-- one decaying oscillation: `n` swings, fading to nothing at the end
local function shake(t, n, amp)
  return sin(t * n * 2 * pi) * amp * (1 - t)
end

-- `n` hops: each one a half-sine up and back down
local function hops(t, n)
  local u = (t * n) % 1
  return -sin(u * pi)
end

-- squash and bounce: compress, spring up, settle
local function squash(t, amp)
  local s = sin(t * 2 * pi) * amp * (1 - t)
  return 1 - s, 1 + s
end

local S = {}

local function reg(names, dur, fn)
  for name in names:gmatch("%S+") do S[name] = { dur = dur, fn = fn } end
end

-- ---- squash and bounce ----------------------------------------------------
reg("V_SQUISH_AND_BOUNCE", 40, function(t)
  local sx, sy = squash(t, 0.18)
  return 0, 0, sx, sy
end)
reg("V_SQUISH_AND_BOUNCE_SLOW", 64, function(t)
  local sx, sy = squash(t, 0.18)
  return 0, 0, sx, sy
end)
reg("DEEP_V_SQUISH_AND_BOUNCE", 44, function(t)
  local sx, sy = squash(t, 0.30)
  return 0, 0, sx, sy
end)
reg("DEEP_V_SQUISH_AND_BOUNCE_TWICE", 72, function(t)
  local sx, sy = squash((t * 2) % 1, 0.30)
  return 0, 0, sx, sy
end)

-- ---- stretch --------------------------------------------------------------
reg("V_STRETCH", 36, function(t)
  local s = sin(t * pi) * 0.22
  return 0, 0, 1 - s * 0.5, 1 + s
end)
reg("H_STRETCH", 36, function(t)
  local s = sin(t * pi) * 0.22
  return 0, 0, 1 + s, 1 - s * 0.5
end)
reg("CIRCULAR_STRETCH_TWICE", 56, function(t)
  -- the stretch rolls around the pic twice; the envelope is what brings it
  -- back onto the still at both ends
  local a, env = t * 4 * pi, sin(t * pi)
  return 0, 0, 1 + cos(a) * 0.14 * env, 1 + sin(a) * 0.14 * env
end)
reg("SHRINK_GROW", 48, function(t)
  local s = 1 - sin(t * 2 * pi) * 0.16
  return 0, 0, s, s
end)
reg("GROW_VIBRATE", 48, function(t)
  local s = 1 + sin(t * pi) * 0.12
  return shake(t, 8, 2), 0, s, s
end)
reg("LUNGE_GROW", 44, function(t)
  local s = 1 + sin(t * pi) * 0.18
  return -sin(t * pi) * 6, 0, s, s
end)
reg("GROW_IN_STAGES", 60, function(t)
  local stage = floor(t * 4) / 4
  local s = 0.7 + stage * 0.3 + (t >= 0.99 and 0 or 0)
  return 0, 0, s, s
end)

-- ---- shakes and vibrations ------------------------------------------------
reg("H_VIBRATE", 40, function(t) return shake(t, 14, 3), 0 end)
reg("CIRCULAR_VIBRATE", 40, function(t)
  local a = t * 14 * 2 * pi
  local r = 3 * (1 - t)
  return cos(a) * r, sin(a) * r
end)
reg("H_SHAKE", 36, function(t) return shake(t, 5, 5), 0 end)
reg("H_SHAKE_SLOW", 56, function(t) return shake(t, 4, 5), 0 end)
reg("V_SHAKE", 36, function(t) return 0, shake(t, 5, 5) end)
reg("V_SHAKE_SLOW", 56, function(t) return 0, shake(t, 4, 5) end)
reg("V_SHAKE_TWICE", 48, function(t) return 0, shake(t, 8, 5) end)
reg("V_SHAKE_TWICE_SLOW", 68, function(t) return 0, shake(t, 6, 5) end)
reg("VIBRATE_TO_CORNERS", 40, function(t)
  local a = t * 10 * 2 * pi
  local r = 4 * (1 - t)
  return cos(a) * r, cos(a) * r
end)
reg("PIVOT_SHAKE", 40, function(t)
  return 0, 0, 1, 1, shake(t, 5, 0.14)
end)
reg("TIP_AND_SHAKE", 48, function(t)
  local tip = sin(t * pi) * 0.18
  return 0, 0, 1, 1, tip + shake(t, 8, 0.05)
end)

-- ---- slides ---------------------------------------------------------------
local function slideOut(t, amp)
  -- out and back, once
  return sin(t * 2 * pi) * amp
end
reg("H_SLIDE", 32, function(t) return slideOut(t, 8), 0 end)
reg("H_SLIDE_SLOW", 56, function(t) return slideOut(t, 8), 0 end)
reg("V_SLIDE", 32, function(t) return 0, slideOut(t, 8) end)
reg("V_SLIDE_SLOW", 56, function(t) return 0, slideOut(t, 8) end)
reg("H_SLIDE_SHRINK", 44, function(t)
  local u = sin(t * 2 * pi)
  return u * 8, 0, 1 - abs(u) * 0.12, 1 - abs(u) * 0.12
end)
reg("V_SLIDE_WOBBLE", 48, function(t)
  return shake(t, 4, 3), slideOut(t, 8)
end)
reg("V_SLIDE_WOBBLE_SMALL", 48, function(t)
  return shake(t, 4, 2), slideOut(t, 4)
end)
reg("H_SLIDE_WOBBLE", 48, function(t)
  return slideOut(t, 8), shake(t, 4, 3)
end)
reg("H_SLIDE_WOBBLE_TWICE", 72, function(t)
  return slideOut((t * 2) % 1, 8), shake(t, 6, 3)
end)
-- a zigzag is a square wave, but it has to leave the still pic and come back
-- to it -- so it ramps in over the first eighth and decays to nothing
local function zigzag(t, n)
  local u = (t * n) % 1
  local amp = 4 * (1 - t) * math.min(1, t * 8)
  return (u < 0.5 and amp or -amp)
end
reg("ZIGZAG_FAST", 40, function(t) return zigzag(t, 6), 0 end)
reg("ZIGZAG_SLOW", 60, function(t) return zigzag(t, 4), 0 end)
reg("TIP_MOVE_FORWARD", 44, function(t)
  return -sin(t * pi) * 6, 0, 1, 1, sin(t * pi) * 0.10
end)
reg("TIP_HOP_FORWARD", 52, function(t)
  return -sin(t * pi) * 6, hops(t, 2) * 8, 1, 1, sin(t * pi) * 0.10
end)
reg("CIRCLE_INTO_BG", 48, function(t)
  local a = t * 2 * pi
  local r = sin(t * pi) * 6
  return cos(a) * r, sin(a) * r, 1 - sin(t * pi) * 0.15,
         1 - sin(t * pi) * 0.15
end)
reg("FOUR_PETAL", 64, function(t)
  local a = t * 4 * 2 * pi
  local r = sin(t * 4 * pi) * 5
  return cos(a) * r, sin(a) * r
end)
reg("FIGURE_8", 56, function(t)
  return sin(t * 2 * pi) * 7, sin(t * 4 * pi) * 4
end)
reg("CIRCLE_C_CLOCKWISE", 48, function(t)
  local a = -t * 2 * pi
  return cos(a) * 6 - 6, sin(a) * 6
end)
reg("CIRCLE_C_CLOCKWISE_SLOW", 68, function(t)
  local a = -t * 2 * pi
  return cos(a) * 6 - 6, sin(a) * 6
end)

-- ---- jumps ----------------------------------------------------------------
reg("V_JUMPS_SMALL", 40, function(t) return 0, hops(t, 2) * 6 end)
reg("V_JUMPS_BIG", 48, function(t) return 0, hops(t, 2) * 14 end)
reg("V_JUMPS_H_JUMPS", 60, function(t)
  if t < 0.5 then return 0, hops(t * 2, 2) * 10 end
  local u = (t - 0.5) * 2
  return sin(u * 2 * pi) * 8, hops(u, 2) * 5
end)
reg("H_JUMPS", 48, function(t)
  return sin(t * 4 * pi) * 8, hops(t, 2) * 5
end)
reg("H_JUMPS_V_STRETCH", 56, function(t)
  local s = sin(t * 4 * pi) * 0.12
  return sin(t * 4 * pi) * 8, hops(t, 2) * 5, 1 - s, 1 + s
end)
reg("RAPID_H_HOPS", 48, function(t)
  return sin(t * 8 * pi) * 5, hops(t, 4) * 5
end)
reg("V_SPRING", 40, function(t)
  local s = sin(t * 2 * pi) * 0.20
  return 0, hops(t, 1) * 10, 1 - s, 1 + s
end)
reg("V_REPEATED_SPRING", 64, function(t)
  local s = sin(t * 4 * pi) * 0.16
  return 0, hops(t, 3) * 8, 1 - s, 1 + s
end)
reg("SPRING_RISING", 52, function(t)
  return 0, -sin(t * pi) * 12, 1 - sin(t * pi) * 0.14,
         1 + sin(t * pi) * 0.14
end)
reg("H_SPRING", 40, function(t)
  local s = sin(t * 2 * pi) * 0.18
  return sin(t * 2 * pi) * 8, 0, 1 + s, 1 - s
end)
reg("H_REPEATED_SPRING_SLOW", 68, function(t)
  local s = sin(t * 4 * pi) * 0.14
  return sin(t * 4 * pi) * 7, 0, 1 + s, 1 - s
end)
reg("RISING_WOBBLE", 52, function(t)
  return shake(t, 5, 4), -sin(t * pi) * 10
end)

-- ---- rotations ------------------------------------------------------------
reg("ROTATE_TO_SIDES", 40, function(t)
  return 0, 0, 1, 1, sin(t * 2 * pi) * 0.20
end)
reg("ROTATE_TO_SIDES_FAST", 28, function(t)
  return 0, 0, 1, 1, sin(t * 2 * pi) * 0.20
end)
reg("ROTATE_TO_SIDES_TWICE", 64, function(t)
  return 0, 0, 1, 1, sin(t * 4 * pi) * 0.20
end)
reg("ROTATE_UP_TO_SIDES", 44, function(t)
  return 0, -sin(t * pi) * 6, 1, 1, sin(t * 2 * pi) * 0.20
end)
reg("ROTATE_UP_SLAM_DOWN", 44, function(t)
  if t < 0.6 then
    local u = t / 0.6
    return 0, -u * 8, 1, 1, -u * 0.26
  end
  local u = (t - 0.6) / 0.4
  local sy = 1 - (1 - abs(1 - u * 2)) * 0.18
  return 0, -(1 - u) * 8, 1, sy, -(1 - u) * 0.26
end)
reg("BOUNCE_ROTATE_TO_SIDES", 48, function(t)
  return 0, hops(t, 2) * 8, 1, 1, sin(t * 4 * pi) * 0.16
end)
reg("BOUNCE_ROTATE_TO_SIDES_SLOW", 68, function(t)
  return 0, hops(t, 2) * 8, 1, 1, sin(t * 4 * pi) * 0.16
end)
reg("BOUNCE_ROTATE_TO_SIDES_SMALL", 48, function(t)
  return 0, hops(t, 2) * 5, 1, 1, sin(t * 4 * pi) * 0.09
end)
reg("BOUNCE_ROTATE_TO_SIDES_SMALL_SLOW", 68, function(t)
  return 0, hops(t, 2) * 5, 1, 1, sin(t * 4 * pi) * 0.09
end)
reg("H_PIVOT", 44, function(t)
  return 0, 0, 1, 1, sin(t * 2 * pi) * 0.12
end)
reg("SWING_CONCAVE", 44, function(t)
  return 0, sin(t * 2 * pi) * -3, 1, 1, sin(t * 2 * pi) * 0.16
end)
reg("SWING_CONCAVE_FAST", 28, function(t)
  return 0, sin(t * 2 * pi) * -3, 1, 1, sin(t * 2 * pi) * 0.16
end)
reg("SWING_CONCAVE_FAST_SHORT", 22, function(t)
  return 0, sin(t * 2 * pi) * -2, 1, 1, sin(t * 2 * pi) * 0.11
end)
reg("SWING_CONVEX", 44, function(t)
  return 0, sin(t * 2 * pi) * 3, 1, 1, sin(t * 2 * pi) * -0.16
end)
reg("SWING_CONVEX_FAST", 28, function(t)
  return 0, sin(t * 2 * pi) * 3, 1, 1, sin(t * 2 * pi) * -0.16
end)
reg("SWING_CONVEX_FAST_SHORT", 22, function(t)
  return 0, sin(t * 2 * pi) * 2, 1, 1, sin(t * 2 * pi) * -0.11
end)

-- ---- flips and spins ------------------------------------------------------
-- a flip is a full turn; a spin is a horizontal squeeze through zero, which
-- is how the hardware fakes a Y-axis rotation with an affine sprite
local function spinScale(u) return cos(u * 2 * pi) end
reg("SPIN", 36, function(t) return 0, 0, spinScale(t), 1 end)
reg("SPIN_LONG", 72, function(t) return 0, 0, spinScale(t * 2), 1 end)
reg("TWIST", 44, function(t) return 0, 0, spinScale(t), 1 end)
reg("TWIST_TWICE", 72, function(t) return 0, 0, spinScale(t * 2), 1 end)
reg("BACK_FLIP", 44, function(t)
  return 0, -sin(t * pi) * 10, 1, 1, -t * 2 * pi
end)
reg("BACK_FLIP_BIG", 56, function(t)
  return 0, -sin(t * pi) * 18, 1, 1, -t * 2 * pi
end)
reg("FRONT_FLIP", 44, function(t)
  return 0, -sin(t * pi) * 10, 1, 1, t * 2 * pi
end)
reg("TUMBLING_FRONT_FLIP", 52, function(t)
  return sin(t * 2 * pi) * 6, -sin(t * pi) * 10, 1, 1, t * 2 * pi
end)
reg("TUMBLING_FRONT_FLIP_TWICE", 76, function(t)
  return sin(t * 4 * pi) * 6, -sin(t * 2 * pi) * 10, 1, 1, t * 4 * pi
end)
-- draw back, lunge past the still, then settle back onto it
reg("BACK_AND_LUNGE", 52, function(t)
  if t < 0.35 then return (t / 0.35) * 6, 0 end
  if t < 0.70 then return 6 - ((t - 0.35) / 0.35) * 16, 0 end
  return -10 + ((t - 0.70) / 0.30) * 10, 0
end)

-- ---- colour ---------------------------------------------------------------
local function glow(r, g, b)
  return function(t)
    local s = sin(t * pi)
    return 0, 0, 1, 1, 0, 1, { r, g, b, s }
  end
end
reg("GLOW_BLACK", 40, glow(0, 0, 0))
reg("GLOW_ORANGE", 40, glow(1, 0.60, 0.15))
reg("GLOW_RED", 40, glow(1, 0.15, 0.15))
reg("GLOW_BLUE", 40, glow(0.20, 0.35, 1))
reg("GLOW_YELLOW", 40, glow(1, 0.95, 0.20))
reg("GLOW_PURPLE", 40, glow(0.70, 0.25, 0.95))
reg("FLASH_YELLOW", 40, function(t)
  local on = (floor(t * 8) % 2) == 0
  return 0, 0, 1, 1, 0, 1, on and { 1, 0.95, 0.20, 0.85 } or nil
end)
reg("FLICKER", 40, function(t)
  return 0, 0, 1, 1, 0, (floor(t * 10) % 2) == 0 and 0.35 or 1
end)
reg("FLICKER_INCREASING", 56, function(t)
  local rate = 4 + t * 12
  return 0, 0, 1, 1, 0, (floor(t * rate) % 2) == 0 and (1 - t * 0.7) or 1
end)

MonAnim.SHAPES = S

-- ---------------------------------------------------------------------------

-- The record for `species`, or nil when the cartridge is not Gen 3 or the
-- import could not read the table.
function MonAnim.record(data, species)
  local c = data and data.constants
  local table_ = c and c.gen3MonAnim and c.gen3MonAnim.anims
  local rec = table_ and species and table_[species]
  if type(rec) ~= "table" or not rec.anim then return nil end
  if not S[rec.anim] then return nil end
  return rec
end

-- A live player, or nil when this species has no procedural animation.
-- Starts PAUSED, for the same reason PicAnim does: the pic is not on screen
-- when the battler is built.
function MonAnim.new(data, species)
  local rec = MonAnim.record(data, species)
  if not rec then return nil end
  local self = setmetatable({
    rec = rec,
    shape = S[rec.anim],
    paused = true,
    clock = 0,
    done = false,
  }, MonAnim)
  return self
end

-- STARTING AN ANIMATION THAT IS ALREADY RUNNING IS NOT A RESTART.
--
-- The battle screen starts this from the DRAW, because the draw is where the
-- pic is known to be on screen -- and a draw happens sixty times a second.
-- This zeroed the clock on every one of them, so the animation was pinned at
-- its first instant and the squash, hop or glow the cartridge gives each
-- species never actually played.  PicAnim (Crystal's front-pic frames) has
-- guarded this since it was written; this is the same guard.
--
-- `restart` is the one that really does begin again, for a caller that means
-- it.
function MonAnim:start()
  if not self.paused then return end
  self:restart()
end

function MonAnim:restart()
  self.paused = false
  self.clock = 0
  self.done = false
end

function MonAnim:update(dt)
  if self.paused or self.done then return end
  self.clock = self.clock + (dt or 0) * 60
  local total = (self.rec.delay or 0) + self.shape.dur
  if self.clock >= total then
    self.clock = total
    self.done = true
  end
end

-- true while the animation still has something to say
function MonAnim:active()
  return not (self.paused or self.done)
end

-- The transform for right now.  Always returns a table -- the identity when
-- the animation is waiting out its delay, finished, or not started.
local IDENTITY = { dx = 0, dy = 0, sx = 1, sy = 1, rot = 0, alpha = 1 }

function MonAnim:transform()
  if self.paused or self.done then return IDENTITY end
  local wait = self.rec.delay or 0
  if self.clock < wait then return IDENTITY end
  local t = (self.clock - wait) / self.shape.dur
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local dx, dy, sx, sy, rot, alpha, tint = self.shape.fn(t)
  return {
    dx = dx or 0, dy = dy or 0,
    sx = sx or 1, sy = sy or 1,
    rot = rot or 0, alpha = alpha or 1,
    tint = tint,
  }
end

MonAnim.IDENTITY = IDENTITY

return MonAnim
