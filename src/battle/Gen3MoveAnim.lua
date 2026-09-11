-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S MOVE ANIMATIONS, as far as the cartridge can be read.
--
-- Reported from play: "when i use slash im not seeing the animation fx of the
-- move slash on the enemy pokemon".  Hoenn's battles played a sound and drew
-- nothing at all, because a Gen 3 move animation is a BYTECODE PROGRAM and
-- this port had never run one.
--
-- WHAT THE IMPORT HANDS OVER.  Each move carries `anim.events`: one record
-- per `createsprite` in its script, saying WHICH sheet the particle comes
-- from, WHICH battler it belongs over, WHAT pixel offset from that battler,
-- and AT WHICH FRAME of the script it appears.  All four are read straight
-- off the cartridge -- the tag and the frame size come from the sprite
-- template the command names, the battler from where Cmd_createsprite spawns
-- the sprite, and the moment from the `delay` commands in front of it.
--
-- WHICH BATTLER, AND THE BIT THAT DOES NOT SAY.  Reported from play: "when an
-- enemy pokemon attacks me the attack animation shows on itself rather than
-- me".  This used to read bit 7 of createsprite's battler byte --
-- ANIMSPRITE_IS_TARGET -- as "over the defender", which is what a bit of that
-- name sounds like and not what the cartridge does with it: Cmd_createsprite
-- reads the bit only to choose whose subpriority the sprite borrows, and then
-- spawns it at GetBattlerSpriteCoord(gBattleAnimTarget, ...) in both arms.
-- Every particle in the game spawns on the TARGET, and a self-aimed move has
-- gBattleAnimTarget pointing back at the user, which is how SWORDS DANCE
-- plays on the mon that danced.  So the import answers from the move's own
-- target field and this file just draws where it is told.
--
-- AND WHAT IT CANNOT.  Where a particle GOES after it is spawned is a C
-- function in the cartridge -- AnimSlashSlice, AnimEllipticalGust, four
-- hundred more -- and a retail ROM ships no symbol table to tell one from
-- another.  So this plays the move's own art, on the right Pokemon, at the
-- right offset, at the right moment, cycling the sheet's own frames; it does
-- not fly a particle along a path nobody can name.  Slash slashes.  Ember
-- burns on the target.  A move whose whole animation is one task function is
-- still quiet, and the record says so by carrying no events.
--
-- THE COORDINATE MIRROR: a script's offsets are authored from the far side
-- of the field, so an x offset on the PLAYER'S own Pokemon is negated -- the
-- cartridge does the same thing in GetBattlerSpriteCoord, and without it
-- every particle on your own mon leans the wrong way.

local Gen3MoveAnim = {}
Gen3MoveAnim.__index = Gen3MoveAnim

-- HOW LONG ONE PARTICLE STAYS UP, AND HOW ITS OWN PICTURE IS TIMED.
--
-- Reported from play: "some arent animating properly as they would on the
-- rom".  Every particle used to riffle its whole sheet at a flat six frames
-- an image and vanish after a flat twenty-six, because those were the two
-- numbers that had to be invented.  Only one of them still is.
--
-- The sprite template names an ANIMATION -- a run of ANIMCMD_FRAMEs, each an
-- image and the number of frames to hold it, ending in END, JUMP or LOOP --
-- and the import now reads it (RomExtractorGen3:spriteAnimTimeline).  Eighty
-- six of the hundred and eighty sheets carry one, and where a sheet does the
-- picture is timed to the cartridge's own numbers rather than to a guess:
-- SLASH's slice is four images of four frames and then it is over; EMBER's
-- flame holds each of three for four and repeats.
--
-- A timeline that ENDS is the particle's whole life -- the sprite plays its
-- animation and the callback destroys it -- so a move whose art ends is over
-- when its art is.  A timeline that REPEATS says nothing about when the
-- sprite goes, because that is in the callback, so those keep the guess.
local LIFETIME = 26
-- ...and a little after the last one clears, so the hit does not land on the
-- same frame the screen empties
local TAIL = 6
local FRAME_HOLD = 6           -- only for a sheet with no timeline of its own

-- The image this particle is showing `age` frames after it appeared, and nil
-- once its animation has finished and it is not one of the repeating ones.
local function frameAt(sheet, age)
  local held = sheet and sheet.held
  local frames = math.max(1, (sheet and sheet.frames) or 1)
  if type(held) ~= "table" or #held == 0 then
    return math.floor(age / FRAME_HOLD) % frames
  end
  local total = 0
  for _, step in ipairs(held) do total = total + (step[2] or 1) end
  if total < 1 then return 0 end
  local t = age
  if t >= total then
    if not sheet.loops then return nil end
    t = t % total
  end
  for _, step in ipairs(held) do
    t = t - (step[2] or 1)
    if t < 0 then return math.min(step[1] or 0, frames - 1) end
  end
  return math.min(held[#held][1] or 0, frames - 1)
end

-- ...and how long it is up for, which for a sheet whose animation ends is the
-- length of that animation and nothing else.
local function lifeOf(sheet)
  local held = sheet and sheet.held
  if type(held) ~= "table" or #held == 0 then return LIFETIME end
  local total = 0
  for _, step in ipairs(held) do total = total + (step[2] or 1) end
  if total < 1 then return LIFETIME end
  if sheet.loops then return math.max(LIFETIME, total) end
  return total
end

function Gen3MoveAnim.new(data)
  local gfx = data and data.constants and data.constants.gen3BattleAnimGfx
  if type(gfx) ~= "table" then return nil end
  return setmetatable({ data = data, gfx = gfx, frame = 0 }, Gen3MoveAnim)
end

-- Does this move have anything to draw?  Asked before the player is started,
-- so a move with no particles falls through to the single-sound path exactly
-- as it did before.
function Gen3MoveAnim:has(moveId)
  local anim = self.data and self.data.moves and self.data.moves[moveId]
                 and self.data.moves[moveId].anim
  if not anim then return false end
  if type(anim.events) == "table" and #anim.events > 0 then return true end
  if type(anim.shakes) == "table" and #anim.shakes > 0 then return true end
  if type(anim.blends) == "table" and #anim.blends > 0 then return true end
  -- ...AND THE MOVES WHOSE WHOLE ANIMATION IS ONE TASK.  DOUBLE TEAM has no
  -- particle, no shake and no blend -- it splits the Pokemon in two -- and
  -- SURF has none either, because its wave is a background layer.  Without
  -- this both were read as "nothing to draw" and fell through to the bare
  -- sound, which is what they did before either was decoded.
  return anim.afterimage ~= nil or anim.surf ~= nil
         or anim.scale ~= nil or anim.flourish ~= nil or anim.rotate ~= nil
         or anim.affine ~= nil
end

-- WHEN A MOVE SPAWNS THE SAME PARTICLE TWICE IN THE SAME PLACE.
--
-- FIRE BLAST puts five flames on the target at frame zero, all at the same
-- offset; HYDRO PUMP four.  On the cartridge the task that spawns them fans
-- them out, and that task is the part that cannot be read -- so drawn where
-- the script says, five flames are one flame.  Identical spawns are placed
-- around a small ring instead, in the order the script makes them.
--
-- THIS IS PRESENTATION, not a reading, and it is deliberately the only one:
-- it moves nothing that the script itself placed, and a move whose particles
-- already have distinct offsets -- PETAL DANCE, THUNDER, SWIFT -- is drawn
-- exactly where it says.
local RING = 14

-- ---------------------------------------------------------------------------
-- THE MON THAT FLINCHES.
--
-- The other half of a Gen 3 move animation is `createvisualtask`, and the C
-- functions those name are the part a retail dump cannot identify -- so no
-- Pokemon in Hoenn ever moved when it was hit.  One of those functions can be
-- had without a name: 157 task calls across 111 moves share one argument
-- shape, held for every call the five functions concerned make (see the
-- import's shake pass), and it is AnimTask_ShakeMon's -- a battler, a pixel
-- offset, a count and a delay.
--
-- HOW LONG IT SWINGS FOR, and the one number here that is a reading rather
-- than a value.  The task's setup writes the offset onto the sprite BEFORE
-- its step function ever runs, so the mon is displaced on the frame the task
-- starts rather than a delay later -- which is also what makes a flinch land
-- on the frame the hit does.  Its step then toggles between the offset and
-- home every `delay + 1` frames, and `count` is spent one per TOGGLE.
--
-- Counting it per out-and-back instead would double every one of these, and
-- the cartridge's own numbers say not to: PSYCHO BOOST asks for 240 and MIST
-- BALL for 70, which at two frames a swing is four seconds of juddering and
-- at one is two.  The scripts' own delay totals agree with the shorter
-- reading as far as they go -- they are a floor rather than a measure, since
-- a script that ends in `waitforvisualfinish` states no delay at all.
local function shakeSpan(shake)
  -- A TRACK IS A LIST OF OFFSETS, one a frame, on either axis or both.
  --
  -- Two families of task write one: nine moves LEAN the Pokemon on a sine
  -- (MON_SWAY) and four LUNGE it across the field and back with a hop
  -- (MON_LUNGE).  Both are walked at import with the cartridge's own integer
  -- arithmetic rather than left to be recomputed here in floating point --
  -- the shifts are arithmetic, so they floor, and floored is not what a
  -- double would give.  To everything below this line they are the same thing
  -- as the square-wave judder: a number a frame on the sprite's own pos2.
  if shake.xs or shake.ys then
    return math.max(shake.xs and #shake.xs or 0, shake.ys and #shake.ys or 0)
  end
  return (shake.count or 1) * ((shake.delay or 0) + 1)
end

-- Where a shake has pushed its battler `age` frames in, or nil once it is
-- over.  Frame zero is DISPLACED, for the reason above.
local function shakeAt(shake, age)
  if age < 0 or age >= shakeSpan(shake) then return nil end
  if shake.xs or shake.ys then
    return (shake.xs and shake.xs[age + 1]) or 0,
           (shake.ys and shake.ys[age + 1]) or 0
  end
  local half = (shake.delay or 0) + 1
  if math.floor(age / half) % 2 == 1 then return 0, 0 end
  return shake.x or 0, shake.y or 0
end
Gen3MoveAnim.shakeSpan = shakeSpan

-- ...AND THE MON THAT GLOWS.
--
-- BlendPalettes lerps a palette toward a colour by a coefficient out of
-- sixteen, and the task that cycles it ramps that coefficient from `from` to
-- `to` one step per `step` frames, then back, `cycles` times.  Everything but
-- the ramp's shape is in the script.
local BLEND_FULL = 16

local function blendLife(b)
  local span = math.abs((b.to or 0) - (b.from or 0))
  -- a one-way ramp arrives and STAYS -- the white flash on an impact is done
  -- by ramping up and then, a few frames later, by a second call ramping back
  -- down -- so the import measured how long it stands before that one starts
  if b.oneWay then
    local ramp = span * (b.step or 1)
    return math.max(1, b.hold or ramp), span
  end
  -- a call whose coefficients are equal sets the blend and stops; same rule
  if span == 0 then return math.max(1, b.hold or 1), 0 end
  return (b.cycles or 1) * 2 * span * (b.step or 1), span
end

-- The blend coefficient, 0..1, `age` frames in -- or nil once it is over.
local function blendAt(b, age)
  local life, span = blendLife(b)
  if age < 0 or age >= life then return nil end
  local level = b.from or 0
  if b.oneWay then
    local up = math.min(span, math.floor(age / (b.step or 1)))
    level = (b.from or 0) + up * (((b.to or 0) > (b.from or 0)) and 1 or -1)
  elseif span > 0 then
    local phase = math.floor(age / (b.step or 1)) % (2 * span)
    local up = (phase <= span) and phase or (2 * span - phase)
    level = (b.from or 0) + up * (((b.to or 0) > (b.from or 0)) and 1 or -1)
  end
  if level < 0 then level = 0 end
  if level > BLEND_FULL then level = BLEND_FULL end
  return level / BLEND_FULL
end

-- 15-bit BGR, which is what the cartridge's palettes are made of
local function blendColour(value)
  value = tonumber(value) or 0
  return (value % 32) / 31,
         (math.floor(value / 32) % 32) / 31,
         (math.floor(value / 1024) % 32) / 31
end
Gen3MoveAnim.blendLife = blendLife
Gen3MoveAnim.blendColour = blendColour

function Gen3MoveAnim:start(moveId, attackerIsPlayer)
  if not self:has(moveId) then return false end
  local anim = self.data.moves[moveId].anim
  self.events = anim.events or {}
  self.shakes = anim.shakes
  self.blends = anim.blends
  self.afterimage = anim.afterimage
  self.orbit = anim.orbit
  self.surf = anim.surf
  self.scale = anim.scale
  self.flourish = anim.flourish
  self.rotate = anim.rotate
  self.affine = anim.affine
  self.attackerIsPlayer = attackerIsPlayer and true or false
  self.frame = 0

  local counts, order = {}, {}
  for _, e in ipairs(self.events) do
    local key = ("%d:%s:%d:%d:%s"):format(e.at or 0, tostring(e.sheet),
                                          e.x or 0, e.y or 0,
                                          tostring(e.target))
    if e.motion ~= "orbit" then
      counts[key] = (counts[key] or 0) + 1
      order[e] = counts[key]
    end
  end
  self.fan = {}
  for _, e in ipairs(self.events) do
    local key = ("%d:%s:%d:%d:%s"):format(e.at or 0, tostring(e.sheet),
                                          e.x or 0, e.y or 0,
                                          tostring(e.target))
    local n = counts[key]
    if n and n > 1 and e.motion ~= "orbit" then
      local angle = 2 * math.pi * (order[e] - 1) / n
      self.fan[e] = { math.floor(math.cos(angle) * RING + 0.5),
                      math.floor(math.sin(angle) * RING + 0.5) }
    end
  end

  -- the animation runs until its last particle has finished its own picture,
  -- or until the script's own delays run out, whichever is later
  local last = 0
  for _, e in ipairs(self.events) do
    local ends = (e.at or 0) + self:eventLife(e, self.gfx[e.sheet])
    if ends > last then last = ends end
  end
  for _, shake in ipairs(self.shakes or {}) do
    local ends = (shake.at or 0) + shakeSpan(shake)
    if ends > last then last = ends end
  end
  for _, blend in ipairs(self.blends or {}) do
    local ends = (blend.at or 0) + blendLife(blend)
    if ends > last then last = ends end
  end
  self.total = math.max(anim.duration or 0, last) + TAIL
  return true
end

function Gen3MoveAnim:update()
  self.frame = (self.frame or 0) + 1
end

function Gen3MoveAnim:isDone()
  if not (self.events or self.shakes or self.blends) then return true end
  return (self.frame or 0) >= (self.total or 0)
end

function Gen3MoveAnim:release()
  self.events, self.total, self.frame, self.fan = nil, nil, 0, nil
  self.shakes, self.blends = nil, nil
  self.orbit, self.surf, self.scale = nil, nil, nil
  self.flourish, self.rotate, self.affine = nil, nil, nil
end

-- What colour this frame has washed one side's Pokemon, and how far.  Like
-- the shake, this belongs to the MON rather than to a particle laid over it:
-- the task writes the battler's own palette.
-- ---------------------------------------------------------------------------
-- THE GHOSTS
--
-- Reported from play: "double team doesnt show the pokemon shift back and
-- forth".  DOUBLE TEAM spawns no particles at all -- its whole animation is
-- one `createvisualtask` -- so there was nothing to draw and nothing drew.
--
-- The import reads that one task (RomExtractorGen3:animAfterimage) and hands
-- over the cartridge's own numbers; this is the same arithmetic, in the same
-- order, with the ROM's own sine table:
--
--     one STEP every framesPerStep frames, steps of them and then it is over
--     radius = sine[step] / radiusDiv          -- grows as the arc widens
--     angle += sine[step] / angleDiv           -- wrapped into the table
--     x      = sine[angle] * radius / 256      -- Sin(angle, radius)
--
-- Two copies, starting phaseStep apart, so they swing in opposite directions.
-- Only x is written, which is why this is a sideways shimmer and not an orbit.
local GHOST_ALPHA = 0.5
local SINE_SCALE = 256

-- integer division that truncates toward zero, which is what the cartridge's
-- __divsi3 does -- Lua's // floors, and the two differ on the negative half
-- of the sine where this spends half its time
local function idiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or -math.floor(-q)
end

function Gen3MoveAnim:monGhosts(isPlayerSide)
  local shape = self.afterimage
  if not shape then return nil end
  -- the attacker is the one that splits: the task asks for
  -- GetAnimBattlerSpriteId(ANIM_ATTACKER) and nothing else
  if isPlayerSide ~= self.attackerIsPlayer then return nil end
  local sine = shape.sine
  if type(sine) ~= "table" then return nil end
  local perStep = shape.framesPerStep or 2
  local step = math.floor((self.frame or 0) / perStep)
  if step > (shape.steps or 64) then return nil end

  local out = {}
  for copy = 0, (shape.copies or 2) - 1 do
    -- the angle is an accumulation, so it has to be walked rather than
    -- solved: each step adds sine[thatStep]/angleDiv to what came before
    local angle = (copy * (shape.phaseStep or 128)) % 256
    for t = 0, step do
      angle = (angle + idiv(sine[t] or 0, shape.angleDiv or 13)) % 256
    end
    local radius = idiv(sine[step] or 0, shape.radiusDiv or 6)
    local x = idiv((sine[angle] or 0) * radius, SINE_SCALE)
    out[#out + 1] = { x = x, alpha = GHOST_ALPHA }
  end
  return out
end

function Gen3MoveAnim:monTint(isPlayerSide)
  if not self.blends then return nil end
  local now = self.frame or 0
  local best, r, g, b
  for _, blend in ipairs(self.blends) do
    local onPlayer
    -- A CALL CAN NAME A SIDE INSTEAD OF A ROLE.  The five-argument blend's
    -- top selector bits are battle POSITIONS, not attacker-and-target, so a
    -- record made from them says which side of the field it is on and whose
    -- turn it is does not enter into it.  HAZE is the move that does this.
    if blend.side then
      onPlayer = blend.side == "player"
    elseif blend.target then
      onPlayer = not self.attackerIsPlayer
    else
      onPlayer = self.attackerIsPlayer
    end
    if onPlayer == (isPlayerSide and true or false) then
      local c = blendAt(blend, now - (blend.at or 0))
      if c and c > 0 and (not best or c > best) then
        best = c
        r, g, b = blendColour(blend.colour)
      end
    end
  end
  if not best then return nil end
  return r, g, b, best
end

-- How far this frame has pushed one side's Pokemon out of its place.  Asked
-- by the battle's own draw, so the shake moves the MON rather than a copy of
-- it -- which is what the cartridge does too: the task writes the sprite's
-- own x2/y2.
function Gen3MoveAnim:monOffset(isPlayerSide)
  if not self.shakes then return 0, 0 end
  local now = self.frame or 0
  local dx, dy = 0, 0
  for _, shake in ipairs(self.shakes) do
    local onPlayer
    if shake.target then
      onPlayer = not self.attackerIsPlayer
    else
      onPlayer = self.attackerIsPlayer
    end
    if onPlayer == (isPlayerSide and true or false) then
      local ox, oy = shakeAt(shake, now - (shake.at or 0))
      -- THE STRONGEST PUSH WINS; they do not add up.  EXPLOSION shakes five
      -- battlers at once because a Gen 3 field can hold four, and a port that
      -- draws one Pokemon a side would otherwise throw its own mon three
      -- times as far off the platform as the cartridge does.
      if ox and math.abs(ox) + math.abs(oy) > math.abs(dx) + math.abs(dy) then
        -- WHICH SIDE THE NUMBER WAS WRITTEN FOR.
        --
        -- The default is the mirror the particles take: an offset authored
        -- from the far side of the field reads backwards on your own
        -- Pokemon.  But the tasks that push the battler NEGATE their own
        -- argument when the attacker is not on the player's side -- the
        -- run-up, the sway and the lunge all do -- which says the number in
        -- the script is already the player's.  Mirroring that one too would
        -- have TACKLE run backwards away from the foe, which is the shape of
        -- the whole animation reversed rather than a pixel out of place.
        if shake.authoredForPlayer then
          dx = onPlayer and ox or -ox
        else
          dx = onPlayer and -ox or ox
        end
        dy = oy
      end
    end
  end
  return dx, dy
end

-- Which battler an event is drawn over: the script names attacker or target,
-- and which SIDE that is depends on whose turn it is.
function Gen3MoveAnim:battlerFor(battle, event)
  local playerSide
  if event.target then
    playerSide = not self.attackerIsPlayer
  else
    playerSide = self.attackerIsPlayer
  end
  return playerSide and battle.player or battle.enemy, playerSide
end

-- ---------------------------------------------------------------------------
-- THE PARTICLES THAT FLY
--
-- Reported from play: "surf isnt showing the wave going through and hitting
-- the enemy pokemon ... i think many more are missing/not working properly".
-- The header above used to say a particle's path was unknowable, and for the
-- four hundred move-specific callbacks it still is.  It is not unknowable for
-- the handful they SHARE, and the import now reads those (see
-- RomExtractorGen3:animMotionOf): a particle whose callback moves it to the
-- attacker and then hands it to StartAnimLinearTranslation crosses the field.
--
-- 288 of Hoenn's 1657 particles do exactly that -- EMBER's flames, ICE BEAM's
-- beam, every projectile in the game -- and they were all sitting still on the
-- Pokemon they were thrown at.
--
-- HOW LONG THE CROSSING TAKES is the fifth operand of createsprite where the
-- script passes five (`sprite->data[0] = gBattleAnimArgs[4]`), which is 152 of
-- them; the rest cross over their own visible life, because that is the only
-- other number that is theirs.
--
-- Everything else keeps drawing exactly where it drew before: a particle with
-- no motion this port can name does not get an invented one.
-- ---------------------------------------------------------------------------
-- THE POKEMON THAT SQUASHES
--
-- SPLASH, MEDITATE and TELEPORT hand their battler to one shared routine with
-- a POINTER TO A TABLE, and the table is the animation: a run of
-- { xScale, yScale, rotation, duration } records whose scales are DELTAS PER
-- FRAME.  The import reads it whole (RomExtractorGen3:affineTable); this
-- walks it.
--
-- GBA affine scale is a divisor, so the cartridge's number going UP is the
-- Pokemon getting SMALLER on that axis.  What comes out of here is the pair
-- of multipliers a renderer wants.
function Gen3MoveAnim:monAffine(isPlayerSide)
  local shape = self.affine
  if not shape then return nil end
  -- WHOSE POKEMON THIS IS.
  --
  -- The shapes that come out of an affine TABLE are the attacker's -- SPLASH
  -- squashes the Pokemon that splashed, and those tasks ask for
  -- GetAnimBattlerSpriteId(ANIM_ATTACKER) and nothing else.  The shape the
  -- fourteen PULSE moves carry is not: their task takes a battler as its
  -- fourth argument, and BIND's and WRAP's name the Pokemon being WRAPPED.
  -- Squeezing the wrong one is not a smaller mistake than not squeezing at
  -- all -- it is the attacker being crushed by its own move.
  local wants = self.attackerIsPlayer and true or false
  if shape.onTarget then wants = not wants end
  if (isPlayerSide and true or false) ~= wants then return nil end
  local steps = shape.steps
  if type(steps) ~= "table" or #steps == 0 then return nil end
  local one = 0
  for _, st in ipairs(steps) do one = one + (st.dur or 0) end
  if one <= 0 then return nil end
  local frame = self.frame or 0
  local repeats = math.max(1, shape.repeats or 1)
  if frame < 0 or frame >= one * repeats then return nil end
  -- ...and inside one pass of it: the scales accumulate step by step
  local t = frame % one
  local base = shape.base or 256
  local sx, sy, rot = base, base, 0
  for _, st in ipairs(steps) do
    local held = math.min(t, st.dur or 0)
    sx = sx + (st.dx or 0) * held
    sy = sy + (st.dy or 0) * held
    rot = rot + (st.rot or 0) * held
    t = t - held
    if t <= 0 then break end
  end
  if sx < 1 then sx = 1 end
  if sy < 1 then sy = 1 end
  return base / sx, base / sy, rot
end

-- ---------------------------------------------------------------------------
-- THE POKEMON THAT TIPS
--
-- WITHDRAW is the other half of the pair MINIMIZE opened: the same helper,
-- but the rotation argument.  The import reads the task's three states whole
-- (RomExtractorGen3:monRotate); this walks them.
--
-- What comes back is RADIANS and a rise in pixels, because that is what a
-- renderer wants.  The cartridge counts a whole turn as 65536.
function Gen3MoveAnim:monRotate(isPlayerSide)
  local shape = self.rotate
  if not shape then return nil end
  local mine = (isPlayerSide and true or false)
  local attacker = (self.attackerIsPlayer and true or false)
  -- the task asks for the attacker's own sprite and nothing else
  if mine ~= attacker then return nil end
  local frame = self.frame or 0
  if frame < 0 or frame >= (shape.life or 74) then return nil end
  local climb = shape.frames or 22
  local hold = shape.hold or 30
  local steps
  if frame < climb then
    steps = frame
  elseif frame < climb + hold then
    steps = climb
  else
    steps = climb - (frame - climb - hold)
  end
  if steps <= 0 then return nil end
  local angle = steps * (shape.step or 176)
  -- ...AND IT TIPS AWAY FROM WHOEVER IS WATCHING.  The step negates the angle
  -- when the attacker is on the near side, which is the one line here that is
  -- about sides rather than numbers.
  if attacker then angle = -angle end
  local turn = shape.turn or 65536
  return angle / turn * 2 * math.pi, steps * (shape.rise or 1)
end

-- ---------------------------------------------------------------------------
-- THE FLOURISH A STAT-UP MOVE MAKES
--
-- HARDEN, IRON DEFENSE and four more used to flash the WHOLE SCREEN white for
-- a fixed sixteen frames, which was this port's invention.  The cartridge
-- draws a sparse white sparkle centred on the Pokemon whose stat went up,
-- drifts it four pixels a frame for three laps of 128, and blends it at eight
-- sixteenths.  The import reads all of that (RomExtractorGen3:statFlourish);
-- this is where it is on any given frame.
function Gen3MoveAnim:flourishLayer(isPlayerSide)
  local shape = self.flourish
  if not shape then return nil end
  -- the task asks for GetAnimBattlerSpriteId(ANIM_ATTACKER) and centres the
  -- layer on it, so it belongs to one side and not the other
  if (isPlayerSide and true or false)
     ~= (self.attackerIsPlayer and true or false) then
    return nil
  end
  local frame = self.frame or 0
  if frame < 0 or frame >= (shape.life or 96) then return nil end
  local drift = shape.drift or 4
  local lap = shape.lap or 128
  -- BG1_X falls by `drift` a frame and is put back by the wrap, so what is on
  -- screen is the drift taken modulo one lap
  return { image = shape.image,
           x = -((frame * drift) % lap),
           centreX = shape.centreX or 96, centreY = shape.centreY or 32,
           alpha = shape.alpha or 0.5,
           width = shape.width or 256, height = shape.height or 256 }
end

-- ---------------------------------------------------------------------------
-- THE POKEMON THAT SHRINKS
--
-- MINIMIZE drew a screen flash, because its whole animation is one task and
-- what that task does -- scale the attacker's own sprite -- is a thing this
-- port could not do.  The import reads the task's state machine whole (see
-- RomExtractorGen3:monScale); this walks it.
--
-- GBA affine scale is a DIVISOR: the matrix maps screen back to texture, so
-- the cartridge's number going UP is the Pokemon getting smaller.  What comes
-- out of here is the multiplier a renderer wants, which is 256 over it.
function Gen3MoveAnim:monScale(isPlayerSide)
  local shape = self.scale
  if not shape then return nil end
  -- only the attacker: the task asks for GetAnimBattlerSpriteId(ANIM_ATTACKER)
  -- and nothing else
  if (isPlayerSide and true or false) ~= (self.attackerIsPlayer and true or false) then
    return nil
  end
  local frame = self.frame or 0
  if frame < 0 then return nil end
  local base = shape.base or 256
  local shrinkFrames = shape.shrinkFrames or 32
  local rounds = math.max(1, shape.rounds or 3)
  -- each round is the shrink plus the two frames its two state changes cost,
  -- except the last, which goes straight on to the hold
  local roundLen = shrinkFrames + 2
  local scale = base
  local t = frame
  for round = 1, rounds do
    local len = (round < rounds) and roundLen or (shrinkFrames + 1)
    if t < len then
      local step = math.min(t, shrinkFrames)
      return base / (base + step * (shape.shrinkStep or 40))
    end
    t = t - len
  end
  if t < (shape.holdFrames or 33) then
    return base / (base + shrinkFrames * (shape.shrinkStep or 40))
  end
  t = t - (shape.holdFrames or 33)
  if t < (shape.growFrames or 16) then
    scale = base + shrinkFrames * (shape.shrinkStep or 40)
            - t * (shape.growStep or 80)
    if scale < base then scale = base end
    return base / scale
  end
  return nil                      -- state 5: the scale is put back and it ends
end

-- ---------------------------------------------------------------------------
-- THE WAVE THAT CROSSES THE FIELD
--
-- Reported from play: "surf isnt showing the wave going through and hitting
-- the enemy pokemon".  SURF spawns no particles at all -- its wave is a
-- background layer, and the import composes it out of the cartridge's own
-- tiles, tilemap and palette (RomExtractorGen3:surfWave).
--
-- This is the scroll, which is two additions a frame, and the alpha, which
-- ramps in double-frames.  The layer WRAPS, exactly as the hardware's does:
-- the screen shows map pixel ((x + sx) mod 512, (y + sy) mod 256), so the
-- picture is drawn at -(x mod 512) and repeated.
--
-- The cartridge also shears the wave row by row through an HBlank scanline
-- table.  This renderer has no scanline hook and the layer is drawn flat --
-- the wave crosses the field at the right speed, in the right direction and
-- with the right blend, but it does not ripple.
function Gen3MoveAnim:surfLayer()
  local shape = self.surf
  if not shape then return nil end
  local frame = self.frame or 0
  if frame < 0 or frame >= (shape.life or 134) then return nil end
  -- the task's two arms: which one is chosen is GetBattlerSide(attacker)
  local side = self.attackerIsPlayer and shape.player or shape.opponent
  if not (side and side.image) then return nil end
  local half = math.floor(frame / (shape.step or 2))
  local fade, hold = shape.fade or 13, shape.hold or 54
  local blend = half
  if half > hold then blend = fade - (half - hold)
  elseif half > fade then blend = fade end
  if blend <= 0 then return nil end
  return { image = side.image,
           x = (side.x or 0) + (side.dx or 0) * frame,
           y = (side.y or 0) + (side.dy or 0) * frame,
           alpha = blend / (shape.blendOf or 16),
           width = shape.width or 512, height = shape.height or 256 }
end

-- ---------------------------------------------------------------------------
-- THE NOTES THAT CIRCLE THE SCREEN
--
-- Reported from play: "perish song the symbols arent moving properly".  The
-- import reads the note callback's arithmetic whole (see
-- RomExtractorGen3:animOrbit); this is that arithmetic, in the same order and
-- with the same rounding.
--
-- Two things about it are unlike every other particle here.  It is drawn in
-- SCREEN coordinates -- the callback writes pos1 = (120, index / 2 - 15) and
-- never asks where a battler is -- and its three createsprite arguments are
-- not offsets but the note's number, its picture and its phase.
--
-- Cos and Sin are the cartridge's: one lookup in gSineTable, one multiply and
-- an arithmetic shift right by eight.  Lua's math.floor and an arithmetic
-- shift round the same way on both halves of the sine, so this agrees exactly
-- -- which the `//`-versus-__divsi3 trouble elsewhere in this port is the
-- reason to say out loud.
local function sineOf(shape, index, amplitude)
  local sine = shape and shape.sine
  if type(sine) ~= "table" then return 0 end
  local v = sine[index % 256]
  if not v then return 0 end
  return math.floor(v * amplitude / 256)
end
Gen3MoveAnim.sineOf = sineOf

-- Where this note is, `age` frames after it appeared, or nil once it is gone.
-- The cartridge's data[0] opens at ONE: the first update takes the
-- first-frame branch and then increments before any of the arithmetic runs.
function Gen3MoveAnim:orbitAt(event, age)
  local shape = self.orbit
  local o = event and event.orbit
  if not (shape and o and age and age >= 0) then return nil end
  local step = age + 1
  if step > (shape.life or 120) then return nil end
  local quarter = shape.quarter or 64
  local fall = shape.fallDiv or 2
  local angle = step * (shape.angleMul or 3) + (o.phase or 0)
  local wobble = step * (shape.wobbleStep or 10)
  local x = (shape.centreX or 120)
            + sineOf(shape, angle + quarter, shape.ampX or 100)
  local y = math.floor((o.index or 0) / fall) + (shape.top or -15)
            + sineOf(shape, angle, shape.ampY or 10)
            + sineOf(shape, wobble + quarter, shape.ampW or 4)
            + math.floor(step / fall)
  return x, y
end

-- How long a particle is up for.  A note outlives its own picture -- the
-- picture is one still image and the callback is what ends it -- so the
-- callback's own count is what says when it goes.
function Gen3MoveAnim:eventLife(event, sheet)
  if event and event.motion == "orbit" and self.orbit then
    return (self.orbit.life or 120) + 1
  end
  return lifeOf(sheet)
end

local function travelFraction(event, age, life)
  if event.motion ~= "linear" or event.from ~= "attacker" then return nil end
  local span = event.travel or life
  if not span or span <= 0 then return nil end
  if age >= span then return 1 end
  return age / span
end
Gen3MoveAnim.travelFraction = travelFraction

function Gen3MoveAnim:draw(battle)
  if not self.events or not battle then return end
  local okG3, Gen3Battle = pcall(require, "src.battle.Gen3Battle")
  local okA, Assets = pcall(require, "src.render.Assets")
  if not (okG3 and okA) then return end
  local g = love.graphics
  local now = self.frame or 0

  -- the wave first, and over everything: the cartridge gives its layer
  -- priority 1 and the battlers' sprites priority 2, so it passes in FRONT of
  -- the Pokemon it is breaking over
  local layer = self:surfLayer()
  if layer then
    local okImg, img = pcall(Assets.image, layer.image)
    if okImg and img and img.getWidth then
      local bottom = Gen3Battle.FIELD_BOTTOM or Gen3Battle.HEIGHT or 160
      local right = Gen3Battle.WIDTH or 240
      g.setScissor(0, 0, right, bottom)
      g.setColor(1, 1, 1, layer.alpha)
      local ox = -(layer.x % layer.width)
      local oy = -(layer.y % layer.height)
      for tx = ox, right - 1, layer.width do
        for ty = oy, bottom - 1, layer.height do
          g.draw(img, tx, ty)
        end
      end
      g.setColor(1, 1, 1, 1)
      g.setScissor()
    end
  end

  -- ...and the stat-up sparkle, which belongs to ONE Pokemon rather than to
  -- the screen: the cartridge centres its layer on the attacker's own sprite.
  for _, side in ipairs({ true, false }) do
    local flourish = self:flourishLayer(side)
    if flourish then
      local okImg, img = pcall(Assets.image, flourish.image)
      local battler = side and battle.player or battle.enemy
      local cxf, cyf
      if battler and Gen3Battle.battlerCentre then
        cxf, cyf = Gen3Battle.battlerCentre(battle, battler)
      end
      if okImg and img and img.getWidth and cxf and cyf then
        local bottom = Gen3Battle.FIELD_BOTTOM or Gen3Battle.HEIGHT or 160
        local right = Gen3Battle.WIDTH or 240
        g.setScissor(0, 0, right, bottom)
        g.setColor(1, 1, 1, flourish.alpha)
        -- the task writes BG1_X = centreX - pos1.x, which puts the layer's
        -- own centre on the Pokemon; the drift is what moves it after that
        local ox = math.floor(cxf - flourish.centreX + flourish.x)
        local oy = math.floor(cyf - flourish.centreY)
        for tx = ox % flourish.width - flourish.width, right - 1,
                 flourish.width do
          g.draw(img, tx, oy)
        end
        g.setColor(1, 1, 1, 1)
        g.setScissor()
      end
    end
  end

  for _, event in ipairs(self.events) do
    local age = now - (event.at or 0)
    local sheet = self.gfx[event.sheet]
    if age >= 0 and sheet and age < self:eventLife(event, sheet) then
      local battler, playerSide = self:battlerFor(battle, event)
      local centreX, centreY
      if battler and Gen3Battle.battlerCentre then
        centreX, centreY = Gen3Battle.battlerCentre(battle, battler)
      end
      -- ...and if this one crosses the field, it starts at the OTHER
      -- Pokemon and arrives here.  `battler` is already the end of the
      -- journey -- every particle spawns on the target -- so the only thing
      -- needed is where it set off from.
      -- a note is not laid over anybody: it is at a place on the screen
      local orbitX, orbitY = self:orbitAt(event, age)
      if orbitX then centreX, centreY = orbitX, orbitY end
      local t = not orbitX and travelFraction(event, age, lifeOf(sheet)) or nil
      if t and centreX and centreY then
        local otherSide = not playerSide
        local other = otherSide and battle.player or battle.enemy
        local fromX, fromY
        if other and Gen3Battle.battlerCentre then
          fromX, fromY = Gen3Battle.battlerCentre(battle, other)
        end
        if fromX and fromY then
          centreX = fromX + (centreX - fromX) * t
          centreY = fromY + (centreY - fromY) * t
        end
      end
      if sheet and centreX and centreY then
        local ok, img = pcall(Assets.image, sheet.image)
        local index = frameAt(sheet, age)
        -- StartSpriteAnim(sprite, args[1]) picks the note's picture, and each
        -- of that template's animations is one still image, so the argument
        -- IS the frame
        if orbitX and event.orbit then
          index = math.min(event.orbit.pic or 0,
                           math.max(1, sheet.frames or 1) - 1)
        end
        if ok and img and img.getWidth and index then
          local fw = sheet.frameWidth or img:getWidth()
          local fh = sheet.frameHeight or img:getHeight()
          -- one Quad per frame of each sheet, kept: a battle draws these
          -- sixty times a second and a fresh Quad every time is pure churn
          self.quads = self.quads or {}
          local key = event.sheet .. ":" .. index
          local quad = self.quads[key]
          if not quad then
            quad = love.graphics.newQuad(0, index * fh, fw, fh,
                                         img:getWidth(), img:getHeight())
            self.quads[key] = quad
          end
          -- the mirror: an offset authored for the far side reads backwards
          -- on your own Pokemon
          local dx = playerSide and -(event.x or 0) or (event.x or 0)
          local dy = event.y or 0
          -- ...and a note's place is already absolute, so it is not mirrored
          -- for the near side and not fanned out with its neighbours
          if orbitX then dx, dy = 0, 0 end
          local fan = not orbitX and self.fan and self.fan[event]
          if fan then dx, dy = dx + fan[1], dy + fan[2] end
          g.setColor(1, 1, 1, 1)
          g.draw(img, quad, math.floor(centreX + dx - fw / 2),
                 math.floor(centreY + dy - fh / 2))
        end
      end
    end
  end
end

return Gen3MoveAnim
