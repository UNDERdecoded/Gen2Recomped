-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 32 CUTSCENE PICTURES (zelda3 names; the GBA's tables read at import).
--
--   The weathervane's wood debris (Ancilla37_WeathervaneExplosion /
--   AncillaDraw_WeathervaneExplosionWoodDebris; AncillaAdd_ExplodingWeatherVane
--   sets the 12 pieces): the GBA's tables 0x1803E0 (x velocity, s8 x 12),
--   0x1803EC (z velocity), 0x1803F8 (y low byte; high byte 7), 0x180404 (x
--   low byte; high byte 2), 0x180410 (z), chars 0x18041C (0x8E / 0x8F, flags
--   0x3C, 8 x 8). They start with the blast (Flute.lua's vane once its 0x280 +
--   128 frames are out): each frame every live piece flips its picture every
--   other frame, moves by Ancilla_MoveY / X / Z (1/16 px; ONE set of
--   sub-pixel accumulators for all twelve, as the cartridge runs them all
--   through one ancilla slot, i = 11 down to 0), its z velocity drops by 1,
--   and it is gone once z wraps under 0 (z >= 0xF0).
--
--   The super bomb (follower 13): Tagalong_Draw draws only its body (char
--   0x22, dma7 of kTagalongDmaAndFlags 0x17EA0E, offsets kTagalongDraw_SprXY
--   0x17EA3E + kTagalongDraw_Offs[13] >> 3, palette kTagalongDraw_Pals[13];
--   at count 1 the palette is frame_counter & 7) from the follower sheet of
--   the GBA's 0x0812F9A8 (base sheet 0x58 for followers 12+). Its HUD count
--   is the GBA's Hud_SuperBombIndicator 0x080AB04C: count = +0xB5C, shown
--   while it is not negative, in the HUD buffer at 0x0200B270 (row 3,
--   columns 24 / 25 of the 6 x 32 words; 0x0200B180 is the HUD's start):
--   ones = kDungFloorIndicator_Gfx0 / Gfx1 (0x16E024 / 0x16E03A, the second
--   row 32 words down) [ones - 1, 0 -> 9], tens [tens - 1, 0 -> 10 = blank].
--
-- OURS: the pieces are drawn with the overworld sprites (OAM order ignored);
-- the bomb faces down when set down and follows Games31's trail picture
-- (frame = direction + 4, standing); the cutscene bird (Ancilla38) is not
-- drawn -- its picture is DMA'd by flag_travel_bird (kTravelBird_DmaStuffs,
-- GBA 0x1803DC) from a source that is not traced.

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}

M.OFF = {
  vaneXv = 0x1803E0, vaneZv = 0x1803EC, vaneY = 0x1803F8, vaneX = 0x180404, vaneZ = 0x180410,
  vaneChar = 0x18041C,
  floorGfx0 = 0x16E024, floorGfx1 = 0x16E03A,
  sbHudLit = 0x0AB108,   -- the literal 0x0200B270 of 0x080AB04C
}
M.HUD_BASE = 0x0200B180
M.SUPER_BOMB = 13

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = {
    xv = s8(rom:bytesU8(O.vaneXv, 12)), zv = rom:bytesU8(O.vaneZv, 12),
    y = rom:bytesU8(O.vaneY, 12), x = rom:bytesU8(O.vaneX, 12), z = rom:bytesU8(O.vaneZ, 12),
    ch = rom:bytesU8(O.vaneChar, 2),
    gfx0 = rom:bytesU16(O.floorGfx0, 11), gfx1 = rom:bytesU16(O.floorGfx1, 11),
  }
  local lit = rom:u32(O.sbHudLit)
  t.sbHud = (lit - M.HUD_BASE) / 2
  check(t.xv[1] == 8 and t.xv[7] == -10 and t.zv[2] == 22 and t.y[1] == 0xB0 and t.x[7] == 0x0E and t.z[1] == 48
        and t.ch[1] == 0x8E and t.ch[2] == 0x8F and t.gfx0[11] == 0x7F and t.gfx1[11] == 0x7F and t.sbHud == 120,
        "weathervane debris / super bomb HUD tables")
  return t
end

local function T(game) local t = game.data.t and game.data.t.cut32 return t and t.xv and t end
M.tabs = T

-- ------------------------------------------------------------ the debris
function M.startDebris(game)
  local t = T(game)
  if not t then return end
  local d = { sub = { 0, 0, 0 }, p = {} }
  for i = 0, 11 do
    d.p[i + 1] = { x = 0x200 + t.x[i + 1], y = 0x700 + t.y[i + 1], z = t.z[i + 1], xv = t.xv[i + 1],
                   zv = t.zv[i + 1], timer = 1, ch = band(i, 1) }
  end
  game.vaneDebris = d
  game.vaneDebrisStarts = (game.vaneDebrisStarts or 0) + 1
end

local function sv(v) v = band(v, 0xFF) return v >= 128 and v - 256 or v end

function M.stepDebris(game)
  local d = game.vaneDebris
  local any = false
  for i = 12, 1, -1 do
    local p = d.p[i]
    if p.ch ~= 0xFF then
      p.timer = p.timer - 1
      if p.timer < 0 then p.timer, p.ch = 1, bit.bxor(p.ch, 1) end
      p.zv = band(p.zv - 1, 0xFF)
      -- Ancilla_MoveY (y velocity 0), MoveX, MoveZ: shared sub-pixels
      local ty = d.sub[1] + p.y * 256
      p.y, d.sub[1] = math.floor(ty / 256), ty % 256
      local tx = d.sub[2] + p.x * 256 + p.xv * 16
      p.x, d.sub[2] = math.floor(tx / 256), tx % 256
      local tz = d.sub[3] + p.z * 256 + sv(p.zv) * 16
      p.z, d.sub[3] = band(math.floor(tz / 256), 0xFF), tz % 256
      p.show = p.ch
      if p.z >= 0xF0 then p.ch = 0xFF end
      any = true
    else
      p.show = nil
    end
  end
  if not any then game.vaneDebris = nil end
end

function M.drawDebris(game, spr, cx, cy)
  local t, d = T(game), game.vaneDebris
  if not (t and d and spr) then return end
  for i = 12, 1, -1 do
    local p = d.p[i]
    if p.show then spr:oam(p.x - cx, p.y - cy - sv(p.z), t.ch[p.show + 1], 0x3C, 0) end
  end
end

-- ------------------------------------------------------------ the super bomb
local function rgba(c) return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31 end
local function followerImage(spr, f, var, palRow)
  local key = "c32f" .. f .. ":" .. var .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local v = spr.info.follower[f + 1] or 0
  -- the GBA's 0x0812F9A8: base sheet 0x58 for followers 12 and up
  local base = (0x58 + rshift(v, 11)) * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow] or spr.pal[4]
  for ty = 0, 1 do
    for tx = 0, 1 do
      local off = base + ty * 0x200 + tx * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = src:byte(off + y * 4 + xb + 1) or 0
          local lo, hi = b % 16, math.floor(b / 16)
          if lo ~= 0 then local r, g, bb = rgba(pal[lo]) img:setPixel(tx * 8 + xb * 2, ty * 8 + y, r, g, bb, 1) end
          if hi ~= 0 then local r, g, bb = rgba(pal[hi]) img:setPixel(tx * 8 + xb * 2 + 1, ty * 8 + y, r, g, bb, 1) end
        end
      end
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  spr.cache[key] = im
  return im
end

-- Tagalong_Draw for follower 13 (body only); x, y = the follower's spot on
-- the screen (its x / y minus the camera)
function M.drawSuperBomb(game, spr, x, y, flash, dir)
  local tb = game.data.t and game.data.t.smith
  if not (tb and tb.tagDma and spr and spr.info and spr.info.follower) then return false end
  local f = M.SUPER_BOMB
  local frame = (dir or 0) + 4
  local d = tb.tagDma
  local dma7, fl = d[frame * 3 + 2], d[frame * 3 + 3]
  local xy = tb.tagXY[frame + rshift(tb.tagOffs[f + 1] or 0, 3) + 1]
  if not (dma7 and fl and xy) then return false end
  local pal = tb.tagPals[f + 1] or 4
  if flash then pal = band(game.frame or 0, 7) end
  local bf = band(fl, 0x0F) * 16
  local im = followerImage(spr, f, dma7, pal)
  local hf, vf = band(bf, 0x40) ~= 0, band(bf, 0x80) ~= 0
  love.graphics.draw(im, x + xy[4] + (hf and 16 or 0), y + xy[3] + 8 + (vf and 16 or 0), 0, hf and -1 or 1, vf and -1 or 1)
  game.superBombDrawn = (game.superBombDrawn or 0) + 1
  return true
end

-- the HUD words of the count (nil when not shown)
function M.hudWords(game)
  local t, sb = T(game), game.superBomb
  if not (t and sb and sb.count and sb.count >= 0) then return nil end
  local c = sb.count
  local r, q = c % 10, math.floor(c / 10)
  local j1 = r - 1; if j1 < 0 then j1 = 9 end
  local j2 = q - 1; if j2 < 0 then j2 = 10 end
  return { { t.sbHud + 1, t.gfx0[j1 + 1] }, { t.sbHud + 33, t.gfx1[j1 + 1] },
           { t.sbHud, t.gfx0[j2 + 1] }, { t.sbHud + 32, t.gfx1[j2 + 1] } }
end

-- ------------------------------------------------------------ install
function M.install(G)
  if G.cut32 then return end
  G.cut32 = true
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    local v = self.vane
    if v and T(self) and v.var2 <= 1 and v.G <= 1 and not v.debris then
      v.debris = true
      M.startDebris(self)
    end
    if self.vaneDebris then M.stepDebris(self) end
    return r
  end
  local dd0 = G.drawDrops
  function G:drawDrops(cx, cy, spr)
    local r = dd0(self, cx, cy, spr)
    if self.state == "play" and self.vaneDebris then M.drawDebris(self, spr, cx, cy) end
    return r
  end
  -- the super bomb's own picture (Games31 drew Bomb_Draw's unlit bomb)
  local G31 = require("src.zelda.alttp.Games31")
  local db0 = G31.drawBomb
  function G31.drawBomb(game, spr, x, y, flash)
    if M.drawSuperBomb(game, spr, x, y, flash, 0) then return end
    return db0(game, spr, x, y, flash)
  end
  -- the HUD count
  local Hud = require("src.zelda.alttp.Hud")
  local words0 = Hud.words
  function Hud.words(ui, st)
    local w = words0(ui, st)
    local add = M.pendingHud
    if add then for _, e in ipairs(add) do w[e[1] + 1] = e[2] end end
    return w
  end
  local hud0 = G.drawHud
  function G:drawHud()
    M.pendingHud = M.hudWords(self)
    local r = hud0(self)
    M.pendingHud = nil
    return r
  end
end

return M
