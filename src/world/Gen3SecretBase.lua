-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SECRET BASES: the way in.
--
-- Reported from play: "secret power to create secret bases also arent working
-- it does nothing when i have the move taught to my pokemon and hit a on a
-- secret base area".  Nothing was the honest answer -- the entrances were all
-- there (75 bg events across thirteen maps, each carrying its own base id) and
-- there was no handler for any of them, so the press fell through to the
-- sign branch and a sign with no text says nothing.
--
-- WHAT A BASE IS, on this cartridge:
--
--   * an ENTRANCE, which is a bg event of kind 8 on a route or in a cave,
--     answered only when the player is facing NORTH into it (080C9510);
--   * a BASE ID, which the entrance carries, and which divided by ten names
--     one of twenty-four rooms in map group 25 (see extractSecretBases);
--   * a SPOT KIND -- a tree, a bush, a cave wall -- read off the METATILE in
--     front of the player rather than out of any table, which is what decides
--     the animation and the words;
--   * and the WAY BACK, which is the cartridge's dynamic warp: the room's one
--     exit names map 127 of group 127, and going in is what fills that in.
--     This port already resolves that pair (the truck a new game starts in is
--     built out of it), so leaving needs nothing new.
--
-- THIS SLICE IS THE ENTRANCE.  A base can be made, entered and left.  What it
-- does NOT do yet is furnish it: decorations, the registry, and other
-- players' bases are their own pieces of work, and the specials that serve
-- them say so rather than pretending.

local Gen3SecretBase = {}

-- The cartridge's own numbers, repeated for a dataset imported before the rip
-- so the entrance still lands somewhere real.
local FALLBACK = { perGroup = 10, group = 25 }

function Gen3SecretBase.record(data)
  return (data and data.constants or {}).gen3SecretBases
end

-- WHICH ROOM a base id opens into.  Ten ids share a room -- the cartridge
-- gives each of the twenty-four rooms ten entrances scattered over the region
-- -- so this is a divide, not a lookup per entrance.
function Gen3SecretBase.roomFor(record, baseId)
  baseId = math.floor(tonumber(baseId) or 0)
  if baseId < 1 then return nil end
  local per = math.floor(tonumber(record and record.perGroup)
                         or FALLBACK.perGroup)
  if per < 1 then return nil end
  local rooms = record and record.rooms
  if type(rooms) ~= "table" then return nil end
  return rooms[math.floor(baseId / per) + 1]
end

-- WHICH KIND OF SPOT a BEHAVIOUR BYTE is, or nil for anything that is not
-- one.  The keys are 144..157 -- the behaviours 080E8BF8 compares against --
-- and NOT metatile ids, which at Hoenn's 75 entrance cells are 38, 39, 416,
-- 424, 432, 520 and 625.  Feeding this a metatile id misses every time.
function Gen3SecretBase.kindOf(record, behaviour)
  local kinds = record and record.kinds
  behaviour = tonumber(behaviour)
  if type(kinds) ~= "table" or not behaviour then return nil end
  return kinds[math.floor(behaviour)]
end

function Gen3SecretBase.mine(save)
  local held = save and save.gen3SecretBase
  if type(held) == "table" and tonumber(held.id) then return held end
  return nil
end

-- The base the player is making theirs, and where they were standing when
-- they made it -- which is where the room's exit has to put them back.
function Gen3SecretBase.claim(save, baseId, map, x, y)
  if not save then return nil end
  save.gen3SecretBase = { id = math.floor(tonumber(baseId) or 0),
                          map = map, x = x, y = y }
  return save.gen3SecretBase
end

-- GIVING ONE UP, which is not the same as leaving one.
--
-- Walking out of a base is a warp and nothing else -- the room's exit is the
-- come-back-out marker.  These three specials are the PC's RETIRE row and the
-- "move my base here" flow, and what they do is clear the record: 9 and 10
-- clear it and walk you out, 332 clears it while you are already outside.
function Gen3SecretBase.giveUp(save)
  if not save then return false end
  local had = save.gen3SecretBase ~= nil
  save.gen3SecretBase = nil
  return had
end

-- Going in: the way back is the dynamic warp, exactly as the cartridge sets
-- it (SetWarpDestination(0, curGroup, curNum, -1) at the top of the enter
-- task), and this port's warp resolver already reads that.
-- The base rooms all live in one map group, so "is this a base room" is a
-- question about the id and needs no table.
function Gen3SecretBase.isRoom(record, mapId)
  if type(mapId) ~= "string" then return false end
  local group = math.floor(tonumber(record and record.group)
                           or FALLBACK.group)
  return mapId:match("^MAP_G(%d+)_N") == ("%02d"):format(group)
end

function Gen3SecretBase.remember(save, map, x, y, record)
  if not save then return end
  -- THE WAY BACK CANNOT BE THE ROOM ITSELF.
  --
  -- Reported from play: "after making a secret base when i try and exit it
  -- puts me right back in the secret base room".  The room's one exit names
  -- the dynamic warp and nothing else, so whatever last wrote that is where
  -- the door goes -- and if anything writes it while you are standing INSIDE
  -- (the enter special running a second time, a script inside the room
  -- setting it), the exit becomes a door back into the room you are in.
  --
  -- Refusing to record a base room is not a guess about which of those
  -- happened: there is no arrangement in which the way OUT of a base is a
  -- base.  With nothing else recorded the old value stands, which is the
  -- outside spot, and the warning says the write was refused.
  if map == nil then
    require("src.core.Logger").warn(
      "gen3 secret base: nowhere recorded to come back out to -- the exit "
      .. "will use whatever was set before it")
    return
  end
  if Gen3SecretBase.isRoom(record, map) then
    require("src.core.Logger").warn(
      "gen3 secret base: refused to make %s the way out of a base -- it IS "
      .. "one", tostring(map))
    return
  end
  save.gen3DynamicWarp = { map = map, x = x, y = y, warp = 0xFF }
end

-- WHERE IN THE ROOM YOU LAND, which is not the same question as which room.
--
-- The enter-warp (080E8F9C) names a WARP id and lets the map's own warp table
-- place you; the newly-made enter (080E9168) does not -- it reads two more
-- bytes off the same row and hands them to SetWarpDestination as x and y.
-- The two are the same cell, but only the second is written down, and it is
-- the second that special 24 needs.
function Gen3SecretBase.entranceFor(record, baseId)
  local room = Gen3SecretBase.roomFor(record, baseId)
  if not (room and room.map and room.x and room.y) then return nil end
  return room, room.x, room.y
end

-- THE PC IN THE ROOM, as a behaviour byte rather than an object.
--
-- Reported from play: "the pc in the secret base room doesnt work".  It is a
-- metatile -- 0x220 in the base tileset, behaviour $B0 for your own base and
-- $B1 for someone else's -- and the field answers it the same way it answers
-- a Poke Centre PC: GetInteractedMetatileScript hands back a script address.
-- Nothing walks a map's events to find it, which is why every search for one
-- came up empty.
function Gen3SecretBase.pcScriptFor(record, behaviour)
  local pc = record and record.pc
  behaviour = tonumber(behaviour)
  if type(pc) ~= "table" or not behaviour then return nil end
  behaviour = math.floor(behaviour)
  for _, key in ipairs({ "own", "friend" }) do
    local arm = pc[key]
    if type(arm) == "table" and tonumber(arm.behaviour) == behaviour then
      return arm.script, key
    end
  end
  return nil
end

-- ------- the registry, which in a game with no link cable is empty
--
-- The friend's-base PC registers other players so their bases keep their
-- decorations and their party between visits; the twenty slots behind it are
-- SaveBlock1 + 1A9C, stride 160, and the two registry bits are bits 6-7 of
-- the byte after the id (080E9C2C flips exactly those two).  Nothing in a
-- single-player save ever fills a slot, so these answer honestly rather than
-- pretending: the list is empty and toggling has nothing to toggle.
function Gen3SecretBase.registered(save)
  local held = save and save.gen3 and save.gen3.secretBaseRegistry
  return type(held) == "table" and held or {}
end

function Gen3SecretBase.registryState(save, index)
  local row = Gen3SecretBase.registered(save)[math.floor(tonumber(index) or 0)]
  return row and row.registered == true or false
end

function Gen3SecretBase.toggleRegistry(save, index)
  local row = Gen3SecretBase.registered(save)[math.floor(tonumber(index) or 0)]
  if not row then return nil end
  row.registered = not row.registered
  return row.registered
end

return Gen3SecretBase
