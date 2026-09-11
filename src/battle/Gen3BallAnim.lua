-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THROWING A POKéBALL.
--
-- Reported from play: "Pokeball throwing animations dont exist in battle
-- either", "neither do the capturing shaking etc eniamtions".  The catch
-- MATHS has been right for a long time -- the shakes are computed and the
-- Pokémon is caught or not caught correctly -- and none of it was ever shown,
-- because the port drives ball animations through Gen 1's and Gen 2's
-- animation SCRIPTS and a Gen 3 dataset has none of them.
--
-- So this is the animation itself, as a timeline, and every number in it was
-- read out of the cartridge's own code rather than felt out:
--
--   THE THROW is 34 frames.  x and y walk to the target in a straight line
--   while Sin() adds a hump of forty pixels over HALF a period -- so the apex
--   is at frame 17 and the ball arrives falling.
--
--   THE ABSORB is 28 frames, and it is two things at once: the Pokémon's
--   affine scale walks 256 -> 1152 in steps of 32, which is a shrink to about
--   0.22x, while its whole palette blends to THE BALL'S OWN COLOUR over 17.
--   A Net Ball's catch is green and a Dive Ball's is blue.
--
--   THE BOUNCE is four falls -- 16, 13, 11 and 10 frames -- with three rises
--   between them, each landing with its own sound.  The height comes off by
--   ten pixels a bounce.
--
--   THE WOBBLE is 59 frames a shake with 31 between them, and the same 31
--   before the first one and before the break-out.  How many shakes is the
--   catch formula's own answer.
--
--   AND THE CATCH is a click at frame 40, the ball fading to white from 60,
--   and the jingle at 95.
--
-- Nothing here decides whether the Pokémon is caught: it is handed the
-- answer.  This is only what the player sees while the answer is revealed.
local Gen3BallAnim = {}
Gen3BallAnim.__index = Gen3BallAnim

-- Used only by a cache imported before the stage existed; the numbers are the
-- cartridge's, so a screen with no art still gets the right RHYTHM.
local FALLBACK = {
  size = 16, frames = 3,
  timing = {
    throwFrames = 34, throwFrom = { x = 32, y = 80 }, throwArc = -40,
    targetOffsetY = -16,
    openFrames = 10, closeFrames = 10,
    absorbFrames = 28, absorbFrom = 256, absorbStep = 32, fadeFrames = 17,
    bounce = { { fall = 16, sound = 56 }, { rise = 13 },
               { fall = 13, sound = 57 }, { rise = 11 },
               { fall = 11, sound = 58 }, { rise = 10 },
               { fall = 10, sound = 59 } },
    bounceHeight = 40,
    shakeFrames = 59, shakePause = 31, preShake = 31,
    clickAt = 40, fadeAt = 60, jingleAt = 95, doneAt = 150,
    sendOut = { from = { x = 24, y = 68 }, frames = 25, arc = -30,
                targetOffsetY = 24, foeOffsetY = 24, foeWait = 16,
                fadeFrames = 14, riseStep = -288 },
    particleFrames = 25, particleCount = 16, particleRadius = 50,
    starFrames = 24,
  },
  sounds = { throw = 61, open = 15, absorb = 60, shake = 23,
             click = 254, caught = 531 },
}

function Gen3BallAnim.record(data)
  local r = (data and data.constants or {}).gen3BallAnim
  if type(r) ~= "table" or type(r.timing) ~= "table" then return nil end
  return r
end

-- Which of the twelve sheets a bag item names.  The cartridge's own
-- ItemIdToBallId, which is a jump table rather than an order.
function Gen3BallAnim.ballIndex(data, itemId, items)
  local r = Gen3BallAnim.record(data)
  local map = r and r.itemToBall
  local def = items and items[itemId]
  local n = def and tonumber(def.index)
  if map and n and map[n] then return map[n] end
  return 0
end

-- The cartridge's sine table is 256 steps to the circle and 256 to the unit;
-- keeping that shape means the arc is the same arc rather than a similar one.
local function sinAt(step, amplitude)
  return math.floor(math.sin(step * 2 * math.pi / 256) * amplitude + 0.5)
end
local function cosAt(step, amplitude)
  return math.floor(math.cos(step * 2 * math.pi / 256) * amplitude + 0.5)
end

function Gen3BallAnim.new(data, opts)
  opts = opts or {}
  local record = Gen3BallAnim.record(data)
  local self = setmetatable({}, Gen3BallAnim)
  self.data = data
  self.record = record
  self.timing = (record and record.timing) or FALLBACK.timing
  self.sounds = (record and record.sounds) or FALLBACK.sounds
  self.size = (record and record.size) or FALLBACK.size
  self.ball = math.max(0, math.floor(tonumber(opts.ball) or 0))
  self.caught = opts.caught and true or false
  self.shakes = math.max(0, math.min(3, math.floor(tonumber(opts.shakes) or 0)))
  self.blocked = opts.blocked and true or false

  local T = self.timing
  -- SENDING ONE OUT IS A DIFFERENT THROW FROM CATCHING ONE.
  --
  -- The capture arcs 34 frames and forty pixels at the Pokemon's BODY,
  -- because it has to swallow it.  A send-out arcs 25 frames and thirty at a
  -- point twenty-four pixels BELOW the Pokemon, because what it has to do is
  -- land where the Pokemon will stand.  And the foe's is not thrown at all:
  -- the cartridge puts the ball on the spot and waits sixteen frames.
  --
  -- `battler` is whose ball this is.  Without it the screen cannot tell which
  -- of the two Pokemon the timeline is talking about, and a send-out on one
  -- side shrank the one on the other.
  self.sendOut = opts.sendOut
  self.battler = opts.battler
  local send = self.sendOut
                and (T.sendOut or FALLBACK.timing.sendOut) or nil
  self.send = send
  self.from = opts.from or (send and send.from) or T.throwFrom
              or { x = 32, y = 80 }
  local to = opts.to or { x = 176, y = 40 }
  local dy = send and (send.targetOffsetY or 24) or (T.targetOffsetY or -16)
  self.to = { x = to.x, y = to.y + dy }
  -- where the bounce happens, which is the platform rather than the body
  self.ground = tonumber(opts.ground)

  self.frame = 0
  self.phase = "throw"
  -- the FOE's ball is placed rather than thrown
  if self.sendOut == "opponent" then
    self.phase = "foewait"
    self.from = { x = self.to.x, y = self.to.y }
  end
  self.phaseFrame = 0
  self.done = false
  self.sound = nil
  -- what the screen reads
  self.x, self.y = self.from.x, self.from.y
  self.ballFrame = 1          -- 1 closed, 2 opening, 3 open
  self.monScale = 1
  self.monBlend = 0
  self.monHidden = false
  self.monRise = 0
  if self.sendOut then
    -- it is still inside the ball, so there is nothing to draw yet
    self.monHidden = true
    self.monScale, self.monBlend = 0, 1
  end
  self.particles = nil
  self.stars = nil
  -- HOENN'S SHINY SPARKLE, which this port never had.  See SHINY_* below.
  self.shiny = (opts.shiny or opts.shinyOnly) and true or false
  self.shinyStars = nil
  self.whiteout = 0
  self.shakeOffset = 0
  self.shakesShown = 0
  self.sound = self.sounds.throw
  -- A WILD POKEMON IS NEVER SENT OUT, so there is no ball to hang the
  -- sparkle on.  PrintBeginningBattleText's wild branch plays the shiny
  -- animation ALONE for exactly that reason, and this is that: no throw, no
  -- ball, no fade -- just the sparkle over a Pokemon already standing there.
  if opts.shinyOnly then
    self.phase, self.phaseFrame = "shiny", 0
    self.shinyStars = { age = 0, made = 0 }
    self.monHidden = false
    self.monScale, self.monBlend, self.monRise = 1, 0, 0
    self.whiteout = 1 -- the ball is not drawn at all
    self.sounds = { }
    -- over the Pokemon itself, not the spot a ball would have been aimed at
    self.to = { x = to.x, y = to.y }
    self.x, self.y = to.x, to.y
  end
  return self
end

-- The ball's own colour, which is what the Pokémon blends to.  Callable as
-- `Gen3BallAnim.colour(anim)` too, because the pic layer holds the animation
-- and not the module.
function Gen3BallAnim:colour()
  local balls = self.record and self.record.balls
  local row = balls and balls[self.ball + 1]
  return (row and row.colour) or { 255, 255, 255 }
end

local function spawnParticles(self)
  local T = self.timing
  self.particles = { age = 0, life = T.particleFrames or 25,
                     count = T.particleCount or 16,
                     radius = T.particleRadius or 50,
                     x = self.x, y = self.y - 5 }
end

-- ---------------------------------------------------------------------------
-- THE SHINY SPARKLE (TryShinyAnimation 08172F10, Task_ShinyStars 08172FEC)
--
-- Read out of the cartridge rather than guessed.  TryShinyAnimation runs the
-- shiny test inline -- the four half-words xored, `cmp r0,#7 / bhi` at
-- 08172F86, which is where SHINY_GEN3_UNDER = 8 comes from -- and on a pass
-- creates TWO Task_ShinyStars, one with data[1] = 0 and one with data[1] = 1
-- (08172F94..08172FA6): two streams of sparkles, not one.
--
-- The task itself:
--   08172FFE  waits while data[13] <= 59            -- SIXTY frames first
--   0817302C  spawns only when (counter & 3) == 0   -- one every FOUR frames
--   08173156  mov r0,#102 / bl PlaySE...WithPanning -- SE_SHINY, id 102, and
--             only on the first one (the `data[11] == 0` guard at 08173142);
--             the pan is 63 or -64 by side
--   08173188  stops at data[11] == 5                -- FIVE sparkles a stream
--
-- So the whole thing is 60 + 4*5 frames long, which is why this gets a phase
-- of its own rather than riding the fourteen-frame release: the release is
-- over long before the first sparkle is due.
local SHINY_DELAY = 60
local SHINY_EVERY = 4
local SHINY_COUNT = 5
local SHINY_SOUND = 102 -- SE_SHINY
Gen3BallAnim.SHINY_DELAY = SHINY_DELAY
Gen3BallAnim.SHINY_EVERY = SHINY_EVERY
Gen3BallAnim.SHINY_COUNT = SHINY_COUNT
Gen3BallAnim.SHINY_SOUND = SHINY_SOUND

-- How long the sparkle runs once it starts, so `estimate` can hold for it.
function Gen3BallAnim.shinyFrames()
  return SHINY_DELAY + SHINY_EVERY * SHINY_COUNT
end

-- The moment the ball opens and the Pokemon starts coming out, which both
-- send-out paths reach -- the player's after its arc, the foe's after its
-- wait (SpriteCB_ReleaseMonFromBall, 075D14).
function Gen3BallAnim:openForRelease()
  self.phase, self.phaseFrame = "release", 0
  self.ballFrame = 3
  self.sound = self.sounds.open
  self.monHidden = false
  spawnParticles(self)
end

-- One frame.  Returns false once there is nothing left to draw.
function Gen3BallAnim:update()
  if self.done then return false end
  local T = self.timing
  -- THE THROW SOUND IS THE FIRST FRAME'S, not the constructor's: `sound` is
  -- what the caller plays for THIS frame and is cleared at the top of every
  -- one, so setting it in `new` meant it was cleared before anything read it.
  self.sound = (self.frame == 0) and self.sounds.throw or nil
  self.frame = self.frame + 1
  self.phaseFrame = self.phaseFrame + 1

  if self.particles then
    self.particles.age = self.particles.age + 1
    if self.particles.age >= self.particles.life then self.particles = nil end
  end
  if self.stars then
    self.stars.age = self.stars.age + 1
    if self.stars.age >= (T.starFrames or 24) then self.stars = nil end
  end
  if self.shinyStars then
    local sp = self.shinyStars
    sp.age = sp.age + 1
    if sp.age >= SHINY_DELAY and sp.made < SHINY_COUNT
       and (sp.age - SHINY_DELAY) % SHINY_EVERY == 0 then
      sp.made = sp.made + 1
      -- two streams, and the cartridge plays SE_SHINY on the first sparkle
      -- only -- five plays would be five overlapping copies of one sound
      if sp.made == 1 then self.sound = SHINY_SOUND end
    end
    if sp.made >= SHINY_COUNT
       and sp.age >= SHINY_DELAY + SHINY_EVERY * SHINY_COUNT then
      self.shinyStars = nil
      if self.phase == "shiny" then self.done = true end
    end
  end

  local send = self.send
  local phase = self.phase
  if phase == "throw" then
    local n = (send and send.frames) or T.throwFrames or 34
    local t = math.min(1, self.phaseFrame / n)
    self.x = self.from.x + (self.to.x - self.from.x) * t
    self.y = self.from.y + (self.to.y - self.from.y) * t
    -- HALF a period, which is why the ball arrives on the way down
    self.y = self.y + sinAt(math.floor(t * 128),
                            (send and send.arc) or T.throwArc or -40)
    if self.phaseFrame >= n then
      if self.blocked then
        self.phase, self.phaseFrame = "blocked", 0
      elseif send then
        self:openForRelease()
      else
        self.phase, self.phaseFrame = "absorb", 0
        self.ballFrame = 3
        self.sound = self.sounds.open
        spawnParticles(self)
      end
    end

  -- THE FOE'S BALL IS NOT THROWN.  It is put on the Pokemon's spot and left
  -- there for sixteen frames before it opens (076398), which is why an
  -- opposing trainer's send-out has no arc in it at all.
  elseif phase == "foewait" then
    if self.phaseFrame >= ((send and send.foeWait) or 16) then
      self:openForRelease()
    end

  -- ...and out it comes: the ball opens, throws its particle ring, and the
  -- Pokemon un-blends from the ball's OWN colour over fourteen frames --
  -- LaunchBallFadeMonTask's own count, and the exact reverse of the absorb.
  -- It rises while it does it, 288 two-hundred-and-fifty-sixths of a pixel a
  -- frame, which is the pos2.y walk in SpriteCB_ReleaseMonFromBall.
  elseif phase == "release" then
    local n = (send and send.fadeFrames) or 14
    local t = math.min(1, self.phaseFrame / n)
    self.monScale = t
    self.monBlend = 1 - t
    self.monRise = ((send and send.riseStep) or -288)
                   * self.phaseFrame / 256
    -- the cartridge frees the ball sprite the moment the Pokemon is out
    self.whiteout = t
    if self.phaseFrame >= n then
      self.monScale, self.monBlend, self.monRise = 1, 0, 0
      -- ...and IF IT SPARKLES, the animation is not over.  The cartridge runs
      -- the sparkle as its own task while the battle carries on; this engine
      -- has one object per send-out, so it holds the object open instead.
      -- Only for a shiny, so nothing else waits a frame longer than it did.
      if self.shiny then
        self.phase, self.phaseFrame = "shiny", 0
        self.shinyStars = { age = 0, made = 0 }
      else
        self.done = true
      end
    end

  elseif phase == "shiny" then
    -- nothing moves; the sparkle block above is doing the work and clears
    -- `done` when the last one has burned out

  elseif phase == "blocked" then
    -- swatted away: the cartridge sends it off the bottom-left
    self.x = self.x - 6.5
    self.y = self.y + 8
    if self.phaseFrame > 30 then self.done = true end

  elseif phase == "absorb" then
    local n = T.absorbFrames or 28
    local from = T.absorbFrom or 256
    local step = T.absorbStep or 32
    local scale = from + step * math.min(n, self.phaseFrame)
    self.monScale = from / scale
    self.monBlend = math.min(1, self.phaseFrame / (T.fadeFrames or 17))
    if self.phaseFrame == 11 then self.sound = self.sounds.absorb end
    if self.phaseFrame >= n then
      self.monHidden = true
      self.monScale = 0
      self.phase, self.phaseFrame = "close", 0
      self.ballFrame = 1
    end

  elseif phase == "close" then
    if self.phaseFrame >= (T.closeFrames or 10) then
      self.phase, self.phaseFrame = "bounce", 0
      self.bounceStep = 1
      self.bounceAngle = 0
      self.bounceAmp = T.bounceHeight or 40
      -- THE GROUND IS NOT WHERE THE MON WAS.  The ball is thrown at the
      -- Pokemon's body and then falls; what it falls ONTO is the platform,
      -- the line the foe's feet stand on.  Resting where the throw ended
      -- leaves it hanging level with the middle of a Pokemon that is no
      -- longer there, which is what "hovering instead of being on the
      -- ground" looks like.  The caller measures the platform; without one
      -- this keeps the old behaviour rather than inventing a floor.
      self.groundY = self.ground or self.y
    end

  elseif phase == "bounce" then
    local row = (T.bounce or {})[self.bounceStep]
    if not row then
      self.y = self.groundY
      self.phase, self.phaseFrame = self.shakes > 0 and "prewait" or "prebreak", 0
      if not (self.shakes > 0) and self.caught then self.phase = "prewait" end
    else
      local len = row.fall or row.rise or 1
      local t = math.min(1, self.phaseFrame / len)
      -- a fall is the cosine coming down, a rise is it going back up
      local a = row.fall and (t * 64) or ((1 - t) * 64)
      self.y = self.groundY - cosAt(math.floor(a), self.bounceAmp)
      if self.phaseFrame >= len then
        if row.sound then self.sound = row.sound end
        if row.fall then self.bounceAmp = math.max(0, self.bounceAmp - 10) end
        self.bounceStep = self.bounceStep + 1
        self.phaseFrame = 0
      end
    end

  elseif phase == "prewait" then
    if self.phaseFrame >= (T.preShake or 31) then
      self.phase, self.phaseFrame = "shake", 0
      self.sound = self.sounds.shake
    end

  elseif phase == "shake" then
    local n = T.shakeFrames or 59
    -- the cartridge's own path: right, then left twice as far, then back
    local t = self.phaseFrame / n
    local sway = (t < 8 / n and 3 * (self.phaseFrame / 8))
                 or (t < 22 / n and 3 - 8 * ((self.phaseFrame - 9) / 13))
                 or (t < 27 / n and -5 + 5 * ((self.phaseFrame - 22) / 5))
                 or 0
    self.shakeOffset = (self.shakesShown % 2 == 0) and sway or -sway
    if self.phaseFrame >= n then
      self.shakeOffset = 0
      self.shakesShown = self.shakesShown + 1
      if self.shakesShown >= self.shakes then
        self.phase, self.phaseFrame = self.caught and "caught" or "prebreak", 0
      else
        self.phase, self.phaseFrame = "pause", 0
      end
    end

  elseif phase == "pause" then
    if self.phaseFrame >= (T.shakePause or 31) then
      self.phase, self.phaseFrame = "shake", 0
      self.sound = self.sounds.shake
    end

  elseif phase == "prebreak" then
    if self.phaseFrame >= (T.shakePause or 31) then
      self.phase, self.phaseFrame = "break", 0
      self.ballFrame = 3
      self.sound = self.sounds.open
      spawnParticles(self)
      self.monHidden = false
    end

  elseif phase == "break" then
    -- the Pokémon comes back out: fourteen frames of growing and unblending
    local t = math.min(1, self.phaseFrame / 14)
    self.monScale = t
    self.monBlend = 1 - t
    if self.phaseFrame >= 16 then
      self.monScale, self.monBlend = 1, 0
      self.done = true
    end

  elseif phase == "caught" then
    if self.phaseFrame == (T.clickAt or 40) then
      self.sound = self.sounds.click
      self.stars = { age = 0 }
    end
    local fadeAt = T.fadeAt or 60
    if self.phaseFrame > fadeAt then
      self.whiteout = math.min(1, (self.phaseFrame - fadeAt) / 16)
    end
    if self.phaseFrame == (T.jingleAt or 95) then self.sound = self.sounds.caught end
    if self.phaseFrame >= (T.jingleAt or 95) then self.done = true end
  end

  return not self.done
end

function Gen3BallAnim:isDone() return self.done end

-- Roughly how long the whole thing runs, so the queue can hold for it.
function Gen3BallAnim:estimate()
  local T = self.timing
  -- the wild sparkle is the whole animation
  if self.phase == "shiny" then return Gen3BallAnim.shinyFrames() end
  if self.send then
    local s = self.send
    local n = (self.sendOut == "opponent") and (s.foeWait or 16)
              or (s.frames or 25)
    n = n + (s.fadeFrames or 14)
    -- a shiny holds the screen for its own sparkle afterwards
    if self.shiny then n = n + Gen3BallAnim.shinyFrames() end
    return n
  end
  local n = (T.throwFrames or 34) + (T.absorbFrames or 28)
            + (T.closeFrames or 10)
  for _, row in ipairs(T.bounce or {}) do n = n + (row.fall or row.rise or 0) end
  if self.blocked then return (T.throwFrames or 34) + 32 end
  if self.shakes > 0 then
    n = n + (T.preShake or 31) + self.shakes * (T.shakeFrames or 59)
        + math.max(0, self.shakes - 1) * (T.shakePause or 31)
  end
  if self.caught then
    n = n + (T.jingleAt or 95)
  else
    n = n + (T.shakePause or 31) + 16
  end
  return n
end

return Gen3BallAnim
