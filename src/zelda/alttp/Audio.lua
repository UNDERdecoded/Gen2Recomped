-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ALttP MUSIC through the engine's existing M4A (MusicPlayer2000) synth and
-- its worker thread (src/core/M4ASynth.lua via ChipAudio). The importer wrote
-- the cartridge's music span (assets/generated/audio/m4a.bin) and its 545 song
-- headers; this picks a song for the screen and hands it to ChipAudio.
--
-- WHICH SONG: the SNES music numbers (2 Light World, 5 Lost Woods, 7 Kakariko,
-- 9 Dark World, ...) are kept by the GBA port. The multi-track BGM block of the
-- song table starts at 400, and SONG = 399 + SNES number is the working
-- mapping. It is NOT yet confirmed against the cartridge's own music-id
-- translation (see docs/zelda/alttp.md, "Music"); a bad guess only plays the
-- wrong tune.

local A = {}
A.__index = A

A.SONG_BASE = 399
A.LW, A.DW, A.FOREST, A.TOWN = 2, 9, 5, 7

function A.new(data, opts)
  opts = opts or {}
  local self = setmetatable({ data = data, current = nil,
                              volume = (opts.options and opts.options.musicVol) or 1,
                              enabled = not opts.headless and opts.cache ~= nil and data.songs ~= nil,
                              cache = opts.cache }, A)
  return self
end

function A.musicFor(screen, world)
  local s = screen % 64
  if world == "dw" or screen >= 0x40 then return A.DW end
  if s == 0 then return A.FOREST end
  if s == 0x18 then return A.TOWN end
  return A.LW
end

function A.songIndex(id) return A.SONG_BASE + id end

function A:play(id)
  if not self.enabled or self.current == id then return end
  local songs = self.data.songs
  local row = songs and songs.songs[A.songIndex(id) + 1]
  if not (row and row.tracks and #row.tracks > 0) then return end
  local ok, ChipAudio = pcall(require, "src.core.ChipAudio")
  if not ok then return end
  local prefix = (self.cache and self.cache.prefix) or ""
  local data = { audio = { gen3 = { file = prefix .. "assets/generated/audio/m4a.bin",
                                    base = songs.base } } }
  local def = { tracks = row.tracks, voicegroup = row.voicegroup, trackCount = row.trackCount,
                priority = row.priority, reverb = row.reverb }
  local okP, src = pcall(ChipAudio.playMusic, data, def, true, "m4a")
  if okP and src then
    pcall(function() src:setVolume(self.volume) end)
    self.current, self.source = id, src
  end
end

function A:playForScreen(screen, world)
  self:play(A.musicFor(screen, world))
end

function A:screenChanged(_, newParent, world)
  self:playForScreen(newParent, world)
end

function A:update()
  if self.source then
    local ok, ChipAudio = pcall(require, "src.core.ChipAudio")
    if ok then pcall(ChipAudio.update) end
  end
end

function A:stop()
  if self.source then
    local ok, ChipAudio = pcall(require, "src.core.ChipAudio")
    if ok then pcall(ChipAudio.stopMusic) end
    self.source, self.current = nil, nil
  end
end

return A
