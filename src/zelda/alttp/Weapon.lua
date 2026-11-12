-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK'S SWORD AND SHIELD (bug round, user report "no sword animation or
-- sprite"). The SNES LinkOam_Main the GBA kept (zelda3 player_oam.c), with
-- the cartridge's own tables (RomMap.weapon, read at import into t.weapon):
--
--   * the pose index r2 = playerOamOffs[dir * 40 + yt] + rt (yt 0 standing
--     or walking, 0x27 the sword swing with rt = button_b_frames 0-8, 0x0D
--     carrying, 0x0E throwing, 0x10 lifting);
--   * the sword: selector j = swordSel[r2] (0xFF none; j >= 29 are rods and
--     other equipment, not drawn here), 3 OAM words swordTiles[j*3..] at
--     (swordX[r2], swordY[r2]) -- two across, the third under the first --
--     16x16 when swordSize[j] = 2; its tiles are DMA'd from the weapon
--     strip at swordDma[swordDmaSel[j] / 2] (chars 5, 6 and 8 rows... the
--     GBA's second row is char + 0x20);
--   * the shield: selector shieldSel[r2], shieldTiles, (shieldX, shieldY - 1)
--     and shieldDma[shieldDmaSel[j] / 2] for j < 8;
--   * draw order: the OAM slot tables by r4loc = spriteLocs[r2] (a lower
--     slot is in front).
--
-- The weapon strip (SNES DecompressSwordGraphics / DecompressShieldGraphics,
-- built in RAM by the cartridge): sprite sheets 0x5E-0x5F (the GBA's sheet
-- table, data.spr), the sword's 12 tiles from the sword type's offset plus
-- the 12 under them (+16 tiles), then the shield's 6 + 6. The type offsets
-- are the SNES kSwordTypeToGfxOffs / kShieldTypeToGfxOffs (3bpp bytes / 24
-- = tiles). Colours: sprite palette 5, columns 8-11 the sword's and 12-15
-- the shield's (the sprite palette loader's sword/shield tables).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Link = require("src.zelda.alttp.Link")

local W = {}
W.__index = W

W.SHEET = 0x5E
W.SWORD_TILE = { [0] = 0, 0, 12, 12, 12 }      -- kSwordTypeToGfxOffs / 24
W.SHIELD_TILE = { [0] = 68, 68, 74, 96 }       -- kShieldTypeToGfxOffs / 24
W.SWORD_CHARS = { [5] = 0, [6] = 1, [0x25] = 12, [0x26] = 13 }   -- char -> strip tile from the DMA source
W.SHIELD_CHARS = { [7] = 0, [8] = 1, [0x27] = 6, [0x28] = 7 }
W.SWING_YT, W.CARRY_YT, W.THROW_YT, W.LIFT_YT = 0x27, 0x0D, 0x0E, 0x10

function W.available(data)
  return data.t and data.t.weapon ~= nil and data.spr ~= nil and data.sprInfo ~= nil
end

function W.new(data)
  return setmetatable({ data = data, w = data.t.weapon, cache = {} }, W)
end

-- the 32 bytes of strip tile b (0-23 sword, 24-35 shield)
function W:stripTile(b, swordType, shieldType)
  local T
  if b < 24 then
    local t0 = W.SWORD_TILE[swordType] or 0
    T = (b < 12) and (t0 + b) or (t0 + 16 + b - 12)
  else
    local s0 = W.SHIELD_TILE[shieldType] or 68
    local k = b - 24
    T = (k < 6) and (s0 + k) or (s0 + 16 + k - 6)
  end
  local sheet, idx = W.SHEET + math.floor(T / 64), T % 64
  local o = sheet * 4096 + idx * 32
  return self.data.spr:sub(o + 1, o + 32)
end

-- sprite palette row 5 for these weapons (16 colours)
function W:palette(swordType, shieldType)
  local key = swordType * 16 + shieldType
  self.pals = self.pals or {}
  if self.pals[key] then return self.pals[key] end
  local p, d = self.data.sprInfo.pal, self.data
  local pal = {}
  for i = 0, 15 do pal[i] = 0 end
  for i = 0, 3 do pal[8 + i] = d:blobColor(0x300 + (p.sword[swordType + 1] or 0) + i) end
  for i = 0, 3 do pal[12 + i] = d:blobColor(0x300 + (p.shield[shieldType + 1] or 0) + i) end
  self.pals[key] = pal
  return pal
end

local function rgb(c)
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end

-- an Image of one 8x8 strip tile (palette row 5)
function W:tileImage(b, swordType, shieldType)
  local key = b * 64 + swordType * 8 + shieldType
  local hit = self.cache[key]
  if hit ~= nil then return hit or nil end
  local src = self:stripTile(b, swordType, shieldType)
  local pal = self:palette(swordType, shieldType)
  local img = love.image.newImageData(8, 8)
  local any = false
  for y = 0, 7 do
    for xb = 0, 3 do
      local v = src:byte(y * 4 + xb + 1) or 0
      for h = 0, 1 do
        local c = h == 0 and v % 16 or math.floor(v / 16)
        if c ~= 0 then
          local r, g, bb = rgb(pal[c] or 0)
          img:setPixel(xb * 2 + h, y, r, g, bb, 1)
          any = true
        end
      end
    end
  end
  local im = false
  if any then
    im = love.graphics.newImage(img)
    im:setFilter("nearest", "nearest")
  end
  self.cache[key] = im
  return im or nil
end

-- the strip tile a weapon char shows, given the DMA source offset (bytes
-- from the strip base) the frame selected
local function charTile(map, char, srcOff)
  local k = map[char]
  if not k then return nil end
  return srcOff / 32 + k
end

-- one OAM word (SNES vhoopppc cccccccc, GBA char numbering) drawn at x, y;
-- big = 16x16 (chars c, c+1, c+0x20, c+0x21)
function W:drawWord(td, x, y, big, map, srcOff, swordType, shieldType)
  local char = band(td, 0x1FF)
  local hf, vf = band(td, 0x4000) ~= 0, band(td, 0x8000) ~= 0
  local n = big and 2 or 1
  local lg = love.graphics
  for ty = 0, n - 1 do
    for tx = 0, n - 1 do
      local b = charTile(map, char + ty * 0x20 + tx, srcOff)
      local im = b and self:tileImage(b, swordType, shieldType)
      if im then
        local sx = hf and (n - 1 - tx) or tx
        local sy = vf and (n - 1 - ty) or ty
        lg.draw(im, x + sx * 8 + (hf and 8 or 0), y + sy * 8 + (vf and 8 or 0), 0, hf and -1 or 1, vf and -1 or 1)
      end
    end
  end
end

-- the pieces of Link's picture for pose (yt, rt): a list of
-- { slot, kind = "body" | "sword" | "shield", ... } sorted back to front
function W:pieces(facing, yt, rt, opts)
  local data, w = self.data, self.w
  local parts, _, r2 = Link.pose(data, facing, rt, yt)
  local loc = w.spriteLocs[r2 + 1] or 0
  local list = {}
  local bodySlot = (w.bodyOamIdx[loc + 1] or 0) / 4
  for i, p in ipairs(parts) do
    list[#list + 1] = { slot = bodySlot + (i - 1), kind = "body", part = p }
  end
  if opts.sword then
    local j = w.swordSel[r2 + 1]
    if j and j ~= 0xFF and j < 29 then
      local dsel = w.swordDmaSel[j + 1] or 0
      local src = (w.swordDma[math.floor(dsel / 2) + 1] or w.stripBase) - w.stripBase
      list[#list + 1] = { slot = (w.swordOamIdx[loc + 1] or 0) / 4, kind = "sword", j = j,
                          x = w.swordX[r2 + 1], y = w.swordY[r2 + 1], big = w.swordSize[j + 1] == 2,
                          src = src }
    end
  end
  -- r21: an item in hand (selectors >= 29: link_dma_var5 = swordDmaSel[j],
  -- LinkOam_SetWeaponVRAMOffsets; the bow only, see W:drawItem)
  if opts.item then
    local j = w.swordSel[r2 + 1]
    if j and j ~= 0xFF and j >= 29 then
      list[#list + 1] = { slot = (w.swordOamIdx[loc + 1] or 0) / 4, kind = "item", j = j,
                          x = w.swordX[r2 + 1], y = w.swordY[r2 + 1], big = w.swordSize[j + 1] == 2,
                          var5 = w.swordDmaSel[j + 1] or 0 }
    end
  end
  if opts.shield then
    local j = w.shieldSel[r2 + 1]
    if j and j ~= 0xFF and j < 8 then
      local dsel = w.shieldDmaSel[j + 1] or 0
      local src = (w.shieldDma[math.floor(dsel / 2) + 1] or (w.stripBase + 0x300)) - w.stripBase - 0x300
      list[#list + 1] = { slot = (w.shieldOamIdx[loc + 1] or 0) / 4, kind = "shield", j = j,
                          x = w.shieldX[r2 + 1], y = w.shieldY[r2 + 1] - 1, src = src }
    end
  end
  table.sort(list, function(a, b) return a.slot > b.slot end)
  return list, r2
end

-- draw a sword or shield piece at Link's screen position (x, y)
function W:drawPiece(pc, x, y, swordType, shieldType)
  local tiles = pc.kind == "sword" and self.w.swordTiles or self.w.shieldTiles
  local map = pc.kind == "sword" and W.SWORD_CHARS or W.SHIELD_CHARS
  local base = pc.kind == "sword" and pc.src or (pc.src + 24 * 32)
  local ox, oy = x + pc.x, y + pc.y
  for i = 0, 2 do
    local td = tiles[pc.j * 3 + i + 1]
    if td and td ~= 0xFFFF then
      -- the shield is always one 16x16 (kShieldStuff r12 = 2 for j < 8)
      self:drawWord(td, ox, oy, pc.kind == "shield" or pc.big, map, base, swordType, shieldType)
    end
    ox = ox + 8
    if i == 1 then ox, oy = ox - 16, oy + 8 end
  end
end

-- r21: THE ITEM STRIP (SNES LoadItemGFXIntoWRAM4BPPBuffer; the GBA keeps its
-- layout: its kLinkDmaSources6 / 7 at 0x22A9F2 / 0x22AAF2 hold the SNES
-- offsets from the strip's start). link_dma_var5 picks the source: chars 9
-- and 10 show the 2 tiles at itemDma[var5], chars 0x29 / 0x2A the 2 at
-- + itemDma2[var5 >> 3] (the second row, VRAM 0x4190). The strip's blocks
-- are sprite sheet tiles, each `n` tiles over the `n` 16 tiles below; only
-- the bow's is listed (rod 7, hammer 7, then the bow: sheet 0 tile 8 =
-- kIntro_LoadGfx_Tab[2], 3 tiles). Colours: the OAM word's palette row of
-- the room's / overworld's sprite palettes (the bow: row 1).
W.ITEM_BLOCKS = { { off = 0x380, n = 3, sheet = 0, tile = 8 } }
W.ITEM_CHARS = { [9] = { 0, 0 }, [10] = { 0, 1 }, [0x29] = { 1, 0 }, [0x2A] = { 1, 1 } }
-- the sheet and tile at a strip byte offset (nil: not a listed block)
function W.itemTile(off)
  for _, b in ipairs(W.ITEM_BLOCKS) do
    local k = (off - b.off) / 32
    if k >= 0 and k < 2 * b.n and k == math.floor(k) then
      return b.sheet, (k < b.n) and (b.tile + k) or (b.tile + 16 + k - b.n)
    end
  end
end
function W:itemImage(sheet, tile, pal, palRow)
  local key = "i" .. sheet * 4096 + tile .. ":" .. palRow .. ":" .. tostring(pal)
  local hit = self.cache[key]
  if hit ~= nil then return hit or nil end
  local o = sheet * 4096 + tile * 32
  local src = self.data.spr:sub(o + 1, o + 32)
  local img = love.image.newImageData(8, 8)
  local any = false
  for y = 0, 7 do
    for xb = 0, 3 do
      local v = src:byte(y * 4 + xb + 1) or 0
      for h = 0, 1 do
        local c = h == 0 and v % 16 or math.floor(v / 16)
        if c ~= 0 and pal[c] then
          local r, g, bb = rgb(pal[c])
          img:setPixel(xb * 2 + h, y, r, g, bb, 1)
          any = true
        end
      end
    end
  end
  local im = false
  if any then
    im = love.graphics.newImage(img)
    im:setFilter("nearest", "nearest")
  end
  self.cache[key] = im
  return im or nil
end
-- draw an item piece at Link's screen position; spr = the room's /
-- overworld's Sprites (its palettes)
function W:drawItem(pc, x, y, spr)
  local fx = self.data.roomIdx and self.data.roomIdx.combat and self.data.roomIdx.combat.fx
  if not fx or not spr or not spr.pal then return end
  local src = fx.itemDma[pc.var5 + 1] or 0
  local src2 = src + (fx.itemDma2[math.floor(pc.var5 / 8) + 1] or 0)
  local tiles = self.w.swordTiles
  local ox, oy = x + pc.x, y + pc.y
  local lg = love.graphics
  for i = 0, 2 do
    local td = tiles[pc.j * 3 + i + 1]
    if td and td ~= 0xFFFF then
      local char = band(td, 0x1FF)
      local hf, vf = band(td, 0x4000) ~= 0, band(td, 0x8000) ~= 0
      local row = band(rshift(td, 9), 7)
      local pal = spr.pal[row]
      local n = pc.big and 2 or 1
      for ty = 0, n - 1 do
        for tx = 0, n - 1 do
          local m = W.ITEM_CHARS[char + ty * 0x20 + tx]
          if m then
            local sheet, tile = W.itemTile((m[1] == 0 and src or src2) + m[2] * 32)
            local im = sheet and pal and self:itemImage(sheet, tile, pal, row)
            if im then
              local sx = hf and (n - 1 - tx) or tx
              local sy = vf and (n - 1 - ty) or ty
              lg.draw(im, ox + sx * 8 + (hf and 8 or 0), oy + sy * 8 + (vf and 8 or 0), 0, hf and -1 or 1, vf and -1 or 1)
            end
          end
        end
      end
    end
    ox = ox + 8
    if i == 1 then ox, oy = ox - 16, oy + 8 end
  end
end

-- The uncle's sword and shield (zelda3 Uncle_Draw: link_dma_var3/4 from
-- kUncleDraw_Dma3/4 by dir * 2 + frame): an OAM entry of his draw list whose
-- page-0 char is below 0x40 shows the weapon strip.
function W:drawUncleChar(char, flags, big, x, y, j)
  local w = self.w
  local d3 = w.uncleDma3[j + 1] or 0
  local d4 = w.uncleDma4[j + 1] or 0
  local td = char + band(flags, 0xC0) * 256
  if W.SWORD_CHARS[char] then
    local src = (w.swordDma[math.floor(d3 / 2) + 1] or w.stripBase) - w.stripBase
    self:drawWord(td, x, y, big, W.SWORD_CHARS, src, 1, 1)
  elseif W.SHIELD_CHARS[char] then
    local src = (w.shieldDma[math.floor(d4 / 2) + 1] or (w.stripBase + 0x300)) - w.stripBase - 0x300
    self:drawWord(td, x, y, big, W.SHIELD_CHARS, src + 24 * 32, 1, 1)
  end
end

return W
