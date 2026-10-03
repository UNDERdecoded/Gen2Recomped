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
local frlgCallbackState
local frlgCallbackLife

-- The image this particle is showing `age` frames after it appeared, and nil
-- once its animation has finished and it is not one of the repeating ones.
local function timelineState(held, loops, frames, age, holdEnded, seekCmd)
  frames = math.max(1, tonumber(frames) or 1)
  if type(held) ~= "table" or #held == 0 then
    return math.floor(age / FRAME_HOLD) % frames, false, false
  end
  local function result(step)
    return math.min(step[1] or 0, frames - 1),
           step[3] and true or false, step[4] and true or false
  end
  age = math.max(0, math.floor(tonumber(age) or 0))
  local total = 0
  for _, step in ipairs(held) do total = total + (step[2] or 1) end
  if total < 1 then return 0, false, false end
  local t = age

  -- SeekSpriteAnim begins at a command index in the current animation.  The
  -- first pass therefore consumes that suffix once; a JUMP(0) animation then
  -- resumes the ordinary loop from command zero rather than looping the
  -- rotated suffix.
  local start = math.max(0, math.floor(tonumber(seekCmd) or 0))
  if start >= #held then start = start % #held end
  if start > 0 then
    local suffixTotal = 0
    for i = start + 1, #held do
      suffixTotal = suffixTotal + (held[i][2] or 1)
    end
    if t < suffixTotal then
      for i = start + 1, #held do
        local step = held[i]
        t = t - (step[2] or 1)
        if t < 0 then return result(step) end
      end
    end
    if not loops then
      if not holdEnded then return nil end
      return result(held[#held])
    end
    t = t - suffixTotal
  end

  if t >= total then
    if not loops then
      if not holdEnded then return nil end
      t = total - 1
    else
      t = t % total
    end
  end
  for _, step in ipairs(held) do
    t = t - (step[2] or 1)
    if t < 0 then return result(step) end
  end
  return result(held[#held])
end

local function frameFromTimeline(held, loops, frames, age, holdEnded)
  return timelineState(held, loops, frames, age, holdEnded)
end

local function frameAt(sheet, age, holdEnded)
  return frameFromTimeline(sheet and sheet.held, sheet and sheet.loops,
                           sheet and sheet.frames, age, holdEnded)
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
  local affines = data and data.constants and data.constants.gen3BattleAnimAffines
  local sine = data and data.constants and data.constants.gen3BattleAnimSine
  return setmetatable({ data = data, gfx = gfx,
                        affines = type(affines) == "table" and affines or {},
                        sine = type(sine) == "table" and sine or nil,
                        frame = 0 }, Gen3MoveAnim)
end

-- Does this move have anything to draw?  Asked before the player is started,
-- so a move with no particles falls through to the single-sound path exactly
-- as it did before.
local function hasVisual(anim)
  if type(anim) ~= "table" then return false end
  if type(anim.events) == "table" and #anim.events > 0 then return true end
  if type(anim.shakes) == "table" and #anim.shakes > 0 then return true end
  if type(anim.blends) == "table" and #anim.blends > 0 then return true end
  if type(anim.backgrounds) == "table" and #anim.backgrounds > 0 then return true end
  if type(anim.scanlines) == "table" and #anim.scanlines > 0 then return true end
  if type(anim.heaves) == "table" and #anim.heaves > 0 then return true end
  if type(anim.voltTackle) == "table" then return true end
  if type(anim.monBgTimeline) == "table" and #anim.monBgTimeline > 0 then return true end
  -- ...AND THE MOVES WHOSE WHOLE ANIMATION IS ONE TASK.  DOUBLE TEAM has no
  -- particle, no shake and no blend -- it splits the Pokemon in two -- and
  -- SURF has none either, because its wave is a background layer.  Without
  -- this both were read as "nothing to draw" and fell through to the bare
  -- sound, which is what they did before either was decoded.
  return anim.afterimage ~= nil or anim.surf ~= nil
         or anim.scale ~= nil or anim.flourish ~= nil or anim.rotate ~= nil
         or (type(anim.rotateTracks) == "table" and #anim.rotateTracks > 0)
         or anim.acidArmor ~= nil or anim.memento ~= nil
         or anim.transform ~= nil or anim.whiteout ~= nil
         or anim.camouflage ~= nil
         or anim.splitFx ~= nil
         or anim.affine ~= nil
         or (type(anim.affineTasks) == "table" and #anim.affineTasks > 0)
end

local function branchMatches(when, ctx)
  if type(when) ~= "table" then return false end
  ctx = ctx or {}
  local turn = tonumber(ctx.moveTurn)
  if when.moveTurn ~= nil and turn ~= tonumber(when.moveTurn) then return false end
  if when.moveTurnOdd and (turn == nil or turn % 2 ~= 1) then return false end
  if when.arg ~= nil then
    local args = ctx.args or {}
    local actual = tonumber(args[when.arg])
    if actual == nil then return false end
    if when.value ~= nil and actual ~= tonumber(when.value) then return false end
    for _, value in ipairs(when.notValues or {}) do
      if actual == tonumber(value) then return false end
    end
  end
  return true
end

function Gen3MoveAnim:recordFor(moveId, ctx)
  local anim = self.data and self.data.moves and self.data.moves[moveId]
                 and self.data.moves[moveId].anim
  if type(anim) ~= "table" then return nil end
  for _, variant in ipairs(anim.variants or {}) do
    if branchMatches(variant.when, ctx) and type(variant.anim) == "table" then
      return variant.anim
    end
  end
  return anim
end

function Gen3MoveAnim:has(moveId, ctx)
  return hasVisual(self:recordFor(moveId, ctx))
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

local function partnerPosition(pos)
  pos = tonumber(pos)
  if pos == nil then return nil end
  return pos < 2 and pos + 2 or pos - 2
end

-- FireRed's battle_anim_mons.c gives the four battler positions fixed OBJ
-- subpriorities.  Cmd_createsprite adds its signed script offset to either the
-- attacker's or the target's value and clamps the result to at least 3.  OAM
-- priority is then the high byte of sprite.c's sort key, so it dominates this
-- subpriority when two OBJ overlap.
local BATTLER_SUBPRIORITY = {
  [0] = 30, -- B_POSITION_PLAYER_LEFT
  [1] = 40, -- B_POSITION_OPPONENT_LEFT
  [2] = 20, -- B_POSITION_PLAYER_RIGHT
  [3] = 50, -- B_POSITION_OPPONENT_RIGHT
}

function Gen3MoveAnim:eventSubpriority(event)
  if type(event) ~= "table" then return nil end
  if tonumber(event.subpriority) ~= nil then
    return math.max(3, tonumber(event.subpriority))
  end
  if event.subpriorityBase ~= "attacker" and event.subpriorityBase ~= "target" then
    return nil
  end
  local position = event.subpriorityBase == "target"
                   and self.targetPosition or self.attackerPosition
  local base = BATTLER_SUBPRIORITY[tonumber(position)]
  if base == nil then return nil end
  local value = base + (tonumber(event.subpriorityOffset) or 0)
  if value < 3 then value = 3 end
  return value
end

function Gen3MoveAnim:eventPriorityKey(event, battle)
  local callbackState
  if event and event.motion == "frlg_callback" and battle then
    local age = (self.frame or 0) - (event.at or 0)
    if age >= 0 then callbackState = self:frlgCallbackState(event, age, battle) end
  elseif event and battle then
    local age = (self.frame or 0) - (event.at or 0)
    if age >= 0 then callbackState = self:splitSpriteState(event, age, battle) end
  end
  local sub = callbackState and callbackState.subpriority
              or self:eventSubpriority(event)
  if sub == nil then return nil end
  local priority = callbackState and tonumber(callbackState.priority)
                   or tonumber(event.priority) or 0
  local dynamic = event.dynamicBgPriority
  if dynamic and battle then
    local refTarget = tonumber(dynamic.reference) ~= 0
    local battler = self:battlerForRole(battle, refTarget, refTarget and 1 or 0)
    if battler then
      priority = self:copiedBgPriority(battle, battler)
      local mode = tonumber(dynamic.mode) or 0
      if mode == 1 or mode == 3 then priority = priority + 1 end
    end
  end
  priority = math.max(0, math.min(3, priority))
  return priority * 256 + sub
end

-- sprite.c sorts lower (oam.priority<<8 | subpriority) keys toward lower OAM
-- indices, which are in front of higher indices.  Equal keys are sorted every
-- frame by the sprite's LIVE OAM Y, with larger screen Y in front.  Exact key+Y
-- ties do not run a new sprite-slot comparison: SortSprites is stable, so the
-- previous gSpriteOrder survives.  We keep that previous hardware rank here.
--
-- LOVE composes in the other direction (later draw wins), so each sortable run
-- is first put in cartridge front-to-back order, its stable ranks are updated,
-- and then emitted in reverse.  Events synthesized by task/helper decoders have
-- no createsprite command/OAM key; they remain barriers because their hardware
-- position cannot be derived from the command stream.
function Gen3MoveAnim:eventsForDraw(battle, Gen3Battle)
  local ordered = {}
  local run = {}
  local ranks = self.oamRanks or {}
  local rankBase = 0
  self.oamGlobalTieResidual = nil
  local function flush()
    if #run == 0 then return end
    for i = 1, #run - 1 do
      for j = i + 1, #run do
        if run[i].key == run[j].key and run[i].oamY ~= nil
           and run[i].oamY == run[j].oamY then
          self.oamGlobalTieResidual = "global-sprite-slot-history"
          break
        end
      end
      if self.oamGlobalTieResidual then break end
    end
    table.sort(run, function(a, b)
      if a.key ~= b.key then return a.key < b.key end
      if a.oamY ~= nil and b.oamY ~= nil and a.oamY ~= b.oamY then
        return a.oamY > b.oamY
      end
      local ar = ranks[a.event] or a.index
      local br = ranks[b.event] or b.index
      if ar ~= br then return ar < br end
      return a.index < b.index
    end)
    for i, item in ipairs(run) do
      ranks[item.event] = rankBase + i
    end
    rankBase = rankBase + #run
    for i = #run, 1, -1 do ordered[#ordered + 1] = run[i] end
    run = {}
  end
  for i, event in ipairs(self.events or {}) do
    local sheet = self.gfx[event.sheet]
    local age = (self.frame or 0) - (event.at or 0)
    local active = not battle or (age >= 0 and sheet
                   and age < self:eventLife(event, sheet))
    if active then
      local key = self:eventPriorityKey(event, battle)
      local oamY = battle and key and self.eventOamY
                   and self:eventOamY(event, battle, Gen3Battle) or nil
      local item = { event = event, index = i, key = key, oamY = oamY }
      if item.key == nil or (battle and item.oamY == nil) then
        flush()
        ordered[#ordered + 1] = item
        rankBase = rankBase + 1
      else
        run[#run + 1] = item
      end
    elseif not battle then
      local item = { event = event, index = i, key = self:eventPriorityKey(event, battle) }
      if item.key == nil then
        flush()
        ordered[#ordered + 1] = item
        rankBase = rankBase + 1
      else
        run[#run + 1] = item
      end
    end
  end
  flush()
  self.oamRanks = ranks
  return ordered
end

-- Arithmetic right shift, matching ARM's signed ASR.  Lua's division is a
-- float and truncating it toward zero is wrong for the negative half of the
-- sine table; ASR rounds those values down toward -infinity.
local function ashr(value, bits)
  return math.floor((tonumber(value) or 0) / (2 ^ (bits or 0)))
end

local function truncDiv(a, b)
  a, b = tonumber(a) or 0, tonumber(b) or 1
  if b == 0 then return 0 end
  local q = math.abs(a) / math.abs(b)
  q = math.floor(q)
  return (a < 0) ~= (b < 0) and -q or q
end

local function scanSine(self, index)
  local sine = self.sine
  if type(sine) ~= "table" then return 0 end
  index = tonumber(index) or 0
  local value = sine[index]
  if value ~= nil then return value end
  -- gSineTable itself is 320 entries.  No authorised scanline task uses a
  -- negative index; the fallback is only for data sets that kept the older
  -- 256-entry extraction rather than the full retail table.
  value = sine[index % 256]
  return tonumber(value) or 0
end

-- The scanline tasks use sBattlerCoords directly, not the rendered image's
-- opaque centre.  Reconstruct the exact native 240x160 y coordinate from the
-- cartridge table already extracted for Gen3Battle, then apply the opponent's
-- species elevation exactly as GetBattlerYCoordWithElevation does.
function Gen3MoveAnim:battlerScanlineY(battle, battler)
  if not battler then return nil end
  local constants = self.data and self.data.constants or {}
  local coords = constants.gen3BattlerCoords
  local double = false
  if battle and battle.isDouble then
    local ok, yes = pcall(battle.isDouble, battle)
    double = ok and yes and true or false
  end
  local row = coords and (double and coords.doubles or coords.singles)
  local pos = tonumber(battler.position)
              or (battler.isPlayer and 0 or 1)
  local point = row and row[pos + 1]
  local y = point and tonumber(point.y)
  if y == nil then return nil end
  if not battler.isPlayer then
    local species = battler.species or (battler.mon and battler.mon.species)
    local elevation = species and constants.gen3Elevation
                      and constants.gen3Elevation[species] or 0
    y = y - (tonumber(elevation) or 0)
  end
  return y
end

function Gen3MoveAnim:battlerCoordHeight(battler)
  local species = battler and (battler.species
                    or (battler.mon and battler.mon.species))
  local def = species and self.data and self.data.pokemon
              and self.data.pokemon[species]
  local coords = def and (battler.isPlayer and def.backPicCoords
                           or def.frontPicCoords or def.picCoords)
  local tiles = coords and tonumber(coords.height)
  return tiles and tiles > 0 and tiles * 8 or 64
end

function Gen3MoveAnim:battlerRawCoords(battle, battler)
  if not battler then return nil end
  local constants = self.data and self.data.constants or {}
  local coords = constants.gen3BattlerCoords
  local double = false
  if battle and battle.isDouble then
    local ok, yes = pcall(battle.isDouble, battle)
    double = ok and yes and true or false
  end
  local row = coords and (double and coords.doubles or coords.singles)
  local pos = tonumber(battler.position) or (battler.isPlayer and 0 or 1)
  local point = row and row[pos + 1]
  if not point then return nil end
  return tonumber(point.x), tonumber(point.y)
end

-- GetBattlerSpriteCoord(..., BATTLER_COORD_Y_PIC_OFFSET), reconstructed from
-- the same MonCoords/elevation tables the cartridge routine reads.  Memento's
-- window and copied-BG origins depend on this value rather than the renderer's
-- opaque-pixel bounds.
function Gen3MoveAnim:battlerPicOffsetY(battle, battler)
  local _, rawY = self:battlerRawCoords(battle, battler)
  if rawY == nil then return nil end
  local species = battler and (battler.species
                    or (battler.mon and battler.mon.species))
  local def = species and self.data and self.data.pokemon
              and self.data.pokemon[species]
  local coords = def and (battler.isPlayer and def.backPicCoords
                           or def.frontPicCoords or def.picCoords)
  local offset = tonumber(coords and coords.yOffset) or 0
  if not battler.isPlayer then
    local constants = self.data and self.data.constants or {}
    offset = offset - (tonumber(species and constants.gen3Elevation
                                and constants.gen3Elevation[species]) or 0)
  end
  local y = rawY + offset
  if battler.isPlayer then y = y + 8 end
  if y > 104 then y = 104 end -- DISPLAY_HEIGHT - MON_PIC_HEIGHT + 8
  return y
end

function Gen3MoveAnim:bgPriorityRank(battler)
  local pos = battler and tonumber(battler.position)
  if pos == nil then pos = battler and battler.isPlayer and 0 or 1 end
  return (pos == 0 or pos == 3) and 2 or 1
end

local function partnerPos(pos)
  pos = tonumber(pos)
  if pos == nil then return nil end
  return pos < 2 and pos + 2 or pos - 2
end

function Gen3MoveAnim:partnerBattler(battle, battler)
  if not (battle and battle.battlerAt and battler) then return nil end
  local pos = partnerPos(battler.position)
  return pos ~= nil and battle:battlerAt(pos) or nil
end

function Gen3MoveAnim:shadowGeometry(battle, battler)
  local x, rawY = self:battlerRawCoords(battle, battler)
  local picY = self:battlerPicOffsetY(battle, battler)
  if x == nil or rawY == nil or picY == nil then return nil end
  local height = self:battlerCoordHeight(battler)
  local top = picY - math.floor(height / 2)
  return {
    x = x, rawY = rawY, picY = picY, height = height,
    top = top, top7 = top - 7,
    limit = battler.isPlayer and -12 or -64,
    baseHofs = 32 - x, baseVofs = 32 - picY,
    bg = self:bgPriorityRank(battler),
  }
end

-- Build VOLT TACKLE's five task-owned spark strips from live battler geometry.
-- Each parent callback emits at most two children; a child survives through
-- callback 12 and destroys on callback 13.  Keeping these as ordinary events
-- lets the existing OAM renderer sort/draw the otherwise-private task sprites.
function Gen3MoveAnim:setupVoltTackle(battle)
  local shape = self.voltTackle
  if type(shape) ~= "table" then return end
  local attacker = self:battlerForRole(battle, false, 0)
  local target = self:battlerForRole(battle, true, 1)
  if not (attacker and target) then return end
  local ax = self:battlerCallbackCoords(battle, attacker, true)
  local tx = self:battlerCallbackCoords(battle, target, true)
  local ay = self:battlerPicOffsetY(battle, attacker)
  local ty = self:battlerPicOffsetY(battle, target)
  if not (ax and tx and ay and ty) then return end
  local slide
  for _, e in ipairs(self.events or {}) do
    if e.motion == "frlg_callback" and e.callbackFamily == "volt_tackle_slide" then
      slide = e
      break
    end
  end
  if not slide then return end
  local slideLife = self:frlgCallbackLife(slide, battle)
  if not slideLife then return end
  local side = attacker.isPlayer and 1 or -1
  local starts = {}
  local at = (slide.at or 0) + slideLife + 8
  for n = 0, 4 do
    local sx, ex, y
    if n == 0 then
      sx, ex, y = ax, 120 + 128 * side, ay
    elseif n == 4 then
      sx, ex, y = 120 - 128 * side, tx - 32 * side, ty
    else
      local playerStart = (n % 2 == 1) and 256 or -16
      sx = attacker.isPlayer and playerStart or (240 - playerStart)
      ex = attacker.isPlayer and (240 - playerStart) or playerStart
      y = attacker.isPlayer and (80 - 10 * n) or (40 + 10 * n)
    end
    local dist = math.abs(ex - sx)
    local count = math.ceil(dist / 16)
    local dir = ex >= sx and 1 or -1
    starts[n + 1] = at
    for j = 0, count - 1 do
      self.events[#self.events + 1] = {
        at = at + math.ceil((j + 1) / 2), sheet = shape.sheet or "10001",
        motion = "frlg_callback", callbackFamily = "volt_tackle_bolt_child",
        screenX = sx + 16 * dir * j, screenY = y,
        waitLife = shape.childLife or 13, subpriority = 35,
        width = shape.childWidth or 8, height = shape.childHeight or 16,
        oamAffineMode = shape.childOamAffineMode or 3,
        oamShape = shape.childOamShape or 2,
        oamSize = shape.childOamSize or 0,
      }
    end
    local parentLife = math.ceil(count / 2) + 13
    if n < 4 then at = at + parentLife end
  end
  shape.boltAt = starts
  shape.reappearAt = starts[5] + 18
end

-- Exact dynamic timing for Memento.  The source uses the species-dependent
-- TOP coordinate in two scanline loops, so these values belong at runtime.
function Gen3MoveAnim:mementoTiming(battle)
  if not self.memento then return nil end
  local attacker = self:battlerForRole(battle, false, 0)
  local target = self:battlerForRole(battle, true, 1)
  local a, t = self:shadowGeometry(battle, attacker),
               self:shadowGeometry(battle, target)
  if not (a and t) then return nil end
  local attackerSteps = math.floor((a.top7 - a.limit) / 8) + 1
  if attackerSteps < 1 then attackerSteps = 1 end
  local attackerLife = 57 + attackerSteps
  local targetDown = math.ceil((t.rawY + 31 - t.limit) / 8)
  local targetUp = math.max(8, math.ceil((t.top7 - t.limit) / 8))
  local targetLife = 53 + targetDown + targetUp
  local attackerAt = tonumber(self.memento.attackerAt) or 2
  local targetAt = attackerAt + attackerLife + 13
  return {
    attacker = attacker, target = target, a = a, t = t,
    attackerAt = attackerAt, attackerSteps = attackerSteps,
    attackerLife = attackerLife, targetAt = targetAt,
    targetDown = targetDown, targetUp = targetUp, targetLife = targetLife,
    total = targetAt + targetLife + 2,
  }
end

-- Exact lifetime of the task itself, not a reconstruction of any surrounding
-- waitforvisualfinish barrier.  Those barriers are intentionally owned by a
-- different lane; this only keeps a decoded task alive for as long as its own
-- state machine says it exists.
function Gen3MoveAnim:scanlineTaskLife(scan, battle)
  if not scan then return nil end
  local kind = scan.kind
  if kind == "dig_up" then return 16 end          -- states 0,1,2, twelve rises, 4
  if kind == "rapid_spin" then return 44 end      -- delayed trailing edge hits top
  if kind == "extrasensory" then return 27 end    -- 24 distort, stop, destroy
  if kind == "dragon_dance" then return 76 end    -- ramp 3, hold 61, ramp 3, stop
  if kind == "sketch" then
    local battler = battle and self:battlerForRole(battle, true, scan.selector)
    local height = self:battlerCoordHeight(battler)
    return 4 * height + 19                         -- 21 hold + H rows / 4f
  end
  if kind == "dig_down" then
    local d2, d3, d4 = 0, 0, 0
    for age = 2, 255 do
      d2 = (d2 + 6) % 128
      d4 = d4 + 1
      if d4 > 2 then d4, d3 = 0, d3 + 1 end
      local d5 = d3 + ashr(scanSine(self, d2), 4)
      if d5 > 63 then
        -- this callback enters state 3; the next stops the scanline and the
        -- following destroys the visual task.
        return age + 3
      end
    end
  end
  return nil
end

function Gen3MoveAnim:start(moveId, attackerIsPlayer, attackerPosition, targetPosition,
                            branchCtx, battle)
  local anim = self:recordFor(moveId, branchCtx)
  if not hasVisual(anim) then return false end
  self.events = anim.events or {}
  self.shakes = anim.shakes
  self.blends = anim.blends
  self.backgrounds = anim.backgrounds
  self.monBgTimeline = anim.monBgTimeline
  self.splitFx = anim.splitFx
  self.scanlines = anim.scanlines
  self.heaves = anim.heaves or (anim.heave and { anim.heave } or nil)
  self.afterimage = anim.afterimage
  self.orbit = anim.orbit
  self.surf = anim.surf
  self.acidArmor = anim.acidArmor
  self.memento = anim.memento
  self.transform = anim.transform
  self.whiteout = anim.whiteout
  self.camouflage = anim.camouflage
  self.scale = anim.scale
  self.flourish = anim.flourish
  self.rotate = anim.rotate
  self.rotateTracks = anim.rotateTracks
  self.affine = anim.affine
  self.affineTasks = anim.affineTasks
  self.voltTackle = anim.voltTackle
  self.attackerIsPlayer = attackerIsPlayer and true or false
  self.moveId = moveId
  self.branchCtx = branchCtx
  self.attackerPosition = tonumber(attackerPosition)
  self.targetPosition = tonumber(targetPosition)
  self._battle = battle
  self._transformApplied = nil
  self.frame = 0
  if self.voltTackle and battle then self:setupVoltTackle(battle) end
  self.oamRanks = {}
  for i, event in ipairs(self.events) do self.oamRanks[event] = i end

  local counts, order = {}, {}
  for _, e in ipairs(self.events) do
    local key = ("%d:%s:%d:%d:%s"):format(e.at or 0, tostring(e.sheet),
                                          e.x or 0, e.y or 0,
                                          tostring(e.target))
    if e.motion ~= "orbit" and e.motion ~= "arc" then
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
    if n and n > 1 and e.motion ~= "orbit" and e.motion ~= "arc" then
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
  -- FireRed's Cmd_end does not finish an animation merely because the script
  -- pointer reached `end`: it keeps waiting while gAnimVisualTaskCount is
  -- non-zero.  The reusable task-family decoders below are visual tasks too,
  -- so their exact decoded lifetimes must participate in the same end-time
  -- calculation.  Without this, e.g. FACADE's 72-frame battler affine was
  -- still visibly running after Gen3MoveAnim had already reported done.
  local function extendTask(shape, life)
    if not shape or not life or life <= 0 then return end
    local ends = (shape.at or 0) + life
    if ends > last then last = ends end
  end
  if self.afterimage then
    extendTask(self.afterimage,
               ((self.afterimage.steps or 64) + 1)
               * (self.afterimage.framesPerStep or 2))
  end
  if self.affineTasks then
    for _, shape in ipairs(self.affineTasks) do
      extendTask(shape, shape.life)
    end
  elseif self.affine then
    extendTask(self.affine, self.affine.life)
  end
  if self.rotate then
    extendTask(self.rotate, self.rotate.life or 74)
  end
  if type(self.rotateTracks) == "table" then
    for _, track in ipairs(self.rotateTracks) do
      extendTask(track, track.life or #(track.angles or {}))
    end
  end
  if self.flourish then
    extendTask(self.flourish, self.flourish.life or 96)
  end
  if self.scale then
    local s = self.scale
    local shrink = s.shrinkFrames or 32
    local rounds = math.max(1, s.rounds or 3)
    local life = (rounds - 1) * (shrink + 2) + (shrink + 1)
                 + (s.holdFrames or 33) + (s.growFrames or 16)
    extendTask(s, life)
  end
  for _, scan in ipairs(self.scanlines or {}) do
    extendTask(scan, self:scanlineTaskLife(scan, battle))
  end
  for _, heave in ipairs(self.heaves or {}) do
    extendTask(heave, heave.life
               or ((heave.swings or 0) * math.max(1, heave.every or 2)))
  end
  if self.voltTackle and self.voltTackle.reappearAt then
    last = math.max(last, self.voltTackle.reappearAt
                          + (self.voltTackle.reappearLife or 51))
  end
  local duration = math.max(anim.duration or 0, last)
  self.total = duration + TAIL
  -- fadetobg/fadetobgfromset/restorebg create Task_FadeToBg and the script's
  -- waitbgfadein does not advance to end until that task has completed.
  -- backgroundLayer reproduces the same 18-frame fade-out + 18-frame fade-in
  -- timeline, so a move cannot be done while one of those exact tasks is still
  -- active.  Keep this separate from the generic particle TAIL: the cartridge
  -- barrier has a known end and should not be padded with an invented delay.
  local backgroundEnd = 0
  for _, bg in ipairs(self.backgrounds or {}) do
    if bg.op == "fade" or bg.op == "fade_set" or bg.op == "restore" then
      backgroundEnd = math.max(backgroundEnd, (bg.at or 0) + 36)
    end
  end
  self.total = math.max(self.total, backgroundEnd)
  if self.splitFx then
    if self.splitFx.nightShadeAt then
      self.total = math.max(self.total, self.splitFx.nightShadeAt
                            + (self.splitFx.nightShadeLife or 129))
    end
    if self.splitFx.grudgeAt then
      self.total = math.max(self.total, self.splitFx.grudgeAt
                            + (self.splitFx.grudgeLife or 89))
    end
    if self.splitFx.frozenAt then
      self.total = math.max(self.total, self.splitFx.frozenAt
                            + (self.splitFx.frozenLife or 106))
    end
    if self.splitFx.bgBlendCycle then
      local cycle = self.splitFx.bgBlendCycle
      self.total = math.max(self.total, (cycle.at or 0) + (cycle.life or 208))
    end
  end
  -- SURF/MUDDY WATER are pure visual-task moves.  Their task has an explicit
  -- two-frame teardown after the visible wave reaches alpha zero, so the
  -- script's waitforvisualfinish ends at waitLife rather than paying the
  -- generic six-frame presentation tail used for particles.
  if self.surf and self.surf.waitLife then
    self.total = math.max(duration, self.surf.waitLife)
  end
  -- ACID ARMOR's task lifetime and the one script-frame delay after clear are
  -- fully known, so do not append the generic particle presentation tail.
  if self.acidArmor then
    self.total = math.max(anim.duration or 0,
                          (self.acidArmor.at or 0)
                          + (self.acidArmor.life or 110))
  end
  -- MEMENTO's two shadow tasks derive their loop counts from the live
  -- species' MonCoords.  Once battle context exists this is the exact script
  -- end, including the two one-frame delays after the target task finishes.
  if self.memento and battle then
    self._mementoTiming = self:mementoTiming(battle)
    if self._mementoTiming then self.total = self._mementoTiming.total end
  end
  -- These three are exact visual-task moves.  Their records already include
  -- waitforvisualfinish teardown; appending the generic particle tail would
  -- move their documented callback boundaries.
  if self.transform then
    self.total = math.max(anim.duration or 0,
                          (self.transform.at or 0)
                          + (self.transform.waitLife or 92))
  end
  if self.whiteout then
    self.total = math.max(anim.duration or 0,
                          (self.whiteout.at or 0)
                          + (self.whiteout.waitLife or 40))
  end
  if self.camouflage then
    self.total = math.max(anim.duration or 0,
                          self.camouflage.waitLife or 0)
  end
  return true
end

function Gen3MoveAnim:update()
  self.frame = (self.frame or 0) + 1
  -- AnimFlyBallAttack restores the attacker's OBJ on the exact callback that
  -- sends the ball off-screen.  FLY's first-turn FlyBallUp callback is what
  -- hid it; BattleState intentionally keeps that hide across the charge turn.
  local battle = self._battle
  if battle then
    for _, event in ipairs(self.events or {}) do
      if event.motion == "frlg_callback"
         and event.callbackFamily == "fly_ball_attack" then
        local age = self.frame - (event.at or 0)
        local life = self:frlgCallbackLife(event, battle)
        if life and age >= life then
          local attacker = self:battlerForRole(battle, false, 0)
          local pf = attacker and battle.picFx and battle.picFx[attacker]
          if pf then pf.hidden = nil end
        end
      end
    end
  end
  if self.transform and not self._transformApplied then
    local swapAt = (self.transform.at or 0) + (self.transform.swapAt or 46)
    if self.frame >= swapAt then
      local battle = self._battle
      if battle and battle.applyGen3TransformVisual then
        local attacker = self:battlerForRole(battle, false, 0)
        local target = self:battlerForRole(battle, true, 1)
        if attacker and target then
          battle:applyGen3TransformVisual(attacker, target,
                                         self.transform.paletteBlend or 6)
        end
      end
      self._transformApplied = true
    end
  end
end

function Gen3MoveAnim:isDone()
  if not (self.events or self.shakes or self.blends or self.scanlines
          or self.monBgTimeline or self.splitFx
          or self.acidArmor or self.memento or self.transform
          or self.whiteout or self.camouflage) then return true end
  return (self.frame or 0) >= (self.total or 0)
end

function Gen3MoveAnim:release()
  self.events, self.total, self.frame, self.fan, self.oamRanks =
    nil, nil, 0, nil, nil
  self.oamGlobalTieResidual = nil
  self.shakes, self.blends, self.backgrounds, self.scanlines = nil, nil, nil, nil
  self.monBgTimeline, self.splitFx, self.moveId = nil, nil, nil
  self.heaves = nil
  self.orbit, self.surf, self.acidArmor, self.memento = nil, nil, nil, nil
  self.transform, self.whiteout, self.camouflage = nil, nil, nil
  self.voltTackle = nil
  self._battle, self._transformApplied = nil, nil
  self._mementoTiming = nil
  self.scale = nil
  self.flourish, self.rotate, self.affine, self.affineTasks = nil, nil, nil, nil
  self.rotateTracks = nil
  self.attackerPosition, self.targetPosition = nil, nil
end

-- The ordinary move-background commands are BG3 replacements, not particle
-- sprites.  Return the field-underlay state for this animation frame.  The
-- importer has already advanced script timestamps across waitbgfadeout/in, so
-- this only reproduces Task_FadeToBg's hardware brightness ramp and the exact
-- frame on which LoadMoveBg/LoadDefaultBg occurs.
function Gen3MoveAnim:backgroundLayer()
  local list = self.backgrounds
  local assets = self.data and self.data.constants
                 and self.data.constants.gen3BattleAnimBackgrounds
  if type(list) ~= "table" or type(assets) ~= "table"
     or type(assets.images) ~= "table" then return nil end

  local function targetIsPlayer()
    local pos = tonumber(self.targetPosition)
    if pos ~= nil then return pos % 2 == 0 end
    return not self.attackerIsPlayer
  end
  local function resolveId(ev)
    if ev.op == "fade_set" then
      return targetIsPlayer() and tonumber(ev.player) or tonumber(ev.opponent)
    end
    local id = tonumber(ev.id)
    -- Four FireRed helpers choose a side-specific row through a visual task.
    -- The two pictures in each pair are the same sheet with side-authored maps.
    if id == 4 or id == 5 then       -- SetImpactBackground: target side
      return targetIsPlayer() and 5 or 4
    elseif id == 9 or id == 10 then  -- Blizzard/Mach Punch/Extreme Speed: attacker
      return self.attackerIsPlayer and 10 or 9
    elseif id == 24 or id == 25 then -- SetSolarBeamBg: target side
      return targetIsPlayer() and 25 or 24
    elseif self.moveId == "SILVER_WIND" and (id == 22 or id == 23) then
      -- AnimTask_GetTargetSide branches to the matching side-authored bug map.
      return targetIsPlayer() and 23 or 22
    end
    return id
  end
  local now = self.frame or 0
  local function layer(id, brightness)
    if id == nil then
      return { default = true, brightness = brightness or 1 }
    end
    local path = assets.images[id]
    if not path then return nil end
    local out = { image = path, brightness = brightness or 1, id = id }
    local fx = self.splitFx
    local needsIndexed = fx and (fx.bgMotion or fx.paletteRotate
                                  or fx.bgBlackAt or fx.bgBlackRestoreAt
                                  or fx.bgBlendCycle)
    local banks = assets.paletteBanks and assets.paletteBanks[id]
    local exactBank, hasMoveBank = type(banks) == "table", false
    if exactBank then
      for _, bank in ipairs(banks) do
        bank = tonumber(bank)
        if bank == 2 then hasMoveBank = true
        elseif bank ~= 0 then exactBank = false break end
      end
      exactBank = exactBank and hasMoveBank
    end
    if needsIndexed and assets.indexImages and assets.indexImages[id]
       and assets.palettes5 and assets.palettes5[id] and exactBank then
      out.indexImage = assets.indexImages[id]
      out.indexed = true
      local size = assets.sizes and assets.sizes[id]
      out.width = tonumber(size and size.width) or 256
      out.height = tonumber(size and size.height) or 160

      local pal = {}
      for i, c in ipairs(assets.palettes5[id]) do
        pal[i] = { tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0 }
      end
      local rotate = fx.paletteRotate
      if rotate and now >= (rotate.at or 0) and now < (rotate.stopAt or math.huge) then
        local count = math.floor((now - (rotate.at or 0))
                                 / math.max(1, rotate.every or 4))
        local first = (rotate.first or 1) + 1
        local last = (rotate.last or 11) + 1
        local span = last - first + 1
        if span > 0 and count > 0 then
          count = count % span
          if count > 0 then
            local before = {}
            for i = first, last do before[i] = pal[i] end
            for i = first, last do
              pal[i] = before[first + ((i - first - count) % span)]
            end
          end
        end
      end

      local black = math.max(self:silverWindBlackLevel(now) or 0,
                             self:splitBgBlendLevel(now) or 0)
      for i, c in ipairs(pal) do
        if black > 0 then
          c = { math.floor(c[1] * (16 - black) / 16),
                math.floor(c[2] * (16 - black) / 16),
                math.floor(c[3] * (16 - black) / 16) }
        end
        pal[i] = { c[1] / 31, c[2] / 31, c[3] / 31 }
      end
      out.palette = pal
    elseif needsIndexed then
      out.indexedResidual = "move-bg-palette-bank"
    end

    local motion = fx and fx.bgMotion
    if motion and now >= (motion.at or 0) and now < (motion.stopAt or math.huge) then
      local age = now - (motion.at or 0)
      out.wrap = true
      if motion.kind == "slide" then
        local updates = math.max(0, age)
        local dx, dy = motion.dx or 0, motion.dy or 0
        if motion.flipAttacker and not self.attackerIsPlayer then dx, dy = -dx, -dy end
        out.scrollX = updates * dx / 256
        out.scrollY = updates * dy / 256
      elseif motion.kind == "silver_wind" then
        local updates = math.max(0, age)
        out.scrollX = updates * (targetIsPlayer() and -6 or 6)
        out.scrollY = 0
      elseif motion.kind == "sky_uppercut" then
        -- The initializer itself adds 2816/256 = 11 to BG3_Y.  Horizontal
        -- acceleration starts only after data[8] has counted 55 down through -1.
        out.scrollY = 11 * (age + 1)
        local n = math.max(0, age - 56)
        local sign = targetIsPlayer() and 1 or -1
        out.scrollX = sign * 5 * n * (n + 1) / 2
      end
    end
    return out
  end

  local current = nil
  for _, ev in ipairs(list) do
    local at = tonumber(ev.at) or 0
    if now < at then break end
    if ev.op == "change" then
      current = resolveId(ev)
    elseif ev.op == "fade" or ev.op == "fade_set" or ev.op == "restore" then
      local age = now - at
      local nextId = ev.op == "restore" and nil or resolveId(ev)
      if age < 18 then
        -- y begins at 0; UpdateHardwarePaletteFade first displays y=1 on the
        -- following frame and clamps at 16 until the load task runs.
        local y = math.min(age, 16)
        return layer(current, 1 - y / 16)
      elseif age < 36 then
        -- Task state 2 loads the replacement on script frame 18 and starts the
        -- reverse fade at y=16.  Its first visible increment is frame 19.
        local y = math.max(0, 16 - math.min(age - 18, 16))
        return layer(nextId, 1 - y / 16)
      else
        current = nextId
      end
    end
  end
  if current ~= nil then return layer(current, 1) end
  return nil
end

-- AnimTask_BlendBattleAnimPalExclude(ANIM_TARGET, 0, 0, 4, BLACK)
-- reaches coefficient 4 one callback at a time and leaves every selected
-- palette there until the later inverse call walks 4 -> 0.  Silver Wind then
-- separately applies the same held level to the newly loaded BG palette.
function Gen3MoveAnim:silverWindBlackLevel(now)
  local fx = self.splitFx
  if not (fx and fx.move == "SILVER_WIND" and fx.bgBlackAt) then return nil end
  now = tonumber(now) or (self.frame or 0)
  if now < fx.bgBlackAt then return 0 end
  if fx.bgBlackRestoreAt and now >= fx.bgBlackRestoreAt then
    return math.max(0, 4 - (now - fx.bgBlackRestoreAt))
  end
  return math.min(4, now - fx.bgBlackAt)
end

function Gen3MoveAnim:splitBgBlendLevel(now)
  local cycle = self.splitFx and self.splitFx.bgBlendCycle
  if not cycle then return nil end
  now = tonumber(now) or (self.frame or 0)
  local age = now - (cycle.at or 0)
  local life = cycle.life or 208
  if age < 0 or age >= life then return 0 end
  local halfLife = math.max(1, cycle.halfLife or 26)
  local half = math.floor(age / halfLife)
  local localAge = age % halfLife
  local k = math.min(5, math.floor(localAge / math.max(1, cycle.stepFrames or 4)))
  local from, to, step = cycle.from or 0, cycle.to or 10, cycle.step or 2
  if half % 2 == 0 then return math.min(to, from + step * k) end
  return math.max(from, to - step * k)
end

function Gen3MoveAnim:positionForSelector(selector)
  selector = tonumber(selector)
  if selector == 0 then return self.attackerPosition end
  if selector == 1 then return self.targetPosition end
  if selector == 2 then return partnerPosition(self.attackerPosition) end
  if selector == 3 then return partnerPosition(self.targetPosition) end
  return nil
end

function Gen3MoveAnim:matchesBattler(battler, target, selector, side, position)
  local exact = tonumber(position)
  if exact == nil then exact = self:positionForSelector(selector) end
  if exact == nil then
    exact = target and self.targetPosition or self.attackerPosition
  end
  if type(battler) == "table" then
    local pos = tonumber(battler.position)
    if exact ~= nil and pos ~= nil then return pos == exact end
    if side then return (battler.isPlayer and "player" or "enemy") == side end
    local wantsPlayer = target ~= self.attackerIsPlayer
    return (battler.isPlayer and true or false) == wantsPlayer
  end
  if side then return (battler and "player" or "enemy") == side end
  local wantsPlayer = target ~= self.attackerIsPlayer
  return (battler and true or false) == wantsPlayer
end

function Gen3MoveAnim:battlerForRole(battle, target, selector)
  local pos = self:positionForSelector(selector)
  if pos == nil then pos = target and self.targetPosition or self.attackerPosition end
  if pos ~= nil and battle and battle.battlerAt then
    local b = battle:battlerAt(pos)
    if b then return b, b.isPlayer and true or false end
  end
  local playerSide = target ~= self.attackerIsPlayer
  return playerSide and battle.player or battle.enemy, playerSide
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

function Gen3MoveAnim:monGhosts(battler)
  local shape = self.afterimage
  if not shape then return nil end
  -- the attacker is the one that splits: the task asks for
  -- GetAnimBattlerSpriteId(ANIM_ATTACKER) and nothing else
  if not self:matchesBattler(battler, false, 0) then return nil end
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

function Gen3MoveAnim:monTint(battler)
  local now = self.frame or 0
  local best, r, g, b
  for _, blend in ipairs(self.blends or {}) do
    if self:matchesBattler(battler, blend.target, blend.selector,
                           blend.side, blend.position) then
      local c = blendAt(blend, now - (blend.at or 0))
      if c and c > 0 and (not best or c > best) then
        best = c
        r, g, b = blendColour(blend.colour)
      end
    end
  end
  local silver = self:silverWindBlackLevel(now)
  if silver and silver > 0
     and not self:matchesBattler(battler, true, 1) then
    local c = silver / 16
    if not best or c > best then best, r, g, b = c, 0, 0, 0 end
  end
  if not best then return nil end
  return r, g, b, best
end

-- How far this frame has pushed one side's Pokemon out of its place.  Asked
-- by the battle's own draw, so the shake moves the MON rather than a copy of
-- it -- which is what the cartridge does too: the task writes the sprite's
-- own x2/y2.
function Gen3MoveAnim:monOffset(battler)
  local now = self.frame or 0
  local dx, dy = 0, 0
  for _, shake in ipairs(self.shakes or {}) do
    if self:matchesBattler(battler, shake.target, shake.selector) then
      local onPlayer = type(battler) == "table"
                       and (battler.isPlayer and true or false)
                       or (battler and true or false)
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
  -- Volt Tackle's orb callback writes the attacker's own x2 on every slide,
  -- including the terminal callback that destroys the orb.  Keep that final
  -- displacement alive for the later reappear task instead of snapping the mon
  -- back as soon as the particle leaves OAM.
  if self:matchesBattler(battler, false, 0) then
    for _, event in ipairs(self.events or {}) do
      if event.motion == "frlg_callback"
         and event.callbackFamily == "volt_tackle_slide" then
        local age = now - (event.at or 0)
        if age >= 42 then
          local life = self:frlgCallbackLife(event, self._battle)
          local slides = age - 41
          if life then slides = math.min(slides, math.max(0, life - 41)) end
          local velocity = battler.isPlayer and 16 or -16
          dx = dx + velocity * math.max(0, slides)
        end
      end
    end
    local volt = self.voltTackle
    if volt and volt.reappearAt then
      local age = now - volt.reappearAt
      if age >= 0 and age <= (volt.reappearLife or 51) then
        local start = battler.isPlayer and -32 or 32
        local step = battler.isPlayer and 2 or -2
        dx = start + step * math.min(16, math.floor(age / 2))
      end
    end
  end
  return dx, dy
end

function Gen3MoveAnim:monHidden(battler)
  if not (self.voltTackle and self.voltTackle.reappearAt
          and self:matchesBattler(battler, false, 0)) then return false end
  local age = (self.frame or 0) - self.voltTackle.reappearAt
  if age < 2 or age >= 51 then return false end
  local toggles
  if age < 34 then
    toggles = math.floor(age / 2)
  else
    toggles = 17 + math.floor((age - 34) / 2)
  end
  return toggles % 2 == 1
end

-- TRANSFORM's BG mosaic is an exact 0..15..0 state machine.  The create call
-- itself is frame 0; scheduled callback 45 reaches 15, 46 swaps the species,
-- 91 reaches zero and 92 tears the task down.
local function transformStateAt(shape, frame)
  if type(shape) ~= "table" then return nil end
  local age = (tonumber(frame) or 0) - (tonumber(shape.at) or 0)
  if age < 0 or age >= (shape.waitLife or 92) then return nil end
  local swapAt = shape.swapAt or 46
  local zeroAt = shape.zeroAt or 91
  local max = shape.max or 15
  local every = shape.growEvery or 3
  local stretch
  if age <= (shape.maxAt or 45) then
    stretch = math.min(max, math.floor(age / every))
  elseif age < zeroAt then
    stretch = math.max(0, max - math.floor((age - swapAt) / every))
  else
    stretch = 0
  end
  return stretch, age >= swapAt
end
Gen3MoveAnim.transformStateAt = transformStateAt

function Gen3MoveAnim:monMosaic(battler)
  if not self.transform or not self:matchesBattler(battler, false, 0) then
    return nil
  end
  local stretch = transformStateAt(self.transform, self.frame)
  if stretch == nil then return nil end
  -- MOSAIC register value n repeats one source pixel over n+1 screen pixels.
  return stretch + 1
end

-- FLASH writes selected palettes immediately, then restores from the unfaded
-- buffers.  Return palette coefficients rather than an overlay opacity:
-- background is blended toward white, visible battlers toward black.
local function flashStateAt(shape, frame)
  if type(shape) ~= "table" then return nil end
  local age = (tonumber(frame) or 0) - (tonumber(shape.at) or 0)
  if age < 0 or age >= (shape.waitLife or 40) then return nil end
  if age <= (shape.fullThrough or 8) then
    return 1, 0
  end
  local first = shape.firstRestore or 9
  local every = shape.every or 2
  local coeff = 15 - math.floor((age - first) / every)
  coeff = math.max(0, math.min(15, coeff))
  return coeff / 16, 1 - coeff / 16
end
Gen3MoveAnim.flashStateAt = flashStateAt

function Gen3MoveAnim:flashState()
  return flashStateAt(self.whiteout, self.frame)
end

local function camouflageStateAt(shape, frame, terrain)
  if type(shape) ~= "table" then return nil end
  local now = tonumber(frame) or 0
  local tintAt = tonumber(shape.tintAt) or 0
  local resetAt = tonumber(shape.resetAt) or math.huge
  local tintCoeff = 0
  if now >= tintAt + (shape.tintFirst or 3) and now < resetAt then
    local step = math.floor((now - tintAt - (shape.tintFirst or 3))
                            / (shape.tintEvery or 4))
    tintCoeff = math.min(shape.tintTo or 14, math.max(0, step)) / 16
  end

  local outAt = tonumber(shape.fadeOutAt) or math.huge
  local inAt = tonumber(shape.fadeInAt) or math.huge
  local alpha = 1
  if now >= outAt then
    local age = now - outAt
    if age < (shape.fadeOutLife or 80) then
      alpha = math.max(0, 16 - math.floor(age / (shape.fadeOutEvery or 5))) / 16
    elseif now < inAt then
      alpha = 0
    else
      local inAge = now - inAt
      alpha = math.min(16, math.floor(inAge / (shape.fadeInEvery or 2))) / 16
    end
  end

  local colour = shape.colours and shape.colours[terrain or "PLAIN"]
                 or (shape.colours and shape.colours.PLAIN)
  return tintCoeff, alpha, colour
end
Gen3MoveAnim.camouflageStateAt = camouflageStateAt

function Gen3MoveAnim:camouflageState(battler)
  if not self.camouflage or not self:matchesBattler(battler, false, 0) then
    return nil
  end
  local terrain = self._battle and self._battle.gen3Terrain
  if not terrain and self._battle and self._battle.game then
    local ok, Gen3Battle = pcall(require, "src.battle.Gen3Battle")
    if ok and Gen3Battle and Gen3Battle.terrainFor then
      terrain = Gen3Battle.terrainFor(self._battle.game)
    end
  end
  local tint, alpha, colour = camouflageStateAt(self.camouflage, self.frame,
                                                 terrain or "PLAIN")
  if tint == nil then return nil end
  local r, g, b = blendColour(colour or 32767)
  return { tint = tint, r = r, g = g, b = b, alpha = alpha }
end

-- A small FireRed task family shakes BG3 and the battler sprites together.
-- Import keeps the task occurrences separate because ERUPTION/IMPRISON start
-- theirs after earlier script work; evaluating the global offset here lets the
-- battle draw move the field and mons as one instead of dropping the effect
-- whenever particle playback is active.
function Gen3MoveAnim:fieldOffset()
  local now = self.frame or 0
  local best = 0
  for _, heave in ipairs(self.heaves or {}) do
    local age = now - (heave.at or 0)
    local every = math.max(1, heave.every or 2)
    local swings = math.max(0, heave.swings or 0)
    local life = heave.life or swings * every
    if age >= 0 and age < life then
      local step = math.floor(age / every)
      if step < swings then
        local dx = (step % 2 == 0) and (heave.amplitude or 0)
                                      or -(heave.amplitude or 0)
        if math.abs(dx) > math.abs(best) then best = dx end
      end
    end
  end
  return best, 0
end

-- ---------------------------------------------------------------------------
-- THE FIVE BATTLER-LOCAL SCANLINE TASKS
--
-- FireRed temporarily copies a battler into BG1/BG2 for these tasks, then
-- writes one scroll value per screen row.  A general background/window model
-- is unnecessary for this narrow class: every changed pixel belongs to the
-- copied battler, so the renderer asks for the exact row displacement/hidden
-- state and draws the battler one source-pixel row at a time.
--
-- The result below is intentionally SCREEN-row state.  scanlineRow consumes
-- the same native 240x160 y that the GBA HBlank callback indexes.
function Gen3MoveAnim:monScanline(battle, battler)
  if type(self.scanlines) ~= "table" or not battler then return nil end
  local now = self.frame or 0
  local chosen = nil
  for _, scan in ipairs(self.scanlines) do
    if self:matchesBattler(battler, scan.selector == 1, scan.selector)
       and now >= (scan.at or 0) then
      -- Later script calls at the same timestamp win.  This deliberately does
      -- not invent time for waitforvisualfinish: if an excluded timing barrier
      -- collapsed two calls onto one `at`, the record exposes that residual.
      if not chosen or (scan.at or 0) >= (chosen.at or 0) then chosen = scan end
    end
  end
  if not chosen then return nil end

  local age = now - (chosen.at or 0)
  local centre = self:battlerScanlineY(battle, battler)
  if centre == nil then return nil end
  local kind = chosen.kind

  if kind == "dig_down" then
    local life = self:scanlineTaskLife(chosen, battle)
    if life and age >= life then return nil end
    local top = math.max(0, centre - 32)
    local bottom = centre + 32
    local dy = 0
    if age >= 2 then
      local d2, d3, d4, d5 = 0, 0, 0, 0
      for _ = 2, age do
        d2 = (d2 + 6) % 128
        d4 = d4 + 1
        if d4 > 2 then d4, d3 = 0, d3 + 1 end
        d5 = d3 + ashr(scanSine(self, d2), 4)
        if d5 > 63 then
          d5 = 120 - top
          dy = d5
          break
        end
        dy = d5
      end
    end
    -- age 0 is the task setup, age 1 installs SetDigScanlineEffect.  The BG
    -- copy already stands in for the now-invisible OBJ on both frames.
    return { kind = kind, top = top, bottom = bottom, dy = dy,
             scanActive = age >= 1 }
  elseif kind == "dig_up" then
    if age >= 15 then return nil end
    local bottom = centre + 32
    if age < 2 then
      -- AnimTask_DigSetVisibleUnderground left the sprite's centre at the
      -- bottom edge.  No pixel is visible before the TRUE arm sets y2=96.
      return { kind = kind, bottom = bottom, hideAll = true }
    end
    local dy = age == 2 and 96 or math.max(0, 96 - 8 * (age - 2))
    return { kind = kind, bottom = bottom, dy = dy, scanActive = age >= 1 }
  elseif kind == "sketch" then
    local height = self:battlerCoordHeight(battler)
    local life = 4 * height + 19
    if age >= life - 1 then return nil end
    local bottom = centre + 32
    local top = bottom - 64
    local restored = {}
    if age >= 22 then
      local last = math.min(height - 1, math.floor((age - 22) / 4))
      for n = 0, last do
        local phase = n % 4
        local jitter = phase == 1 and -2 or (phase >= 2 and 1 or 0)
        restored[bottom - n + jitter] = true
      end
    end
    return { kind = kind, top = top, bottom = bottom, restored = restored }
  elseif kind == "rapid_spin" then
    local top = math.max(0, centre - 33)
    local bottom = centre + 36
    local hidden = chosen.restore and true or false
    local rows = {}
    for y = top, bottom do rows[y] = hidden end
    local d0, d1, d4, d6, d7, d12 = bottom, bottom, 8, 0, 0, 0
    local d11 = chosen.restore and 0 or 240
    local speed = tonumber(chosen.speed) or 2
    local steps = math.min(age, 43)
    for _ = 1, steps do
      d0 = math.max(top, d0 - speed)
      if d4 == 0 then
        d1 = math.max(top, d1 - speed)
      else
        d4 = d4 - 1
      end
      d6 = d6 + 1
      if d6 > 1 then
        d6 = 0
        d7 = d7 == 0 and 1 or 0
        d12 = d7 ~= 0 and 0 or 240
      end
      for y = d0, d1 - 1 do rows[y] = d12 ~= 0 end
      for y = d1, bottom do rows[y] = d11 ~= 0 end
    end
    if chosen.restore and age >= 44 then return nil end
    -- The first task destroys itself WITHOUT disabling the scanline effect;
    -- its final buffer therefore remains active until the restore call.
    return { kind = kind, top = top, bottom = bottom, hiddenRows = rows }
  elseif kind == "extrasensory" then
    if age < 1 or age >= 25 then return nil end
    local top, bottom = math.max(0, centre - 32), centre + 32
    local stage = tonumber(chosen.stage) or 0
    local step, shift, index
    if stage == 0 then step, shift, index = 2, 5, 64
    elseif stage == 1 then step, shift, index = 2, 5, 192
    else step, shift, index = 4, 4, 0 end
    local pulse = (age - 1) % 4
    local offsets = {}
    for y = top, bottom do
      local off = ashr(scanSine(self, index), shift)
      if off > 0 then off = off + pulse
      elseif off < 0 then off = off - pulse end
      offsets[y] = off
      index = index + step
    end
    return { kind = kind, top = top, bottom = bottom, offsets = offsets,
             stage = stage }
  elseif kind == "dragon_dance" then
    if age < 1 or age >= 74 then return nil end
    local top, bottom = math.max(0, centre - 32), centre + 32
    local amplitude
    if age < 2 then amplitude = 0
    elseif age < 4 then amplitude = 1
    elseif age < 6 then amplitude = 2
    elseif age <= 68 then amplitude = 3
    elseif age <= 70 then amplitude = 2
    elseif age <= 72 then amplitude = 1
    else amplitude = 0 end
    local index = ((age - 1) * 9) % 256
    local offsets = {}
    for y = top, bottom do
      offsets[y] = ashr(scanSine(self, index) * amplitude, 7)
      index = (index + 8) % 256
    end
    return { kind = kind, top = top, bottom = bottom, offsets = offsets,
             amplitude = amplitude }
  end
  return nil
end

-- `screenY` is an integer native GBA scanline.  The returned dx/dy are also
-- native pixels; `hidden` means that row's BG horizontal offset is +240 and
-- therefore the copied battler is completely outside the 240px display.
function Gen3MoveAnim:scanlineRow(state, screenY)
  if not state then return 0, 0, false end
  local y = math.floor(tonumber(screenY) or 0)
  if state.hideAll then return 0, 0, true end
  if state.kind == "dig_down" or state.kind == "dig_up" then
    local dy = state.dy or 0
    local destination = y + dy
    return 0, dy, state.scanActive and destination >= (state.bottom or 160)
  elseif state.kind == "sketch" then
    if y >= (state.top or 0) and y <= (state.bottom or 159)
       and not (state.restored and state.restored[y]) then
      return 0, 0, true
    end
  elseif state.kind == "rapid_spin" then
    if y >= (state.top or 0) and y <= (state.bottom or 159) then
      return 0, 0, state.hiddenRows and state.hiddenRows[y] or false
    end
  elseif state.kind == "extrasensory" or state.kind == "dragon_dance" then
    local off = state.offsets and state.offsets[y]
    if off then return -off, 0, false end -- BG HOFS +n moves pixels left n
  end
  return 0, 0, false
end

-- ---------------------------------------------------------------------------
-- COPIED BATTLER BACKGROUNDS WITH DESTINATION-ROW SAMPLING
--
-- Acid Armor and Memento cannot use the source-row slicer above.  Their HBlank
-- DMA changes VOFS per DESTINATION scanline, which can repeat, stretch or skip
-- source rows.  These state functions expose the hardware register values to a
-- small BG-copy renderer in BattleState.

function Gen3MoveAnim:acidArmorState(battle)
  local shape = self.acidArmor
  if not shape then return nil end
  local age = (self.frame or 0) - (shape.at or 0)
  local life = shape.life or 110
  if age < 0 or age >= life then return nil end
  local battler = self:battlerForRole(battle, false, shape.selector or 0)
  local geom = self:shadowGeometry(battle, battler)
  local centreY = self:battlerScanlineY(battle, battler)
  if not (battler and geom and centreY) then return nil end

  local eva, evb
  if age < 32 then
    eva, evb = 15, 0
  elseif age <= 63 then
    local k = age - 31
    eva, evb = 16 - math.ceil(k / 2), math.floor(k / 2)
  elseif age <= 76 then
    eva, evb = 0, 16
  elseif age <= 108 then
    local k = age - 76
    eva, evb = math.ceil(k / 2), 16 - math.floor(k / 2)
  else
    eva, evb = 16, 0
  end

  local state = {
    kind = "acid_armor", battler = battler, bg = geom.bg,
    baseHofs = geom.baseHofs, baseVofs = geom.baseVofs,
    eva = eva, evb = evb, age = age,
    top = math.max(0, centreY - 34),
  }
  state.bottom = state.top + 66
  if age >= 1 and age <= 63 then
    local d6 = math.min(64, 32 + age - 1)
    local signedStep = battler.isPlayer and 24 or -24
    local d7 = signedStep * math.min(age - 1, 31)
    local d9 = truncDiv(0x7E0, d6)
    state.distort = true
    state.d6, state.d7 = d6, d7
    state.d10 = -truncDiv(d7 * 2, d9)
    state.phase = (age * 2) % 256
  end
  return state
end

function Gen3MoveAnim:mementoState(battle)
  if not self.memento then return nil end
  local timing = self._mementoTiming or self:mementoTiming(battle)
  if not timing then return nil end
  local now = self.frame or 0

  if now >= timing.attackerAt
     and now < timing.attackerAt + timing.attackerLife then
    local age = now - timing.attackerAt
    local g = timing.a
    local updates = math.floor(math.min(age, 46) / 2)
    local state = {
      kind = "memento", battler = timing.attacker, bg = g.bg,
      baseHofs = g.baseHofs, baseVofs = g.baseVofs,
      black = true, age = age,
      eva = math.min(12, math.ceil(updates / 2)),
      evb = 16 - math.min(8, math.floor(updates / 2)),
      windowLeft = g.x - 32, windowRight = g.x + 32,
      d6 = g.top7, d7 = g.rawY + 31,
      d13 = (g.rawY + 31 - g.top7) * 256,
      tailMode = "base",
    }
    if age <= 46 then
      state.mode = "base"
    elseif age <= 46 + timing.attackerSteps then
      local k = age - 46
      state.mode = "memento_do"
      state.d4 = g.top7 - 8 * k
      state.d5 = state.d7
      state.eva, state.evb = 12, 8
    elseif age <= 46 + timing.attackerSteps + 8 then
      local k = age - 46 - timing.attackerSteps
      state.mode = "memento_do"
      state.d4 = g.top7 - 8 * (timing.attackerSteps + k)
      state.d5 = state.d7
      state.windowLeft = g.x - 32 + 4 * k
      state.windowRight = g.x + 32 - 4 * k
      state.eva, state.evb = 12, 8
    else
      -- state 3 requests scanline teardown and state 4 destroys the task.  The
      -- window is already closed by the eighth state-2 callback.
      state.mode = "base"
      state.windowLeft, state.windowRight = g.x, g.x
      state.eva, state.evb = 12, 8
    end
    return state
  end

  if now >= timing.targetAt and now < timing.targetAt + timing.targetLife then
    local age = now - timing.targetAt
    local g = timing.t
    local state = {
      kind = "memento", battler = timing.target, bg = g.bg,
      baseHofs = g.baseHofs, baseVofs = g.baseVofs,
      black = true, age = age,
      d6 = g.top7, d7 = g.rawY + 31,
      d13 = (g.rawY + 31 - g.top7) * 256,
      tailMode = "target_initial",
      windowLeft = g.x, windowRight = g.x,
      eva = 0, evb = 16,
    }
    if age < 4 then
      state.mode = "hidden"
      return state
    elseif age == 4 then
      state.mode = "target_initial"
      state.windowLeft, state.windowRight = g.x - 4, g.x + 4
      state.eva, state.evb = 12, 8
      return state
    end

    local stepAge = age - 4
    if stepAge <= timing.targetDown then
      state.mode = "memento_do"
      state.d4 = g.limit
      state.d5 = math.min(state.d7, g.limit + 8 * stepAge)
      state.windowLeft, state.windowRight = g.x - 4, g.x + 4
      state.eva, state.evb = 12, 8
    elseif stepAge <= timing.targetDown + timing.targetUp then
      local k = stepAge - timing.targetDown
      local half = math.min(32, 4 + 4 * math.min(k, 7))
      state.mode = "memento_do"
      state.d4 = math.min(g.top7, g.limit + 8 * k)
      state.d5 = state.d7
      state.windowLeft, state.windowRight = g.x - half, g.x + half
      state.eva, state.evb = 12, 8
    else
      local k = stepAge - timing.targetDown - timing.targetUp
      if k <= 46 then
        local updates = math.floor(k / 2)
        state.mode = "memento_do"
        state.d4, state.d5 = g.top7, state.d7
        state.windowLeft, state.windowRight = g.x - 32, g.x + 32
        state.eva = 12 - math.min(12, math.ceil(updates / 2))
        state.evb = 8 + math.min(8, math.floor(updates / 2))
      else
        state.mode = "hidden"
        state.eva, state.evb = 0, 16
      end
    end
    return state
  end
  return nil
end

-- Return the source texture row and horizontal destination displacement for
-- one native 240x160 screen row.  `hidden` is the equivalent of HOFS +240 or
-- a row whose copied 64x64 tile data cannot contribute a pixel.
function Gen3MoveAnim:bgCopyRow(state, screenY)
  if not state then return nil, 0, true end
  local y = math.floor(tonumber(screenY) or 0)
  local vofs = state.baseVofs or 0
  local dx = 0
  if state.kind == "acid_armor" and state.distort then
    if y <= (state.top or 0) then return nil, 0, true end
    if y <= (state.bottom or -1) then
      local i = (state.bottom or 0) - y
      local var2 = ashr(i * (state.d6 or 32), 5)
      vofs = vofs + i - var2
      local var3 = ashr((state.d7 or 0) + i * (state.d10 or 0), 5)
      local hoffs = (state.baseHofs or 0) + var3
                    + ashr(scanSine(self, (state.phase or 0) + i * 10), 5)
      dx = - (hoffs - (state.baseHofs or 0))
    end
  elseif state.kind == "memento" then
    if state.mode == "hidden" then return nil, 0, true end
    if y >= 112 then return nil, 0, true end
    if state.mode == "target_initial" then
      vofs = vofs + 159 - y
    elseif state.mode == "memento_do" then
      local d4, d5, d7 = state.d4 or 0, state.d5 or 0, state.d7 or 0
      if y >= d4 and y <= d5 then
        local span = d5 - d4
        if span == 0 then return nil, 0, true end
        local step = truncDiv(state.d13 or 0, span)
        local var1 = (state.d6 or 0) * 256 + (y - d4) * step
        vofs = vofs + ashr(var1, 8) - y
      elseif y < d7 then
        vofs = vofs + 159 - y
      elseif state.tailMode == "target_initial" then
        vofs = vofs + 159 - y
      end
    end
  end
  return y + vofs, dx, false
end

function Gen3MoveAnim:splitBgApplies(battle, split)
  if type(split) ~= "table" then return false end
  if split.kind == "all" then return true end
  local wantsTarget = tonumber(split.battler) ~= 0
  local battler = self:battlerForRole(battle, wantsTarget, wantsTarget and 1 or 0)
  if not battler then return false end
  if split.kind == "foes" then
    local attacker = self:battlerForRole(battle, false, 0)
    local target = self:battlerForRole(battle, true, 1)
    if not (attacker and target)
       or (attacker.isPlayer and true or false) == (target.isPlayer and true or false) then
      return false
    end
  end
  local pos = tonumber(battler.position)
  if pos == nil then pos = battler.isPlayer and 0 or 1 end
  return pos == 0 or pos == 3
end

-- Reconstruct Cmd_monbg/Cmd_clearmonbg as script state rather than attaching it
-- only to createsprite events.  Task-created visuals (Night Shade, Grudge,
-- Sheer Cold) need the copied battler even when the script creates no OBJ.
function Gen3MoveAnim:monBgSnapshot(battle)
  if type(self.monBgTimeline) ~= "table" then return nil end
  local active, split = {}, nil
  local now = self.frame or 0
  for _, ev in ipairs(self.monBgTimeline) do
    if now < (tonumber(ev.at) or 0) then break end
    if ev.op == "monbg" then
      active[tonumber(ev.selector) or 0] = { static = ev.static and true or false }
    elseif ev.op == "clear" then
      active[tonumber(ev.selector) or 0] = nil
      if next(active) == nil then split = nil end
    elseif ev.op == "split" then
      split = { kind = ev.kind, battler = ev.battler }
    end
  end
  if next(active) == nil then return nil end
  return { active = active, split = split,
           promoted = self:splitBgApplies(battle, split) }
end

local function addUniqueBattler(list, seen, battler, static)
  if not battler then return end
  local pos = tonumber(battler.position)
  local key = pos ~= nil and ("p" .. tostring(pos)) or tostring(battler)
  if seen[key] then
    if not static then seen[key].static = false end
    return
  end
  local one = { battler = battler, static = static and true or false }
  seen[key], list[#list + 1] = one, one
end

function Gen3MoveAnim:genericMonBgCopies(battle)
  local snapshot = self:monBgSnapshot(battle)
  if not snapshot then return {} end
  local selected, seen = {}, {}
  for selector, state in pairs(snapshot.active) do
    local base
    if selector == 2 then
      base = self:battlerForRole(battle, false, 0)
    elseif selector == 3 then
      base = self:battlerForRole(battle, true, 1)
    else
      base = self:battlerForRole(battle, selector == 1, selector)
    end
    addUniqueBattler(selected, seen, base, state.static)
    if selector > 1 then
      addUniqueBattler(selected, seen, self:partnerBattler(battle, base), state.static)
    end
  end

  local out = {}
  for _, chosen in ipairs(selected) do
    local battler = chosen.battler
    if battler and battler.sprite and not battler.fainted then
      local geom = self:shadowGeometry(battle, battler)
      if geom then
        local dx, dy = 0, 0
        if battle and battle.gen3AnimShake then
          local ok, ox, oy = pcall(battle.gen3AnimShake, battle, battler)
          if ok then dx, dy = tonumber(ox) or 0, tonumber(oy) or 0 end
        end
        local priority = (snapshot.promoted and geom.bg == 1) and 1 or 2
        out[#out + 1] = {
          kind = "monbg_generic", battler = battler, bg = geom.bg,
          priority = priority, static = chosen.static,
          baseHofs = geom.baseHofs - dx, baseVofs = geom.baseVofs - dy,
          eva = 16, evb = 0,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.priority or 2) ~= (b.priority or 2) then
      return (a.priority or 2) > (b.priority or 2)
    end
    return (a.bg or 2) > (b.bg or 2) -- BG1 wins equal-priority BG2 ties.
  end)
  return out
end

function Gen3MoveAnim:copiedBgPriority(battle, battler)
  if not battler then return 2 end
  local bg = self:bgPriorityRank(battler)
  local snapshot = self:monBgSnapshot(battle)
  return (snapshot and snapshot.promoted and bg == 1) and 1 or 2
end

function Gen3MoveAnim:nightShadeState(battler)
  local fx = self.splitFx
  if not (fx and fx.nightShadeAt and battler
          and self:matchesBattler(battler, false, 0)) then return nil end
  local age = (self.frame or 0) - fx.nightShadeAt
  -- The age-128 callback resets affine/OBJ mode and destroys the task.  Its
  -- 129-call lifetime still matters to waitforvisualfinish, but no transformed
  -- pixels survive that final callback.
  if age < 0 or age >= 128 then return nil end
  local n = math.min(9, math.floor(math.min(age, 27) / 3))
  local scaleValue = 128
  if age >= 113 then scaleValue = math.min(248, 128 + 8 * (age - 112)) end
  return { scale = 256 / scaleValue, eva = n, evb = 16 - n }
end

function Gen3MoveAnim:monBgCopies(battle, phase)
  local out = {}
  local acid = self:acidArmorState(battle)
  if acid and phase == "pre" then
    out[#out + 1] = acid
    local partner = self:partnerBattler(battle, acid.battler)
    if partner and partner.sprite and not partner.fainted then
      local g = self:shadowGeometry(battle, partner)
      if g then
        out[#out + 1] = {
          kind = "monbg_static_copy", battler = partner, bg = g.bg,
          baseHofs = g.baseHofs, baseVofs = g.baseVofs,
          eva = 16, evb = 0,
        }
      end
    end
    -- Both copied battler BGs use priority 2.  BG1 wins ties over BG2, so LOVE
    -- must draw BG2 first and BG1 second.
    table.sort(out, function(a, b) return (a.bg or 2) > (b.bg or 2) end)
  elseif self.memento and phase == "post" then
    local state = self:mementoState(battle)
    if state then out[1] = state end
  elseif phase == "oam" then
    out = self:genericMonBgCopies(battle)
  end
  return out
end

function Gen3MoveAnim:monBgHidesBattler(battle, battler)
  local acid = self:acidArmorState(battle)
  if acid and battler then
    if self:matchesBattler(battler, false, self.acidArmor.selector or 0) then
      return true
    end
    local partner = self:partnerBattler(battle, acid.battler)
    return partner ~= nil and tonumber(partner.position) == tonumber(battler.position)
  end
  if not battler then return false end
  if battle and battle.isDouble then
    local ok, double = pcall(battle.isDouble, battle)
    if ok and double then return false end
  end
  for _, copy in ipairs(self:genericMonBgCopies(battle)) do
    if tonumber(copy.battler and copy.battler.position) == tonumber(battler.position) then
      if copy.static then return false end
      -- AnimTask_NightShadeClone calls PrepareBattlerSpriteForRotScale, which
      -- explicitly unhides the attacker's OBJ while the monbg copy remains.
      if self:nightShadeState(battler) then return false end
      return true
    end
  end
  return false
end

-- Which battler an event is drawn over: the script names attacker or target,
-- and which SIDE that is depends on whose turn it is.
function Gen3MoveAnim:battlerFor(battle, event)
  return self:battlerForRole(battle, event.target and true or false,
                             event.selector)
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
function Gen3MoveAnim:monAffine(battler)
  local shapes = self.affineTasks
  if type(shapes) ~= "table" or #shapes == 0 then
    shapes = self.affine and { self.affine } or nil
  end
  if not shapes then return nil end
  local now = self.frame or 0
  -- New imports preserve one record per createvisualtask.  Walk newest first
  -- so simultaneous wrappers match the cartridge's last writer if they ever
  -- address the same battler; normally simultaneous calls address opposite
  -- battlers (TRICK is the concrete case).
  local shape, frame
  for i = #shapes, 1, -1 do
    local one = shapes[i]
    local age = now - (one.at or 0)
    local life = one.life
    if not life then
      local span = 0
      for _, st in ipairs(one.steps or {}) do span = span + (st.dur or 0) end
      life = span * math.max(1, one.repeats or 1)
    end
    if age >= 0 and age < (life or 0)
       and self:matchesBattler(battler, one.onTarget and true or false,
                               one.selector) then
      shape, frame = one, age
      break
    end
  end
  if not shape then return nil end
  local steps = shape.steps
  if type(steps) ~= "table" or #steps == 0 then return nil end
  local one = 0
  for _, st in ipairs(steps) do one = one + (st.dur or 0) end
  if one <= 0 then return nil end
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
-- Six more moves tip, on the cartridge's GENERAL rotation task rather than
-- WITHDRAW's one-shape one, and those arrive as TRACKS -- an angle and a lift
-- per frame, already accumulated by the import because the cartridge's own
-- step accumulates (RomExtractorGen3:tipOffsets).  A track answers first; the
-- WITHDRAW shape is the fallback, so neither reading moves the other.
--
-- What comes back is RADIANS and a rise in pixels, because that is what a
-- renderer wants.  The cartridge counts a whole turn as 65536.
function Gen3MoveAnim:monRotate(battler)
  local track = self:rotateTrackAt(battler)
  if track then return track.angle, track.rise end
  local shape = self.rotate
  if not shape then return nil end
  local attacker = (self.attackerIsPlayer and true or false)
  -- the task asks for the attacker's own sprite and nothing else
  if not self:matchesBattler(battler, false, 0) then return nil end
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

-- The tip track covering this battler on this frame, as radians and pixels.
--
-- TWO THINGS THE IMPORT LEFT TO HERE, and they are not the same thing:
--
--   the ANGLE is authored for the player's side (`authoredForPlayer`, the
--   convention the offsets already use), so it is used as it stands on your
--   own Pokemon and negated on the other one.  Both of the cartridge's two
--   entries negate on side, and work both through and the enemy's track is
--   the exact negation of the player's -- so one track covers both.
--
--   the RISE does NOT negate; it is an absolute value on the cartridge.  But
--   the plain entry only lifts the sprite when it is the player's, while the
--   restoring entry lifts both, and `risesOnEnemy` is which.  Mirroring the
--   lift, or applying it on both sides unconditionally, would each be wrong
--   for half the six moves.
--
-- The LONGEST angle wins when two tracks overlap, matching how the offsets
-- settle a tie: the tasks do not add up on the cartridge either, because each
-- one writes the sprite's rotation outright rather than accumulating onto
-- what another left there.
function Gen3MoveAnim:rotateTrackAt(battler)
  local list = self.rotateTracks
  if type(list) ~= "table" or battler == nil then return nil end
  local now = self.frame or 0
  local onPlayer = type(battler) == "table"
                   and (battler.isPlayer and true or false)
                   or (battler and true or false)
  local best = nil
  for _, track in ipairs(list) do
    local angles = track.angles
    if type(angles) == "table" then
      local age = now - (track.at or 0)
      if age >= 0 and age < (track.life or #angles) then
        local raw = angles[age + 1]
        if raw and raw ~= 0 then
          local angle = raw
          if track.authoredForPlayer then
            if not onPlayer then angle = -angle end
          elseif onPlayer then
            angle = -angle
          end
          if self:matchesBattler(battler, track.target and true or false, 0) then
            local rise = 0
            if onPlayer or track.risesOnEnemy then
              rise = (track.rises and track.rises[age + 1]) or 0
            end
            if not best or math.abs(angle) > math.abs(best.raw) then
              local turn = track.turn or 65536
              best = { raw = angle, rise = rise,
                       angle = angle / turn * 2 * math.pi }
            end
          end
        end
      end
    end
  end
  return best
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
function Gen3MoveAnim:flourishLayer(battler)
  local shape = self.flourish
  if not shape then return nil end
  -- the task asks for GetAnimBattlerSpriteId(ANIM_ATTACKER) and centres the
  -- layer on it, so it belongs to one side and not the other
  if not self:matchesBattler(battler, false, 0) then return nil end
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
function Gen3MoveAnim:monScale(battler)
  local shape = self.scale
  if not shape then return nil end
  -- only the attacker: the task asks for GetAnimBattlerSpriteId(ANIM_ATTACKER)
  -- and nothing else
  if not self:matchesBattler(battler, false, 0) then return nil end
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
-- The cartridge's companion scanline task writes BLDALPHA row by row.  Rows
-- outside its moving band use (0,16), which makes BG1 invisible; rows inside
-- use the task's current alpha.  Reproducing that as a scissor gives the same
-- reveal without needing a literal HBlank callback.
function Gen3MoveAnim:surfLayer()
  local shape = self.surf
  if not shape then return nil end
  local frame = self.frame or 0
  if frame < 0 or frame >= (shape.life or 134) then return nil end
  -- the task's two arms: which one is chosen is GetBattlerSide(attacker)
  local side = self.attackerIsPlayer and shape.player or shape.opponent
  if not (side and side.image) then return nil end
  -- CreateSurfWave seeds data[6]=1, so its very first Step1 tick advances
  -- the blend from 0/16 to 1/15.  With the setup frame represented by
  -- frame==0 here, the cartridge's two-frame alpha cadence is therefore
  -- floor((frame + 1) / 2), not floor(frame / 2).
  local half = math.floor((frame + 1) / (shape.step or 2))
  local fade, hold = shape.fade or 13, shape.hold or 54
  local blend = half
  if half > hold then blend = fade - (half - hold)
  elseif half > fade then blend = fade end
  if blend <= 0 then return nil end
  local scan = self.attackerIsPlayer
               and shape.scanline and shape.scanline.player
               or shape.scanline and shape.scanline.opponent
  local clipTop, clipBottom = 0, 112
  if scan then
    -- The script launches on frame 0.  On frame 1 CreateSurfWave creates the
    -- scanline task, then RunTasks executes its state 0 later in that same
    -- frame, drawing the initial 48..111 (player) / empty (opponent) band.
    -- State 1 does not move the edge until frame 2.
    local age = math.max(0, frame - 1)
    clipTop = (scan.top or 0) + (scan.topStep or 0) * age
    clipBottom = (scan.bottom or 0) + (scan.bottomStep or 0) * age
    if clipTop < 0 then clipTop = 0 end
    if clipBottom > (scan.limit or 112) then clipBottom = scan.limit or 112 end
    if clipBottom < clipTop then clipBottom = clipTop end
  end
  return { image = side.image,
           x = (side.x or 0) + (side.dx or 0) * frame,
           y = (side.y or 0) + (side.dy or 0) * frame,
           alpha = blend / (shape.blendOf or 16),
           clipTop = clipTop, clipBottom = clipBottom,
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

-- PERISH SONG'S POST-ORBIT TAIL.
--
-- AnimPerishSongMusicNote does not disappear when data[0] passes 120.  That
-- same callback first computes the 121st orbit position, commits x2/y2 into
-- the sprite's primary coordinates, then starts affine animation 1.  Step1
-- holds those coordinates for eleven callbacks while the affine animation
-- turns by -8/256 of a revolution per frame for sixteen frames.  Step2 then
-- drops and bounces the note until the fourth floor crossing destroys it.
--
-- Keeping these numbers local to the one `motion == "orbit"` path is
-- deliberate: they are the state machine in battle_anim_effects_2.c, not a
-- generic particle behavior.
local PERISH_WAIT_FRAMES = 11
local PERISH_ROTATE_FRAMES = 16
local PERISH_ROTATE_STEP = -8
local PERISH_FALL_START = 5
local PERISH_FLOOR = 48
local PERISH_REBOUND_BASE = -5
local PERISH_DESTROY_BOUNCE = 4
-- Visible ages are 0..163: 121 orbit/commit frames, 11 wait frames, and 32
-- visible Step2 callbacks.  The next Step2 callback destroys the sprite before
-- AnimateSprite/OAM rendering, so it must not be drawn.
local PERISH_EVENT_LIFE = 164

-- Step2's y2, `frames` callbacks after it starts, or nil when that callback
-- destroys the note.  This mirrors the cartridge's update order exactly:
-- data[3] += data[2], y2 = data[3], data[2]++, then the floor/bounce test.
local function perishBounceY(frames)
  local speed, y, bounce = PERISH_FALL_START, 0, 0
  for _ = 1, frames do
    y = y + speed
    speed = speed + 1
    if y > PERISH_FLOOR and speed > 0 then
      speed = bounce + PERISH_REBOUND_BASE
      bounce = bounce + 1
    end
    if bounce >= PERISH_DESTROY_BOUNCE then return nil end
  end
  return y
end

-- Where this note is, `age` frames after it appeared, or nil once it is gone.
-- Returns x, y, rotationRadians, phase.  Existing callers that only need x/y
-- keep working; draw() also consumes the affine rotation for the retail tail.
-- The cartridge's data[0] opens at ONE: the first update takes the first-frame
-- branch and then increments before any of the arithmetic runs.
function Gen3MoveAnim:orbitAt(event, age)
  local shape = self.orbit
  local o = event and event.orbit
  if not (shape and o and age and age >= 0) then return nil end
  if age >= PERISH_EVENT_LIFE then return nil end
  local life = shape.life or 120
  local step = math.min(age + 1, life + 1)
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
  if age < life then return x, y, 0, "orbit" end

  -- age==life is the callback that computes step life+1, commits x2/y2 and
  -- calls StartSpriteAffineAnim(1).  BeginAffineAnim runs later that same
  -- AnimateSprites pass, so the first -8 rotation is already visible here.
  local tailAge = age - life
  local rotateSteps = math.min(PERISH_ROTATE_FRAMES, tailAge + 1)
  local rotation = PERISH_ROTATE_STEP * rotateSteps / 256 * 2 * math.pi
  if tailAge == 0 then return x, y, rotation, "commit" end

  -- Eleven Step1 callbacks leave the committed primary position untouched.
  if tailAge <= PERISH_WAIT_FRAMES then
    return x, y, rotation, "affine_wait"
  end

  local bounceY = perishBounceY(tailAge - PERISH_WAIT_FRAMES)
  if bounceY == nil then return nil end
  return x, y + bounceY, rotation, "bounce"
end

-- How long a particle is up for.  A note outlives its own picture -- the
-- picture is one still image and the callback is what ends it -- so the
-- callback's own count is what says when it goes.
function Gen3MoveAnim:eventLife(event, sheet)
  if event and event.explicitLife then return event.explicitLife end
  if event and event.psychoBoost then return 224 end
  if event and event.motion == "orbit" and self.orbit then
    return PERISH_EVENT_LIFE
  end
  if event and event.motion == "frlg_callback" then
    local life = self:frlgCallbackLife(event, self._battle)
    if life and life > 0 then return life end
  end
  -- StartAnimLinearTranslation destroys the sprite through its stored followup
  -- when data[0] (the imported travel duration) runs out.  ANIMCMD_END only
  -- stops changing the picture; it does not destroy that moving sprite, so a
  -- one-frame ICE BEAM crystal remains visible for the whole crossing.
  if event and event.motion == "linear" and event.travel and event.travel > 0 then
    return event.travel + 1
  end
  -- Arc callbacks initialise on their creation frame and begin translating on
  -- the following callback, so ages 0..travel are visible.
  if event and event.motion == "arc" and event.travel and event.travel > 0 then
    return event.travel + 1
  end
  -- AnimToTargetInSinWave calls its step immediately on creation: thirty
  -- translation callbacks are visible, and callback 31 destroys before OAM.
  if event and event.motion == "sine30" and event.travel and event.travel > 0 then
    return event.travel
  end
  -- The water-bubble callback also starts immediately.  When its translation
  -- timer expires it unpauses the 1/5/5-frame picture, waits for that animation
  -- to end, then holds the final frame for ten callbacks.  The callback swaps
  -- themselves consume the remaining visible frames, for a 24-frame tail.
  if event and event.motion == "water_bubble"
      and event.travel and event.travel > 0 then
    return event.travel + (event.postLife or 24)
  end
  -- SingleSine deliberately keeps taking the fixed delta after reaching its
  -- nominal destination and destroys only once it leaves the screen.  The
  -- runtime position check below makes that visible cutoff exact; this bound
  -- merely leaves enough callbacks for either side to get there without
  -- inventing a fixed per-move lifetime.
  if event and event.motion == "single_sine"
      and event.travel and event.travel > 0 then
    return event.travel * 3
  end
  if event and (event.motion == "callback_linear"
                or event.motion == "linear_wave"
                or event.motion == "screen_linear")
      and event.travel and event.travel > 0 then
    -- These callbacks either take their first translation step in the
    -- initializer (+1), on the next callback (0), or after one setup callback
    -- (-1).  The last translation callback is visible; the following callback
    -- destroys the sprite.
    return math.max(1, event.travel + 1 - (event.stepOffset or 0))
  end
  if event and event.motion == "powder"
      and event.travel and event.travel > 0 then
    -- The initializer is visible, then exactly data[0] movement callbacks are
    -- visible before the next callback destroys the particle.
    return event.travel + 1
  end
  if event and event.motion == "falling_coin" then
    -- Two 0..125 half-waves at a phase step of five.  Callback 52 destroys
    -- after computing its offsets, before OAM is built, so ages 0..51 draw.
    return 52
  end
  if event and event.motion == "eruption_rock" then
    local startY, targetY = event.screenY or 0, event.targetY or 0
    local fall = math.max(1, math.ceil((targetY - startY) / 8))
    -- Creation frame + fall delay + fall callbacks + sixteen visible bounce
    -- callbacks; the seventeenth bounce callback destroys before draw.
    return math.max(1, (event.fallDelay or 0) + fall + 17)
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

-- InitAnimLinearTranslation / AnimTranslateLinear use 8.8 fixed point and put
-- the direction in bit 0 of each delta.  Keep that odd/even encoding here so
-- the arc families land on the same integer pixels instead of a floating-point
-- interpolation that merely looks similar.
local function gbaLinearOffset(diff, span, steps)
  if not span or span <= 0 or not steps or steps <= 0 then return 0 end
  local delta = math.floor(math.abs(diff) * 256 / span)
  if diff < 0 then
    if delta % 2 == 0 then delta = delta + 1 end
  elseif delta % 2 == 1 then
    delta = delta - 1
  end
  local out = math.floor(delta * steps / 256)
  return delta % 2 == 1 and -out or out
end

local function gbaSin(table_, index, amplitude)
  if type(table_) ~= "table" then return 0 end
  local v = table_[index % 256]
  if v == nil then return 0 end
  -- GBA Sin is an arithmetic >>8; math.floor gives the same result for the
  -- negative half of the signed table.
  return math.floor(v * (amplitude or 0) / 256)
end

local function gbaCos(table_, index, amplitude)
  return gbaSin(table_, (index or 0) + 64, amplitude)
end

local function callbackArg(event, index)
  local args = event and event.args
  return type(args) == "table" and (tonumber(args[index + 1]) or 0) or 0
end

local function callbackTimelineLife(held)
  local total = 0
  for _, step in ipairs(held or {}) do
    total = total + (tonumber(step[2]) or 1)
  end
  return total
end

local function u16(value)
  return (tonumber(value) or 0) % 65536
end

local function s16(value)
  value = u16(value)
  return value >= 32768 and value - 65536 or value
end

local function battleIsDouble(battle)
  if not (battle and battle.isDouble) then return false end
  local ok, value = pcall(battle.isDouble, battle)
  return ok and value and true or false
end

local function battlerVisible(battler)
  return battler ~= nil and battler.visible ~= false and not battler.fainted
end

function Gen3MoveAnim:battlerCallbackCoords(battle, battler, respectPic)
  if not battler then return nil end
  local x, rawY = self:battlerRawCoords(battle, battler)
  if x == nil then return nil end
  if respectPic then
    return x, self:battlerPicOffsetY(battle, battler)
  end
  return x, rawY
end

function Gen3MoveAnim:averageBattlerCoords(battle, battler, respectPic)
  local x, y = self:battlerCallbackCoords(battle, battler, respectPic)
  if x == nil or y == nil then return nil end
  if not battleIsDouble(battle) then return x, y end
  local partner = self:partnerBattler(battle, battler)
  local px, py = self:battlerCallbackCoords(battle, partner, respectPic)
  if px == nil or py == nil then return x, y end
  return truncDiv(x + px, 2), truncDiv(y + py, 2)
end

function Gen3MoveAnim:battlerCoordWidth(battler)
  local species = battler and (battler.species
                    or (battler.mon and battler.mon.species))
  local def = species and self.data and self.data.pokemon
              and self.data.pokemon[species]
  local coords = def and (battler.isPlayer and def.backPicCoords
                           or def.frontPicCoords or def.picCoords)
  local tiles = coords and tonumber(coords.width)
  return tiles and tiles > 0 and tiles * 8 or 64
end

local function linearPoint(sx, sy, dx, dy, span, steps)
  if not span or span <= 0 then return sx, sy end
  steps = math.max(0, math.min(span, steps or 0))
  return sx + gbaLinearOffset(dx - sx, span, steps),
         sy + gbaLinearOffset(dy - sy, span, steps)
end

local function encodedFastDelta(diff, span)
  if not span or span <= 0 then return 0 end
  local delta = math.floor(math.abs(diff) * 16 / span)
  if diff < 0 then
    if delta % 2 == 0 then delta = delta + 1 end
  elseif delta % 2 == 1 then
    delta = delta - 1
  end
  return delta
end

local function fastOffset(encoded, steps)
  local value = math.floor((tonumber(encoded) or 0) * math.max(0, steps or 0) / 16)
  return encoded % 2 == 1 and -value or value
end

local function normalSpeedSpan(sx, dx, speed)
  speed = math.abs(tonumber(speed) or 0)
  if speed == 0 then return nil end
  return math.floor(math.abs(dx - sx) * 256 / speed)
end

local function fastSpeedSpan(sx, dx, speed)
  speed = math.abs(tonumber(speed) or 0)
  if speed == 0 then return nil end
  return math.floor(math.abs(dx - sx) * 16 / speed)
end

local function fastOutOfBounds(x, y, wideY)
  return x > 256 or x < -16 or y > (wideY and 256 or 160) or y < -16
end

local function fastPrecomputedStart(sx, sy, dx, dy, speed, wideY)
  local firstSpan = fastSpeedSpan(sx, dx, speed)
  if not firstSpan or firstSpan <= 0 then return sx, sy, 0, 0, 0 end
  local ex = encodedFastDelta(dx - sx, firstSpan)
  local ey = encodedFastDelta(dy - sy, firstSpan)
  local rx = ex % 2 == 0 and ex + 1 or ex - 1
  local ry = ey % 2 == 0 and ey + 1 or ey - 1
  local step = 0
  repeat
    step = step + 1
    if step > 2048 then break end
  until fastOutOfBounds(sx + fastOffset(rx, step), sy + fastOffset(ry, step), wideY)
  local startX, startY = sx + fastOffset(rx, step), sy + fastOffset(ry, step)
  local span = fastSpeedSpan(startX, dx, speed)
  if not span or span <= 0 then return startX, startY, 0, 0, 0 end
  return startX, startY, span,
         encodedFastDelta(dx - startX, span),
         encodedFastDelta(dy - startY, span)
end

local function callbackArcPoint(sine, sx, sy, dx, dy, span, amplitude, step)
  if not span or span <= 0 then return sx, sy end
  step = math.max(0, math.min(span, step or 0))
  local x, y = linearPoint(sx, sy, dx, dy, span, step)
  if step > 0 then
    local phaseStep = math.floor(0x8000 / span)
    local phase = math.floor(step * phaseStep / 256) % 256
    y = y + gbaSin(sine, phase, amplitude or 0)
  end
  return x, y
end

local function subpriorityForBattler(battler)
  local pos = battler and tonumber(battler.position)
  if pos == nil then return nil end
  return BATTLER_SUBPRIORITY[pos]
end

local function grudgeAlphaAt(taskAge)
  taskAge = math.max(0, math.floor(tonumber(taskAge) or 0))
  if taskAge <= 1 then return 0, 16 end
  if taskAge <= 28 then
    local n = taskAge - 1
    return math.min(14, math.ceil(n / 2)),
           16 - math.min(12, math.floor(n / 2))
  end
  if taskAge <= 59 then return 14, 4 end
  if taskAge <= 86 then
    local n = taskAge - 59
    return 14 - math.min(14, math.ceil(n / 2)),
           4 + math.min(12, math.floor(n / 2))
  end
  return 0, 16
end

function Gen3MoveAnim:splitSpriteState(event, age, battle)
  if not (event and battle) then return nil end
  age = math.max(0, math.floor(tonumber(age) or 0))
  if event.motion == "grudge_flame" then
    local attacker = self:battlerForRole(battle, false, 0)
    if not attacker then return nil end
    local x = self:battlerCallbackCoords(battle, attacker, true)
    local y = self:battlerScanlineY(battle, attacker)
    if x == nil or y == nil then return nil end
    local sub = math.max(3, (subpriorityForBattler(attacker) or 4) - 2)
    local eva, evb = grudgeAlphaAt(age + 1)
    if age == 0 then
      return { x = x, y = y, priority = 2, subpriority = sub,
               blend = { eva = eva, evb = evb } }
    end
    local i = math.max(0, math.floor(tonumber(event.grudgeIndex) or 0))
    local direction = attacker.isPlayer and -1 or 1
    local angle = (i * 42 + direction * 2 * age) % 256
    local radius = self:battlerCoordWidth(attacker) / 2 + 8
    x = x + gbaSin(self.sine, angle, radius)
    y = y + gbaSin(self.sine, ((i * 6 + age) * 8) % 256, 7)
    local priority = self:copiedBgPriority(battle, attacker)
    if u16(angle - 65) < 127 then priority = priority + 1 end
    return { x = x, y = y, priority = priority, subpriority = sub,
             blend = { eva = eva, evb = evb } }
  elseif event.motion == "frozen_cube" then
    local target = self:battlerForRole(battle, true, 1)
    if not target then return nil end
    local x, y = self:battlerCallbackCoords(battle, target, true)
    if x == nil or y == nil then return nil end
    x, y = x - 32, y - 36
    local eva, evb = 0, 16
    if age >= 1 and age <= 9 then eva, evb = age, 16 - age
    elseif age >= 10 and age <= 56 then eva, evb = 9, 7
    elseif age >= 57 and age <= 65 then eva, evb = 65 - age, age - 49 end
    return { x = x, y = y, drawDx = 32, drawDy = 32,
             priority = 2, subpriority = 4,
             blend = { eva = eva, evb = evb } }
  elseif event.psychoBoost then
    local attacker = self:battlerForRole(battle, false, 0)
    if not attacker then return nil end
    local x, y = self:battlerRawCoords(battle, attacker)
    if x == nil or y == nil then return nil end
    local eva, evb, y2 = 8, 8, 0
    if age >= 200 then
      local n = age - 199
      y2 = -(7 * math.floor(n / 2) + 3 * (n % 2))
      eva = math.max(0, 8 - math.floor(n / 3))
      evb = 16 - eva
    end
    local sx, sy, rotation, doubleSize
    if age <= 198 then
      local program = event.affine0 and self.affines[event.affine0]
      if program and Gen3MoveAnim.particleAffineAt then
        sx, sy, rotation, doubleSize = Gen3MoveAnim.particleAffineAt(program, age)
      end
    else
      local k = math.min(15, age - 198)
      sx = (0x130 - 0x14 * k) / 0x100
      sy = (0x130 + 0x18 * k) / 0x100
      rotation, doubleSize = 0, true
    end
    return { x = x, y = y + y2, blend = { eva = eva, evb = evb },
             invisible = age >= 223,
             affineScaleX = sx, affineScaleY = sy,
             affineRotation = rotation, affineDouble = doubleSize }
  end
  return nil
end

-- Exact state for the source-complete FireRed residual callback batches A-C.
-- `age == 0` is the creation callback itself.  Returning nil means that the
-- source callback destroyed the sprite before OAM was built for that age.
function Gen3MoveAnim:frlgCallbackState(event, age, battle)
  if not (event and event.motion == "frlg_callback") then return nil end
  age = math.max(0, math.floor(tonumber(age) or 0))
  battle = battle or self._battle
  if not battle then return nil end

  local family = event.callbackFamily
  local attacker = self:battlerForRole(battle, false, 0)
  local target = self:battlerForRole(battle, true, 1)
  if not (attacker and target) then return nil end
  local ax, ay = self:battlerCallbackCoords(battle, attacker, true)
  local arx, ary = self:battlerCallbackCoords(battle, attacker, false)
  local tx, ty = self:battlerCallbackCoords(battle, target, true)
  local trx, try = self:battlerCallbackCoords(battle, target, false)
  if not (ax and ay and arx and ary and tx and ty and trx and try) then return nil end
  local aSide = attacker.isPlayer and 1 or -1
  local tSide = target.isPlayer and 1 or -1
  local aMirror
  if arx > trx then aMirror = -1
  elseif arx < trx then aMirror = 1
  else aMirror = attacker.isPlayer and 1 or -1 end
  local function a(i) return callbackArg(event, i) end
  local function state(x, y, extra)
    extra = extra or {}
    extra.x, extra.y = x, y
    return extra
  end

  if family == "volt_tackle_bolt_child" then
    if age >= (event.waitLife or 13) then return nil end
    return state(event.screenX, event.screenY, {
      affineScaleX = 1, affineScaleY = 1,
      affineRotation = -math.pi / 2, affineDouble = true,
    })
  elseif family == "ice_ball" then
    local span = a(4)
    if span <= 0 or age >= 49 then return nil end
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    -- FireRed mirrors only the authored destination-X argument by attacker
    -- side here; the initial helper uses the live attacker/target X ordering.
    local dx, dy = tx + aSide * a(2), ty + a(3)
    if age == 0 then return state(sx, sy) end
    local ex, ey = callbackArcPoint(self.sine, sx, sy, dx, dy,
                                    span, a(5), span)
    if age <= span then
      local x, y = callbackArcPoint(self.sine, sx, sy, dx, dy,
                                    span, a(5), age)
      return state(x, y)
    end
    -- AnimThrowIceBall starts sprite animation 1 one callback after the final
    -- arc tick and holds the actual fixed-point endpoint until Destroy runs.
    return state(ex, ey, { selectedAnim = true, frameAge = age - span - 1 })
  elseif family == "leech_seed" then
    local span = a(4)
    if span <= 0 or age >= 110 then return nil end
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    -- Unlike most projectile helpers the destination is the target's RAW
    -- BATTLER_COORD_X/Y, with only arg2 mirrored by attacker side.
    local dx, dy = trx + aSide * a(2), try + a(3)
    if age == 0 then return state(sx, sy) end
    local ex, ey = callbackArcPoint(self.sine, sx, sy, dx, dy,
                                    span, a(5), span)
    if age <= span then
      local x, y = callbackArcPoint(self.sine, sx, sy, dx, dy,
                                    span, a(5), age)
      return state(x, y)
    end
    if age <= 47 then return state(ex, ey, { invisible = true }) end
    -- Sprouts becomes visible at age48, starts animation 1, loops for sixty
    -- callbacks, and remains drawable through age109.
    return state(ex, ey, { selectedAnim = true, frameAge = age - 48 })
  elseif family == "sludge_projectile" then
    local span = a(2)
    if span <= 0 or age > span then return nil end
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local x, y = sx, sy
    if age > 0 then
      x, y = callbackArcPoint(self.sine, sx, sy, tx, ty, span, -30, age)
    end
    -- arg3==0 calls StartSpriteAnim(sprite, 2) during the creation callback.
    return state(x, y, { selectedAnim = a(3) == 0, frameAge = age })
  elseif family == "acid_poison" then
    local mx, my = self:averageBattlerCoords(battle, target, true)
    local sx, sy = mx + aSide * a(0), my + a(1)
    local span = a(4)
    if span <= 0 or age > span + 1 then return nil end
    -- FireRed stores data[4] = sprite->y + data[0]: arg4 is both duration
    -- and destination-Y delta.  arg3 is intentionally unused.
    local x, y = linearPoint(sx, sy, sx + a(2), sy + span, span,
                             math.min(age, span))
    return state(x, y)
  elseif family == "air_wave" then
    local mx, my = tx, ty
    if a(6) ~= 0 then mx, my = self:averageBattlerCoords(battle, target, true) end
    local sx, sy = ax + aSide * a(0), ay + aSide * a(1)
    local dx, dy = mx + aSide * a(2), my + aSide * a(3)
    local span = a(4)
    if span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, math.min(age, span))
    return state(x, y, { selectedAnim = true, frameAge = age })
  elseif family == "bonemerang" then
    if age == 0 then return state(ax, ay) end
    if age <= 20 then
      local x, y = callbackArcPoint(self.sine, ax, ay, tx, ty, 20, -40, age)
      return state(x, y)
    end
    if age == 21 then return state(tx, ty) end
    if age >= 42 then return nil end
    local x, y = callbackArcPoint(self.sine, tx, ty, ax, ay, 20, 40, age - 21)
    return state(x, y)
  elseif family == "dirt_plume" then
    local battler = a(0) == 0 and attacker or target
    local bx = self:battlerCallbackCoords(battle, battler, true)
    local by = self:battlerScanlineY(battle, battler)
    local right = a(1) == 1
    local sx, sy = bx + (right and -24 or 24), by + 30
    local dx = sx + (right and -a(2) or a(2))
    local dy, span = sy + a(3), a(5)
    if span <= 0 or age > span then return nil end
    local x, y = callbackArcPoint(self.sine, sx, sy, dx, dy, span, a(4), age)
    return state(x, y)
  elseif family == "guard_ring" then
    local sx, sy, useAffine = arx, ary, false
    local partner = self:partnerBattler(battle, attacker)
    if battleIsDouble(battle) and battlerVisible(partner) then
      sx, sy = self:averageBattlerCoords(battle, attacker, false)
      useAffine = true
    end
    sy = sy + 40
    if age >= 15 then return nil end
    local x, y = linearPoint(sx, sy, sx, sy - 72, 13, math.min(age, 13))
    return state(x, y, { affine1 = useAffine })
  elseif family == "leech_life" then
    local sx, sy = tx + tSide * -a(0), ty + tSide * -a(1)
    -- The source negates both offsets only when the target is on the player
    -- side; authored offsets are otherwise used verbatim.
    if not target.isPlayer then sx, sy = tx + a(0), ty + a(1) end
    local span = a(2)
    if span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(sx, sy, tx, ty, span, math.min(age, span))
    return state(x, y)
  elseif family == "megahorn" then
    local sx0, sy0, dx0, dy0 = a(0), a(1), a(2), a(3)
    local affine1 = false
    if target.isPlayer then
      sx0, sy0, dx0, dy0 = -sx0, -sy0, -dx0, -dy0
      affine1 = true
    end
    local span = a(4)
    if span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(tx + sx0, ty + sy0, tx + dx0, ty + dy0,
                             span, math.min(age, span))
    return state(x, y, { affine1 = affine1 })
  elseif family == "rock_blast" then
    local flags = u16(a(5))
    local respectStart = math.floor(flags / 256) == 0
    local sy0 = respectStart and ay or ary
    local dy0 = flags % 256 == 0 and ty or try
    local sx, sy = ax + aMirror * a(0), sy0 + a(1)
    local dx, dy = tx + aSide * a(2), dy0 + a(3)
    local span = a(4)
    if span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, math.min(age, span))
    return state(x, y, { affine1 = not attacker.isPlayer })
  elseif family == "spikes" then
    local mx, my = self:averageBattlerCoords(battle, target, false)
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local span = a(4)
    local arcEnd = span
    if span <= 0 then return nil end
    if age <= arcEnd then
      local x, y = callbackArcPoint(self.sine, sx, sy,
        mx + aSide * a(2), my + a(3), span, -50, age)
      return state(x, y)
    end
    local ex, ey = callbackArcPoint(self.sine, sx, sy,
      mx + aSide * a(2), my + a(3), span, -50, span)
    if age <= arcEnd + 32 then return state(ex, ey) end
    local blink = age - (arcEnd + 32)
    if blink >= 16 then return nil end
    return state(ex, ey, { invisible = math.floor(blink / 2) % 2 == 1 })
  elseif family == "tear_drop" then
    local battler = a(0) == 0 and attacker or target
    local bx, by = self:battlerCallbackCoords(battle, battler, true)
    local width, height = self:battlerCoordWidth(battler), self:battlerCoordHeight(battler)
    local top, left, right = by - math.floor(height / 2), bx - math.floor(width / 2), bx + math.floor(width / 2)
    local kind = a(1)
    local sx, sy, deltaX, affine1
    if kind == 0 then sx, sy, deltaX = right - 8, top + 8, 20
    elseif kind == 1 then sx, sy, deltaX = right - 14, top + 16, 20
    elseif kind == 2 then sx, sy, deltaX, affine1 = left + 8, top + 8, -20, true
    else sx, sy, deltaX, affine1 = left + 14, top + 16, -20, true end
    if age > 32 then return nil end
    local x, y = callbackArcPoint(self.sine, sx, sy, sx + deltaX, sy + 12, 32, -12, age)
    return state(x, y, { affine1 = affine1, frameOffset = 1 })
  elseif family == "vice_grip" then
    local invert = a(0) ~= 0
    local sx, sy = tx + (invert and -32 or 32), ty + (invert and 32 or -32)
    local dx, dy = tx + (invert and -16 or 16), ty + (invert and 16 or -16)
    if age <= 6 then
      local x, y = linearPoint(sx, sy, dx, dy, 6, age)
      return state(x, y, { selectedAnim = true, frameAge = age })
    end
    local animLife = 0
    for _, step in ipairs(event.selectedHeld or {}) do animLife = animLife + (tonumber(step[2]) or 1) end
    if age >= 8 and animLife > 0 and age >= animLife then return nil end
    return state(dx, dy, { selectedAnim = true, frameAge = age })
  elseif family == "weather_ball_down" then
    -- Cmd_createsprite always begins at target X_2/Y_PIC_OFFSET.  This callback
    -- captures that original point as its destination before replacing x/y.
    local dx, dy = tx + a(4), ty + a(5)
    local sx = tx + s16(u16(a(4)) + (target.isPlayer and 30 or -30))
    local sy = a(5) + (target.isPlayer and -20 or -80)
    local span = a(2)
    if span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, math.min(age, span))
    return state(x, y)
  elseif family == "coin_throw" then
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local dx, dy = tx + aSide * a(2), ty + a(3)
    local span = normalSpeedSpan(sx, dx, a(4))
    if not span or span <= 0 or age > span + 1 then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, math.min(age, span))
    return state(x, y)
  elseif family == "confuse_bounce" then
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local dx, dy = tx, ty
    local span = normalSpeedSpan(sx, dx, a(2))
    if not span or span <= 0 then return nil end
    if age == 0 then return state(sx, sy, { blend = { eva = 16, evb = 0 } }) end
    local data6, data7, phase = 16, 0, 0
    local px, py = sx, sy
    local linearSteps = 0
    local stage2 = false
    for callback = 1, age do
      -- Step1 updates blend before checking translation completion.  Step2
      -- checks zero after its forced one-step translation and before updating.
      if not stage2 then
        if data6 > 0xFF then
          data6 = data6 + 1
          if data6 == 0x10D then data6 = 0 end
        else
          local old = data7
          data7 = data7 + 1
          if old % 256 == 0 then
            data7 = math.floor(data7 / 256) * 256
            if math.floor(data7 / 256) % 2 == 1 then data6 = data6 + 1 else data6 = data6 - 1 end
            if data6 == 0 or data6 == 16 then data7 = (data7 + 0x100) % 0x200 end
            if data6 == 0 then data6 = 0x100 end
          end
        end
        if linearSteps >= span then
          stage2 = true
        else
          linearSteps = linearSteps + 1
          px, py = linearPoint(sx, sy, dx, dy, span, linearSteps)
          px = px + gbaSin(self.sine, phase, 10)
          py = py + gbaCos(self.sine, phase, 15)
          phase = (phase + 5) % 256
        end
      else
        linearSteps = linearSteps + 1
        -- Step2 forces data[0]=1 and calls the same AnimTranslateLinear
        -- translator.  It keeps the original 8.8 deltas instead of switching
        -- to the separate 4.4 fast-translation format.
        px = sx + gbaLinearOffset(dx - sx, span, linearSteps)
        py = sy + gbaLinearOffset(dy - sy, span, linearSteps)
        px = px + gbaSin(self.sine, phase, 10)
        py = py + gbaCos(self.sine, phase, 15)
        phase = (phase + 5) % 256
        if data6 == 0 then return nil end
        if data6 > 0xFF then
          data6 = data6 + 1
          if data6 == 0x10D then data6 = 0 end
        else
          local old = data7
          data7 = data7 + 1
          if old % 256 == 0 then
            data7 = math.floor(data7 / 256) * 256
            if math.floor(data7 / 256) % 2 == 1 then data6 = data6 + 1 else data6 = data6 - 1 end
            if data6 == 0 or data6 == 16 then data7 = (data7 + 0x100) % 0x200 end
            if data6 == 0 then data6 = 0x100 end
          end
        end
      end
    end
    local eva = data6 > 16 and 0 or math.max(0, math.min(16, data6))
    return state(px, py, { blend = { eva = eva, evb = 16 - eva } })
  elseif family == "gust_to_target" then
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local dx, dy = tx + aSide * a(2), ty + a(3)
    local span = a(4)
    if span <= 0 then return nil end
    local affineEnd = 0
    local program = event.affine0 and self.affines[event.affine0]
    if program and Gen3MoveAnim.particleAffineAt then
      for i = 0, 255 do
        local _, _, _, _, ended = Gen3MoveAnim.particleAffineAt(program, i)
        if ended then affineEnd = i break end
      end
    end
    if age <= affineEnd then return state(sx, sy) end
    local step = age - affineEnd
    if step > span then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, step)
    return state(x, y)
  elseif family == "hyper_voice" then
    local reverse = a(5) ~= 0
    local b1, b2 = reverse and target or attacker, reverse and attacker or target
    local respect = a(6) ~= 0
    local b1x, b1y = self:battlerCallbackCoords(battle, b1, respect)
    local b2x, b2y = self:battlerCallbackCoords(battle, b2, respect)
    local b1Side = b1.isPlayer and -1 or 1
    local b2Side = b2.isPlayer and -1 or 1
    local sx, sy = b1x + b1Side * a(0), b1y + a(1)
    local partner2 = self:partnerBattler(battle, b2)
    if battlerVisible(partner2) then b2x, b2y = self:averageBattlerCoords(battle, b2, respect) end
    local dx, dy = b2x + b2Side * a(3), b2y + a(4)
    local span = a(0)
    if span <= 0 or age >= span then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, age + 1)
    local sub
    if not b1.isPlayer then
      local ref = battlerVisible(partner2) and partner2 or b2
      sub = (subpriorityForBattler(ref) or 4) - 1
    else
      local p1 = self:partnerBattler(battle, b1)
      if battlerVisible(p1) then
        local p1x = self:battlerCallbackCoords(battle, p1, respect)
        if b1x < p1x then sub = (subpriorityForBattler(p1) or 3) + 1 end
      end
      sub = sub or ((subpriorityForBattler(b1) or 4) - 1)
    end
    return state(x, y, { subpriority = math.max(3, sub) })
  elseif family == "web_thread" then
    local sx, sy = ax + aSide * a(0), ay + a(1)
    local dx, dy
    if a(4) ~= 0 then dx, dy = self:averageBattlerCoords(battle, target, true) else dx, dy = tx, ty end
    local span = normalSpeedSpan(sx, dx, a(2))
    if not span or span <= 0 or age > span then return nil end
    local x, y = linearPoint(sx, sy, dx, dy, span, age)
    if age > 0 then x = x + gbaSin(self.sine, (age - 1) * 13, a(3)) end
    return state(x, y)
  elseif family == "zap_cannon_spark" then
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local span = a(3)
    if span <= 0 or age >= span then return nil end
    local step = age + 1
    local x, y = linearPoint(sx, sy, tx, ty, span, step)
    local phase = (a(4) + age * a(5)) % 256
    x = x + gbaSin(self.sine, phase, a(2))
    y = y + gbaCos(self.sine, phase, a(2))
    local invisible = false
    local p = a(4) % 256
    for _ = 0, age do
      p = (p + a(5)) % 256
      if p % 3 == 0 then invisible = not invisible end
    end
    return state(x, y, { invisible = invisible, frameOffset = a(6) })
  elseif family == "confuse_spiral" then
    if age >= 60 then return nil end
    local phase = (age * 19) % 256
    local x = tx + aSide * a(0) + gbaSin(self.sine, phase, 32)
    local y = ty + a(1) + gbaCos(self.sine, phase, 8) + ashr((age + 1) * 80, 8)
    local test = u16(phase - 65)
    return state(x, y, { priority = test <= 130 and 2 or 1 })
  elseif family == "falling_rock" then
    local bx, by = tx, ty
    if a(3) ~= 0 then bx, by = self:averageBattlerCoords(battle, target, false) end
    local sx, sy = bx + a(0), by + 14
    if age < 16 then
      local theta = (age * 4) % 256
      return state(sx, sy + gbaCos(self.sine, theta, -70),
                   { selectedAnim = true, frameAge = age })
    end
    if age == 16 then
      return state(sx, sy + gbaCos(self.sine, 60, -70),
                   { selectedAnim = true, frameAge = age })
    end
    local bx2 = sx + a(2)
    local step = age - 17
    if step < 32 then
      local theta = (192 + step * 4) % 256
      return state(bx2 + gbaSin(self.sine, theta, a(2)),
                   sy + gbaCos(self.sine, theta, -24),
                   { selectedAnim = true, frameAge = age })
    end
    if step == 32 then
      return state(bx2 + gbaSin(self.sine, (192 + 31 * 4) % 256, a(2)),
                   sy + gbaCos(self.sine, (192 + 31 * 4) % 256, -24),
                   { selectedAnim = true, frameAge = age })
    end
    return nil
  elseif family == "fire_spiral_in" or family == "ice_punch_swirl" then
    if age >= 31 then return nil end
    local sampleAge = math.min(age, 29)
    local phase = (a(0) + sampleAge * 9) % 256
    local amp = 60 - sampleAge * 2
    return state(tx + gbaSin(self.sine, phase, amp),
                 ty + gbaCos(self.sine, phase, amp))
  elseif family == "fire_spiral_out" then
    local wait = math.max(0, a(3))
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    if age <= wait + 1 then return state(sx, sy, { invisible = true }) end
    local step = age - wait - 2
    if step >= math.max(0, a(2)) then return nil end
    local phase = (step * 10) % 256
    local amp = ashr(step * 0xD0, 8)
    return state(sx + gbaSin(self.sine, phase, amp), sy + gbaCos(self.sine, phase, amp))
  elseif family == "twister_particle" then
    local bx, by = tx, ty
    if battleIsDouble(battle) then bx, by = self:averageBattlerCoords(battle, target, true) end
    local duration = a(0)
    if duration <= 0 or age >= duration then return nil end
    local ybase = by + 32
    local rise = a(1)
    local phase = 0
    for i = 1, age do
      if rise == 0xFF then ybase = ybase - 2
      elseif rise > 0 then ybase, rise = ybase - 2, rise - 2 end
      phase = phase + a(2)
      if duration - (i - 1) < a(4) then phase = phase + a(2) end
      phase = phase % 256
    end
    local priority = self:copiedBgPriority(battle, target) + (phase < 0x80 and -1 or 1)
    return state(bx + gbaCos(self.sine, phase, a(3)),
                 ybase + gbaSin(self.sine, phase, 5), { priority = priority })
  elseif family == "orbit_scatter" then
    local vx, vy = gbaSin(self.sine, a(0), 10), gbaCos(self.sine, a(0), 7)
    local x, y = ax + vx * age, ay + vy * age
    if age > 0 and (u16(x + 16) > 272 or y > 160 or y < -16) then return nil end
    return state(x, y)
  elseif family == "overheat_flame" then
    local dyAmp = truncDiv(a(2) * 3, 5)
    local vx, vy = gbaCos(self.sine, a(1), a(2)), gbaSin(self.sine, a(1), dyAmp)
    if age > a(3) then return nil end
    local sx, sy = ax + vx * a(0), ay + a(4) + vy * a(0)
    return state(sx + truncDiv(vx * age, 10), sy + truncDiv(vy * age, 10))
  elseif family == "swirling_fog" then
    local battler = a(4) == 0 and attacker or target
    local respectAverage = a(5) ~= 0
    local bx, by
    if respectAverage then
      bx, by = self:averageBattlerCoords(battle, battler, false)
      bx = bx + (battler.isPlayer and a(0) or -a(0))
      by = by + a(1)
    else
      bx, by = self:battlerCallbackCoords(battle, battler, false)
      bx = bx + (battler.isPlayer and a(0) or -a(0))
      by = by + a(1)
    end
    if target.isPlayer then by = by + 8 end
    local span = a(3)
    if span <= 0 or age >= span then return nil end
    local _, ly = linearPoint(bx, by, bx, by + a(2), span, age + 1)
    local phase = (64 + age * 3) % 256
    local amp = respectAverage and battleIsDouble(battle) and 64 or 32
    local priority = self:copiedBgPriority(battle, battler)
    if u16(phase - 64) > 0x7F then priority = priority + 1 end
    return state(bx + gbaSin(self.sine, phase, amp),
                 ly + gbaCos(self.sine, phase, -6), { priority = priority })
  elseif family == "beyond_target" or family == "swirling_snowball" then
    local sx, sy = ax + aMirror * a(0), ay + a(1)
    local avgArg = family == "beyond_target" and a(7) or a(5)
    local dx, dy
    if avgArg ~= 0 then dx, dy = self:averageBattlerCoords(battle, target, true) else dx, dy = tx, ty end
    dx = dx + aSide * a(2)
    if family == "beyond_target" or avgArg == 0 then dy = dy + a(3) end
    local startX, startY, span, ex, ey = fastPrecomputedStart(sx, sy, dx, dy, a(4), false)
    if span <= 0 then return nil end
    if family == "beyond_target" then
      local steps = age
      local x = startX + fastOffset(ex, steps)
      local y = startY + fastOffset(ey, steps)
      if steps > 0 then y = y + gbaSin(self.sine, (steps - 1) * a(6), a(5)) end
      if steps > span and fastOutOfBounds(x, y, false) then return nil end
      return state(x, y)
    end
    if age <= span then
      return state(startX + fastOffset(ex, age), startY + fastOffset(ey, age))
    end
    local orbitAge = age - span - 1
    local targetX, targetY = startX + fastOffset(ex, span), startY + fastOffset(ey, span)
    local sideAmp = attacker.isPlayer and -20 or 20
    if orbitAge < 32 then
      local phase = (128 + orbitAge * 16) % 256
      local baseX = gbaSin(self.sine, 128, sideAmp)
      local baseY = gbaCos(self.sine, 128, 15)
      return state(targetX + gbaSin(self.sine, phase, sideAmp) - baseX,
                   targetY + gbaCos(self.sine, phase, 15) - baseY)
    end
    local tail = orbitAge - 32
    local x = targetX + fastOffset(ex, tail)
    local y = targetY + fastOffset(ey, tail)
    if tail > 0 and (u16(x + 16) > 272 or y > 256 or y < -16) then return nil end
    return state(x, y)
  elseif family == "fly_ball_attack" then
    local sx, sy = attacker.isPlayer and -32 or 272, -32
    local span = a(0)
    if span <= 0 then return nil end
    local x = sx + gbaLinearOffset(tx - sx, span, age)
    local y = sy + gbaLinearOffset(ty - sy, span, age)
    if age > 0 and (x < -32 or x > 272 or y > 160) then return nil end
    return state(x, y, { affine1 = not attacker.isPlayer })
  elseif family == "thunder_wave" then
    if age >= 51 then return nil end
    local x = tx + a(0) + (tonumber(event.childOffsetX) or 0)
    local y = ty + a(1)
    return state(x, y, {
      invisible = math.floor(age / 3) % 2 == 1,
      tileOffset = tonumber(event.tileOffset) or 0,
    })
  elseif family == "volt_tackle_slide" then
    local velocity = attacker.isPlayer and 16 or -16
    local slides = math.max(0, age - 41)
    local x = ax + velocity * slides
    if slides > 0 and u16(x + 80) > 400 then return nil end
    return state(x, ay, { affine1 = true })
  elseif family == "recycle" then
    -- AnimRecycle anchors the 64x64 arrow to the attacker's X_2 and the top
    -- edge of its MonCoords box, clamps that top edge to scanline 16, then
    -- drives BLDALPHA itself.  The first fade takes 32 two-callback steps,
    -- state 1 holds ten callbacks, and state 2 reverses the same 32 steps;
    -- state 3 destroys on callback age 139.
    if age >= 139 then return nil end
    local y = math.max(16, ay - math.floor(self:battlerCoordHeight(attacker) / 2))
    local eva, evb
    if age <= 64 then
      local steps = math.min(32, math.floor(age / 2))
      eva = math.ceil(steps / 2)
      evb = 16 - math.floor(steps / 2)
    elseif age <= 75 then
      eva, evb = 16, 0
    else
      local steps = math.min(32, math.floor((age - 74) / 2))
      eva = 16 - math.ceil(steps / 2)
      evb = math.floor(steps / 2)
    end
    return state(ax, y, { blend = { eva = eva, evb = evb } })
  elseif family == "will_o_wisp_orb" then
    local sx, sy = arx + aMirror * a(0), ary + a(1)
    local priority = self:copiedBgPriority(battle, target)
    local amp = attacker.isPlayer and -4 or 4
    if age == 0 then
      return state(sx, sy, {
        selectedAnim = true, frameAge = 0, priority = priority,
      })
    end
    if age <= 32 then
      local phase = age == 1 and 0 or ((age - 1) * 4) % 256
      return state(sx + gbaSin(self.sine, phase, amp), sy, {
        selectedAnim = true, frameAge = age, priority = priority,
      })
    end
    local commitX = sx + gbaSin(self.sine, 124, amp)
    local commitY = sy
    local span = normalSpeedSpan(commitX, tx, 256)
    if not span or span <= 0 then return nil end
    local step = age - 32
    if step > span then return nil end
    local x, y = linearPoint(commitX, commitY, tx, ty, span, step)
    x = x + gbaSin(self.sine, ((step - 1) * 4) % 256, 16)
    return state(x, y, {
      selectedAnim = true, frameAge = age, priority = priority,
    })
  elseif family == "poison_gas" then
    local span0 = a(0)
    if span0 <= 0 then return nil end
    local x1, x3 = a(1), a(3)
    if target.isPlayer then x1, x3 = -x1, -x3 end
    local respectPic = a(7) ~= 0
    local destX0 = (respectPic and tx or trx) + x3
    local destY0 = (respectPic and ty or try) + a(4)
    local initX0, initY0 = ax + x1, ay + a(2)
    local initialSub
    if target.isPlayer and attacker.isPlayer and arx < trx then
      initialSub = (subpriorityForBattler(target) or 0) + 1
    end
    if age == 0 then return state(ax, ay, { subpriority = initialSub }) end
    local direction = target.isPlayer and -8 or 8
    if age < span0 then
      local phase = ((age - 1) * direction) % 256
      local x = ax + gbaLinearOffset(destX0 - initX0, span0, age)
                  + gbaSin(self.sine, phase, 16)
      local y = ay + gbaLinearOffset(destY0 - initY0, span0, age)
      return state(x, y, { subpriority = initialSub })
    end

    local phaseStart = target.isPlayer and 80 or 204
    local phase1Y = ay + gbaLinearOffset(destY0 - initY0, span0, span0)
    local transitionX = trx + gbaSin(self.sine, phaseStart, 32)
    if age == span0 then
      return state(transitionX, phase1Y, { subpriority = initialSub })
    end

    local phase1Age = age - span0
    local phase = (phaseStart + 2 + (phase1Age - 1) * 4) % 256
    local priority = self:copiedBgPriority(battle, target)
    if u16(phase - 64) > 0x7F then priority = priority + 1 end
    local x = trx + gbaSin(self.sine, phase, 32)
    local y = phase1Y + gbaLinearOffset(29, 80, math.min(phase1Age, 80))
                    + gbaCos(self.sine, phase, -3)
    if phase1Age < 80 then
      return state(x, y, { subpriority = initialSub, priority = priority })
    end

    local lastPhase = (phaseStart + 2 + 79 * 4) % 256
    local commitX = trx + gbaSin(self.sine, lastPhase, 32)
    local commitY = phase1Y + gbaLinearOffset(29, 80, 80)
                    + gbaCos(self.sine, lastPhase, -3)
    local lastPriority = self:copiedBgPriority(battle, target)
    if u16(lastPhase - 64) > 0x7F then lastPriority = lastPriority + 1 end
    if phase1Age == 80 then
      return state(commitX, commitY, {
        subpriority = initialSub, priority = lastPriority,
      })
    end
    local destX2 = target.isPlayer and -16 or 256
    local span2 = normalSpeedSpan(commitX, destX2, 0x300)
    if not span2 or span2 <= 0 then return nil end
    local step = phase1Age - 80
    if step > span2 then return nil end
    local px, py = linearPoint(commitX, commitY, destX2, commitY + 4,
                               span2, step)
    return state(px, py, {
      subpriority = initialSub, priority = lastPriority,
    })
  elseif family == "guillotine" then
    local invert = a(0) ~= 0
    local sx, sy = tx + (invert and -32 or 32), ty + (invert and 32 or -32)
    local dx, dy = tx + (invert and -16 or 16), ty + (invert and 16 or -16)
    local animLife = callbackTimelineLife(event.selectedHeld)
    local contact = math.max(7, animLife + 1)
    if age <= 6 then
      local x, y = linearPoint(sx, sy, dx, dy, 6, age)
      return state(x, y, { selectedAnim = true, frameAge = age })
    end
    if age < contact then
      return state(dx, dy, { selectedAnim = true, frameAge = age })
    end
    if age <= contact + 50 then
      local jitterAge = age - contact
      local sign = math.floor(jitterAge / 2) % 2 == 0 and 1 or -1
      return state(dx + 2 * sign, dy - 2 * sign, {
        selectedAnim = true, frameAge = 0,
      })
    end
    if age == contact + 51 then
      return state(dx, dy, { alternateAnim = true, frameAge = 0 })
    end
    if age < contact + 58 then
      local step = age - (contact + 51)
      local x, y = linearPoint(dx, dy, sx, sy, 6, step)
      return state(x, y, { alternateAnim = true, frameAge = step })
    end
    return nil
  elseif family == "movement_waves" then
    local repeats = a(2)
    if repeats <= 0 then return nil end
    local battler = a(0) == 0 and attacker or target
    local bx, by = self:battlerCallbackCoords(battle, battler, true)
    local sx = bx + (a(1) == 0 and 32 or -32)
    local animLife = callbackTimelineLife(event.selectedHeld)
    if animLife <= 0 then return nil end
    local cycle = animLife + 1
    local life = repeats * cycle
    if age >= life then return nil end
    return state(sx, by, {
      selectedAnim = true, frameAge = age % cycle,
    })
  elseif family == "orbit_fast" then
    local duration = a(0)
    if duration <= 0 then return nil end
    local signal = tonumber(event.signalAt)
    if signal and age >= signal
       and not (age == signal and age == duration * 2 - 1) then
      return nil
    end
    local phase = (a(1) + age * 9) % 256
    local radius
    if age < duration then
      radius = age
    elseif age < duration * 2 then
      radius = duration * 2 - age
    else
      radius = 0
    end
    local sub = (subpriorityForBattler(attacker) or 4)
                + ((phase >= 64 and phase <= 191) and 1 or -1)
    return state(ax + gbaSin(self.sine, phase, radius * 4),
                 ay + gbaCos(self.sine, phase, radius), {
                   subpriority = math.max(3, sub),
                   affinePaused = true,
                 })
  elseif family == "lock_on" then
    local param = a(0)
    local offX = (param == 1 or param == 2) and -24 or 24
    local offY = (param == 1 or param == 3) and -24 or 24
    local sx, sy = tx + offX - 32, ty + offY - 32
    local d1x, d1y = sx + 64, sy + 64
    local d2x, d2y = d1x, d1y - 64
    local d3x, d3y = d2x - 64, d2y + 64
    local d4x, d4y = d3x + 32, d3y - 32
    local finalX = tx + ((param == 1 or param == 2) and -8 or 8)
    local finalY = ty + ((param == 1 or param == 3) and -8 or 8)
    local x, y
    if age <= 25 then
      x, y = sx, sy
    elseif age <= 33 then
      x, y = linearPoint(sx, sy, d1x, d1y, 8, age - 25)
    elseif age <= 39 then
      x, y = d1x, d1y
    elseif age <= 47 then
      x, y = linearPoint(d1x, d1y, d2x, d2y, 8, age - 39)
    elseif age <= 53 then
      x, y = d2x, d2y
    elseif age <= 61 then
      x, y = linearPoint(d2x, d2y, d3x, d3y, 8, age - 53)
    elseif age <= 67 then
      x, y = d3x, d3y
    elseif age <= 75 then
      x, y = linearPoint(d3x, d3y, d4x, d4y, 8, age - 67)
    elseif age <= 89 then
      x, y = d4x, d4y
    elseif age <= 95 then
      x, y = linearPoint(d4x, d4y, finalX, finalY, 6, age - 89)
    else
      x, y = finalX, finalY
    end
    local signal = tonumber(event.signalAt)
    local gate = signal and math.max(97, signal) or nil
    if gate and age >= gate + 22 then return nil end
    local invisible = false
    if gate and age >= gate + 1 then
      local toggles = math.floor((age - (gate + 1)) / 3) + 1
      invisible = toggles % 2 == 1
    end
    return state(x, y, {
      frameOffset = 4,
      flipX = param == 3 or param == 4,
      flipY = param == 2 or param == 4,
      invisible = invisible,
    })
  end
  return nil
end

function Gen3MoveAnim:frlgCallbackLife(event, battle)
  self._frlgCallbackLives = self._frlgCallbackLives or {}
  local cached = self._frlgCallbackLives[event]
  if cached then return cached end
  for age = 0, 4095 do
    if not self:frlgCallbackState(event, age, battle) then
      local life = math.max(1, age)
      self._frlgCallbackLives[event] = life
      return life
    end
  end
  return nil
end

-- Absolute particle position for the callback families decoded after the
-- generic linear pass.  These records deliberately contain only arithmetic
-- operands shared by a callback family -- no move names or screen guesses.
function Gen3MoveAnim:pathAt(event, age, battle, Gen3Battle)
  local targetLinear = event and event.motion == "linear" and event.localLinear
  local callbackLinear = event and (event.motion == "callback_linear"
                                    or event.motion == "linear_wave")
  local callbackLocal = event and (event.motion == "powder"
                                   or event.motion == "falling_coin")
  local screenPath = event and (event.motion == "screen_linear"
                                or event.motion == "eruption_rock")
  if not event or (event.motion ~= "arc" and not targetLinear
                   and event.motion ~= "sine30"
                   and event.motion ~= "single_sine"
                   and event.motion ~= "water_bubble"
                   and not callbackLinear and not callbackLocal
                   and not screenPath) then return nil end
  age = math.max(age or 0, 0)

  if event.motion == "screen_linear" then
    local span = event.travel or 0
    if span <= 0 then return nil end
    local steps = math.max(0, math.min(span, age + (event.stepOffset or 0)))
    local sx, sy = event.screenX or 0, event.screenY or 0
    local dx, dy = event.screenToX or sx, event.screenToY or sy
    return sx + gbaLinearOffset(dx - sx, span, steps),
           sy + gbaLinearOffset(dy - sy, span, steps)
  end

  if event.motion == "eruption_rock" then
    local sx, sy = event.screenX or 0, event.screenY or 0
    local targetY = event.targetY or sy
    local delay = math.max(0, event.fallDelay or 0)
    if age <= delay then return sx, sy end
    local fallSteps = math.max(1, math.ceil((targetY - sy) / 8))
    local fallAge = age - delay
    if fallAge <= fallSteps then
      return sx, math.min(sy + fallAge * 8, targetY)
    end
    local bounce = fallAge - fallSteps
    if bounce <= 1 then return sx, targetY end
    local pair = math.floor(bounce / 2)
    return sx, targetY + (pair % 2 == 1 and -3 or 3)
  end

  if not (battle and Gen3Battle and Gen3Battle.battlerCentre) then return nil end
  local attacker = self:battlerForRole(battle, false)
  local target = self:battlerForRole(battle, true)
  if not (attacker and target) then return nil end
  local ax, ay = Gen3Battle.battlerCentre(battle, attacker)
  local tx, ty = Gen3Battle.battlerCentre(battle, target)
  if not (ax and ay and tx and ty) then return nil end

  -- SetAnimSpriteInitialXOffset and the projectile callbacks' destination-x
  -- mirror use the attacker's side: player-authored offsets are positive,
  -- opponent-authored offsets negative.
  local sign = self.attackerIsPlayer and 1 or -1
  local xSign = event.mirrorX == false and 1 or sign
  local startXSign = xSign
  if targetLinear and (event.callbackFamily == "bone_hit"
                       or event.callbackFamily == "cross_chop"
                       or event.callbackFamily == "teal_alert"
                       or event.callbackFamily == "water_droplet") then
    -- InitSpritePosToAnimTarget(TRUE) delegates to
    -- SetAnimSpriteInitialXOffset, which mirrors from the live raw attacker /
    -- target X ordering rather than merely from the attacker's side.
    local arx = self:battlerRawCoords(battle, attacker)
    local trx = self:battlerRawCoords(battle, target)
    if arx and trx then
      if arx > trx then startXSign = -1
      elseif arx < trx then startXSign = 1
      else startXSign = self.attackerIsPlayer and 1 or -1 end
    end
  end
  local ySign = event.mirrorY and sign or 1
  local sx, sy
  if event.from == "target" then
    sx, sy = tx + startXSign * (event.x or 0), ty + ySign * (event.y or 0)
  else
    sx, sy = ax + xSign * (event.x or 0), ay + ySign * (event.y or 0)
  end
  local dx, dy
  if event.to == "attacker" then
    dx, dy = ax + xSign * (event.toX or 0), ay + ySign * (event.toY or 0)
  else
    dx, dy = tx + xSign * (event.toX or 0), ty + ySign * (event.toY or 0)
  end
  local span = event.travel or 0

  if event.motion == "powder" then
    if span <= 0 then return sx, sy end
    local steps = math.min(age, span)
    if steps <= 0 then return sx, sy end
    local phase = ((steps - 1) * (event.phaseStep or 0)) % 256
    local amp = event.waveX or 0
    if not self.attackerIsPlayer then amp = -amp end
    return sx + gbaSin(self.sine, phase, amp),
           sy + ashr((steps - 1) * (event.verticalSpeed or 0), 8)
  end

  if event.motion == "falling_coin" then
    local steps = math.min(age, 51)
    local x = math.floor(steps * 128 / 256)
    if self.attackerIsPlayer then x = -x end
    if steps <= 0 then return sx, sy end
    local phase, amp
    if steps <= 26 then
      phase, amp = (steps - 1) * 5, -16
    else
      phase, amp = (steps - 27) * 5, -8
    end
    return sx + x, sy + gbaSin(self.sine, phase, amp)
  end

  if callbackLinear then
    if span <= 0 then return sx, sy end
    local steps = math.max(0, math.min(span, age + (event.stepOffset or 0)))
    local x = sx + gbaLinearOffset(dx - sx, span, steps)
    local y = sy + gbaLinearOffset(dy - sy, span, steps)
    if event.motion == "linear_wave" and steps > 0 then
      local phase
      if event.phaseStepFixed then
        phase = (event.phase or 0)
                + math.floor((steps - 1) * event.phaseStepFixed / 256)
      else
        phase = (event.phase or 0) + (steps - 1) * (event.phaseStep or 0)
      end
      local wx = gbaSin(self.sine, phase, event.waveX or 0)
      if event.waveXDirection and dx < sx then wx = -wx end
      x = x + wx
      if event.waveCosY then
        y = y + gbaCos(self.sine, phase, event.waveY or 0)
      else
        y = y + gbaSin(self.sine, phase, event.waveY or 0)
      end
    end
    return x, y
  end

  if targetLinear then
    if event.localLinear == "delta" then
      -- AnimWaterGunDroplet adds these to the already mirrored target-local
      -- start.  The deltas themselves are screen-space in the callback.
      dx, dy = sx + (event.linearDX or 0), sy + (event.linearDY or 0)
    elseif event.localLinear == "cross_chop" then
      -- Two exact target-local translations with the source callback's pause
      -- between them.  StartAnimLinearTranslation invokes its first translation
      -- step immediately: ages 0..29 are the thirty first-leg steps, age 30 is
      -- the translator->followup handoff, ages 31..40 are followup counts 1..10,
      -- age 41 reaches count 11 and only installs the second translation;
      -- second-leg step 1 is the following callback at age 42.  The
      -- hand's +/-20 is screen-space, not side mirrored.
      local firstFrames = event.firstFrames or 30
      local holdFrames = event.holdFrames or 12
      local secondFrames = event.secondFrames or 8
      local firstDX = gbaLinearOffset(event.firstX or 0, firstFrames, firstFrames)
      local firstDY = gbaLinearOffset(event.firstY or 0, firstFrames, firstFrames)
      local fx, fy = sx + firstDX, sy + firstDY
      -- The source computes data[2]/data[4] as primary - pos2 BEFORE committing
      -- pos2 into primary, so the second destination is the original point
      -- minus the first leg's *actual fixed-point displacement*.
      local zx, zy = sx - firstDX, sy - firstDY
      if age < firstFrames then
        local step = age + 1
        return sx + gbaLinearOffset(event.firstX or 0, firstFrames, step),
               sy + gbaLinearOffset(event.firstY or 0, firstFrames, step)
      end
      if age < firstFrames + holdFrames then return fx, fy end
      local step = math.min(age - firstFrames - holdFrames + 1, secondFrames)
      return fx + gbaLinearOffset(zx - fx, secondFrames, step),
             fy + gbaLinearOffset(zy - fy, secondFrames, step)
    end
    -- All four callbacks hand directly to StartAnimLinearTranslation, which
    -- calls AnimTranslateLinear_WithFollowup once before returning.
    local steps = math.min(age + 1, span)
    return sx + gbaLinearOffset(dx - sx, span, steps),
           sy + gbaLinearOffset(dy - sy, span, steps)
  end
  if event.motion == "sine30" then
    -- The initializer stores a 30-frame delta and immediately invokes Step.
    -- The shared timer's phase byte is converted into the callback's 0..127
    -- half-wave representation, flipping amplitude each time the next seven
    -- sine-table entries would pass 127.
    local steps = math.min(age + 1, span)
    local x = sx + gbaLinearOffset(dx - sx, span, steps)
    local y = sy + gbaLinearOffset(dy - sy, span, steps)
    local phase, amp = (event.phase or 0) % 256, event.arc or 0
    if phase > 127 then phase, amp = phase - 127, -amp end
    for _ = 1, age do
      if phase + 7 > 127 then
        phase, amp = 0, -amp
      else
        phase = phase + 7
      end
    end
    return x, y + gbaSin(self.sine, phase, amp)
  end

  if event.motion == "water_bubble" then
    -- The primary position is shifted opposite the initial Sin/Cos only AFTER
    -- the linear deltas have been prepared.  Each visible travel callback then
    -- adds those trig offsets back at its current phase; the last result stays
    -- fixed throughout the post-impact animation/wait tail.
    local steps = math.min(age + 1, span)
    local phase0 = (event.phase or 0) % 256
    local ampX = sign * (event.waveX or 0)
    local ampY = event.waveY or 0
    local waveAge = math.min(age, math.max(span - 1, 0))
    local phase = (phase0 * 256 + waveAge * (event.phaseStep or 0)) % 65536
    local x = sx - gbaSin(self.sine, phase0, ampX)
              + gbaLinearOffset(dx - sx, span, steps)
              + gbaSin(self.sine, math.floor(phase / 256), ampX)
    local y = sy - gbaCos(self.sine, phase0, ampY)
              + gbaLinearOffset(dy - sy, span, steps)
              + gbaCos(self.sine, math.floor(phase / 256), ampY)
    return x, y
  end

  local steps
  if event.motion == "single_sine" then
    -- Unlike an ordinary arc, this callback temporarily sets data[0]=1 every
    -- frame, so it continues by one fixed delta indefinitely after reaching
    -- the target.  Its own source bounds test destroys before drawing the first
    -- step outside these limits.
    steps = age
  else
    steps = math.min(age, span)
  end
  local x = sx + gbaLinearOffset(dx - sx, span, steps)
  local y = sy + gbaLinearOffset(dy - sy, span, steps)
  if steps > 0 and span > 0 then
    local phaseStep = math.floor(0x8000 / span)
    local phase = math.floor((steps * phaseStep) / 256) % 256
    y = y + gbaSin(self.sine, phase, event.arc or 0)
  end
  if event.motion == "single_sine"
      and (x > 256 or x < -16 or y > 160 or y < -16) then
    -- Keep the draw path handled while putting it fully offscreen; returning
    -- nil here would fall back to the generic target-centred renderer.
    return 10000, 10000
  end
  return x, y
end

-- X offset after the callback's own initial-position helper has run.  Keeping
-- this separate from draw() also makes the cartridge's self-target sign easy
-- to regression-test without needing to rasterize a whole battle frame.
function Gen3MoveAnim:eventXOffset(event, playerSide)
  if event and event.mirrorInitial then
    return self.attackerIsPlayer and (event.x or 0) or -(event.x or 0)
  end
  return playerSide and -((event and event.x) or 0)
                    or ((event and event.x) or 0)
end

-- The cartridge sorts on each sprite's current OAM coordinates, after its
-- callback has updated x/y/pos2 for this frame.  Keep the source position in
-- one place so drawing and ordering cannot drift apart.  Presentation-only
-- `fan` offsets are deliberately absent here: they do not exist in FireRed and
-- therefore must never influence OAM order.
function Gen3MoveAnim:eventPose(event, battle, Gen3Battle)
  if not (event and battle and Gen3Battle) then return nil end
  local age = (self.frame or 0) - (event.at or 0)
  local sheet = self.gfx[event.sheet]
  if age < 0 or not sheet or age >= self:eventLife(event, sheet) then return nil end

  local battler, playerSide = self:battlerFor(battle, event)
  if event.motion == "frlg_callback" then
    local callbackState = self:frlgCallbackState(event, age, battle)
    if not callbackState or callbackState.x == nil or callbackState.y == nil then
      return nil
    end
    return {
      age = age, sheet = sheet,
      centreX = callbackState.x, centreY = callbackState.y,
      dx = 0, dy = 0, pathX = callbackState.x,
      playerSide = playerSide, callbackState = callbackState,
    }
  end
  local splitState = self:splitSpriteState(event, age, battle)
  if splitState and splitState.x ~= nil and splitState.y ~= nil then
    return {
      age = age, sheet = sheet,
      centreX = splitState.x, centreY = splitState.y,
      dx = splitState.drawDx or 0, dy = splitState.drawDy or 0,
      pathX = splitState.x, playerSide = playerSide,
      callbackState = splitState,
    }
  end
  local centreX, centreY
  if battler and Gen3Battle.battlerCentre then
    centreX, centreY = Gen3Battle.battlerCentre(battle, battler)
  end

  local orbitX, orbitY, orbitRotation = self:orbitAt(event, age)
  if orbitX then centreX, centreY = orbitX, orbitY end
  local pathX, pathY
  if not orbitX then pathX, pathY = self:pathAt(event, age, battle, Gen3Battle) end
  if pathX then centreX, centreY = pathX, pathY end

  local t = not orbitX and not pathX
            and travelFraction(event, age, lifeOf(sheet)) or nil
  if t and centreX and centreY then
    local other = self:battlerForRole(battle, not (event.target and true or false))
    local fromX, fromY
    if other and Gen3Battle.battlerCentre then
      fromX, fromY = Gen3Battle.battlerCentre(battle, other)
    end
    if fromX and fromY then
      centreX = fromX + (centreX - fromX) * t
      centreY = fromY + (centreY - fromY) * t
    end
  end
  if not (centreX and centreY) then return nil end

  local dx = pathX and 0 or self:eventXOffset(event, playerSide)
  local dy = event.y or 0
  if orbitX or pathX then dx, dy = 0, 0 end
  return {
    age = age, sheet = sheet, centreX = centreX, centreY = centreY,
    dx = dx, dy = dy, orbitX = orbitX, orbitRotation = orbitRotation,
    pathX = pathX, playerSide = playerSide,
  }
end

local function normalizedOamY(y, affineMode, shape, size)
  local raw = math.floor(tonumber(y) or 0) % 256
  -- SortSprites first maps normal offscreen OAM Y 160..255 to -96..-1.  A
  -- 64-pixel affine-double square/vertical sprite gets the wider signed window:
  -- its 129..159 range is also above the display and therefore wraps negative.
  local special = tonumber(affineMode) == 3 and tonumber(size) == 3
                  and (tonumber(shape) == 0 or tonumber(shape) == 2)
  local threshold = special and 129 or 160
  if raw >= threshold then raw = raw - 256 end
  return raw
end
Gen3MoveAnim.normalizedOamY = normalizedOamY

function Gen3MoveAnim:eventOamY(event, battle, Gen3Battle)
  local pose = self:eventPose(event, battle, Gen3Battle)
  if not pose then return nil end
  if event and event.motion == "frozen_cube" then
    -- The 96x96 image is a compositor convenience.  Hardware sorts the 64x64
    -- parent OBJ that owns the four subsprites, so ignore the +32 draw offset.
    return normalizedOamY(pose.centreY - 32, 0, 0, 3)
  end
  local sheet = pose.sheet
  local fh = (sheet and sheet.frameHeight) or tonumber(event.height)
  if not fh then return nil end
  local affineMode = tonumber(event.oamAffineMode) or 0
  local cornerY = -fh / 2
  if affineMode == 3 then cornerY = cornerY * 2 end
  return normalizedOamY(pose.centreY + pose.dy + cornerY,
                        affineMode, event.oamShape, event.oamSize)
end

function Gen3MoveAnim:battlerPriorityKey(battler)
  local pos = battler and tonumber(battler.position)
  if pos == nil then pos = battler and battler.isPlayer and 0 or 1 end
  local sub = BATTLER_SUBPRIORITY[pos]
  return sub and (2 * 256 + sub) or nil
end

function Gen3MoveAnim:battlerOamY(battle, battler)
  if not battler then return nil end
  local _, rawY = self:battlerRawCoords(battle, battler)
  if rawY == nil then return nil end
  local centreY
  if battler.substituteHP and not battler.fainted then
    -- GetSubstituteSpriteDefault_Y: raw BATTLER_COORD_Y + 17 (player) / 16
    -- (opponent).  The substitute still uses the ordinary 64x64 battler OAM.
    centreY = rawY + (battler.isPlayer and 17 or 16)
  else
    local species = battler.species or (battler.mon and battler.mon.species)
    local def = species and self.data and self.data.pokemon
                and self.data.pokemon[species]
    local coords = def and (battler.isPlayer and def.backPicCoords
                             or def.frontPicCoords or def.picCoords)
    local yOffset = tonumber(coords and coords.yOffset) or 0
    if not battler.isPlayer then
      local constants = self.data and self.data.constants or {}
      yOffset = yOffset - (tonumber(species and constants.gen3Elevation
                                   and constants.gen3Elevation[species]) or 0)
    end
    centreY = rawY + yOffset
  end
  if battle.gen3AnimShake then
    local ok, _, dy = pcall(battle.gen3AnimShake, battle, battler)
    if ok then centreY = centreY + (tonumber(dy) or 0) end
  end
  -- gOamData_BattlerPlayer/Opponent are affine-normal 64x64 sprites, so
  -- CalcCenterToCornerVec contributes -32 and uses the ordinary Y wrap rule.
  return normalizedOamY(centreY - 32, 1, 0, 3)
end

-- Direct OBJ events can join the battlers' hardware sort only while every
-- active event has a source OAM key and live pose.  Cmd_monbg is represented
-- separately as a BG1/BG2 copy by the compositor, so particles remain sortable
-- here while their copied destination BG is active.
function Gen3MoveAnim:oamEventDescriptors(battle, Gen3Battle)
  if not (battle and Gen3Battle) then return nil, "no-battle" end
  if self.acidArmor or self.memento then return nil, "copied-bg-special" end
  local out = {}
  for i, event in ipairs(self.events or {}) do
    local sheet = self.gfx[event.sheet]
    local age = (self.frame or 0) - (event.at or 0)
    if age >= 0 and sheet and age < self:eventLife(event, sheet) then
      if (event.monbg or event.splitbg) and type(self.monBgTimeline) ~= "table" then
        return nil, "monbg"
      end
      local key = self:eventPriorityKey(event, battle)
      local pose = key and self:eventPose(event, battle, Gen3Battle) or nil
      local y = pose and self:eventOamY(event, battle, Gen3Battle) or nil
      if not (key and pose and y ~= nil) then return nil, "unknown-direct-oam" end
      out[#out + 1] = {
        kind = "particle", event = event, index = i,
        key = key, oamY = y, pose = pose,
        rank = (self.oamRanks and self.oamRanks[event]) or i,
      }
    end
  end
  return out
end

-- The matrix a SpriteTemplate's automatic affine animation 0 has reached at
-- `age`. This mirrors sprite.c's BeginAffineAnim/ContinueAffineAnim state
-- machine: duration-zero frames set an absolute matrix, nonzero frames apply a
-- per-frame delta immediately and for the remaining duration, and LOOP/JUMP
-- change the command cursor without consuming their own frame.
--
-- These are particle matrices. They stay separate from self.affine (the
-- task-driven battler squash path) and the Perish Song note tail that
-- explicitly starts affine animation 1.
local function particleAffineAt(program, age)
  local cmds = program and program.commands
  if type(cmds) ~= "table" or type(cmds[1]) ~= "table"
     or type(cmds[1][1]) ~= "number" then return nil end
  age = math.max(0, math.floor(tonumber(age) or 0))

  local state = {
    x = 0x100, y = 0x100, rotation = 0,
    index = 1, delay = 0, loopCounter = 0, ended = false,
  }

  local function applyFrame(cmd)
    local dx, dy = tonumber(cmd[1]) or 0, tonumber(cmd[2]) or 0
    local rot = (tonumber(cmd[3]) or 0) % 256
    local duration = math.max(0, tonumber(cmd[4]) or 0)
    if duration == 0 then
      state.x, state.y = dx, dy
      state.rotation = (rot * 256) % 65536
      state.delay = 0
    else
      state.x = state.x + dx
      state.y = state.y + dy
      state.rotation = (state.rotation + rot * 256) % 65536
      state.delay = duration - 1
    end
  end

  local function previousLoopStart(index)
    for i = index - 1, 1, -1 do
      local c = cmds[i]
      if type(c) == "table" and c[1] == "loop" then return i + 1 end
    end
    return 1
  end

  local function enter(index)
    local guard = 0
    while guard < 64 do
      guard = guard + 1
      local cmd = cmds[index]
      if type(cmd) ~= "table" then state.ended = true return end
      state.index = index
      if type(cmd[1]) == "number" then
        applyFrame(cmd)
        return
      elseif cmd[1] == "end" then
        state.ended = true
        return
      elseif cmd[1] == "jump" then
        -- AffineAnimJumpCmd.target is a zero-based command index.
        index = (tonumber(cmd[2]) or 0) + 1
      elseif cmd[1] == "loop" then
        local count = math.max(0, tonumber(cmd[2]) or 0)
        if state.loopCounter ~= 0 then
          state.loopCounter = state.loopCounter - 1
        else
          state.loopCounter = count
        end
        if state.loopCounter ~= 0 then
          index = previousLoopStart(index)
        else
          index = index + 1
        end
      else
        state.ended = true
        return
      end
    end
    state.ended = true
  end

  -- BeginAffineAnim runs on the creation frame.
  enter(1)
  for _ = 1, age do
    if not state.ended then
      if state.delay > 0 then
        state.delay = state.delay - 1
        local cmd = cmds[state.index]
        if type(cmd) == "table" and type(cmd[1]) == "number" then
          state.x = state.x + (tonumber(cmd[1]) or 0)
          state.y = state.y + (tonumber(cmd[2]) or 0)
          state.rotation = (state.rotation
                            + ((tonumber(cmd[3]) or 0) % 256) * 256) % 65536
        else
          state.ended = true
        end
      else
        enter(state.index + 1)
      end
    end
  end

  -- ObjAffineSet receives ConvertScaleParam(affineStateScale), so the hardware
  -- matrix is reciprocal and the visible sprite grows in direct proportion to
  -- affineStateScale. Positive matrix rotation is the inverse screen-to-texture
  -- mapping, hence the visible angle is its negative.
  return state.x / 0x100, state.y / 0x100,
         -(state.rotation / 65536) * 2 * math.pi,
         tonumber(program.mode) == 3, state.ended
end
Gen3MoveAnim.particleAffineAt = particleAffineAt

-- A semi-transparent OBJ is not ordinary source-alpha compositing on the GBA.
-- Cmd_setalpha writes EVA/EVB and the PPU computes, per opaque OBJ pixel:
--
--   result = OBJ * EVA/16 + destination-BG * EVB/16
--
-- with both coefficients clamped to 16.  Every FireRed move-script particle
-- for which the importer records this state is ST_OAM_OBJ_BLEND and is born
-- while monbg has copied the relevant battler into a BG, so the destination
-- already present in this renderer is the same second target the hardware
-- sees.  Two ordinary LOVE blend passes reproduce that equation without a
-- framebuffer/shader rewrite: black source-alpha first scales the destination,
-- then additive drawing contributes the OBJ term.
local function drawHardwareAlpha(g, image, quad, blend, ...)
  if not (blend and g.setBlendMode) then
    g.setColor(1, 1, 1, 1)
    g.draw(image, quad, ...)
    return
  end
  local eva = math.max(0, math.min(16, tonumber(blend.eva) or 16)) / 16
  local evb = math.max(0, math.min(16, tonumber(blend.evb) or 0)) / 16
  if evb < 1 then
    g.setBlendMode("alpha")
    g.setColor(0, 0, 0, 1 - evb)
    g.draw(image, quad, ...)
  end
  if eva > 0 then
    g.setBlendMode("add")
    g.setColor(eva, eva, eva, 1)
    g.draw(image, quad, ...)
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
end
Gen3MoveAnim.drawHardwareAlpha = drawHardwareAlpha

local function drawHardwareAlphaImage(g, image, blend, ...)
  if not (blend and g.setBlendMode) then
    g.setColor(1, 1, 1, 1)
    g.draw(image, ...)
    return
  end
  local eva = math.max(0, math.min(16, tonumber(blend.eva) or 16)) / 16
  local evb = math.max(0, math.min(16, tonumber(blend.evb) or 0)) / 16
  if evb < 1 then
    g.setBlendMode("alpha")
    g.setColor(0, 0, 0, 1 - evb)
    g.draw(image, ...)
  end
  if eva > 0 then
    g.setBlendMode("add")
    g.setColor(eva, eva, eva, 1)
    g.draw(image, ...)
  end
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
end
Gen3MoveAnim.drawHardwareAlphaImage = drawHardwareAlphaImage

function Gen3MoveAnim:drawEvent(event, battle, Gen3Battle, Assets, pose,
                                allowSplitBlend)
  pose = pose or self:eventPose(event, battle, Gen3Battle)
  if not pose then return false end
  local g = love.graphics
  local age, sheet = pose.age, pose.sheet
  local callbackState = pose.callbackState
  if callbackState and callbackState.invisible then return true end
  local ok, img = pcall(Assets.image, sheet.image)
  local callbackTimed = event.motion == "linear" or event.motion == "arc"
                        or event.motion == "sine30"
                        or event.motion == "single_sine"
                        or event.motion == "callback_linear"
                        or event.motion == "linear_wave"
                        or event.motion == "screen_linear"
                        or event.motion == "powder"
                        or event.motion == "falling_coin"
                        or event.motion == "eruption_rock"
                        or event.motion == "frlg_callback"
  local index
  local commandFlipX, commandFlipY = false, false
  if callbackState and callbackState.selectedAnim and event.selectedHeld then
    index, commandFlipX, commandFlipY =
      timelineState(event.selectedHeld, event.selectedLoops, sheet.frames,
                    callbackState.frameAge or age, true,
                    callbackState.seekAnimCmd or event.seekAnimCmd)
  elseif callbackState and callbackState.alternateAnim and event.alternateHeld then
    index, commandFlipX, commandFlipY =
      timelineState(event.alternateHeld, event.alternateLoops, sheet.frames,
                    callbackState.frameAge or age, true)
  elseif event.forceSelectedAnim and event.selectedHeld then
    index, commandFlipX, commandFlipY =
      timelineState(event.selectedHeld, event.selectedLoops, sheet.frames,
                    age, true)
  elseif event.motion == "water_bubble" and event.travel then
    if age < event.travel then
      index = sheet.held and sheet.held[1] and sheet.held[1][1] or 0
    else
      index = frameAt(sheet, age - event.travel + 1, true)
    end
  else
    index = frameAt(sheet, age,
                    event.motion == "frlg_callback"
                    or (callbackTimed and event.travel ~= nil))
  end
  if index and callbackState and callbackState.tileOffset then
    local tilesWide = math.floor((tonumber(event.width) or 0) / 8)
    local tilesHigh = math.floor((tonumber(event.height) or 0) / 8)
    local frameTiles = tilesWide * tilesHigh
    if frameTiles > 0 then
      index = index + math.floor((tonumber(callbackState.tileOffset) or 0)
                                 / frameTiles)
    end
  end
  if index and callbackState and callbackState.frameOffset then
    index = math.max(0, math.min(math.max(1, sheet.frames or 1) - 1,
                                index + callbackState.frameOffset))
  end
  if pose.orbitX and event.orbit then
    index = math.min(event.orbit.pic or 0, math.max(1, sheet.frames or 1) - 1)
  end
  if not (ok and img and img.getWidth and index) then return false end

  local fw = sheet.frameWidth or img:getWidth()
  local fh = sheet.frameHeight or img:getHeight()
  self.quads = self.quads or {}
  local key = event.sheet .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    quad = love.graphics.newQuad(0, index * fh, fw, fh,
                                 img:getWidth(), img:getHeight())
    self.quads[key] = quad
  end

  local dx, dy = pose.dx, pose.dy
  -- This fan only separates callback families whose motion is still unknown.
  -- It is a presentation fallback, never an input to eventOamY/sorting.
  local fan = not pose.orbitX and not pose.pathX and self.fan and self.fan[event]
  if fan then dx, dy = dx + fan[1], dy + fan[2] end
  local hardwareBlend = callbackState and callbackState.blend or nil
  if not hardwareBlend then
    hardwareBlend = event.monbg
                    and (not event.splitbg or allowSplitBlend)
                    and event.blend or nil
  end

  local affineKey
  if not (callbackState and callbackState.affinePaused) then
    affineKey = callbackState and callbackState.affine1 and event.affine1
                or event.affine0
  end
  local drawFlipX = event.oamFlipX and true or false
  local drawFlipY = event.oamFlipY and true or false
  if commandFlipX then drawFlipX = not drawFlipX end
  if commandFlipY then drawFlipY = not drawFlipY end
  if callbackState and callbackState.flipX then drawFlipX = not drawFlipX end
  if callbackState and callbackState.flipY then drawFlipY = not drawFlipY end

  local manualRotation
  if event.manualRotation == "teal_alert" then
    local attacker = self:battlerForRole(battle, false, 0)
    local target = self:battlerForRole(battle, true, 1)
    local arx = attacker and self:battlerRawCoords(battle, attacker)
    local trx = target and self:battlerRawCoords(battle, target)
    local mirror = self.attackerIsPlayer and 1 or -1
    if arx and trx then
      if arx > trx then mirror = -1
      elseif arx < trx then mirror = 1 end
    end
    local vx = mirror * (event.x or 0)
    local vy = event.y or 0
    local base = math.atan2(vy, vx)
    local gba = math.floor(base / (2 * math.pi) * 65536 + 0.5) % 65536
    local rotation = (-gba + 0x6000) % 65536
    manualRotation = -(rotation / 65536) * 2 * math.pi
  end

  if pose.orbitX then
    local cx = math.floor(pose.centreX + dx)
    local cy = math.floor(pose.centreY + dy)
    g.setScissor(cx - fw / 2, cy - fh / 2, fw, fh)
    drawHardwareAlpha(g, img, quad, hardwareBlend,
                      cx, cy, pose.orbitRotation or 0, 1, 1, fw / 2, fh / 2)
    g.setScissor()
  elseif manualRotation then
    local cx = math.floor(pose.centreX + dx)
    local cy = math.floor(pose.centreY + dy)
    drawHardwareAlpha(g, img, quad, hardwareBlend,
                      cx, cy, manualRotation, 1, 1, fw / 2, fh / 2)
  elseif callbackState and callbackState.affineScaleX
         and callbackState.affineScaleY then
    local cx = math.floor(pose.centreX + dx)
    local cy = math.floor(pose.centreY + dy)
    local clipW = fw * (callbackState.affineDouble and 2 or 1)
    local clipH = fh * (callbackState.affineDouble and 2 or 1)
    g.setScissor(cx - clipW / 2, cy - clipH / 2, clipW, clipH)
    drawHardwareAlpha(g, img, quad, hardwareBlend, cx, cy,
                      callbackState.affineRotation or 0,
                      callbackState.affineScaleX, callbackState.affineScaleY,
                      fw / 2, fh / 2)
    g.setScissor()
  elseif affineKey and self.affines[affineKey] then
    local affineAge = event.callbackFamily == "bone_hit" and age + 1 or age
    local sx, sy, rotation, doubleSize =
      particleAffineAt(self.affines[affineKey], affineAge)
    if sx and sy and rotation then
      local cx = math.floor(pose.centreX + dx)
      local cy = math.floor(pose.centreY + dy)
      local clipW = fw * (doubleSize and 2 or 1)
      local clipH = fh * (doubleSize and 2 or 1)
      g.setScissor(cx - clipW / 2, cy - clipH / 2, clipW, clipH)
      drawHardwareAlpha(g, img, quad, hardwareBlend,
                        cx, cy, rotation, sx, sy, fw / 2, fh / 2)
      g.setScissor()
    end
  elseif drawFlipX or drawFlipY then
    local cx = math.floor(pose.centreX + dx)
    local cy = math.floor(pose.centreY + dy)
    drawHardwareAlpha(g, img, quad, hardwareBlend,
                      cx, cy, 0,
                      drawFlipX and -1 or 1,
                      drawFlipY and -1 or 1,
                      fw / 2, fh / 2)
  else
    drawHardwareAlpha(g, img, quad, hardwareBlend,
                      math.floor(pose.centreX + dx - fw / 2),
                      math.floor(pose.centreY + dy - fh / 2))
  end
  return true
end

function Gen3MoveAnim:draw(battle, skipEvents)
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
      local clipTop = math.max(0, math.floor(layer.clipTop or 0))
      local clipBottom = math.min(bottom, math.floor(layer.clipBottom or bottom))
      if clipBottom > clipTop then
        g.setScissor(0, clipTop, right, clipBottom - clipTop)
      else
        g.setScissor(0, 0, 0, 0)
      end
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
  do
    local battler = self:battlerForRole(battle, false, 0)
    local flourish = self:flourishLayer(battler)
    if flourish and battler then
      local okImg, img = pcall(Assets.image, flourish.image)
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

  if not skipEvents then
    for _, ordered in ipairs(self:eventsForDraw(battle, Gen3Battle)) do
      self:drawEvent(ordered.event, battle, Gen3Battle, Assets)
    end
  end
end

return Gen3MoveAnim
