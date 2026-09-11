-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE THREE REGI CHAMBERS -- doing what the braille walls say.
--
-- Reading a wall is one half of the puzzle and this is the other, and none of
-- it is script: all three chambers are C on the cartridge, hooked into the
-- field, which is why nothing in the whole script pool opens one and why
-- REGIROCK, REGICE and REGISTEEL could not be reached at all.
--
-- What each wall asks for, and what the cartridge's own code checks, is read
-- by RomExtractorGen3:extractRegiChambers and travels in
-- constants.gen3RegiChambers; that stage's comment carries the disassembly.
-- The three shapes are
--
--   DESERT RUINS   stand on one of three tiles and use ROCK SMASH
--   ANCIENT TOMB   stand on one tile and use FLASH  ("SHINE IN THE MIDDLE")
--   ISLAND CAVE    walk the room's 36-tile perimeter without leaving it,
--                  then stand where you started
--
-- and all three open the same six metatiles with the same sound.
--
-- Nothing here invents a number.  Where the dataset has no record -- a cache
-- imported before this stage existed -- every question below answers "no",
-- which leaves the chambers exactly as shut as they were rather than opening
-- them on a guess.

local Gen3Regi = {}

local function constants(game)
  local data = game and game.data
  return (data and data.constants) or {}
end

function Gen3Regi.record(game)
  local record = constants(game).gen3RegiChambers
  if type(record) ~= "table" then return nil end
  return record
end

-- The chamber a map is, if it is one.
--
-- THE SEALED CHAMBER COUNTS AS ONE.  It is the fourth braille wall and the
-- first in order: ShouldDoBrailleDigEffect (1795E8) has the same three lines
-- as the other two field-move tests -- flag clear, right map, right tile --
-- and DoBrailleDigEffect lays the SAME SIX METATILES the Regi doors do.  Its
-- coordinates are its own, which is why the wall travels on the chamber
-- rather than being taken from the shared door below.
function Gen3Regi.chamberFor(game, mapId)
  local record = Gen3Regi.record(game)
  if not (record and mapId) then return nil end
  for _, chamber in ipairs(record.chambers or {}) do
    if chamber.map == mapId then return chamber end
  end
  local sealed = record.sealedChamber
  if sealed and sealed.map == mapId then return sealed end
  return nil
end

local function flagSet(game, key)
  local flags = game and game.save and game.save.flags
  return (flags and flags[key]) and true or false
end
Gen3Regi.flagSet = flagSet

-- Is the player standing where this chamber's field move would do something?
-- Both C tests are the same three lines -- the flag is clear, the map is the
-- chamber's, the position is one of the listed ones -- so both are this.
function Gen3Regi.spotHere(game, ow, move)
  local map = ow and ow.map
  local player = ow and ow.player
  if not (map and player) then return nil end
  local chamber = Gen3Regi.chamberFor(game, map.id)
  if not (chamber and chamber.move) then return nil end
  if move and chamber.move ~= move then return nil end
  if flagSet(game, chamber.flag) then return nil end
  for _, spot in ipairs(chamber.spots or {}) do
    if player.cellX == spot[1] and player.cellY == spot[2] then
      return chamber
    end
  end
  return nil
end

-- The six metatiles, the sound and the flag -- every one of them off the
-- cartridge's own door script.
function Gen3Regi.open(game, ow, chamber)
  local record = Gen3Regi.record(game)
  if not (record and ow and ow.map and chamber) then return false end
  local map = ow.map
  -- the chamber's own wall when it has one -- the Sealed Chamber's six sit
  -- at (9..11, 1..2) rather than the Regi rooms' (7..9, 19..20), even though
  -- the tiles themselves are identical
  for _, tile in ipairs(chamber.door or record.door or {}) do
    if map.setBlock then
      map:setBlock(tile.x, tile.y, tile.tile,
                   (tonumber(tile.impassable) or 0) ~= 0)
    end
  end
  if ow.redrawBlocks then ow:redrawBlocks(map) end
  -- `playse 20` names a slot in the same table every other script sound
  -- comes out of, and the VM spells that slot SONG_%03X -- so the door's
  -- sound is the door script's own rather than a name picked here.
  local sound = tonumber(record.sound)
  if sound then
    require("src.core.Sound").play(game.data, ("SONG_%03X"):format(sound))
  end
  local flags = game.save and game.save.flags
  if flags then flags[chamber.flag] = true end
  return true
end

-- ---------------------------------------------------------------------------
-- ISLAND CAVE'S LAP
--
-- gSpecials[498] is called twice on the cartridge: once by the wall's own
-- script, which sets the "running" flag first, and once per step by the field
-- controller.  Each call marks the tile the player is on, and a call that
-- finds the player OFF the path breaks the lap.  The 36 bits live in three
-- vars because that is where the cartridge puts them -- sixteen to a var,
-- four left over -- and keeping them there is what makes a save written by
-- this port and a save written by the cartridge say the same thing about a
-- half-run lap.
-- ---------------------------------------------------------------------------

function Gen3Regi.lapOf(game, mapId)
  local chamber = Gen3Regi.chamberFor(game, mapId)
  local lap = chamber and chamber.lap
  if type(lap) ~= "table" or type(lap.path) ~= "table" then return nil end
  return chamber, lap
end

-- Which entry of the path the player is on, or nil.
function Gen3Regi.pathIndex(lap, x, y)
  for i, tile in ipairs(lap.path) do
    if tile[1] == x and tile[2] == y then return i end
  end
  return nil
end

-- The bit for path entry i (1-based here, 0-based on the cartridge), as
-- var, bit.
function Gen3Regi.bitFor(lap, index)
  local bits = tonumber(lap.varBits) or 16
  local zero = index - 1
  local slot = math.floor(zero / bits) + 1
  local var = (lap.vars or {})[slot]
  if not var then return nil end
  return var, zero % bits
end

-- Every bit the lap needs, per var: the leading vars are full and the last
-- holds the remainder.  Derived from the path's own length rather than
-- written down, so a dataset with a different path checks a different mask.
function Gen3Regi.masks(lap)
  local bits = tonumber(lap.varBits) or 16
  local out = {}
  local left = #lap.path
  for _, var in ipairs(lap.vars or {}) do
    if left <= 0 then break end
    local here = math.min(bits, left)
    out[#out + 1] = { var = var, mask = 2 ^ here - 1 }
    left = left - here
  end
  return out
end

return Gen3Regi
