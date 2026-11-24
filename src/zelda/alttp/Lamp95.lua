-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BUG ROUND 95 (user report "I'm getting multiple lamps"): a chest's item is
-- swapped for its alternate when Link already owns it.
--
-- GBA Link_PerformOpenChest (0x080A16B6..0x080A16FA): the chest's item i
-- (OpenChestForItem; 0x80+ is nothing) ->
--   alt = kReceiveItemAlternates[i] (the table its literal at 0x080A16CA
--   points to, read at import); alt != 0xFF and the inventory byte
--   kMemoryLocationToGiveItemTo[i] (Gear.lua) != 0 -> i = alt;
--   then i == 0x44 (`cmp r2, #imm` 0x080A16EA) and the bow's byte (the
--   literal at 0x080A16EE) == 0 -> i = 0x36 (`movs r2, #imm` 0x080A16F6)
--   -> Link_ReceiveItem(i).
-- The SNES table: the lamp, the blue boomerang and the second red-boomerang
-- source each have an alternate (a small rupee prize). The port gave the
-- chest's own item every time: the second lamp chest (Hyrule Castle's) gave
-- a second lamp -- another receipt, another entry in progress.items.
--
-- The magic: a new file starts with an empty meter (Hud.NEW, the GBA's new
-- file routine), as on the cartridge; the lamp costs magic only to light a
-- torch / show its flame (LinkItem_Lamp, Items.lua) -- its dark-room cone
-- needs none.
--
-- Save repair (a save from before this round): duplicate entries of an item
-- that has an alternate are dropped from progress.items, and each dropped
-- one gives the alternate's rupees (Receipt52.rupeesOf) the cartridge would
-- have given.

local bit = require("bit")
local band = bit.band

local M = { NAME = "lamp95" }

M.SITES = { open = 0x080A16B6, altLdr = 0x080A16CA, arrowCmp = 0x080A16EA, bowLdr = 0x080A16EE,
            arrowMovs = 0x080A16F6 }
M.INV_BASE = 0x02002300

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
-- `cmp rN, #imm8` (0x28xx..0x2Fxx) / `movs rN, #imm8` (0x20xx..0x27xx)
local function imm8(rom, a, top)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= top then return nil end
  return band(h, 0xFF)
end

function M.extract(rom, R, check)
  local p = lit(rom, M.SITES.altLdr)
  check(p ~= nil and p >= 0x08000000 and p < 0x0A000000, "lamp95: kReceiveItemAlternates literal")
  if not p then return {} end
  local alt = {}
  local n = 0
  for i = 0, 75 do
    alt[i + 1] = rom:u8(off(p) + i)
    if alt[i + 1] ~= 0xFF then n = n + 1 end
  end
  check(n > 0 and n < 16, "lamp95: kReceiveItemAlternates entries")
  local t = { alt = alt }
  local bow = lit(rom, M.SITES.bowLdr)
  t.arrowItem = imm8(rom, M.SITES.arrowCmp, 0x2800)
  t.arrowElse = imm8(rom, M.SITES.arrowMovs, 0x2000)
  t.bowByte = bow and bow - M.INV_BASE or nil
  check(t.arrowItem and t.arrowElse and t.bowByte and t.bowByte >= 0x20 and t.bowByte < 0x80,
        "lamp95: the no-bow arrows rule")
  return t
end

local function tabs(game) return game.data and game.data.t and game.data.t.lamp95 end

-- the item a chest gives (Link_PerformOpenChest): the alternate when Link
-- owns the item already, the no-bow arrows rule
function M.chestItem(game, item)
  local t = tabs(game)
  if not (t and t.alt and item and item >= 0 and item < 0x80) then return item end
  local inv = require("src.zelda.alttp.Menu").inventory(game)
  local a = t.alt[item + 1]
  if a and a ~= 0xFF then
    local gear = game.data.t.gear
    local addr = gear and gear.addr and gear.addr[item + 1]
    if addr and (inv[addr] or 0) ~= 0 then item = a end
  end
  if t.arrowItem and item == t.arrowItem and (inv[t.bowByte] or 0) == 0 then item = t.arrowElse end
  return item
end

-- drop the duplicates of items that have an alternate; returns how many
function M.repair(game)
  local t = tabs(game)
  local p = game.progress
  if not (t and t.alt and p and type(p.items) == "table") then return 0 end
  local seen, keep, dropped = {}, {}, 0
  local rupees = 0
  for _, id in ipairs(p.items) do
    local a = type(id) == "number" and id >= 0 and id < 76 and t.alt[id + 1]
    if a and a ~= 0xFF and seen[id] then
      dropped = dropped + 1
      local R = require("src.zelda.alttp.Receipt52")
      local tb = game.data.t.rcpt52
      rupees = rupees + ((tb and R.rupeesOf(tb, a)) or 0)
    else
      seen[id] = true
      keep[#keep + 1] = id
    end
  end
  if dropped > 0 then
    p.items = keep
    local s = game.stats
    if s and rupees > 0 then s.rupees = math.min(999, (s.rupees or 0) + rupees) end
    game.itemRepair95 = dropped
  end
  return dropped
end

function M.install(G)
  if G.lamp95Installed then return end
  G.lamp95Installed = true

  local new0 = G.new
  G.new = function(opts)
    local self = new0(opts)
    M.repair(self)
    return self
  end

  local act0 = G.escapeAct
  function G:escapeAct()
    local inside = self.interior
    local E = require("src.zelda.alttp.Escape")
    local lk = self.link
    local f = inside and E.FRONT and E.FRONT[lk.facing]
    local chest = f and inside.chestAt and inside:chestAt(lk.x + f[1], lk.y + f[2])
    local item = chest and not chest.opened and chest.item
    if not item then return act0(self) end
    local alt = M.chestItem(self, item)
    if alt == item then return act0(self) end
    chest.item = alt
    self.chestAlts95 = (self.chestAlts95 or 0) + 1
    local ok, r = pcall(act0, self)
    chest.item = item
    if not ok then error(r, 0) end
    return r
  end
end

return M
