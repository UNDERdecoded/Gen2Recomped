-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK'S GEAR (round 26, team A): every item receipt into the inventory,
-- the sword / shield / mail levels and their pictures.
--
--   Link_ReceiveItem      kMemoryLocationToGiveItemTo / kValueToGiveItemTo:
--                         the GBA keeps both, its addresses already in its
--                         own inventory layout (0x02002300 + n: 76 u32 at
--                         0x16E344, 76 int8 at 0x16E4A4 -- e.g. receipt 0x14
--                         the flute -> 0x2E = 2, 0x4A the active flute -> 3,
--                         0x13 the shovel -> 0x32, 0x1B / 0x1C the gloves ->
--                         0x38 = 1 / 2, 0x22 / 0x23 the mails -> 0x3F = 1 / 2,
--                         0x00-0x03 the swords -> 0x3D = 1..4, 0x04-0x06 the
--                         shields -> 0x3E = 1..3). A positive value is
--                         written; the negative ones (keys, rupees, hearts,
--                         bottles, arrows, bombs) keep their own routines.
--   LoadGearPalettes      the mail's palette kPalette_ArmorAndGloves +
--                         armor * 15: the GBA's palette blob rows 0xB0
--                         (green), 0xC0 (blue), 0xD0 (red), 0xE0 (the
--                         bunny, LoadGearPalettes_bunny = armour 3).
--   the sword / shield    LinkOam's weapon strip by link_sword_type /
--                         link_shield_type (Weapon.lua: kSwordTypeToGfxOffs,
--                         kShieldTypeToGfxOffs and their palettes).

local bit = require("bit")
local band = bit.band

local GR = {}

GR.OFF = { giveAddr = 0x16E344, giveValue = 0x16E4A4 }
GR.INV_BASE = 0x02002300
GR.PAL_ROW = { [0] = 0xB0, 0xC0, 0xD0, 0xE0 }

function GR.extract(rom, R, check)
  local t = { addr = {}, value = {} }
  for i = 0, 75 do
    local a = rom:u32(GR.OFF.giveAddr + i * 4)
    t.addr[i + 1] = a - GR.INV_BASE
    local v = rom:u8(GR.OFF.giveValue + i)
    t.value[i + 1] = v >= 128 and v - 256 or v
  end
  check(t.addr[0x00 + 1] == 0x3D and t.value[0x03 + 1] == 4 and t.addr[0x04 + 1] == 0x3E
        and t.addr[0x14 + 1] == 0x2E and t.value[0x4A + 1] == 3 and t.addr[0x4B + 1] == 0x39,
        "kMemoryLocationToGiveItemTo / kValueToGiveItemTo (GBA layout)")
  return t
end

local function T(game) return game.data.t and game.data.t.gear end

function GR.inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
function GR.swordType(game)
  local v = GR.inv(game)[0x3D] or 0
  if v == 0 and game.progress.sword then v = 1 end
  return v
end
function GR.shieldType(game)
  local v = GR.inv(game)[0x3E] or 0
  if v == 0 and game.progress.sword then v = 1 end
  return v
end
function GR.armor(game) return GR.inv(game)[0x3F] or 0 end

-- Link's 16 colours for an armour row (0 green .. 3 bunny)
function GR.palette(game, row)
  game.gearPals = game.gearPals or {}
  local p = game.gearPals[row]
  if p then return p end
  p = {}
  local base = GR.PAL_ROW[row] or 0xB0
  for i = 0, 15 do p[i] = game.data:blobColor(base + i) end
  game.gearPals[row] = p
  return p
end

-- ItemReceipt_GiveBottledItem: kBottleList fills the first bottle below 2
-- with j + 2, kPotionList the first empty one (2) with j + 3 (the GBA's
-- bottles are grid slots 6 / 12 / 18 / 24)
GR.BOTTLES = { 0x25, 0x2B, 0x31, 0x37 }
GR.BOTTLE_LIST = { 0x16, 0x2B, 0x2C, 0x2D, 0x3D, 0x3C, 0x48 }
GR.POTION_LIST = { 0x2E, 0x2F, 0x30, 0xFF, 0x0E }
function GR.giveBottled(game, id)
  local p = game.progress
  local inv = GR.inv(game)
  local function put(k, v) p.inv[k] = v; p.inv[tostring(k)] = nil; game.bottleFills = (game.bottleFills or 0) + 1 end
  for j, b in ipairs(GR.BOTTLE_LIST) do
    if b == id then
      for _, k in ipairs(GR.BOTTLES) do
        if (inv[k] or 0) < 2 then return put(k, (j - 1) + 2) end
      end
    end
  end
  for j, b in ipairs(GR.POTION_LIST) do
    if b == id then
      for _, k in ipairs(GR.BOTTLES) do
        if (inv[k] or 0) == 2 then return put(k, (j - 1) + 3) end
      end
    end
  end
end

function GR.install(G)
  -- the receipt (positive kValueToGiveItemTo values)
  local getItem0 = G.getItem
  function G:getItem(id)
    local tb = T(self)
    local r = getItem0(self, id)
    if not (tb and id >= 0 and id < 76) then return r end
    local p = self.progress
    p.inv = p.inv or {}
    local inv = GR.inv(self)
    local function set(addr, v)
      p.inv[addr] = v
      p.inv[tostring(addr)] = nil
      if addr == 0x3D then p.sword = true; p.swordLevel = v end
      if addr == 0x3E then p.shieldLevel = v end
    end
    local addr, v = tb.addr[id + 1], tb.value[id + 1]
    -- receipt 0 (the uncle's sword) also gives shield 1
    if id == 0 then set(tb.addr[4 + 1], tb.value[1]) end
    if v and v > 0 and addr and addr >= 0x20 and addr < 0x80 then
      set(addr, v)
      self.gearReceipts = (self.gearReceipts or 0) + 1
    elseif id == 0x22 then
      if (inv[addr] or 0) == 0 then set(addr, 1) end             -- the blue mail never lowers the red
      self.gearReceipts = (self.gearReceipts or 0) + 1
    elseif id == 0x29 then
      if (inv[addr] or 0) ~= 2 then set(addr, 1) end             -- the mushroom (not over the powder)
    elseif id == 0x17 then
      -- a piece of heart: (n + 1) & 3; the fourth is a heart container
      local n = band((inv[addr] or 0) + 1, 3)
      set(addr, n)
      if n == 0 then
        local s = self.stats
        -- Link_ReceiveItem(0x26): capacity + 8, filled to it
        s.healthMax = math.min(160, (s.healthMax or 24) + 8)
        s.health = s.healthMax
      end
      self.heartPieces = (self.heartPieces or 0) + 1
    else
      GR.giveBottled(self, id)
    end
    return r
  end

  -- the mail / bunny palette and the weapon types for Link's picture
  local drawLink0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk ~= self.link or tint then return drawLink0(self, lk, tint) end
    local row = GR.armor(self)
    if self.isBunny and self:isBunny() then row = 3 end
    local savedPal, savedKey = self.linkPal, self.linkPalKey
    self.linkPal = GR.palette(self, row)
    self.linkPalKey = row == 0 and "green" or ("mail" .. row)
    self.swordType, self.shieldType = math.max(1, GR.swordType(self)), math.max(1, GR.shieldType(self))
    drawLink0(self, lk, tint)
    self.linkPal, self.linkPalKey = savedPal, savedKey
  end
end

return GR
