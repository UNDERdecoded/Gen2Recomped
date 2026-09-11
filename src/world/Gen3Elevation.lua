-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH SPRITES THE MAP'S TOP LAYER COVERS.
--
-- Reported from play: "when walking on bridges it makes my character go under
-- them rather than walking on top of them".  It did, because the port drew
-- every metatile's top layer over every sprite: a bridge deck's rail covers
-- whoever is under the bridge, and it was covering whoever was ON it too.
--
-- The cartridge settles this per sprite, every frame, and it takes three
-- pieces to do it:
--
--   * the field draws its map on three backgrounds, and only ONE of them
--     covers sprites -- the one at priority 1 (sOverworldBgTemplates);
--   * an object's OAM priority is a table lookup on its elevation
--     (UpdateObjectEventZCoordAndPriority, 08096D14): elevation 3, ordinary
--     ground, gives priority 2, and elevation 4, a bridge deck, gives 1;
--   * and the hardware draws a sprite in FRONT of a background when the
--     sprite's priority is less than or equal to the background's.
--
-- So the deck's walkers tie with the covering layer and are drawn on top of
-- it, and everyone else loses to it.  The import reads the first two off the
-- cartridge (extractSpritePriority); the third is the GBA's rule and is
-- written down here rather than derived, because there is nothing in the ROM
-- to derive it from.
--
-- THE ELEVATION IS STICKY, and that is the cartridge's own rule too
-- (ObjectEventUpdateElevation, 08096DB8): the value the priority is looked up
-- with only changes when the cell stepped on names a real level.  0 means
-- "any level" and 15 means "under a bridge", and neither replaces what the
-- object was standing at -- which is exactly what keeps a player who has
-- walked UNDER a bridge (over its 15-marked cells) drawn beneath it.

local Gen3Elevation = {}

-- The cartridge's own table, repeated so a dataset extracted before this rip
-- still draws bridges right.  The record wins wherever it exists.
local FALLBACK = {
  -- elevation 0..15, indexed +1
  priority = { 2, 2, 2, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 0, 0, 2 },
  aboveWhen = 1,
}

local ELEVATION_ANY, ELEVATION_UNDER_BRIDGE = 0, 15

function Gen3Elevation.record(data)
  return (data and data.constants or {}).gen3SpritePriority
end

-- What an object's looked-up elevation becomes after standing on a cell whose
-- elevation is `at`.  Neither wildcard replaces what is held.
function Gen3Elevation.sticky(held, at)
  at = tonumber(at)
  if at == nil or at == ELEVATION_ANY or at == ELEVATION_UNDER_BRIDGE then
    return held
  end
  return math.floor(at)
end

function Gen3Elevation.priorityOf(data, elevation)
  elevation = tonumber(elevation)
  if elevation == nil then return nil end
  local record = Gen3Elevation.record(data)
  local list = (record and record.priority) or FALLBACK.priority
  return list[math.floor(elevation) + 1]
end

-- Is a sprite at this elevation drawn ON TOP of the covering layer?
function Gen3Elevation.aboveTop(data, elevation)
  local priority = Gen3Elevation.priorityOf(data, elevation)
  if priority == nil then return false end
  local record = Gen3Elevation.record(data)
  local when = tonumber(record and record.aboveWhen) or FALLBACK.aboveWhen
  return priority <= when
end

return Gen3Elevation
