-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH PICTURE IS THE ONE FACING SOUTH.
--
-- An overworld sheet out of mmodel.narc is a stack of textures in the
-- archive's own order, and that order is NOT "stand down, stand up, stand
-- left, walk down, ...".  The engine's SpriteRenderer has read every sheet in
-- every earlier generation with those six fixed slots, so a Platinum sheet
-- read the same way puts a BACK view where the standing south frame belongs
-- and a LEFT view where the southward step belongs.  The symptom on screen is
-- precise and was reported as such: the character spins in circles as it
-- walks.
--
-- THE ORDER IS IN THE CARTRIDGE, in the same archive as the sheets.  The last
-- twenty-five members of mmodel.narc are not models at all: they are the
-- BillboardGfxSequence tables, and each one says which texture is showing on
-- each frame of that sprite's animation.  The layout is four fields back to
-- back, exactly as billboard_gfx_sequence.c reads it:
--
--     u32  seqCount
--     u16  startFrame[seqCount]     the animation frame each segment begins on
--     u8   textureIdx[seqCount]     the texture shown from that frame
--     u8   plttIdx[seqCount]        and the palette
--
-- and a frame's texture is the last segment whose startFrame is <= it.
--
-- THE FRAMES ARE GROUPED INTO ANIMATIONS BY A SECOND TABLE, which is code
-- rather than data (object_event_gfx_data.c): a walker's animation N covers
-- frames 16N to 16N+15, and the direction picks N through { 0, 1, 2, 3 } for
-- a walk.  Directions are NORTH, SOUTH, WEST, EAST -- constants/map_object.h
-- -- so the sixteen frames of each animation are four segments of four, and
-- the four segments are that direction's cycle.
--
-- A CYCLE IS stand, step, stand, step.  The two steps are REAL art here: a
-- Platinum sheet carries an east side as well as a west one, so nothing is
-- mirrored and nothing is faked, which is the one place this differs from
-- every earlier generation the renderer serves.
--
-- WHAT THIS REFUSES TO DO IS GUESS.  A member is accepted as a sequence only
-- when its four fields account for its length exactly, its startFrames begin
-- at zero and ascend, and its texture indices stay inside the sheet they are
-- read against.  A sheet is given a cycle table only when the segments divide
-- evenly into four directions.  Anything else is reported, not approximated:
-- a sprite with no cycle table keeps the renderer's classic six slots, which
-- is what it had before this module existed.

local Gen4Facings = {}

local floor = math.floor

-- The twenty-five sequences, in the order the archive stores them.  The NAMES
-- are pret's (res/graphics/field_sprites/field_sprites.order); every number
-- below comes out of the cartridge.  Kept because a count alone cannot tell
-- `generic_walk` from `contest` -- both are sixteen -- and the player's own
-- variants are named sprites, so the name is how they are told apart.
Gen4Facings.SEQUENCE_NAMES = {
  "generic_walk", "walk_and_run", "berry_tree", "bike", "holding_poke_ball",
  "spray_duck", "surf", "starly", "alternating_frames", "contest", "fishing",
  "pokecenter_nurse", "magikarp", "poketch", "save", "heal_pokecenter",
  "arceus", "darkrai", "cresselia", "giratina_altered", "heatran",
  "giratina_origin", "vs_seeker", "unused_1", "unused_2",
}

Gen4Facings.SEQUENCE_COUNT = #Gen4Facings.SEQUENCE_NAMES

-- DIR_NORTH 0, DIR_SOUTH 1, DIR_WEST 2, DIR_EAST 3, and the renderer's own
-- names for the same four.
Gen4Facings.DIRECTIONS = { "up", "down", "left", "right" }

local function u8(data, at)
  local b = data:byte(at + 1)
  return b
end

local function u16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

local function u32(data, at)
  local a, b, c, d = data:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- parse(bytes) -> { count, startFrame[], textureIdx[], plttIdx[], frames },
-- or nil plus the invariant that refused it.  `frames` is the number of
-- animation frames the table covers, which is what the animation grouping is
-- measured in.
function Gen4Facings.parse(bytes)
  if type(bytes) ~= "string" then return nil, "not a string" end
  if #bytes < 8 then return nil, "too short to hold a count" end
  local count = u32(bytes, 0)
  if not count or count < 1 or count > 255 then
    return nil, ("count %s out of range"):format(tostring(count))
  end
  -- THE LENGTH IS THE TEST THAT CANNOT BE FOOLED.  Four fields, one size:
  -- a member that is not this table will not land on it.
  local want = 4 + 2 * count + count + count
  if #bytes ~= want then
    return nil, ("length %d, a %d-entry table is %d"):format(#bytes, count, want)
  end
  local startFrame, textureIdx, plttIdx = {}, {}, {}
  local base = 4
  for i = 1, count do
    local v = u16(bytes, base + (i - 1) * 2)
    if not v then return nil, "ran off the start frames" end
    startFrame[i] = v
  end
  if startFrame[1] ~= 0 then
    return nil, ("first segment begins at %d, not 0"):format(startFrame[1])
  end
  for i = 2, count do
    if startFrame[i] <= startFrame[i - 1] then
      return nil, ("segment %d begins at %d, not after %d")
                  :format(i, startFrame[i], startFrame[i - 1])
    end
  end
  base = 4 + 2 * count
  for i = 1, count do textureIdx[i] = u8(bytes, base + i - 1) end
  base = base + count
  for i = 1, count do plttIdx[i] = u8(bytes, base + i - 1) end

  -- How long the last segment runs is not stored; every sequence in the
  -- cartridge is uniform, so the stride of the ones that ARE stored gives it.
  local stride = count > 1 and (startFrame[2] - startFrame[1]) or 1
  local frames = startFrame[count] + stride
  return {
    count = count, startFrame = startFrame, textureIdx = textureIdx,
    plttIdx = plttIdx, stride = stride, frames = frames,
  }
end

-- textureAt(seq, frame) -> the texture showing on that animation frame.
-- Written the way billboard_gfx_sequence.c reads it -- the last segment that
-- has begun -- rather than by dividing, because a sequence with an uneven
-- stride would divide wrong and this cannot.
function Gen4Facings.textureAt(seq, frame)
  local i = 1
  while i < seq.count and seq.startFrame[i + 1] <= frame do i = i + 1 end
  return seq.textureIdx[i]
end

-- FRAMES PER ANIMATION.  Sixteen for every walker in the cartridge
-- (object_event_gfx_data.c), and stated here rather than derived because it
-- is the one number that is not in the table.
Gen4Facings.WALK_ANIM_FRAMES = 16

-- cycles(seq) -> { up = {a,b,c,d}, down = ..., left = ..., right = ... }
--
-- Only for a sequence whose frames divide into four whole animations of
-- sixteen.  Anything else returns nil and a reason: a berry tree has two
-- textures and no facing at all, and inventing four directions for it would
-- be the same class of mistake this module exists to undo.
function Gen4Facings.cycles(seq, offset)
  if type(seq) ~= "table" then return nil, "no sequence" end
  offset=tonumber(offset) or 0
  local per = Gen4Facings.WALK_ANIM_FRAMES
  if seq.frames < offset + per * 4 then
    return nil, ("%d frames, four walk animations need %d")
                :format(seq.frames, per * 4)
  end
  local out = {}
  for d = 0, 3 do
    local name = Gen4Facings.DIRECTIONS[d + 1]
    local cycle = {}
    local first = offset + d * per
    local at = first
    while at < first + per do
      cycle[#cycle + 1] = Gen4Facings.textureAt(seq, at)
      at = at + seq.stride
    end
    if #cycle < 2 then
      return nil, ("direction %s has %d frames"):format(name, #cycle)
    end
    out[name] = cycle
  end
  return out
end

-- facings(seq, textureCount) -> { down = { stand, step, step }, ... }
--
-- The renderer wants three pictures per side: the one standing still and the
-- two steps.  A cycle is stand, step, stand, step -- its first and third
-- entries are the same pose, which is exactly why a two-step walk reads as a
-- walk -- so the three are entries 1, 2 and 4.  A cycle with only two entries
-- has one step and repeats it, which is what a Game Boy sheet does anyway.
function Gen4Facings.facings(seq, textureCount, offset)
  local cycles, why = Gen4Facings.cycles(seq,offset)
  if not cycles then return nil, why end
  local out = {}
  for _, name in ipairs(Gen4Facings.DIRECTIONS) do
    local c = cycles[name]
    local stand = c[1]
    local step1 = c[2] or c[1]
    local step2 = c[4] or c[2] or c[1]
    if textureCount then
      for _, v in ipairs({ stand, step1, step2 }) do
        if v >= textureCount then
          return nil, ("%s names texture %d of a %d-frame sheet")
                      :format(name, v, textureCount)
        end
      end
    end
    out[name] = { stand, step1, step2 }
  end
  return out
end

-- read(arc) -> { [name] = seq }, { [count] = name }, report
--
-- The sequences are the tail of the archive and are found BY THEIR OWN SHAPE,
-- walking backwards: the last member that parses is the last name in the
-- list, and the walk stops at the first member that does not.  A cartridge
-- that reorders the archive still works; one that does not have these tables
-- returns an empty set and says how far it got, rather than handing back a
-- model's bytes wearing a sequence's name.
function Gen4Facings.read(arc)
  local byName, report = {}, { found = 0, stoppedAt = nil }
  if not arc or not arc.count then return byName, report end
  local names = Gen4Facings.SEQUENCE_NAMES
  local slot = #names
  local member = arc.count - 1
  while member >= 0 and slot >= 1 do
    local bytes = arc:get(member)
    local seq, why = Gen4Facings.parse(bytes)
    if not seq then
      report.stoppedAt = { member = member, reason = why }
      break
    end
    seq.member = member
    seq.name = names[slot]
    byName[names[slot]] = seq
    report.found = report.found + 1
    slot = slot - 1
    member = member - 1
  end
  report.complete = (slot == 0)
  return byName, report
end

-- WHICH SEQUENCE A SHEET USES.
--
-- The cartridge answers this through a table in overlay 5 keyed by graphics
-- id; this answers it by the two things the cache already holds, and says so.
-- The texture count picks a single sequence for every walker in the game --
-- sixteen is `generic_walk`, thirty-two is `walk_and_run` -- and the only
-- collisions are the player's own special sheets, which carry their own names
-- and are matched by name first.
local BY_NAME = {
  player_m_contest = "contest", player_f_contest = "contest",
  dp_player_m_contest = "contest", dp_player_f_contest = "contest",
  player_m_fishing = "fishing", player_f_fishing = "fishing",
  player_m_bike = "bike", player_f_bike = "bike",
  pokecenter_nurse = "pokecenter_nurse",
}

local BY_COUNT = { [16] = "generic_walk", [32] = "walk_and_run" }

-- sequenceFor(label, textureCount) -> name, how
function Gen4Facings.sequenceFor(label, textureCount)
  local named = BY_NAME[label]
  if named then return named, "name" end
  local counted = BY_COUNT[textureCount]
  if counted then return counted, "count" end
  return nil, nil
end

return Gen4Facings
