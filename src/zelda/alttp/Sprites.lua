-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SPRITE GRAPHICS (round 7): the GBA's OBJ VRAM and sprite palettes for a
-- room, rebuilt the way its loaders build them (RomMap.sprites), and the
-- per-sprite drawing routines of the escape's actors (SNES zelda3 names):
--
--   Guard_HandleAllAnimation   blue/green guards (head, body, weapon)
--   Recruit_Draw               the green knife guard (0x4B)
--   SpriteDraw_SingleLarge     rats, ropes, keese (kSprite_PrepAndDrawSingleLarge)
--   Sprite_DrawThinAndTall     the small key
--   Uncle/Priest_Draw          kUncleDraw_Table / kPriest_Dmd
--   CrystalMaiden_Draw         Zelda (her tiles DMA'd from the follower sheet)
--   MovableMantle_Draw         the shelf
--   GoodPullSwitch_Draw        the lever
--
-- The tables are the cartridge's (SprExtract.lua); the drawing order is the
-- OAM order (an earlier OAM slot is drawn on top). OURS: entries whose tiles
-- the cartridge DMAs from Link's sword/shield graphics (the uncle's sword
-- and shield, page-0 chars below 0x40) and the guards' page-0 0x40 parts
-- (an SNES char 0x20 placeholder) are not drawn; shadows are not drawn.

local bit = require("bit")
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local S = {}
S.__index = S

function S.new(data)
  local self = setmetatable({ data = data, info = data.sprInfo, cache = {} }, S)
  return self
end

function S.available(data) return data.spr ~= nil and data.sprInfo ~= nil end

-- the sheet slot a GBA OBJ tile (0..511) comes from: sheet number, tile in sheet
function S:tileSource(t)
  local page = t >= 256 and 1 or 0
  local r, c = math.floor((t % 256) / 32), t % 32
  local half, col = c >= 16 and 1 or 0, c % 16
  local lr = r % 4
  local sheet
  if page == 0 then
    -- round 9: the rupee's two chars (0x0B over 0x2B) are DMA'd each frame
    -- from sprite sheet 96 (SNES LoadItemGFXIntoWRAM4BPPBuffer "rupees":
    -- 3 shimmer frames, the lower halves one sheet row below)
    if t == 0x0B or t == 0x2B then return 96, (t == 0x2B and 16 or 0) + (self.rupeeFrame or 0) end
    -- round 10: rows 2-3 hold sprite sheet 0's lower half (the GBA's
    -- 0x0812EED8 copies sheet 0's four 16-tile rows to OBJ rows 0-3,
    -- 0x06010000/0400/0800/0C00): the drop heart 0x49, the small shadow
    -- 0x68; rows 0-1 are overwritten by Link's DMA'd sword/shield tiles
    if r >= 2 and r < 4 and half == 0 then return 0, lr * 16 + col end
    if r < 4 and half == 0 then return nil end          -- Link / follower (DMA)
    if r >= 4 and half == 0 then sheet = self.misc
    elseif r < 4 then sheet = 6 else sheet = 7 end
  else
    sheet = self.subsets[(r >= 4 and 2 or 0) + half + 1]
  end
  if not sheet or sheet == 0xFF then return nil end
  return sheet, lr * 16 + col
end

-- set up VRAM and palettes for a dungeon room: hdr = the 14 header bytes,
-- palMain/sp0l/sp5l/sp6l from the room's palette set
function S:setRoom(hdr, palSet, palSets)
  local info = self.info
  local ss = (hdr[4] or 0) + 0x40
  local st = info.spriteTilesets
  self.subsets = self.subsets or { 0xFF, 0xFF, 0xFF, 0xFF }
  for k = 1, 4 do
    local v = st[ss * 4 + k]
    if v and v ~= 0xFF then self.subsets[k] = v end
  end
  self.misc = 10                                         -- misc_sprites_graphics_index indoors
  local pm = palSets[palSet * 4 + 1] or 0
  local sp0l, sp5l, sp6l = palSets[palSet * 4 + 2] or 0, palSets[palSet * 4 + 3] or 0, palSets[palSet * 4 + 4] or 0
  local key = table.concat(self.subsets, ",") .. "/" .. pm .. "," .. sp0l .. "," .. sp5l .. "," .. sp6l
  if key == self.key then return end
  self.key = key
  self.cache = {}
  local d, p = self.data, info.pal
  local pal = {}
  for r = 0, 7 do pal[r] = {} for c = 0, 15 do pal[r][c] = 0 end end
  local function cp(src, row, col, n)
    for i = 0, n - 1 do pal[row][col + i] = d:blobColor(src + i) end
  end
  cp(0x100 + (p.aux3[sp0l + 1] or 0), 0, 0, 8)
  cp(0x400 + (p.dungMain[pm + 1] or 0), 0, 8, 8)
  for r = 0, 3 do cp(p.main[1] + 16 * r, 1 + r, 0, 16) end
  cp(0x200 + (p.aux1[sp5l + 1] or 0), 5, 0, 8)
  cp(0x300 + (p.sword[2] or 0), 5, 8, 4)                 -- fighter sword
  cp(0x300 + (p.shield[2] or 0), 5, 12, 4)               -- fighter shield
  cp(0x200 + (p.aux1[sp6l + 1] or 0), 6, 0, 8)
  cp(0x108 + (p.misc[10 + 1] or 0), 6, 8, 8)             -- palette_sp6r_indoors = 10
  cp(0xB0 + (p.misc[1] or 0), 7, 0, 16)                  -- green mail
  self.pal = pal
end

local function rgba(c)
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end

-- 4bpp tile bytes -> pixels into ImageData at (ox, oy)
local function blit(img, src, off, ox, oy, pal)
  for y = 0, 7 do
    for xb = 0, 3 do
      local b = src:byte(off + y * 4 + xb + 1) or 0
      local lo, hi = b % 16, math.floor(b / 16)
      if lo ~= 0 then local r, g, bb = rgba(pal[lo]) img:setPixel(ox + xb * 2, oy + y, r, g, bb, 1) end
      if hi ~= 0 then local r, g, bb = rgba(pal[hi]) img:setPixel(ox + xb * 2 + 1, oy + y, r, g, bb, 1) end
    end
  end
end

function S:tileImage(tile, big, palRow)
  local key = tile * 32 + palRow * 2 + (big and 1 or 0)
  local im = self.cache[key]
  if im ~= nil then return im or nil end
  local n = big and 2 or 1
  local img = love.image.newImageData(8 * n, 8 * n)
  local any = false
  for ty = 0, n - 1 do
    for tx = 0, n - 1 do
      local sheet, idx = self:tileSource(tile + ty * 32 + tx)
      if sheet then
        blit(img, self.data.spr, sheet * 4096 + idx * 32, tx * 8, ty * 8, self.pal[palRow])
        any = true
      end
    end
  end
  if any then
    im = love.graphics.newImage(img)
    im:setFilter("nearest", "nearest")
  end
  self.cache[key] = im or false
  return im
end

-- one OAM entry: GBA char (0..255), SNES flags (vhoopppN), big = 2 for 16x16
function S:oam(x, y, char, flags, big)
  local tile = band(flags, 1) * 256 + char
  local im = self:tileImage(tile, big == 2, band(rshift(flags, 1), 7))
  if not im then return end
  local w = big == 2 and 16 or 8
  local hf, vf = band(flags, 0x40) ~= 0, band(flags, 0x80) ~= 0
  love.graphics.draw(im, x + (hf and w or 0), y + (vf and w or 0), 0, hf and -1 or 1, vf and -1 or 1)
end

-- Zelda's tiles: the follower sheet rows the cartridge copies to RAM
-- (0x0812F9A8: 0x200 bytes at the follower's offset, and the next 0x200),
-- then DMAs two tiles across from offset var * 2 (SNES dma_var6/7)
function S:followerImage(var, palRow)
  local key = "f" .. var .. ":" .. palRow
  local im = self.cache[key]
  if im ~= nil then return im or nil end
  local info = self.info
  local v = info.follower[2] or 0                       -- follower 1 = Zelda
  local sheet = info.followerZelda + rshift(v, 11)
  local base = sheet * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  for ty = 0, 1 do
    for tx = 0, 1 do
      blit(img, self.data.spr, base + ty * 0x200 + tx * 32, tx * 8, ty * 8, self.pal[palRow])
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  self.cache[key] = im
  return im
end

-- ------------------------------------------------------------- actors

-- our actor directions (0 up, 1 down, 2 left, 3 right) -> SNES sprite_D
-- (0 right, 1 left, 2 down, 3 up)
local SD = { [0] = 3, 2, 1, 0 }
S.SNES_DIR = SD

local function oamFlags(info, t) return band(info.flags3[t + 1] or 0, 0x0F) end

-- draw list helpers: entries { slot, x, y, char, flags, big }, drawn from the
-- highest OAM slot to the lowest
local function flush(self, list)
  table.sort(list, function(a, b) return a[1] > b[1] end)
  for _, e in ipairs(list) do
    if e.weapon then
      -- bug round: a page-0 char below 0x40 is the weapon strip (the uncle's
      -- sword and shield, Weapon.lua)
      e.weapon:drawUncleChar(e[4], e[5], e[6] == 2, e[2], e[3], e.dmaFrame or 0)
    else
      self:oam(e[2], e[3], e[4], e[5], e[6])
    end
  end
end

function S:drawGuard(a, x, y, frame)
  local g = self.info.guard
  local D = SD[a.dir or 1]
  local anim = a.moving and math.floor(frame / 8) % 4 or 0
  local gr = g.gfx2[D * 4 + anim + 1] or 0
  local hd = D
  local f = oamFlags(self.info, a.type)
  local list = {}
  list[#list + 1] = { 0, x, y - (g.d1yd[gr + 1] or 8), g.d1char[hd + 1], bit.bor(g.d1flags[hd + 1], f), 2 }
  local bodySlot = rshift(g.d2oam[D + 1] or 12, 2)
  for i = 3, 0, -1 do
    local j = i + gr * 4 + 1
    local ch, big = g.d2char[j], g.d2big[j]
    if ch ~= 0x40 then
      local fl = bit.bor(g.d2flags[j], f)
      if big == 0 then fl = bit.bor(band(fl, 0xF1), 8) end
      list[#list + 1] = { bodySlot + (3 - i), x + g.d2xd[j], y + g.d2yd[j], ch, fl, big }
    end
  end
  local wSlot = rshift(g.d3oam[D + 1] or 4, 2)
  for i = 1, 0, -1 do
    local j = i + gr * 2 + 1
    list[#list + 1] = { wSlot + (1 - i), x + g.d3xd[j], y + g.d3yd[j],
                        g.d3char[j] + (a.type < 0x43 and 3 or 0), bit.bor(g.d3flags[j], f), 0 }
  end
  flush(self, list)
end

function S:drawRecruit(a, x, y, frame)
  local g, r = self.info.guard, self.info.recruit
  local D = SD[a.dir or 1]
  local f = oamFlags(self.info, a.type)
  local gr = r.gfx[D + (a.moving and band(math.floor(frame / 2), 4) or 0) + 1] or 0
  local list = {
    { 0, x, y - 11, g.d1char[D + 1], bit.bor(g.d1flags[D + 1], f), 2 },
    { 1, x + r.x[gr + 1], y, r.char[gr + 1], bit.bor(r.flags[gr + 1], f), 2 },
  }
  flush(self, list)
end

function S:single(a, x, y, gr, extraFlags, thin)
  local info = self.info
  local t = a.type
  local ch = info.single2[(info.single1[t + 1] or 0) + gr + 1]
  if not ch then return end
  local f = bit.bor(band(oamFlags(info, t), 0x3F), extraFlags or 0)
  if thin then
    self:oam(x, y, ch, f, 0)
    self:oam(x, y + 8, ch + 0x20, f, 0)
  else
    self:oam(x, y, ch, f, 2)
  end
end

function S:drawRat(a, x, y, frame)
  local r = self.info.rat
  local D = SD[a.dir or 1]
  local A = a.moving and r.tab4[D * 2 + math.floor(frame / 4) % 2 + 1] or r.tab2[D * 2 + math.floor(frame / 8) % 2 + 1]
  self:single(a, x, y, r.tab0[A + 1] or 0, r.tab1[A + 1] or 0)
end

function S:drawRope(a, x, y, frame)
  local r = self.info.rope
  local A = SD[a.dir or 1] * 2 + math.floor(frame / 8) % 2       -- OURS: the anim index
  self:single(a, x, y, r.gfx[A + 1] or 0, band(r.flags[A + 1] or 0, 0xC0))
end

function S:drawKeese(a, x, y, frame)
  self:single(a, x, y, a.moving and (math.floor(frame / 4) % 2 + 1) or 0)
end

function S:drawDmd(t, list, first, n, x, y, f)
  local out = {}
  for i = 0, n - 1 do
    local e = list[first + i + 1]
    if e then
      local fl = bxor(e[4], f)
      -- page-0 chars below 0x40 are Link's DMA'd sword/shield tiles
      if not (band(fl, 1) == 0 and e[3] < 0x40) then
        out[#out + 1] = { i, x + e[1], y + e[2], e[3], fl, e[5] }
      elseif self.weaponFrame then
        out[#out + 1] = { i, x + e[1], y + e[2], e[3], fl, e[5], weapon = self.weaponGfx(),
                          dmaFrame = self.weaponFrame }
      end
    end
  end
  flush(self, out)
end

function S:drawUncle(a, x, y, frame, priest)
  local info = self.info
  local f = oamFlags(info, a.type)
  local D = SD[a.dir or 1]
  if priest then
    local j = D * 2 + (a.moving and math.floor(frame / 8) % 2 or 0)
    self:drawDmd(a, info.priest, j * 2, 2, x, y, f)
  else
    local gr = a.moving and math.floor(frame / 8) % 2 or 0
    -- bug round: his sword and shield (Uncle_Draw's link_dma_var3/4 by
    -- direction * 2 + frame) from the weapon strip
    local Weapon = require("src.zelda.alttp.Weapon")
    if Weapon.available(self.data) then
      self.weaponGfx = self.weaponGfx or function()
        self.weapon = self.weapon or Weapon.new(self.data)
        return self.weapon
      end
      self.weaponFrame = D * 2 + gr
    end
    self:drawDmd(a, info.uncle, D * 12 + gr * 6, 6, x, y, f)
    self.weaponFrame = nil
  end
end

function S:drawZelda(a, x, y, frame)
  local info = self.info
  local D = SD[a.dir or 1]
  local j = D * 2 + (a.moving and math.floor(frame / 8) % 2 or 0)
  local f = oamFlags(info, a.type ~= nil and a.type or 0x76)
  -- head (dma_var6) above the body (dma_var7), the DMD positions and flips
  for part = 1, 0, -1 do
    local e = info.maiden[j * 2 + part + 1]
    local var = info.maidenDma[j * 2 + part + 1] or 0
    local fl = bxor(e[4], f)
    local im = self:followerImage(var, band(rshift(fl, 1), 7))
    local hf = band(fl, 0x40) ~= 0
    love.graphics.draw(im, x + e[1] + (hf and 16 or 0), y + e[2], 0, hf and -1 or 1, 1)
  end
end

function S:drawMantle(a, x, y)
  local m = self.info.mantle
  local list = {}
  for i = 5, 0, -1 do
    list[#list + 1] = { 5 - i, x + m.x[i + 1], y + m.y[i + 1], m.char[i + 1], m.flags[i + 1], 2 }
  end
  flush(self, list)
end

-- GoodPullSwitch_Draw: chars 0xEE / 0xCE (SNES), the lower part dropped by
-- kGoodPullSwitch_Tab2 while pulled
S.SWITCH_TOP, S.SWITCH_BOTTOM = 0xDE, 0x9E   -- the SNES chars in the GBA layout
function S:drawSwitch(a, x, y)
  local f = oamFlags(self.info, a.type)
  local t = self.info.switchTab2[(a.pulled and 13 or 0) + 1] or 1
  self:oam(x, y - 1 + t, S.SWITCH_BOTTOM, f, 2)
  self:oam(x, y - 1, S.SWITCH_TOP, f, 2)
end

function S:drawKey(a, x, y)
  self:single({ type = 0xE4 }, x, y, 0, 0, true)
end

-- dispatch by sprite type; returns false when the type has no routine here
-- round 9: the drops (sprite types 0xD8-0xE6), zelda3
-- SpriteDraw_AbsorbableTransient with the GBA's tables (data.t.drops):
-- numbered ones (bombs, arrows) as kNumberedAbsorbable entries, else a
-- single small / thin-and-tall / single large picture from the
-- kSprite_PrepAndDrawSingleLarge tables; the heart flips with its sway
-- the rupee shimmer (SNES kLinkDmaCtrs0 / kLinkDmaSources9: frames 0, 1, 2,
-- 0, 1, 2 held 14, 4, 6, 16, 6, 8 frames)
local SHIMMER = { { 14, 0 }, { 4, 1 }, { 6, 2 }, { 16, 0 }, { 6, 1 }, { 8, 2 } }
function S.shimmerFrame(frame)
  local t = (frame or 0) % 54
  for _, e in ipairs(SHIMMER) do
    if t < e[1] then return e[2] end
    t = t - e[1]
  end
  return 0
end

function S:drawAbsorbable(d, x, y, frame)
  local tabs = self.data.t and self.data.t.drops
  if not tabs then return end
  local rf = S.shimmerFrame(frame)
  if rf ~= self.rupeeFrame then
    -- the cached pictures of the two DMA'd chars change with the frame
    self.rupeeFrame = rf
    -- round 13: the cache also holds string keys (a prize rupee dropped
    -- by an enemy hit this in the real app)
    for k in pairs(self.cache) do
      local tile = type(k) == "number" and math.floor(k / 32) or nil
      if tile == 0x0B or tile == 0x2B then self.cache[k] = nil end
    end
  end
  local i = d.type - 0xD8
  local f = band(oamFlags(self.info, d.type), 0x3F)
  local a = tabs.absorbNum[i + 1] or 0
  if a ~= 0 then
    local base = (a - 1) * 3
    for j = base + 2, base, -1 do
      self:oam(x + tabs.numX[j + 1], y + tabs.numY[j + 1], tabs.numChar[j + 1], f, tabs.numExt[j + 1])
    end
    return
  end
  local k = tabs.absorbKind[i + 1] or 0
  local gr = 0
  if d.kind == "heart" then
    gr = (d.ai == 1) and 1 or 0
    if (d.xvel or 0) >= 0 then f = bit.bor(f, 0x40) end
  end
  if k == 0 then
    local ch = self.info.single2[(self.info.single1[d.type + 1] or 0) + gr + 1]
    if ch then self:oam(x, y, ch, f, 0) end
  elseif k == 1 then
    self:single({ type = d.type }, x, y, gr, 0, true)
  else
    self:single({ type = d.type }, x, y, gr, 0, false)
  end
end

-- round 9: shadows. Sprites (zelda3 SpriteDraw_Shadow, drawn when the
-- type's flags3 has 0x10): the big shadow, SNES char 0x6C = GBA 0xCC (16x16)
-- at y + 10 with palette 4 ((flags & 0x30) | 8); round 10: the small one
-- (flags3 & 0x20, SNES char 0x38 = GBA 0x68, sprite sheet 0) 8x8 at y + a + 1
-- (a = 2 for SpriteDraw_SingleSmall, else 10).
-- Link (LinkOam shadow, the GBA's kLinkShadows_Chardata 0x169774 = 0x28CC
-- twice, the second h-flipped; kOffsToShadowGivenDir 0x16AAF0/0x16AAFC).
S.LINK_SHADOW_Y = { [0] = 16, 16, 17, 17 }
S.LINK_SHADOW_X = { [0] = 0, 0, -1, 1 }
function S:hasShadow(t)
  local f3 = self.info.flags3[t + 1] or 0
  return band(f3, 0x10) ~= 0
end
function S:drawShadow(x, y, t, a)
  local f3 = t and self.info.flags3[t + 1] or 0
  if band(f3, 0x20) ~= 0 then
    self:oam(x, y + (a or 10) + 1, 0x68, 0x08, 0)
  else
    self:oam(x, y + (a or 10), 0xCC, 0x08, 2)
  end
end
function S:drawLinkShadow(x, y, facing)
  local d = math.floor((facing or 2) / 2)
  local sx, sy = x + (S.LINK_SHADOW_X[d] or 0), y + (S.LINK_SHADOW_Y[d] or 16)
  self:oam(sx, sy, 0xCC, 0x08, 0)
  self:oam(sx + 8, sy, 0xCC, 0x48, 0)
end

-- round 9: outdoors (drops on the overworld): the misc sheet is
-- kVariousPacks[6] (Light World) / [14] (Dark World) -- 1 / 0x0B --, the
-- main sprite palettes as indoors (rows 1-4, 7)
function S:setOverworld(dark, gfx, palSet)
  local info = self.info
  self.subsets = self.subsets or { 0xFF, 0xFF, 0xFF, 0xFF }
  -- round 10: the area's sprite graphics (SNES Overworld_LoadGFXAndScreenSize:
  -- sprite_graphics_index = overworld_sprite_gfx[screen], kSpriteTilesets)
  if gfx then
    local st = info.spriteTilesets
    for k = 1, 4 do
      local v = st[gfx * 4 + k]
      if v and v ~= 0xFF then self.subsets[k] = v end
    end
  end
  local t = self.data.t
  local pi = palSet and t and t.owSprPalInfo
  local sp5l, sp6l = pi and pi[palSet * 2 + 1], pi and pi[palSet * 2 + 2]
  local misc = dark and 0x0B or 1
  local key = "ow" .. misc .. "/" .. table.concat(self.subsets, ",") .. "/" .. tostring(sp5l) .. "," .. tostring(sp6l)
  if key == self.key then return end
  self.key = key
  self.misc = misc
  self.cache = {}
  local d, p = self.data, info.pal
  local pal = {}
  for r = 0, 7 do pal[r] = {} for c = 0, 15 do pal[r][c] = 0 end end
  for r = 0, 3 do for c = 0, 15 do pal[1 + r][c] = d:blobColor(p.main[1] + 16 * r + c) end end
  for c = 0, 15 do pal[7][c] = d:blobColor(0xB0 + (p.misc[1] or 0) + c) end
  -- Palette_MiscSprite_Outdoors: misc sprite palette 7 (Dark World 9) to
  -- sp0r, the one before it to sp6r (the leaves and pot shards)
  -- r23: sp0l outdoors (Overworld_LoadPalettes: palette_sp0l = 1, Dark
  -- World 3; Palette_Load_Sp0L from kPalette_SpriteAux3) -- the desert
  -- statues use it
  for c = 0, 7 do pal[0][c] = d:blobColor(0x100 + (p.aux3[(dark and 3 or 1) + 1] or 0) + c) end
  local t = dark and 9 or 7
  for c = 0, 7 do
    pal[0][8 + c] = d:blobColor(0x108 + (p.misc[t + 1] or 0) + c)
    pal[6][8 + c] = d:blobColor(0x108 + (p.misc[t] or 0) + c)
  end
  -- round 10: Overworld_LoadPalettes' sprite part (kOwSprPalInfo, 0xFF keeps):
  -- rows 5 and 6 left halves from the sprite aux sets (blob 0x200 + n)
  for row, v in pairs({ [5] = sp5l, [6] = sp6l }) do
    if v and v ~= 0xFF then
      for c = 0, 7 do pal[row][c] = d:blobColor(0x200 + (p.aux1[v + 1] or 0) + c) end
    end
  end
  self.pal = pal
end

function S:drawActor(a, x, y, frame, room)
  local t = a.type
  if t == 0x4B then self:drawRecruit(a, x, y, frame)
  elseif t == 0x6A and a.bc and require("src.zelda.alttp.BallChain").draw(self, a, x, y) then
    -- round 16: the ball-and-chain guard's own drawing (BallChain.lua)
  elseif (t >= 0x41 and t <= 0x4A) or t == 0x6A then self:drawGuard(a, x, y, frame)
  elseif t == 0x6D then self:drawRat(a, x, y, frame)
  elseif t == 0x6E then self:drawRope(a, x, y, frame)
  elseif t == 0x6F then self:drawKeese(a, x, y, frame)
  elseif t == 0x73 then self:drawUncle(a, x, y, frame, room == 0x12)
  elseif t == 0x76 then self:drawZelda(a, x, y, frame)
  elseif t == 0xEE then self:drawMantle(a, x, y)
  elseif t == 0x04 or t == 0x06 then self:drawSwitch(a, x, y)
  elseif t == 0xE4 then self:drawKey(a, x, y)
  -- round 10: what a secret holds (SpriteDraw_SingleSmall for the bee,
  -- SingleLarge for the cucco and the hoarder; h-flip by x velocity, the
  -- hoarder's kRupeeCrab_OamFlags 0, 0, 0x40, 0)
  elseif t == 0x79 then
    local ch = self.info.single2[(self.info.single1[t + 1] or 0) + (a.gfx or 0) + 1]
    if ch then self:oam(x, y, ch, bit.bor(band(oamFlags(self.info, t), 0x3F), a.flip and 0x40 or 0), 0) end
  elseif t == 0x0B then self:single(a, x, y, 0, a.flip and 0x40 or 0)
  elseif t == 0x3E then
    local j = math.floor((a.sub2 or 0) / 2) % 4
    self:single(a, x, y, a.gfx or 0, (j == 2) and 0x40 or 0)
  -- round 17: the Eastern Palace's sprites (Palace.lua)
  elseif a.palace then
    return require("src.zelda.alttp.Palace").draw(self, a, x, y, frame)
  -- r23: the desert statues (Desert.lua)
  elseif a.desert then
    return require("src.zelda.alttp.Desert").draw(self, a, x, y, frame)
  -- round 16: the townsfolk (Npc.lua)
  elseif require("src.zelda.alttp.Npc").TYPES[t] then
    return require("src.zelda.alttp.Npc").draw(self, a, x, y, frame)
  else return false end
  return true
end

return S
