-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S SOUNDPLATES: the ambient sound of the tile the
-- player stands on -- rivers, the windmill, the sea, the Tin Tower's pillars,
-- whirlpools, waterfalls, cheers, the ship's whistle, Snorlax snoring, the
-- Rocket generators, bells, the strong wind on the Bell Tower roof, engines,
-- fountains, Lt. Surge's barriers (pokeheartgold src/field/field_control.c).
-- Data: src/import/Gen4HgssSoundplates.lua (`gen4_hgss_soundplates`).
--
-- READ FROM CODE
--   * FieldSystem_ProcessSoundplateAtCoords: the plate under the tile (the
--     LAST plate in the chunk whose box holds the tile's 0..31 chunk
--     coordinates); a new plate's sound starts only when it differs from the
--     one already playing (environmentSoundState); off every plate the sound
--     stops (StopSE fade 10) and the state clears.
--   * FieldSystem_SoundplateIsActive: Cianwood Gym's waterfall is silent
--     once FLAG_SYS_CIANWOOD_WATERFALL_DISABLE (0x981), Vermilion Gym's
--     barriers once FLAG_SYS_SOLVED_LT_SURGE_GYM (0x9A6), the snoring once
--     FLAG_SNORLAX_MEET (0xF9), the generators once FLAG_ROCKET_HIDEOUT_CLEARED
--     (0xCA).
--   * the volumes, sSoundplateVolume[sound][volumeIndex] out of 127.
--   * ScrCmd_ProcessSoundplate (scrcmd_pokemon_misc.c) re-runs it with the
--     state wiped; fieldmap.c runs it on map load; field_control.c on every
--     step (line 643).
--
--   * the BGM dip: GF_SndHandleMoveVolume(0, sBGMVolume[volumeIndex] =
--     96 / 64 / 32, 15) on a plate, (0, 128, 15) off every plate
--     (Music.moveHandleVolume, out of 127; 15 field frames = 30 ticks).
-- INFERRED: every plate sound is held looping (the cartridge's sequences loop
-- themselves).

local M = {}

-- sSoundplateSounds: { sequence, loopKind } and sSoundplateVolume
M.BGM_VOLUME = { [0] = 96, 64, 32 }   -- sBGMVolume
M.BGM_FRAMES = 15 * 2                -- 15 field frames, in 60 Hz ticks
local function bgm(level)
  pcall(function() require("src.core.Music").moveHandleVolume(math.min(1, level / 127), M.BGM_FRAMES) end)
end

M.SOUNDS = {
  [0] = { "SEQ_SE_GS_N_SESERAGI", { 64, 96, 127 } },
  { "SEQ_SE_GS_N_HUUSHA", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_UMIBE", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_HASHIRA", { 64, 96, 127 } },
  { "SEQ_SE_GS_N_UZUSIO", { 46, 64, 96 } },
  { "SEQ_SE_GS_N_TAKI", { 64, 96, 108 } },
  { "SEQ_SE_GS_N_YOUGAN", { 46, 96, 108 } },
  { "SEQ_SE_GS_N_KANSEI", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_KITEKI", { 46, 96, 127 } },
  { "SEQ_SE_GS_KABIGON_IBIKI", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_MOTER", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_KANE", { 46, 72, 108 } },
  { "SEQ_SE_GS_KYOUHUU", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_ENGINE", { 46, 96, 127 } },
  { "SEQ_SE_GS_N_HUNSUI", { 64, 96, 127 } },
  { "SEQ_SE_GS_DENGEKIBARIA", { 46, 96, 127 } },
}

local state = { name = nil, src = nil }
local bases = {}
M.state = state

local function flag(save, id)
  local f = save and save.flags
  return f and f[("FLAG_G4_%04X"):format(id)] and true or false
end

function M.enabled(data)
  local v = data and data.gen4_version
  return type(v) == "table" and v.family == "hgss" and type(data.gen4_hgss_soundplates) == "table"
end

-- the plate under global tile (gx, gz) of map `def`, or nil
function M.plateAt(data, def, gx, gz)
  local rec = data.gen4_hgss_soundplates
  local mx = data.gen4_map_matrices and def and data.gen4_map_matrices[def.layout]
  if not (rec and rec.lands and mx and mx.maps and mx.width) then return nil end
  local cx, cz = math.floor(gx / 32), math.floor(gz / 32)
  if cx < 0 or cz < 0 or cx >= mx.width then return nil end
  local land = mx.maps[cz * mx.width + cx + 1]
  local plates = land and rec.lands[land]
  if not plates then return nil end
  local lx, lz = gx % 32, gz % 32
  local hit
  for _, p in ipairs(plates) do
    if p.x <= lx and lx <= p.x2 and p.z <= lz and lz <= p.z2 then hit = p end
  end
  return hit
end

-- FieldSystem_SoundplateIsActive
function M.active(save, mapId, seq)
  if mapId == "T24GYM0101" and flag(save, 0x981) and seq == "SEQ_SE_GS_N_TAKI" then return false end
  if mapId == "T06GYM0101" and flag(save, 0x9A6) and seq == "SEQ_SE_GS_DENGEKIBARIA" then return false end
  if flag(save, 0xF9) and seq == "SEQ_SE_GS_KABIGON_IBIKI" then return false end
  if flag(save, 0xCA) and seq == "SEQ_SE_GS_N_MOTER" then return false end
  return true
end

function M.stop(game)
  if state.src then pcall(state.src.stop, state.src) end
  if state.name and game and game.data then
    pcall(function() require("src.core.Sound").stopSe(game.data, state.name) end)
  end
  state.name, state.src, state.volume = nil, nil, nil
end

local function play(game, name, volume)
  local Sound = require("src.core.Sound")
  -- no handle: a script's StopSE of the same sequence stops it, as on the
  -- cartridge (the Bell Tower roof's wind before the Kimono Girls' dance)
  local ok, src = pcall(Sound.playSe, game.data, name)
  src = ok and src or nil
  if src then
    pcall(src.setLooping, src, true)
    -- the option volume the source came with, read once (a cached source
    -- keeps what was set on it last time)
    if bases[name] == nil then
      local okV, base = pcall(src.getVolume, src)
      bases[name] = okV and base or 1
    end
    pcall(src.setVolume, src, bases[name] * volume / 127)
  end
  state.name, state.src, state.volume = name, src, volume
end

-- FieldSystem_ProcessSoundplate(fieldSystem, wipe)
function M.process(game, ow, wipe)
  local data = game and game.data
  if not (M.enabled(data) and ow and ow.player and ow.map) then return end
  -- a wipe (map load, ProcessSoundplate) forgets the sound; the music comes
  -- back up unless the new tile is a plate again (below)
  if wipe then local had = state.name; M.stop(game); if had then bgm(128) end end
  local def = ow.map.def
  local p = ow.player
  local gx, gz = (def.originX or 0) + (p.cellX or 0), (def.originY or 0) + (p.cellY or 0)
  local plate = M.plateAt(data, def, gx, gz)
  local s = plate and M.SOUNDS[plate.sound]
  if s and M.active(game.save, ow.map.id, s[1]) then
    local vol = s[2][(plate.volume or 0) + 1] or 127
    if state.name ~= s[1] then
      M.stop(game)
      play(game, s[1], vol)
    elseif state.src and state.volume ~= vol then
      pcall(state.src.setVolume, state.src, (bases[state.name] or 1) * vol / 127)
      state.volume = vol
    end
    local b = M.BGM_VOLUME[plate.volume or 0]
    if b then bgm(b) end
    M.last = { seq = s[1], volume = vol, gx = gx, gz = gz, bgm = b }
  elseif not plate then
    if state.name then M.stop(game); bgm(128) end
    M.last = nil
  end
end

return M
