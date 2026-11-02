-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S SOUNDPLATES: the ambient sounds a map chunk plays
-- where the player stands (pokeheartgold src/field/field_control.c,
-- FieldSystem_ProcessSoundplateAtCoords; include/field/field_control.h).
--
-- Every land chunk (/a/0/6/5) opens with u16 0x1234 and a u16 size, then
-- size / 8 plates (Gen4Maps.land's `backgroundSounds`), each
--   u8 soundplateSoundID, u8 volumeIndex, u8, u8, u8 x, u8 z, u8 xBounds, u8 zBounds
-- in the chunk's own 0..31 tile coordinates (GetLocalSoundplateID takes the
-- highest-numbered plate that contains the tile).
--
-- Written as `gen4_hgss_soundplates`: { [landId] = { { sound, volume, x, z, x2, z2 }, ... } }
-- for the chunks that have any. The runtime is src/world/HgssSoundplates.lua.

local Gen4Maps = require("src.import.Gen4Maps")

local M = {}

M.PATH = "/a/0/6/5"

function M.parse(bytes)
  local out = {}
  if type(bytes) ~= "string" then return out end
  for at = 1, #bytes - 7, 8 do
    local b = { bytes:byte(at, at + 7) }
    out[#out + 1] = { sound = b[1], volume = b[2], x = b[5], z = b[6], x2 = b[7], z2 = b[8] }
  end
  return out
end

function M.build(ex)
  local arc = ex:archiveAt(M.PATH)
  if not arc then error(M.PATH .. " missing") end
  local out = { source = "ROM:" .. M.PATH .. " (land data background-sound section)", lands = {} }
  local n = 0
  for i = 0, arc.count - 1 do
    local chunk = Gen4Maps.land(arc:get(i))
    local plates = chunk and M.parse(chunk.backgroundSounds)
    if plates and #plates > 0 then out.lands[i] = plates; n = n + 1 end
  end
  out.count = n
  return out
end

return M
