-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 33: what makes the ALttP driver (AlttpSynth.lua) heard.
--   * Sfx.backend: a started sound (sub-bank 0, the number Sfx.start chose)
--     is rendered once into a SoundData (cached by number) and played as a
--     static LÖVE source; one sound per channel (the GBA's player per
--     channel: a new start stops the channel's old sound, 0x0812C548).
--   * room music: the entrance's music id (the entrance table 0x150EC4,
--     +0x28, read at import into data.t.sfx.entMusic) on G:enterRoom
--     (the GBA's 0x0806A7F8: id 3 is skipped while the progress indicator
--     is 0 / 1, 0xFFF2 keeps the current song), the area's music on the way
--     out (G:leaveRoom).
-- Headless games keep the render path (tests) but play nothing.

local M = {}

local Synth = require("src.zelda.alttp.AlttpSynth")

local function bankOf(game)
  local d = game and game.data
  if not d then return nil end
  if d.sndBank == nil then
    d.sndBank = (d.snd and Synth.open(d.snd)) or false
  end
  return d.sndBank or nil
end
M.bankOf = bankOf

-- a sound's interleaved stereo floats (cached on the data, by number)
function M.render(game, sound)
  local b = bankOf(game)
  if not b then return nil end
  local d = game.data
  d.sndPcm = d.sndPcm or {}
  local c = d.sndPcm[sound]
  if c == nil then
    local ok, out, frames = pcall(Synth.renderSfx, b, 0, sound, 60 * 6)
    c = ok and { out = out, frames = frames } or false
    d.sndPcm[sound] = c
  end
  return c or nil
end

local function canPlay(game)
  return not (game.opts and game.opts.headless) and love and love.audio and love.sound
end

local function sfxVolume(game)
  local o = game.opts and game.opts.options
  local v = o and o.sfxVol
  if v == nil then return 1 end
  if v > 1 then v = v / 7 end
  return math.max(0, math.min(1, v))
end

function M.backend(game, sound, channel)
  local c = M.render(game, sound)
  if not c then return end
  game.sndPlayed = (game.sndPlayed or 0) + 1
  if not canPlay(game) then return end
  local d = game.data
  d.sndData = d.sndData or {}
  local sd = d.sndData[sound]
  if not sd then
    sd = Synth.toSoundData(c.out, #c.out)
    if not sd then return end
    d.sndData[sound] = sd
  end
  game.sndSources = game.sndSources or {}
  local old = game.sndSources[channel]
  if old then pcall(old.stop, old) end
  local ok, src = pcall(love.audio.newSource, sd, "static")
  if not ok or not src then return end
  pcall(src.setVolume, src, sfxVolume(game))
  pcall(src.play, src)
  game.sndSources[channel] = src
end

-- the GBA's sram_progress_indicator, from the port's flags
function M.progressIndicator(game)
  local p = game.progress or {}
  if game.link and game.link.world == "dw" then return 3 end
  if p.agahnim or p.agahnim2 or (p.crystals or 0) > 0 then return 3 end
  if p.escaped then return 2 end
  if p.sword or p.zelda then return 1 end
  return 0
end

function M.roomMusic(game, entrance)
  local t = game.data and game.data.t and game.data.t.sfx
  local m = t and t.entMusic and t.entMusic[(entrance or -1) + 1]
  if not m then return nil end
  if m == 3 and M.progressIndicator(game) <= 1 then return nil end
  if m == 0xFFF2 then return nil end
  return m
end

function M.install(G)
  if G.sound33 then return end
  G.sound33 = true
  require("src.zelda.alttp.Sfx").backend = M.backend
  local enter = G.enterRoom
  function G:enterRoom(entrance)
    local r = enter(self, entrance)
    local m = M.roomMusic(self, entrance)
    if m and self.music and self.music.playId then self.music:playId(m) end
    return r
  end
  local leave = G.leaveRoom
  function G:leaveRoom()
    local was = self.state
    local r = leave(self)
    if was == "room" and self.state == "play" and self.music and self.area then
      self.music:playForScreen(self.area.parent, self.link.world)
    end
    return r
  end
end

return M
