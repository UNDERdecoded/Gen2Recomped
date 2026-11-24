-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 78: the moving wall's shake and its stop sound, from the cartridge.
--
-- RoomTag_MovingWallShakeItUp (GBA 0x0807AB2C; called each moving frame by
-- the moving-wall tags: `bl` at 0x0807ABE0, 0x0807ADA0 -- the Misery Mire
-- room's own path -- and 0x0807AF78): while the wall's flag (the byte at
-- +0x9E6 indexed by +0x97C) is set, +0xA28 = tableA[frame & 1] (`ldr r1` at
-- 0x0807AB44) and +0xA2A = tableB[frame & 1] (`ldr r1` at 0x0807AB5C), two
-- s16 each, frame = the byte at +0x996; else both 0. The frame's scroll
-- copy (0x0806A78A..) adds +0xA2A to BG1's and BG2's horizontal scroll
-- (+0x950 / +0x956) and +0xA28 to their vertical scroll (+0x952 / +0x958):
-- both room maps shake (our "bg3" on BG1, "bg2" on BG2), the high-priority
-- map on BG3 and the sprites do not. (The same tables drive another shake at
-- 0x0808E16A / 0x0808E182; the extract checks that they agree.)
-- When the wall stops each path plays sound 0x7B (`movs r0, #id` at
-- 0x0807AC66, 0x0807AE14 -- the Mire room -- and 0x0807AFF8, then `bl
-- 0x0812A324`).
--
-- Before this the port shook only the lower map ("bg3") by literal +-1 and
-- not at all in the Misery Mire room 0x97 (whose lower map is empty: the
-- shake was invisible there), and the stop was silent.
--
-- Only the code sites live here; the tables and the sound id are read from
-- the player's ROM at import (data.t.shake78).

local bit = require("bit")
local band, bnot = bit.band, bit.bnot

local M = {}

M.SITES = {
  tabA = { 0x0807AB44, 0x0808E16A },     -- ldr r1, =tableA (-> +0xA28, the vertical offset)
  tabB = { 0x0807AB5C, 0x0808E182 },     -- ldr r1, =tableB (-> +0xA2A, the horizontal offset)
  sound = { 0x0807AC66, 0x0807AE14, 0x0807AFF8 },   -- movs r0, #id (the stop sound)
}
M.LAYERS = { bg2 = true, bg3 = true }   -- GBA BG2 / BG1 (Layers.lua)

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xFF00) ~= op then return nil end
  return band(h, 0xFF)
end

local function s16(v) if v >= 0x8000 then return v - 0x10000 end return v end

-- the pointer every site of a name loads (all the same)
local function ptr(rom, check, name)
  local p
  for _, a in ipairs(M.SITES[name]) do
    local v = lit(rom, a)
    check(v and v >= 0x08000000 and (p == nil or p == v), "shake78 %s pointer", name)
    p = v
  end
  return p
end

function M.extract(rom, R, check)
  local t = {}
  for _, n in ipairs({ "tabA", "tabB" }) do
    local p = ptr(rom, check, n)
    t[n] = { [0] = s16(rom:u16(off(p))), s16(rom:u16(off(p) + 2)) }
  end
  local id
  for _, a in ipairs(M.SITES.sound) do
    local v = imm8(rom, a, 0x2000)
    check(v and (id == nil or id == v), "shake78 stop sound")
    id = v
  end
  t.sound = id
  return t
end

-- ------------------------------------------------------------ run time

local function tab(data) return data and data.t and data.t.shake78 end
M.tab = tab

-- the BG content offset (screen pixels) this frame: the scroll moves by
-- (+0xA2A, +0xA28), the picture the other way
function M.offset(game)
  local inside = game and game.interior
  local w = inside and inside.wall
  local t = tab(inside and inside.data)
  if not (w and w.moving and not w.moved and t) then return 0, 0 end
  local j = band(game.frame or 0, 1)
  return -(t.tabB[j] or 0), -(t.tabA[j] or 0)
end

function M.install(G)
  if G.shake78 then return end
  G.shake78 = true
  local DP = require("src.zelda.alttp.DesertPalace")
  -- the lower map's offset keeps the slide; the shake is drawn below for
  -- both room maps
  local off0 = DP.bg3Offset
  function DP.bg3Offset(game)
    local dx, dy, show = off0(game)
    local inside = game.interior
    local w = inside and inside.wall
    local W = require("src.zelda.alttp.Wall76")
    local wt = W.tab(inside and inside.data)
    local own = wt and w and w.tag == W.TAG and inside.room == wt.room   -- (Wall76: no slide, no literal shake)
    if w and not own and tab(inside.data) then
      dx, dy = dx + (w.shakeX or 0), dy + (w.shakeY or 0)
    end
    return dx, dy, show
  end
  -- the stop sound
  local frame0 = DP.wallFrame
  function DP.wallFrame(game)
    local inside = game.interior
    local w = inside and inside.wall
    local was = w and w.moving
    frame0(game)
    local t = tab(inside and inside.data)
    if w and was and w.moved and t and t.sound then
      game.wallSound78 = (game.wallSound78 or 0) + 1
      pcall(require("src.zelda.alttp.Sfx").start, game, t.sound, "wall78")
    end
  end
  local dbl0 = G.drawBgLayer
  function G:drawBgLayer(im, x, y, blend)
    local ri = self.roomImages
    if ri and im and (im == ri.bg2 or im == ri.bg3) and self.state == "room" then
      local dx, dy = M.offset(self)
      if dx ~= 0 or dy ~= 0 then
        x, y = x + dx, y + dy
        self.shake78Draws = (self.shake78Draws or 0) + 1
      end
    end
    return dbl0(self, im, x, y, blend)
  end
end

return M
