-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A DARK CAVE IN HOENN IS A HOLE, NOT A SHADE.
--
-- The port already knew which seven maps need FLASH -- the map header says so
-- and OverworldState.isDarkMap reads it -- and then drew them the way Kanto
-- and Johto are drawn: the whole picture one shade darker, uniformly, to the
-- edges of the screen.  That is the Game Boy's darkness and it is not
-- Emerald's.  Emerald draws the map at full brightness and lays a black
-- window over it with a CIRCLE cut out around the player; how big that circle
-- is IS the mechanic, and it is why FLASH is a Hidden Machine rather than a
-- convenience:
--
--     level 7   radius 24   a cave you walked into without FLASH
--     level 1   radius 72   the same cave after you use it
--     level 0   radius 200  bigger than the screen -- no darkness at all
--
-- The radii, the levels, the flag and the centre are all read off the
-- cartridge by RomExtractorGen3:extractFlash; that stage's comment carries the
-- disassembly.  Nothing here invents a number: with no record the questions
-- below answer "no darkness", which leaves a cave lit rather than guessing a
-- radius and drawing a hole in the wrong place.
--
-- WHERE THE HOLE GOES.  The cartridge centres it on (120,80), the middle of
-- the GBA screen, because the field camera keeps the player there.  This port
-- lets the window be other sizes, so the centre is taken from where the player
-- actually IS -- which is the same point whenever the view is 240x160 and
-- stays right when it is not.

local Gen3Flash = {}

local function record(data)
  local r = (data and data.constants or {}).gen3Flash
  if type(r) ~= "table" or type(r.radii) ~= "table" then return nil end
  return r
end
Gen3Flash.record = record

-- radii[level + 1] -- see the record's own comment about the off-by-one
function Gen3Flash.radiusOf(data, level)
  local r = record(data)
  if not r then return nil end
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > (tonumber(r.maxLevel) or 0) then level = r.maxLevel end
  return tonumber(r.radii[level + 1])
end

-- HAS FLASH BEEN USED?  Two answers have to be one.
--
-- The port has kept this in `save.flashLit` since Kanto, and the cartridge
-- keeps it in an ordinary script flag -- $888, which extractFlash reads out of
-- SetDefaultFlashLevel and files as `record.flag`.  Nothing joined them, so a
-- real Emerald save that had used FLASH arrived here with the flag set and
-- `flashLit` unset, and walked into Granite Cave at a radius of 24; and a port
-- save exported the other way told the cartridge FLASH had never been used.
--
-- The flag is the truth where the record names one, because that is what
-- survives a round trip through a .sav; `flashLit` is kept in step for the
-- generations that have no such flag and for a dataset with no record.
function Gen3Flash.lit(game)
  local save = game and game.save
  if not save then return false end
  local r = record(game.data)
  local key = r and r.flag
  if key and save.flags and save.flags[key] ~= nil then
    return save.flags[key] and true or false
  end
  return save.flashLit and true or false
end

function Gen3Flash.setLit(game, on)
  local save = game and game.save
  if not save then return end
  on = on and true or nil
  save.flashLit = on
  local r = record(game.data)
  if r and r.flag then
    save.flags = save.flags or {}
    save.flags[r.flag] = on
  end
end

-- Overworld_SetFlashLevel: out of range means 0, which is "no darkness".
function Gen3Flash.setLevel(game, level)
  local save = game and game.save
  if not save then return 0 end
  local r = record(game.data)
  local max = r and tonumber(r.maxLevel) or 0
  level = math.floor(tonumber(level) or 0)
  if level < 0 or level > max then level = 0 end
  save.gen3FlashLevel = level
  return level
end

function Gen3Flash.level(game)
  return math.floor(tonumber(game and game.save and game.save.gen3FlashLevel)
                    or 0)
end

-- SetDefaultFlashLevel, which runs on every map load: not a cave, no darkness;
-- a cave you have used FLASH in, the lit level; a cave you have not, the dark
-- one.  `lit` here is the port's own save bit -- the same one the FLASH menu
-- entry sets -- and the cartridge's flag name travels beside it in the record
-- so a save converted either way agrees about which it is.
function Gen3Flash.defaultFor(game, isCave, lit)
  local r = record(game and game.data)
  if not r then return Gen3Flash.setLevel(game, 0) end
  if not isCave then return Gen3Flash.setLevel(game, 0) end
  return Gen3Flash.setLevel(game, lit and r.lit or r.dark)
end

-- The circle to cut, or nil when there is no darkness to draw.  `radius` is
-- nil at level 0 and at any level whose radius covers the whole view, so the
-- caller never draws a window it cannot see the edge of.
function Gen3Flash.circle(game, viewW, viewH)
  local r = record(game and game.data)
  if not r then return nil end
  local level = Gen3Flash.level(game)
  if level <= 0 then return nil end
  local radius = Gen3Flash.radiusOf(game.data, level)
  if not radius or radius <= 0 then
    -- the darkest level the table has closes the window completely; the
    -- cartridge does not use it, but a script may set it
    return { radius = 0 }
  end
  -- bigger than the corner of the view is the same as no darkness
  local w = (tonumber(viewW) or r.screen[1]) / 2
  local h = (tonumber(viewH) or r.screen[2]) / 2
  if radius * radius >= w * w + h * h then return nil end
  return { radius = radius }
end

return Gen3Flash
