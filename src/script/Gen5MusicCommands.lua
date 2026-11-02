-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S CUTSCENE MUSIC.
--
-- 113 places in Black's scripts change the music for a scene -- Plasma's
-- theme as the grunts run in (0x098 0x443 SEQ_BGM_E_PLASMA), N's (0x444),
-- Bianca's, Cheren's, the "trainer's eyes" theme before Pinwheel's grunts
-- (0x09F 0x467) -- and 57 hand it back to the map (0x09E). They had been
-- linked as no-ops ("BW's sequence ids are not the engine's music keys"),
-- so every scene played on over the town's theme. The ids ARE the SDAT's
-- sequence numbers, the same numbers the zone headers' music carries
-- (Gen5Audio keys `songs` by them), so they play as they are.
--
-- READ FROM CODE (Black, ov21 / arm9; Gen5ScriptLink has the addresses):
--   0x098 <seq>        the old BGM stopped (sound queue 2, 6 frames), seq
--                      played (queue 7); the script waits on the task
--   0x09F <var|seq>    the same with the old BGM PAUSED (queue 3)
--   0x09E              the current zone's BGM back (0x02029DF4), faded
--   0x0A1 <frames>     the BGM paused over <frames> (queue 3)
--   0x0A2 <u16, f>     ...and resumed over f frames (queue 4)
-- The sound-state bit 0x098 sets (cleared by 0x09E, 0x25F and the end-of-
-- script cleanup) stops the field's ambient sound loops, which this port
-- does not play, so it carries nothing here.
--
-- AN OLD CACHE (imported before these were named) keeps 0x098 / 0x09F /
-- 0x09E as operand-less `noop` rows; 0x09E needs no operand, so its row is
-- recognised by op and still hands the map's music back (a no-op when the
-- map's music is already playing). 0x098 / 0x09F need the re-import.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function valueOf(ctx, v)
  local okG, G4 = pcall(require, "src.script.Gen4Commands")
  if okG and G4 and G4.valueOf then return G4.valueOf(ctx, v) end
  return tonumber(v)
end

function Commands.g5_event_music(ctx, seq)
  local id = math.floor(tonumber(valueOf(ctx, seq)) or 0)
  if id <= 0 or id == 0xFFFF then return end
  Commands.play_music(ctx, id)
end

function Commands.g5_map_music(ctx)
  if Commands.play_default_music then Commands.play_default_music(ctx) end
end

function Commands.g5_pause_music(ctx, frames)
  pcall(require, "src.script.Gen4Commands")
  if Commands.g4_fade_out_bgm then Commands.g4_fade_out_bgm(ctx, 0, valueOf(ctx, frames)) end
end

function Commands.g5_resume_music(ctx, _, frames)
  pcall(require, "src.script.Gen4Commands")
  if Commands.g4_fade_in_bgm then Commands.g4_fade_in_bgm(ctx, valueOf(ctx, frames)) end
end

Commands.meta = Commands.meta or {}
Commands.meta.g5_pause_music = { blocking = true }
Commands.meta.g5_resume_music = { blocking = true }

M.BW_MAP_MUSIC_OP = 0x09E

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bweventmusic = L.bweventmusic or function(ins, s) emit(s, { "g5_event_music", ins.args[1] }) end
  L.bwmapmusic = L.bwmapmusic or function(_, s) emit(s, { "g5_map_music" }) end
  L.bwpausemusic = L.bwpausemusic or function(ins, s) emit(s, { "g5_pause_music", ins.args[1] }) end
  L.bwresumemusic = L.bwresumemusic or function(ins, s)
    emit(s, { "g5_resume_music", ins.args[1], ins.args[2] })
  end
  -- the old cache's operand-less 0x09E (see the header); the op alone says
  -- whose row it is only on Black / White
  local noop = L.noop
  if noop and not M.wrappedNoop then
    M.wrappedNoop = true
    L.noop = function(ins, s)
      if ins and ins.op == M.BW_MAP_MUSIC_OP and require("src.core.GameVersion").isGen5() then
        return emit(s, { "g5_map_music" })
      end
      return noop(ins, s)
    end
  end
end

return M
