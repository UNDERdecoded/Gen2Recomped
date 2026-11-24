-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MIRE'S RAIN AND THE THUNDER (round 72). Traced on the GBA:
--
--   OverworldOverlay_HandleRain (0x0807407C), every overworld frame:
--     if overworld_screen_index (+0x9C6) != 0x70 (`cmp r1, #0x70` at
--     0x08074088) and sram_progress_indicator (+0x165E) > 1: no rain;
--     if save_ow_event_info[0x70] (0x020022F0) & 0x20 (the Mire opened by
--     Ether): no rain -- so the Dark World's area 0x70 rains until Ether
--     opens Misery Mire, whatever the story, as the escape's Light World.
--     frame_counter (+0x996) == 3 (`cmp r0, #3` at 0x080740AA): the
--     thunder (the sound player 0x0812A324 with the id of the movs at
--     0x080740B2) and the flash; == 0x5C (`cmp r0, #0x5C` at 0x080740D4):
--     the flash alone. The flash sets +0x998 / +0x999 to the movs at
--     0x080740DC (0x1F); on odd frames they fall by 1 while above the
--     `cmp r0, #0x0A` at 0x080740FE. Every 4th frame the drift
--     (kDrawBadWeather X / Y, Escape.lua) as before.
--   The port's escape rain (round 7) flashed for one frame at 3, 36 and 88
--   and had no thunder; both rains now use the cartridge's two flashes,
--   their fall and the thunder.
--
-- OURS: +0x998 / +0x999 are drawn as an additive pass of the rain picture
-- with alpha (v - floor) / (peak - floor) (the GBA's blend registers for it
-- are not read); the half-added rain itself is Escape.lua's.

local bit = require("bit")
local band = bit.band

local M = {}

M.ADDR = {
  areaCmp = 0x074088,    -- cmp r1, #0x70
  frameA = 0x0740AA,     -- cmp r0, #3 (thunder + flash)
  sfxMovs = 0x0740B2,    -- movs r0, #sound
  frameB = 0x0740D4,     -- cmp r0, #0x5C (flash)
  peakMovs = 0x0740DC,   -- movs r1, #0x1F
  floorCmp = 0x0740FE,   -- cmp r0, #0x0A
  rainX = 0x074190,      -- the literal pool's kDrawBadWeather X (checks the routine)
}

local function imm(rom, at, op)
  local h = rom:u16(at)
  if band(h, 0xF800) ~= op then return nil end
  return band(h, 0xFF)
end

function M.extract(rom, R, check)
  local A = M.ADDR
  local out = {
    area = imm(rom, A.areaCmp, 0x2800), frameA = imm(rom, A.frameA, 0x2800), frameB = imm(rom, A.frameB, 0x2800),
    sfx = imm(rom, A.sfxMovs, 0x2000), peak = imm(rom, A.peakMovs, 0x2000), floor = imm(rom, A.floorCmp, 0x2800),
  }
  check(rom:u32(A.rainX) == 0x0814D794, "OverworldOverlay_HandleRain's literal pool")
  check(out.area and out.frameA and out.frameB and out.sfx and out.peak and out.floor, "rain immediates")
  check(out.peak > out.floor and out.frameB > out.frameA, "rain flash levels")
  return out
end

local function tab(game) return game.data and game.data.t and game.data.t.rain72 end
M.tab = tab

-- the Mire not yet opened (save_ow_event_info[0x70] & 0x20)
function M.mireShut(game, area)
  local e = game.progress.owEvents or {}
  return band(e[tostring(area)] or 0, 0x20) == 0
end

-- +0x998 at frame counter fc (0..255): the last flash's level after its fall
function M.level(t, fc)
  local last
  if fc >= t.frameB then last = t.frameB elseif fc >= t.frameA then last = t.frameA else last = t.frameB - 256 end
  local v = t.peak
  for f = last + 1, fc do
    if band(f % 256, 1) == 1 and v > t.floor then v = v - 1 end
  end
  return v
end

function M.install(G)
  local raining0 = G.raining
  function G:raining()
    local t = tab(self)
    if not t then return raining0(self) end
    if self.link.world == "dw" and self.area and self.area.parent == t.area then
      return M.mireShut(self, t.area)
    end
    -- the escape's rain also stops once the Mire is open (the GBA checks the bit for every area)
    return raining0(self) and M.mireShut(self, t.area)
  end

  -- the thunder on frame 3 (the overworld frame)
  local ow0 = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    local t = tab(self)
    if t and self.state == "play" and not self.interior and self.frame % 256 == t.frameA and self.rainThunder72 ~= self.frame and self:raining() then
      self.rainThunder72 = self.frame
      self.thunders72 = (self.thunders72 or 0) + 1
      local ok, S = pcall(require, "src.zelda.alttp.Sfx")
      if ok and S.start then pcall(S.start, self, t.sfx, "thunder72") end
    end
    return ow0(self, inp)
  end

  -- the rain: Escape.lua's draw (overlay 0x9F half-added, the drift every
  -- 4th frame) with the cartridge's flash in place of its one-frame flashes
  local draw0 = G.drawRain
  function G:drawRain()
    local t = tab(self)
    if not t then return draw0(self) end
    if not self:raining() then return end
    local fc = self.frame % 256
    if fc % 4 == 0 and self.rainStep72 ~= self.frame then
      self.rainStep72 = self.frame
      local RT = require("src.zelda.alttp.RomTables")
      local rx, ry = RT.get("escape.rainX"), RT.get("escape.rainY")
      self.rainCtr = ((self.rainCtr or 0) + 1) % 4
      self.rainX = ((self.rainX or 0) + rx[self.rainCtr] * 256) % 512
      self.rainY = ((self.rainY or 0) + ry[self.rainCtr] * 256) % 512
    end
    local scr = self.view:screen(0x9F)
    local ox = (math.floor(self.cam.x / 2) + (self.rainX or 0)) % 512
    local oy = (math.floor(self.cam.y / 2) + (self.rainY or 0)) % 512
    local lg = love.graphics
    local function pass()
      for dy = 0, math.ceil((self.viewH or 160) / 512) do for dx = 0, math.ceil((self.viewW or 240) / 512) do
        lg.draw(scr.bg2, dx * 512 - ox, dy * 512 - oy)
        lg.draw(scr.bg1, dx * 512 - ox, dy * 512 - oy)
      end end
    end
    lg.setColor(1, 1, 1, 0.5)
    pass()
    local v = M.level(t, fc)
    self.rainFlash72 = v
    if v <= t.floor then lg.setColor(1, 1, 1, 1) return end
    lg.setBlendMode("add")
    lg.setColor(1, 1, 1, (v - t.floor) / (t.peak - t.floor))
    pass()
    lg.setBlendMode("alpha")
    lg.setColor(1, 1, 1, 1)
  end
end

return M
