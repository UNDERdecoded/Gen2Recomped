-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 74: values the runtime modules still carried as literals, now read
-- from the player's ROM at import (data.t.tab74) and poured into live
-- tables when the cache is bound (RomTables.onBind). A module asks for a
-- table by name (M.get) at load time and gets an empty table the bind fills
-- in place. Only the code sites live here; the values come from the cartridge.
--
--   points     Player_TileDetectNearby (0x0809EDA4): Link's four detection
--              points. x + T1[0] / T2[0], y + T1[2] / T2[2], the tables
--              loaded by `ldr r5` at 0x0809EDC4 (T1) and `ldr r2` at
--              0x0809EDDE (T2), s16. Used by Hook73 (the hookshot arrival)
--              and Dungeons26.pitBits. Rows in bit order 8 / 4 / 2 / 1:
--              (x0, y0), (x1, y0), (x0, y1), (x1, y1).
--   potSwitch  RevealPotItem (0x080929C8), secret 0x88: the four switch
--              words (UL LL UR LR) loaded at 0x080929E8 / F2 / FC / 0x08092A06.
--   blindTrig  Follower_CheckBlindTrigger: the maiden's spot in room 0xAC,
--              y = the literal `ldr` at 0x08115C52, x = `movs #; lsls #5` at
--              0x08115C64, both & 0x1FF (room-relative), and the reach
--              (`cmp r0, #n; bgt` at 0x08115C5C / 70: |d| <= n).
--   agahOam    kAgahnim_OamFlags (SpritePrep_Agahnim, `ldr r2` at 0x080DB514),
--              2 bytes indexed by the Dark World flag.
--   giboFlags2 kGibo_OamFlags2 (Gibo_Draw, `ldr r3` at 0x080FF5F0), 2 bytes.

local band, bnot, lshift = bit.band, bit.bnot, bit.lshift

local M = {}

M.SITES = {
  tdnT1 = 0x0809EDC4, tdnT2 = 0x0809EDDE,
  potSwitch = { 0x080929E8, 0x080929F2, 0x080929FC, 0x08092A06 },
  blindY = 0x08115C52, blindX = 0x08115C64, blindR = { 0x08115C5C, 0x08115C70 },
  agahOam = 0x080DB514,
  giboFlags2 = 0x080FF5F0,
}

local function off(a) return a - 0x08000000 end

-- `ldr rN, [pc, #imm]` at GBA address a -> the literal's value
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

-- `movs rN, #imm` (optionally followed by `lsls rN, rN, #s`)
local function movs(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x2000 then return nil end
  local r, v = band(bit.rshift(h, 8), 7), band(h, 0xFF)
  local h2 = rom:u16(o + 2)
  if band(h2, 0xF800) == 0x0000 and band(h2, 7) == r and band(bit.rshift(h2, 3), 7) == r then
    v = lshift(v, band(bit.rshift(h2, 6), 0x1F))
  end
  return v
end

-- `cmp rN, #imm`
local function cmpImm(rom, a)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= 0x2800 then return nil end
  return band(h, 0xFF)
end

local function s16(rom, o)
  local v = rom:u16(o)
  return v >= 0x8000 and v - 0x10000 or v
end

function M.extract(rom, R, check)
  local S, t = M.SITES, {}
  local t1, t2 = lit(rom, S.tdnT1), lit(rom, S.tdnT2)
  check(t1 and t2 and t1 >= 0x08000000 and t2 >= 0x08000000, "TileDetectNearby tables")
  local x0, x1 = s16(rom, off(t1)), s16(rom, off(t2))
  local y0, y1 = s16(rom, off(t1) + 4), s16(rom, off(t2) + 4)
  check(x0 >= 0 and x1 > x0 and x1 < 32 and y0 >= 0 and y1 > y0 and y1 < 32, "TileDetectNearby points")
  t.points = { { x0, y0 }, { x1, y0 }, { x0, y1 }, { x1, y1 } }
  t.potSwitch = {}
  for k, a in ipairs(S.potSwitch) do
    local v = lit(rom, a)
    check(v and v < 0x10000, "pot switch word %d", k)
    t.potSwitch[k] = v
  end
  check(t.potSwitch[3] == t.potSwitch[1] + 0x400 and t.potSwitch[4] == t.potSwitch[2] + 0x400, "pot switch words")
  local by, bx = lit(rom, S.blindY), movs(rom, S.blindX)
  local r1, r2 = cmpImm(rom, S.blindR[1]), cmpImm(rom, S.blindR[2])
  check(by and bx and r1 and r1 == r2, "Blind trigger")
  t.blindTrig = { band(bx, 0x1FF), band(by, 0x1FF), r = r1 + 1 }
  for _, k in ipairs({ "agahOam", "giboFlags2" }) do
    local p = lit(rom, S[k])
    check(p and p >= 0x08000000, "%s pointer", k)
    local a, b = rom:u8(off(p)), rom:u8(off(p) + 1)
    check(a < 16 and b < 16 and a ~= b, "%s flags", k)
    t[k] = { [0] = a, b }
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
  if all and all.tab74 then M.bind(all.tab74) end
end)

return M
