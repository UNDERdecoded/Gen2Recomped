-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 94: the fairy (sprite 0xE3) flies about.
--
-- GBA, Sprite_E3_Fairy (sprite table entry 0x080CF9A4; its state table
-- 0x08174A08, state 0 at 0x080CFA30) touches Link (heal) and then runs
-- Fairy_HandleMovement (0x080CFAA8):
--   * indoors (+0x9B2) and its timer +0xFD2 at 0: the tile collision
--     (0x080C7A20 -> the wall bits +0x1042): wall & 3 -> x speed and its
--     target B (+0xFB2) negated, timer 0x20; then the wall bits compared
--     with 0x0C (`cmp r0, #0xc` / `beq`, 0x080CFB20): any other value ->
--     y speed and its target A (+0xF62) negated, timer 0x20
--   * Sprite_MoveXY (0x080C3568)
--   * frame & 0x3F == 0: a new target, a random point in Link's 256 px
--     quarter (random low bytes 0x080CEFE0, Link's high bytes), A / B =
--     the speed 0x10 projected at it (0x080C2DCC)
--   * frame & 0x0F == 0: y speed = (A + y speed) >> 1, x speed = (B + x
--     speed) >> 1 (0x080CFC64.., 0x080CFCB0..)
--   * Sprite_MoveZ (0x080C2C4C), z speed += t[random & 1] + t[0] (the
--     two bytes the literal at 0x080CFD3C points to, read at import), z
--     kept in 8..0x18 (below: z 8, z speed 5; above: z 0x18, z speed -5)
-- The port moved a fairy as the heart (Sprite_D8_Heart's glide and rest):
-- a room's own fairies sat where the sprite list puts them -- Ganon's
-- Tower 0x1C's four over the NW pit, out of Link's reach.
--
-- Like every sprite it waits while it is off the screen (the return-if-
-- paused call 0x080C3438 before the state routine); OURS: "off" is more
-- than 0x40 px outside the 240 x 160 camera.
-- OURS: the wall bits are Interior:blocked at four probe points (right /
-- left x + 14 / x + 1, down / up y + 14 / y + 2, at the middle of the other
-- axis), not the cartridge's Sprite_CheckTileCollision tables. The drop's
-- own pickup test (Drops.updateDrops) is kept.

local bit = require("bit")
local band = bit.band

local M = { NAME = "fairy94" }

M.SITES = { main = 0x080CF9A4, move = 0x080CFAA8, zTabLit = 0x080CFCD2 }
M.SPEED, M.ZLO, M.ZHI, M.ZV = 0x10, 8, 0x18, 5

local function off(a) return a - 0x08000000 end
-- the Thumb `ldr rX, [pc, #imm]` literal at a
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
local function s8(v) v = band(v, 0xFF) return v >= 128 and v - 256 or v end

function M.extract(rom, R, check)
  local p = lit(rom, M.SITES.zTabLit)
  check(p ~= nil and p >= 0x08000000, "fairy94: z table literal")
  if not p then return {} end
  return { zt = { s8(rom:u8(off(p))), s8(rom:u8(off(p) + 1)) } }
end

local function tabs(game) return game.data and game.data.t and game.data.t.fairy94 end

-- the wall bits (1 right, 2 left, 4 down, 8 up) of a fairy at x, y
function M.wallBits(inside, d)
  if not (inside and inside.blocked) then return 0 end
  local w = 0
  if inside:blocked(d.x + 14, d.y + 8) then w = w + 1 end
  if inside:blocked(d.x + 1, d.y + 8) then w = w + 2 end
  if inside:blocked(d.x + 8, d.y + 14) then w = w + 4 end
  if inside:blocked(d.x + 8, d.y + 2) then w = w + 8 end
  return w
end

-- the sprite is run (not paused) within 0x40 px of the 240 x 160 screen
function M.onScreen(d, cx, cy)
  local sx, sy = d.x - cx + 0x40, d.y - cy + 0x40
  return sx >= 0 and sx < 240 + 0x80 and sy >= 0 and sy < 160 + 0x80
end

local function move8(p, sub, v)
  local s = p * 256 + sub + v * 16
  local np = math.floor(s / 256)
  return np, s - np * 256
end

-- one frame of Fairy_HandleMovement on a drop record d (game: frame, link, interior, rng)
function M.step(game, d, rnd, T)
  local f = d.f94
  if not f then
    f = { xv = 0, yv = 0, A = 0, B = 0, zv = 0, wt = 0, xs = 0, ys = 0, zs = 0 }
    d.f94 = f
  end
  local frame = game.frame or 0
  local inside = game.state == "room" and game.interior or nil
  if f.wt > 0 then f.wt = f.wt - 1 end
  if inside and f.wt == 0 then
    local w = M.wallBits(inside, d)
    if band(w, 3) ~= 0 then f.xv, f.B, f.wt = s8(-f.xv), s8(-f.B), 0x20 end
    if w ~= 0x0C then f.yv, f.A, f.wt = s8(-f.yv), s8(-f.A), 0x20 end
  end
  if f.xv ~= 0 then d.flip = f.xv > 0 end
  d.x, f.xs = move8(d.x, f.xs, f.xv)
  d.y, f.ys = move8(d.y, f.ys, f.yv)
  local lk = game.link
  if band(frame, 0x3F) == 0 then
    local tx = rnd() + math.floor(lk.x / 256) * 256
    local ty = rnd() + math.floor(lk.y / 256) * 256
    local px, py = require("src.zelda.alttp.Actors").project(d.x, d.y, tx, ty, M.SPEED)
    f.A, f.B = s8(py), s8(px)
  end
  if band(frame, 0x0F) == 0 then
    f.yv = s8(math.floor((f.A + f.yv) / 2))
    f.xv = s8(math.floor((f.B + f.xv) / 2))
  end
  d.z, f.zs = move8(d.z or 0, f.zs, f.zv)
  local zt = (T and T.zt) or { 0, 0 }
  f.zv = s8(f.zv + zt[band(rnd(), 1) + 1] + zt[1])
  if d.z < M.ZLO then d.z, f.zv = M.ZLO, M.ZV
  elseif d.z > M.ZHI then d.z, f.zv = M.ZHI, -M.ZV end
  d.f94moves = (d.f94moves or 0) + 1
end

function M.install(G)
  if G.fairy94Installed then return end
  G.fairy94Installed = true
  local upd0 = G.updateDrops
  if not upd0 then return end
  function G:updateDrops()
    local T = tabs(self)
    if T and T.zt and self.drops then
      local D = require("src.zelda.alttp.Drops")
      local here = self.state == "room" and self.interior and self.interior.room or nil
      local function rnd() return D.rng(self:dropRng()) end
      for _, d in ipairs(self.drops) do
        if d.kind == "fairy" and not d.gone and d.room == here
           and (here or (d.world == self.link.world and d.area == (self.area and self.area.parent))) then
          local cx, cy = 0, 0
          if self.ancCamera then cx, cy = self:ancCamera() end
          if M.onScreen(d, cx, cy) then M.step(self, d, rnd, T) end
          -- the drop routine's own glide stays off (its rest state: no speeds)
          d.ai, d.zvel, d.xvel, d.zsub = 3, 0, 0, 0
        end
      end
    end
    return upd0(self)
  end
end

return M
