-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EVERY DOOR IN SINNOH OPENED IN SILENCE.
--
-- `loaddooranimation`, `playdooropenanimation` and `playdoorcloseanimation`
-- lowered onto `g4_noop` with the subject "door animations", and measured over
-- the whole decoded script corpus they are **194 invocations** -- the single
-- largest declined subject in the port, ahead of the money box (109) and the
-- journal (78).
--
-- The comment that declined them said the port "has no SE bank for Gen 4 yet".
-- That was true when it was written and is not any more: `audio.lua` carries
-- **2,030 sound effects**, keyed by numeric id AND by the cartridge's own SSEQ
-- symbol, and `g4_play_sound` has been routing `playse` through them all along.
-- A declined feature outliving its blocker is the same shape as
-- `g4_overworld_weather`'s "the port keeps no saved weather" -- so the first
-- thing this module is, is a re-measurement of a stale claim.
--
-- WHAT IS STILL MISSING, stated up front: the ANIMATION -- but NOT for the
-- reasons this comment used to give, both of which were already false when
-- it was written and are corrected here by pass 183.
--
-- It said "this port reads NSBMD without NSBCA and bakes a chunk's props into
-- a flat canvas". NSBCA is read (`Gen4Anim.jointMatrices`, worn by the title
-- sequence and the starter models) and props are NOT baked -- `Gen4Ground`
-- draws every one as a live model each frame, and `Gen4Model:draw` takes a
-- pose as its second argument. So this module's own opening paragraph, about
-- a stale claim outliving its blocker, applied to the paragraph below it.
--
-- The real blocker was the JOIN: which of `bm_anime.narc`'s 98 animations
-- belongs to which prop. `src/import/Gen4PropAnim.lua` has it now, from
-- `bm_anime_list.narc`, and `Gen4Doors.animationFor` below answers it for
-- all twenty doors. What is left is threading a pose into the prop draw.
--
-- The sound was, and is, available and audible on all 194 of them.
--
-- THE SOUND IS CHOSEN FROM THE DOOR'S MODEL, which is why this is not a
-- one-line change: `DoorAnimation_PlayOpenAnimation` asks
-- `DoorAnimation_GetSoundEffectType(doorModelID)`, and the model comes from
-- `DoorAnimation_FindDoorAndLoad`'s search of the loaded map props. Defaulting
-- every door to the hinged creak would be wrong in every Pokemon Centre, gym
-- and lift in the region -- 76 of the placed door props.
local Gen4Doors = {}

local Logger = require("src.core.Logger")

Gen4Doors.MODEL_PATH = "/fielddata/build_model/build_model.narc"

-- `doorModelIDs[]` in `DoorAnimation_FindDoorAndLoad`, IN ORDER. The order is
-- not load-bearing for the sound -- the function searches the whole list -- but
-- it is kept so the check can compare this against pret row for row rather
-- than as a set, which is the comparison that catches a dropped entry.
Gen4Doors.MODELS = {
  "door01",
  "brown_wooden_door",
  "green_wooden_door",
  "iron_door",
  "jubilife_city_building_door",
  "pokecenter_door",
  "pokecenter_inside_door",
  "gts_inside_door",
  "hearthome_gym_inside_door",
  "blue_door",
  "iron_door_2",
  "yellow_wooden_door",
  "blue_wooden_door",
  "mansion_door",
  "veilstone_dpt_store_door",
  "gym_door",
  "card_door",
  "pokecenter_inside_counter_door",
  "hotel_grand_lake_door",
  "elevator_door",
}

-- `DoorAnimation_GetSoundEffectType`, which is three arms and names six models
-- in the middle one:
--
--     if (id == veilstone_dpt_store_door)            -> VEILSTONE_DPT_STORE_CHIME
--     if (id == pokecenter_door || gym_door || gts_inside_door
--         || pokecenter_inside_door || card_door || elevator_door) -> SLIDING
--     otherwise                                      -> HINGED
Gen4Doors.CHIME = { veilstone_dpt_store_door = true }
Gen4Doors.SLIDING = {
  pokecenter_door = true,
  gym_door = true,
  gts_inside_door = true,
  pokecenter_inside_door = true,
  card_door = true,
  elevator_door = true,
}

function Gen4Doors.soundType(name)
  if Gen4Doors.CHIME[name] then return "chime" end
  if Gen4Doors.SLIDING[name] then return "sliding" end
  return "hinged"
end

-- THE SOUNDS, BY THE CARTRIDGE'S OWN SSEQ SYMBOL rather than by number.
-- `audio.lua` keys its 2,030 effects under both the numeric id and the symbol,
-- so naming the symbol here means a re-import that renumbers the archive does
-- not silently play a different sound -- and the check can assert the join.
--
-- `false` IS NOT "the same as hinged". A sliding door and the Veilstone chime
-- play NOTHING on close: `DoorAnimation_PlayCloseAnimation` sets
-- `soundEffectID = 0` for both and only the hinged arm gets
-- `SEQ_SE_DP_DOOR_CLOSE2`. A pneumatic door that creaked shut would be
-- audibly wrong in every Pokemon Centre.
Gen4Doors.SOUND = {
  hinged  = { open = "SEQ_SE_DP_DOOR_OPEN",  close = "SEQ_SE_DP_DOOR_CLOSE2" },
  sliding = { open = "SEQ_SE_DP_DOOR10",     close = false },
  chime   = { open = "SEQ_SE_PL_DOOR_OPEN5", close = false },
}

-- The SSEQ symbol for a model and an action, or false when the cartridge plays
-- nothing, or nil when the model is not a door this module knows.
function Gen4Doors.soundNameFor(model, action)
  local row = Gen4Doors.SOUND[Gen4Doors.soundType(model)]
  if not row then return nil end
  local name = row[action]
  if name == nil then return nil end
  return name
end

-- ---------------------------------------------------------------------------
-- the model join
-- ---------------------------------------------------------------------------

-- build_model member index <-> name, both ways, worked out once.
local index, nameOf
local function join()
  if index then return index, nameOf end
  index, nameOf = {}, {}
  local okA, A = pcall(require, "src.import.Gen4Archives")
  if not okA or not A or not A.find then return index, nameOf end
  for _, name in ipairs(Gen4Doors.MODELS) do
    local i = A.find(Gen4Doors.MODEL_PATH, name .. ".nsbmd")
    if i then index[name] = i; nameOf[i] = name end
  end
  return index, nameOf
end
Gen4Doors.join = join

function Gen4Doors.indexOf(name)
  local idx = join()
  return idx[name]
end

function Gen4Doors.modelNameOf(member)
  local _, names = join()
  return names[member]
end

-- ---------------------------------------------------------------------------
-- the search, which is the cartridge's hitbox
-- ---------------------------------------------------------------------------
--
-- `TerrainCollisionHitbox_Init(x, z, -1, 0, 3, 1, &hitbox)` -- a box starting
-- ONE TILE LEFT of the named tile, three tiles wide and one deep. A door prop
-- is anchored on a half-tile, so a box of exactly one tile would miss most of
-- them; the cartridge's three-wide window is why it does not.
--
-- The script's operands are MATRIX coordinates and a tile within that chunk:
--
--     x = mapX * MAP_TILES_COUNT_X + tileX     (32 tiles to a chunk)
--
-- which is the same space `Gen4Ground` draws in, so `def.layout` names the
-- matrix and `matrices[layout].land[mapZ * width + mapX + 1]` names the chunk.
-- A map's `originX`/`originY` crop does NOT enter into it: a matrix cell is
-- absolute within its matrix.
Gen4Doors.HITBOX_OFFSET_X = -1
Gen4Doors.HITBOX_SIZE_X = 3
Gen4Doors.HITBOX_SIZE_Z = 1

-- VERIFIED AGAINST THE CARTRIDGE, and this is the measurement that made the
-- whole pass possible: of the 52 `loaddooranimation` sites in the ROM, the 15
-- on a region map resolve **15 of 15** through this search, and the 37 on an
-- indoor map have a door prop in the hitbox for 33 of them. See
-- tools/gen4_door_sound_check.lua.
function Gen4Doors.modelAt(data, def, mapX, mapZ, tileX, tileZ)
  local terrain = data and data.gen4_terrain
  if type(terrain) ~= "table" then return nil, "this cache has no gen4_terrain" end
  local grid = terrain.matrices and def and terrain.matrices[def.layout]
  if type(grid) ~= "table" or type(grid.land) ~= "table" then
    return nil, ("map %s names matrix %s, which this cache has no grid for")
                  :format(tostring(def and def.id), tostring(def and def.layout))
  end
  local w, h = grid.width or 0, grid.height or 0
  if mapX < 0 or mapZ < 0 or mapX >= w or mapZ >= h then
    return nil, ("matrix cell %d,%d is outside the %dx%d grid"):format(mapX, mapZ, w, h)
  end
  local land = grid.land[mapZ * w + mapX + 1]
  local record = land and terrain.chunks and terrain.chunks[land]
  if type(record) ~= "table" then
    return nil, ("matrix cell %d,%d names chunk %s, which has no record")
                  :format(mapX, mapZ, tostring(land))
  end
  local half = (terrain.chunkUnits or 512) / 2
  local unit = terrain.tileUnits or 16
  local x0 = tileX + Gen4Doors.HITBOX_OFFSET_X
  local z0 = tileZ
  local _, names = join()
  for _, o in ipairs(record.objects or {}) do
    local name = names[o.model]
    if name then
      -- the prop's own tile, with the chunk's origin at its CENTRE
      local px = ((tonumber(o.x) or 0) + half) / unit
      local pz = ((tonumber(o.z) or 0) + half) / unit
      if px >= x0 and px < x0 + Gen4Doors.HITBOX_SIZE_X
         and pz >= z0 and pz < z0 + Gen4Doors.HITBOX_SIZE_Z then
        -- THE OBJECT ITSELF comes back as a third return, because it is the
        -- same table `Gen4Ground` iterates: both read
        -- `terrain.chunks[land].objects`.  Carrying it by identity is what
        -- lets a one-shot animation find the prop it belongs to without a
        -- second coordinate search that could disagree with this one.
        --
        -- Third rather than second so every existing `local model, why =
        -- Gen4Doors.modelAt(...)` caller keeps the reason in `why`.
        return name, nil, { object = o, land = land }
      end
    end
  end
  return nil, ("no door prop in the hitbox at matrix %d,%d tile %d,%d (chunk %s)")
                :format(mapX, mapZ, tileX, tileZ, tostring(land))
end

-- ---------------------------------------------------------------------------
-- playing it
-- ---------------------------------------------------------------------------
--
-- WHEN THE MODEL IS UNKNOWN THE DOOR STILL MAKES A SOUND, and `hinged` is the
-- right default rather than silence: it is what the cartridge plays for every
-- model it does not name specially, and 111 of the 190 door props placed in
-- the terrain are hinged. The cartridge's own answer to "no door found" is
-- `GF_ASSERT(FALSE)`, which is to say it does not expect this -- so it is
-- logged once per reason, not swallowed.
local saidWhy = {}

function Gen4Doors.play(game, model, action)
  local data = game and game.data
  local name = Gen4Doors.soundNameFor(model or "unknown-door", action)
  if name == false then return true end          -- the cartridge plays nothing
  if name == nil then return false end
  -- THE SYMBOL IS HANDED STRAIGHT TO `Sound.play`, which looks its argument up
  -- in `data.audio.sfx` -- and that table is keyed by the SSEQ symbol as well
  -- as by the numeric id, so resolving the number here would be a second
  -- spelling of a join the engine already does.
  --
  -- The presence check stays, because `Sound.play` returns nil for a name it
  -- cannot find and a silent door is exactly what this pass is fixing: an
  -- absent symbol has to be reported rather than look like success.
  local sfx = data and data.audio and data.audio.sfx
  if not (sfx and sfx[name]) then
    if not saidWhy[name] then
      saidWhy[name] = true
      Logger.warn("gen4 door: this cache has no sound effect named %s, so the "
                  .. "door is silent -- re-import to pick up the SDAT symbols",
                  name)
    end
    return false
  end
  local okS, Sound = pcall(require, "src.core.Sound")
  if not okS or not Sound or not Sound.play then return false end
  Sound.play(data, name)
  return true
end

function Gen4Doors.note(reason)
  if not reason or saidWhy[reason] then return end
  saidWhy[reason] = true
  Logger.info("gen4 door: %s, so the hinged sound is played -- the model "
              .. "decides which of the three the cartridge uses and this one "
              .. "could not be identified", reason)
end

-- ---------------------------------------------------------------------------
-- the animation join (pass 183)
-- ---------------------------------------------------------------------------
--
-- Delegated rather than copied: `Gen4PropAnim` owns the `bm_anime_list`
-- record and the twenty rows, because the join is a map-PROP fact and the
-- doors are one consumer of it. Honey trees and the elevator platform are
-- others, and a second copy of the table here is how they would drift.

-- animationFor(model, action) -> bm_anime member id, or nil
--
-- `open` is animation index 0 and `close` is index 1, for a two-animation
-- door and a four-animation one alike -- both of pokeplatinum's arms collapse
-- to the same index and the other two animations of a four are never played
-- by the door path.
function Gen4Doors.animationFor(model, action)
  local okP, P = pcall(require, "src.import.Gen4PropAnim")
  if not okP or not P then return nil end
  return P.animationFor(model, action)
end

-- THE COUNT IS NOT THE SOUND TYPE. Eleven hinged doors have four
-- animations; `mansion_door` and `pokecenter_inside_counter_door` are hinged
-- with two, and `mansion_door` shares its pair with the Veilstone chime while
-- playing the hinged creak. `soundType` above and this are two axes.
function Gen4Doors.animationCount(model)
  local okP, P = pcall(require, "src.import.Gen4PropAnim")
  if not okP or not P then return nil end
  return P.countFor(model)
end

-- ...and one of the twenty is not a joint animation at all: `elevator_door`
-- is BTP0, a texture-pattern flipbook, which `Gen4TexAnim` already renders.
function Gen4Doors.animatesByTexture(model)
  local okP, P = pcall(require, "src.import.Gen4PropAnim")
  if not okP or not P then return false end
  return P.isTexturePattern(model)
end

return Gen4Doors
