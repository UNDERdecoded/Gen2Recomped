-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 75: the last two literals Tables74 left (Dungeons26.CRYSTAL_PAL,
-- Cape.DEPLETE), read from the player's ROM at import (data.t.tab75) and
-- poured into live tables on RomTables.onBind, as Tables74 does. Only the
-- code sites live here.
--
--   crystalPal   kCrystalSwitchPal: Sprite_CrystalSwitch (type 0x1E, main
--                0x0810FC0C) loads the table with `ldr r4` at 0x0810FC2E and
--                indexes it with the barrier state & 1 (0x0810FC3C..42), the
--                byte or-ed into the OAM flags (palette bits 0x0E).
--   capeDeplete  kCapeDepletionTimers: LinkItem_Cape puts on the cape
--                (`ldr r1` at 0x080A37C8) and the drain reloads it
--                (`ldr r1` at 0x080A3836), indexed by link_magic_consumption
--                (inventory byte 0x5B, GBA 0x0200235B), 3 bytes.

local band, bnot = bit.band, bit.bnot

local M = {}

M.SITES = {
  crystalPal = 0x0810FC2E,
  capeDeplete = { 0x080A37C8, 0x080A3836 },
}

local function off(a) return a - 0x08000000 end

-- `ldr rN, [pc, #imm]` at GBA address a -> the literal's value
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end
M.lit = lit

function M.extract(rom, R, check)
  local S, t = M.SITES, {}
  local p = lit(rom, S.crystalPal)
  check(p and p >= 0x08000000, "crystal switch palette pointer")
  local a, b = rom:u8(off(p)), rom:u8(off(p) + 1)
  check(band(a, 0xF1) == 0 and band(b, 0xF1) == 0 and a ~= b, "crystal switch palettes")
  t.crystalPal = { [0] = a, b }
  local c1, c2 = lit(rom, S.capeDeplete[1]), lit(rom, S.capeDeplete[2])
  check(c1 and c1 == c2 and c1 >= 0x08000000, "cape depletion table pointer")
  t.capeDeplete = {}
  for i = 0, 2 do
    local v = rom:u8(off(c1) + i)
    check(v >= 1 and v <= 64, "cape depletion timer %d", i)
    t.capeDeplete[i + 1] = v
  end
  return t
end

function M.install(G) end

-- live tables
local live = {}
function M.get(name)
  local t = live[name]
  if not t then t = {}; live[name] = t end
  return t
end

function M.bind(tab)
  for name, src in pairs(tab) do
    local dst = M.get(name)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
  end
end

require("src.zelda.alttp.RomTables").onBind(function(all)
  if all and all.tab75 then M.bind(all.tab75) end
end)

return M
