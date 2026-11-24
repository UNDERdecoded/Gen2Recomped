-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 76: literals Tables75 left, read from the player's ROM at import
-- (data.t.tab76) and poured into live tables on RomTables.onBind, as
-- Tables74 / Tables75 do. Only the code sites live here (every table is
-- signed bytes, indexed by a direction 0-3).
--
--   Hera.lua's Kodongo (Sprite_86_Kodongo / Sprite_87_KodongoFire):
--     kodXv / kodYv     kKodondo_Xvel / _Yvel, the first move's probe
--                       (`ldr r1` at 0x0810FE28 / 0x0810FE34)
--     dirXv / dirYv     Kodongo_SetDirection's speeds (kFluteBoyAnimal_Xvel
--                       / kZazak_Yvel: `ldr r1` at 0x0810FE78 / 0x0810FE82,
--                       again at 0x0810FECE / 0x0810FEDE)
--     fireX / fireY     Kodongo_SpawnFire's spot: the low bytes (`ldr r0`
--                       at 0x0811005A / 0x08110084) and the high bytes
--                       (0x08110064 / 0x0811008E) of a 16-bit offset
--     fireXv / fireYv   the flame's speed (`ldr r0` at 0x081100B0 /
--                       0x081100BE)
--   Items.lua's arrow in a sprite: Ancilla_CheckSpriteCollision's recoil,
--   indexed by the ancilla's direction & 3 (+0xE3D):
--     arrowRx / arrowRy `ldr r0` at 0x080C0CAE (-> the sprite's x recoil,
--                       +0x1112) / 0x080C0CBC (-> y recoil, +0x1102)

local band, bnot = bit.band, bit.bnot

local M = {}

M.SITES = {
  kodXv = { 0x0810FE28 }, kodYv = { 0x0810FE34 },
  dirXv = { 0x0810FE78, 0x0810FECE }, dirYv = { 0x0810FE82, 0x0810FEDE },
  fireXlo = { 0x0811005A }, fireXhi = { 0x08110064 }, fireYlo = { 0x08110084 }, fireYhi = { 0x0811008E },
  fireXv = { 0x081100B0 }, fireYv = { 0x081100BE },
  arrowRx = { 0x080C0CAE }, arrowRy = { 0x080C0CBC },
}

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

local function s8(v) if v >= 128 then return v - 256 end return v end

-- the table every site of a name loads (all of them the same pointer)
local function ptr(rom, check, name)
  local p
  for _, a in ipairs(M.SITES[name]) do
    local v = lit(rom, a)
    check(v and v >= 0x08000000 and (p == nil or p == v), "table76 %s pointer", name)
    p = v
  end
  return p
end

local function bytes4(rom, p)
  local t = {}
  for i = 0, 3 do t[i] = rom:u8(off(p) + i) end
  return t
end

function M.extract(rom, R, check)
  local t = {}
  for _, n in ipairs({ "kodXv", "kodYv", "dirXv", "dirYv", "fireXv", "fireYv", "arrowRx", "arrowRy" }) do
    local b = bytes4(rom, ptr(rom, check, n))
    t[n] = { [0] = s8(b[0]), s8(b[1]), s8(b[2]), s8(b[3]) }
  end
  for _, n in ipairs({ "fireX", "fireY" }) do
    local lo, hi = bytes4(rom, ptr(rom, check, n .. "lo")), bytes4(rom, ptr(rom, check, n .. "hi"))
    local v = {}
    for i = 0, 3 do
      local w = lo[i] + hi[i] * 256
      v[i] = (w >= 0x8000) and (w - 0x10000) or w
    end
    t[n] = v
  end
  -- shapes: one axis per direction pair (up / down move y, left / right x)
  check(t.kodXv[2] == 0 and t.kodYv[0] == 0 and t.arrowRx[0] == 0 and t.arrowRy[2] == 0
        and t.kodXv[0] == -t.kodXv[1] and t.arrowRx[2] == -t.arrowRx[3], "table76 shapes")
  return t
end

function M.install(G) end

-- live tables (0-based, by direction)
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
  if all and all.tab76 then M.bind(all.tab76) end
end)

return M
