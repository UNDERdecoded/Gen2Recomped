-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SLATEPORT'S TRAINER FAN CLUB.
--
-- Eight members and a counter, and the port had neither -- so every line in
-- the building printed a hole where a name goes ("I'm a big fan of .") and the
-- count of your fans was always nothing.
--
-- All of it is ONE HALFWORD on the cartridge and the shape is read off the
-- three specials that touch it (see RomExtractorGen3:extractFanClub, whose
-- comment carries the disassembly):
--
--   the low seven bits are a COUNTER of things you have done;
--   bits 8 to 15 are the eight FANS, one bit each;
--   doing something the club notices adds one of four amounts to the counter,
--   and when the total passes nineteen -- with fewer than three fans already
--   listening -- one more joins and the counter starts again.
--
-- A script names a BIT, not a member: `IsFanClubMemberFanOfPlayer` shifts the
-- halfword by whatever is in $8004 and takes the bottom bit, so the numbers in
-- the scripts are 8 to 15 and this file keeps them that way rather than
-- renumbering from one.
--
-- Nothing here invents a number: with no record every question answers the way
-- an empty club does, which is what the building said before any of this
-- existed.

local Gen3FanClub = {}

local function record(data)
  local r = (data and data.constants or {}).gen3FanClub
  if type(r) ~= "table" or type(r.fans) ~= "table" then return nil end
  return r
end
Gen3FanClub.record = record

local function state(save, make)
  if not save then return nil end
  if make then
    save.gen3FanClub = save.gen3FanClub or { counter = 0, fans = {} }
    save.gen3FanClub.fans = save.gen3FanClub.fans or {}
  end
  return save.gen3FanClub
end

-- Is the member at this BIT a fan of the player?
function Gen3FanClub.isFan(save, bit)
  local held = state(save)
  bit = math.floor(tonumber(bit) or -1)
  return (held and held.fans and held.fans[bit]) and true or false
end

function Gen3FanClub.count(game)
  local r = record(game and game.data)
  local held = state(game and game.save)
  if not (r and held and held.fans) then return 0 end
  local n = 0
  for i = 0, r.count - 1 do
    if held.fans[r.firstBit + i] then n = n + 1 end
  end
  return n
end

-- The name the club uses for the member at this bit.  Four of the eight are
-- link trainers on the cartridge and fall back to the same fixed name when
-- there are no link records, which this port never has -- so that is the
-- answer here too, and it is the cartridge's rather than a placeholder.
function Gen3FanClub.nameFor(game, bit)
  local r = record(game and game.data)
  if not r then return nil end
  bit = math.floor(tonumber(bit) or -1)
  for _, fan in ipairs(r.fans) do
    if fan.bit == bit then return fan.name end
  end
  return nil
end

-- TryGainNewFanFromCounter.  `which` picks how much this counts for; the four
-- amounts are the cartridge's.  Answers true when a fan actually joined.
function Gen3FanClub.gain(game, which)
  local r = record(game and game.data)
  local save = game and game.save
  if not (r and save) then return false end
  -- the club has to be running: the cartridge asks one var first and does
  -- nothing at all when it does not answer
  local Gen3Commands = require("src.script.Gen3Commands")
  if Gen3Commands.getVar(save, r.var) ~= r.active then return false end

  local step = r.increments[(math.floor(tonumber(which) or 0)) + 1]
  if not step then return false end
  local held = state(save, true)
  local counter = (math.floor(tonumber(held.counter) or 0)) + step
  if counter <= r.threshold then
    held.counter = counter
    return false
  end
  -- past the threshold: one more joins, but only while the club is still
  -- small.  The counter is only cleared when somebody actually joins, which
  -- is what stops a full club from resetting it every time.
  if Gen3FanClub.count(game) > r.maxFans then
    held.counter = counter
    return false
  end
  for i = 0, r.count - 1 do
    local bit = r.firstBit + i
    if not held.fans[bit] then
      held.fans[bit] = true
      held.counter = 0
      return true
    end
  end
  held.counter = counter
  return false
end

return Gen3FanClub
