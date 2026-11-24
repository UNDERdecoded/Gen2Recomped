-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ALttP MUSIC (round 33) through the ALttP half's own sound driver
-- (AlttpSynth.lua), streamed into a LÖVE QueueableSource from the main
-- thread. Before round 33 this played M4A song 399 + SNES number: that is
-- the Four Swords half's bank (its songs are not ALttP's), so it is gone.
--
-- MUSIC IDS are the GBA's own (the u16 at RAM 0x03002230 + 0xA3C, read by
-- 0x08068502; 0xFFFF / 0xFFF2 = no change, 0xFFF1.. = fades), NOT the SNES
-- numbers: song = the table 0x198C50 [id] (0x0812A044). Read from the
-- cartridge's code:
--   overworld (0x080732FC): areas 0x80 / 0x2A / 0x0F keep the song; LW 7,
--     DW 0x0E; area & 0x3F == 0: DW 0x0F, LW 0x0B (Lost Woods) unless the
--     flag 0x02002300 & 0x40 (0xFFFF: keep); Kakariko (0x18) 8 while the
--     progress indicator <= 2 (0x08072748)
--   rooms: the entrance's +0x28 (AlttpSound.roomMusic)
--   events: the fairy queen 0x14 (0x080DFF0E), the Master Sword 0x19
--     (0x080D46B4).
-- The port's older callers pass SNES numbers to A:play; A.SNES maps the ones
-- matched so far (castle 9, sanctuary 0x0A from the entrances; LW / DW /
-- woods / town from the overworld code). SNES 4 (the bunny) is not matched
-- (OURS: the Dark World song plays).
--
-- Round 34 (Music34.lua wires the events): SNES 4 (the bunny) = GBA 0x0C
-- (0x080736C0). The request codes are the cartridge's (0x08068502):
--   0xFFF1 fade out: 0x0812A0A0 (0x28) -> driver command 0 / sub-op 2
--          (0x0812C5F0): the music player's volume steps to 0 linearly
--          over 0x28 = 40 frames, then the song stops (0x08129F30: state
--          2 / 3 -> 0, current song -1)
--   0xFFF2 lower: 0x0812A10C(1): the player volume (0x030000C3, normally
--          0x80) steps down 4 a frame to 0x30 (0x08129FAC)
--   0xFFF3 normal: 0x0812A10C(0): back up 4 a frame to 0x80 (0x08129FF8)
-- OURS: the steps are applied to the stream's LÖVE volume (the cartridge
-- changes the player volume inside the mixer), so they are heard at once,
-- not after the queued buffers.

local A = {}
A.__index = A

local Synth = require("src.zelda.alttp.AlttpSynth")

A.LW, A.DW, A.FOREST, A.TOWN = 2, 9, 5, 7          -- SNES numbers (callers)
-- r35: the GBA song numbers come from the import (Music34's call sites,
-- data.t.mus34.music), poured in when the cache loads: A.ID by name, A.SNES
-- by the SNES number the callers use
A.ID, A.SNES = {}, {}
local ID_SITE = { LW = "owLW", DW = "owDW", WOODS = "woods", SKULL = "owSkull", TOWN = "town",
                  CASTLE = "castle", SANCTUARY = "sanctuary", FAIRY = "fairy", SWORD = "sword", BUNNY = "bunny" }
local SNES_ID = { [2] = "LW", [4] = "BUNNY", [5] = "WOODS", [7] = "TOWN", [9] = "DW", [0x0A] = "SWORD",
                  [0x10] = "CASTLE", [0x14] = "SANCTUARY", [0x1B] = "FAIRY" }
require("src.zelda.alttp.RomTables").onBind(function(t)
  local m = t.mus34 and t.mus34.music or {}
  for k in pairs(A.ID) do A.ID[k] = nil end
  for k in pairs(A.SNES) do A.SNES[k] = nil end
  for name, site in pairs(ID_SITE) do A.ID[name] = m[site] end
  for snes, name in pairs(SNES_ID) do A.SNES[snes] = A.ID[name] end
  if t.mus34 and t.mus34.fadeFrames then A.FADE_FRAMES = t.mus34.fadeFrames end
  if t.mus34 and t.mus34.lowVol then A.VOL_LOW = t.mus34.lowVol end
end)
A.CHUNK = 4      -- frames a queued buffer
A.GAIN = 1 / 26000   -- up to 7 voices: a little under the effects' 1 / 20000
A.BUFFERS = 6
A.FADE_FRAMES = 0x28   -- 0x08068594 (Music34 reads it at import)
A.VOL_FULL, A.VOL_LOW, A.VOL_STEP = 0x80, 0x30, 4   -- 0x08129F0E / 0x08129FC8 / 0x08129FBC

function A.new(data, opts)
  opts = opts or {}
  local o = opts.options or {}
  local vol = o.musicVol or 7
  if vol > 1 then vol = vol / 7 end
  local self = setmetatable({ data = data, current = nil, volume = vol,
                              headless = opts.headless, pvol = A.VOL_FULL, pvolTarget = A.VOL_FULL,
                              enabled = not opts.headless and data and data.snd ~= nil }, A)
  return self
end

function A:bank()
  local d = self.data
  if not d then return nil end
  if d.sndBank == nil then d.sndBank = (d.snd and Synth.open(d.snd)) or false end
  return d.sndBank or nil
end

-- the GBA id for an overworld screen (0x080732FC / 0x08072748); ctx = the game
function A.musicFor(screen, world, ctx)
  screen = screen or 0
  local dw = world == "dw" or screen >= 0x40
  local s = screen % 64
  if screen == 0x80 or screen == 0x2A or screen == 0x0F then return nil end
  if s == 0 then
    if dw then return A.ID.SKULL end
    local p = ctx and ctx.progress
    if p and p.sword and (p.swordLevel or 1) >= 2 then return 0xFFFF end
    return A.ID.WOODS
  end
  if not dw and s == 0x18 then
    local Snd = require("src.zelda.alttp.AlttpSound")
    if not ctx or Snd.progressIndicator(ctx) <= 2 then return A.ID.TOWN end
  end
  return dw and A.ID.DW or A.ID.LW
end

function A:playId(id)
  if id == nil or id == 0xFFFF then return end
  if id >= 0xFFF0 then return self:control(id) end
  self.wanted = id
  if self.current == id and not self.fade then return end
  self.fade = nil
  self.current = id
  self.started = (self.started or 0) + 1
  self.log = self.log or {}
  if #self.log >= 32 then table.remove(self.log, 1) end
  self.log[#self.log + 1] = id
  if not self.enabled then return end
  local b = self:bank()
  local song = b and b:songFor(id)
  if not song then return end
  self:stopStream()
  if not (love and love.audio and love.audio.newQueueableSource) then return end
  local ok, qs = pcall(love.audio.newQueueableSource, Synth.RATE, 16, 2, A.BUFFERS)
  if not ok or not qs then return end
  self.engine = Synth.engine(b, { gain = A.GAIN })
  self.engine:playSong(song)
  self.qs = qs
  self.sd = love.sound.newSoundData(A.CHUNK * Synth.SPF, Synth.RATE, 16, 2)
  self:applyVolume()
  self:fill()
  pcall(qs.play, qs)
end

-- r34: the control requests 0xFFF0.. (see the header)
function A:control(id)
  if id == 0xFFF1 then
    if self.current and not self.fade then
      local n = (self.data and self.data.t and self.data.t.mus34 and self.data.t.mus34.fadeFrames) or A.FADE_FRAMES
      self.fade = { left = n, total = n }
      self.fades = (self.fades or 0) + 1
    end
  elseif id == 0xFFF2 then self.pvolTarget = (self.data and self.data.t and self.data.t.mus34 and self.data.t.mus34.lowVol) or A.VOL_LOW
  elseif id == 0xFFF3 then self.pvolTarget = A.VOL_FULL
  elseif id == 0xFFF0 then self:stop() end
end

-- the stream's volume: options x player volume x the fade
function A:applyVolume()
  local v = self.volume * (self.pvol / A.VOL_FULL)
  local f = self.fade
  if f then v = v * (f.left / f.total) end
  if self.qs then pcall(self.qs.setVolume, self.qs, v) end
  return v
end

-- one game frame of the fade / volume steps (0x08129F30)
function A:tick()
  local changed = false
  if self.pvol ~= self.pvolTarget then
    if self.pvol < self.pvolTarget then self.pvol = math.min(self.pvolTarget, self.pvol + A.VOL_STEP)
    else self.pvol = math.max(self.pvolTarget, self.pvol - A.VOL_STEP) end
    changed = true
  end
  local f = self.fade
  if f then
    f.left = f.left - 1
    changed = true
    if f.left <= 0 then
      self.fade = nil
      self:stopStream()
      self.current = nil
      return
    end
  end
  if changed then self:applyVolume() end
end

-- callers' SNES numbers (A.SNES); unknown ones keep the current song
function A:play(snes)
  return self:playId(A.SNES[snes])
end

function A:playForScreen(screen, world)
  self:playId(A.musicFor(screen, world, self.game))
end

function A:screenChanged(_, newParent, world)
  self:playForScreen(newParent, world)
end

function A:fill()
  local qs, E = self.qs, self.engine
  if not (qs and E) then return end
  local n = 0
  while qs:getFreeBufferCount() > 0 and n < A.BUFFERS do
    local out, at = E:renderFrames(A.CHUNK, self.buf, 0)
    self.buf = out
    Synth.fillSoundData(self.sd, out, at)
    qs:queue(self.sd)
    n = n + 1
  end
  if not qs:isPlaying() then pcall(qs.play, qs) end
end

function A:update()
  self:tick()
  if self.qs then pcall(self.fill, self) end
end

-- r34: the song has ended by itself (0x0812A0B8 returns -1)
function A:idle()
  if self.fade then return false end
  if self.current == nil then return true end
  local E = self.engine
  if E then return not E:busy() end
  return false   -- headless: no engine, the song counts as playing
end

function A:stopStream()
  if self.qs then pcall(self.qs.stop, self.qs) end
  self.qs, self.engine = nil, nil
end

function A:stop()
  self:stopStream()
  self.current, self.wanted, self.fade = nil, nil, nil
end

return A
