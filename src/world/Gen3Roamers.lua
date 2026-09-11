-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ONE THAT WON'T STAND STILL.
--
-- Beat the league in Emerald and the television tells you a Pokemon has been
-- seen over Hoenn -- LATIAS or LATIOS, whichever the broadcast names -- and
-- the scene calls special 299 to put it in the air.  This port had no handler
-- for 299 and no Gen 3 roamer at all: `src/world/RoamMons.lua` is Crystal's
-- three-beast byte roll, keyed by names that a Hoenn save has none of, so it
-- answered nothing on every route in the region.  The whole thing was a
-- legendary the game announces and that is nowhere.
--
-- WHAT IT IS, and every rule is the cartridge's:
--
--   * ONE roamer, kept in the save rather than on a map: species, level,
--     IVs, personality, HP and status, plus where it currently is.  The HP
--     is the point of chasing one -- damage carries between meetings.
--   * TWENTY PLACES, with up to five ways out of each.  A map load moves it
--     one step along that graph (RoamerMove, 08161D54)...
--   * ...except one load in sixteen, when it LEAVES the graph entirely and
--     turns up anywhere but where it was (RoamerMoveToOtherLocationSet).
--     That is what makes one genuinely hard to corner.
--   * AND IT WILL NOT DOUBLE BACK onto the map the player was on two loads
--     ago, which is why the location history exists at all.
--   * Meeting it is one wild encounter in four ON THE ROUTE IT IS ON, and it
--     REPLACES that encounter rather than being an extra roll on top
--     (TryStartRoamerEncounter, 08161EDC).
--
-- Fleeing writes the HP and status back and sends it to a fresh place;
-- catching it or knocking it out clears the record, which is the cartridge's
-- `active = 0` and stops every one of the rules above.

local Gen3Roamers = {}

local HISTORY = 3        -- how many maps back the cartridge remembers
local AVOID = 3          -- ...and which of them it will not hop onto

function Gen3Roamers.record(data)
  local r = (data and data.constants or {}).gen3Roamers
  if type(r) == "table" and type(r.places) == "table" and #r.places > 0 then
    return r
  end
  return nil
end

local function held(save, make)
  if type(save) ~= "table" then return nil end
  if make then save.gen3Roamer = save.gen3Roamer or {} end
  local it = save.gen3Roamer
  if type(it) ~= "table" then return nil end
  return it
end

-- The roamer, or nil when there is none -- never released, already caught,
-- or knocked out.  Everything below is a no-op without one, which is the
-- honest state of a save that has not finished the league.
function Gen3Roamers.active(save)
  local it = held(save)
  if not it or it.active ~= true or not it.species then return nil end
  return it
end

local function randInt(rng, n)
  rng = rng or (love and love.math and love.math.random) or math.random
  return rng(0, n - 1)
end

-- Where it starts: any one of the twenty, chosen with no reference to where
-- the player is (CreateInitialRoamerMon picks Random() % 20 and stops).
local function placeAt(record, index)
  return record.places[index] and record.places[index].map or nil
end

-- 299: the scene that releases it.  VAR_0x8004 picks WHICH -- the cartridge
-- loads one species number in each arm of a single branch -- and the level
-- comes off the CreateMon call beside them.
function Gen3Roamers.release(data, save, which, rng)
  local record = Gen3Roamers.record(data)
  if not (record and save) then return nil end
  local species = record.species[math.floor(tonumber(which) or 0)]
             or record.species[0]
  if not species then return nil end
  local it = held(save, true)
  it.species = species
  it.level = math.floor(tonumber(record.level) or 40)
  it.hp = 0                  -- 0 is "make fresh stats", as it is for Gen 2
  it.status = nil
  it.active = true
  it.map = placeAt(record, randInt(rng, #record.places) + 1)
  save.gen3RoamerHistory = {}
  -- ONE INDIVIDUAL, MET AGAIN.
  --
  -- The cartridge makes the Pokemon ONCE here and keeps its personality and
  -- its IVs in the save, rebuilding the same one from them every time you
  -- corner it (CreateMonWithIVsPersonality).  That is the whole point of a
  -- hunt: the LATIOS you chased last week has the same nature, the same
  -- ability and the same shininess this week.  Rolling a fresh one each
  -- meeting is a different Pokemon wearing the same name.
  --
  -- THE IVs ARE THIS PORT'S, and deliberately.  The cartridge's CreateMon
  -- call passes a fixed IV of 32, which is outside the five bits an IV field
  -- has -- what actually ends up stored there is the subject of a documented
  -- hardware quirk, and inventing an answer to it would be worse than saying
  -- so.  The record keeps the number; what this rolls is an ordinary set,
  -- once, and then never again.
  local roll = rng or (love and love.math and love.math.random) or math.random
  it.personality = roll(0, 65535) * 65536 + roll(0, 65535)
  local okIvs, ivs = pcall(function()
    return require("src.pokemon.Stats").randomIVs(roll)
  end)
  it.ivs = okIvs and ivs or nil
  return it
end

-- ------- where it is

function Gen3Roamers.at(save, mapId)
  local it = Gen3Roamers.active(save)
  return it ~= nil and type(mapId) == "string" and it.map == mapId
end

-- The long hop: anywhere but where it stands.  The cartridge rerolls until
-- the place differs, which on twenty places always terminates.
function Gen3Roamers.jump(data, save, rng)
  local record = Gen3Roamers.record(data)
  local it = Gen3Roamers.active(save)
  if not (record and it) then return nil end
  for _ = 1, 64 do
    local pick = placeAt(record, randInt(rng, #record.places) + 1)
    if pick and pick ~= it.map then
      it.map = pick
      return pick
    end
  end
  return it.map
end

-- One map load.  The history goes in first (the cartridge updates it before
-- it moves, so entry 1 is the map you have just walked onto), then the
-- roamer takes one step -- or, one load in sixteen, leaves the graph.
function Gen3Roamers.step(data, save, mapId, rng)
  local record = Gen3Roamers.record(data)
  if not (record and save) then return nil end
  local history = save.gen3RoamerHistory
  if type(history) ~= "table" then history = {}; save.gen3RoamerHistory = history end
  if type(mapId) == "string" then
    table.insert(history, 1, mapId)
    for i = #history, HISTORY + 1, -1 do table.remove(history, i) end
  end
  local it = Gen3Roamers.active(save)
  if not it then return nil end
  local jump = math.floor(tonumber(record.jumpOneIn) or 16)
  if jump > 0 and randInt(rng, jump) == 0 then
    return Gen3Roamers.jump(data, save, rng), "jump"
  end
  -- one step along the graph
  local row
  for _, place in ipairs(record.places) do
    if place.map == it.map then row = place break end
  end
  if not (row and row.nextMaps and #row.nextMaps > 0) then return it.map end
  local avoid = history[AVOID]
  for _ = 1, 64 do
    local pick = row.nextMaps[randInt(rng, #row.nextMaps) + 1]
    if pick and pick ~= avoid then
      it.map = pick
      return pick, "step"
    end
  end
  return it.map
end

-- ------- meeting it
--
-- One encounter in four, and only on the route it is standing on.  The
-- caller has already decided that a wild battle is happening; this says
-- whether THIS one is the roamer instead.
function Gen3Roamers.check(data, save, mapId, rng)
  local record = Gen3Roamers.record(data)
  local it = Gen3Roamers.active(save)
  if not (record and it) then return nil end
  if not Gen3Roamers.at(save, mapId) then return nil end
  local odds = math.floor(tonumber(record.meetOneIn) or 4)
  if odds > 1 and randInt(rng, odds) ~= 0 then return nil end
  return it
end

function Gen3Roamers.encounterFor(data, save)
  local record = Gen3Roamers.record(data)
  local it = Gen3Roamers.active(save)
  if not (record and it) then return nil end
  return {
    species = it.species,
    level = math.floor(tonumber(it.level) or record.level or 40),
    roamerHP = math.floor(tonumber(it.hp) or 0),
    -- the two numbers the cartridge stores, which is all it needs to make
    -- the same Pokemon again
    roamerSeed = it.personality and { personality = it.personality,
                                      ivs = it.ivs } or nil,
    -- the cartridge keeps a status BYTE beside the HP; this port names its
    -- statuses, so what is carried is the name rather than the bitfield --
    -- the same fact in this engine's own spelling
    roamerStatus = it.status,
  }
end

-- ------- after the fight
--
-- It got away: the HP and the status stay on it, and it leaves for a place
-- with no path from where it was -- UpdateRoamerHPStatus ends by calling the
-- long hop, so a roamer you have just met is never on the next route over.
function Gen3Roamers.remember(data, save, hp, status, rng)
  local it = Gen3Roamers.active(save)
  if not it then return false end
  it.hp = math.max(1, math.floor(tonumber(hp) or 0))
  it.status = status or nil
  Gen3Roamers.jump(data, save, rng)
  return true
end

-- Caught, or knocked out: the record goes inactive, which is the whole of
-- the cartridge's `active = 0` and stops the movement, the encounter and the
-- map marker together.
function Gen3Roamers.retire(save)
  local it = held(save)
  if not it then return false end
  it.active = false
  return true
end

return Gen3Roamers
