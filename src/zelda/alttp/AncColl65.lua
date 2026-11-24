-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE THROWN BOMB'S TILE TEST (round 65). The port flew a thrown bomb
-- (Carry.lua / Items.lua bombFrame) until Link's own collision met a wall,
-- so the bomb could not be thrown over the attic's low rail (room 0x65,
-- attribute 0x02) onto the cracked floor that lets the light into Blind's
-- room. The cartridge tests ancillae with their own class per attribute:
--
--   Ancilla07_Bomb (0x0811AC24) calls Ancilla_CheckTileCollision
--   (0x080BFE6C, bl at 0x0811ACF4, r1 = 0) -> Ancilla_CheckTileCollisionOne
--   Floor (0x080BFFFC, bl at 0x080BFF70): the probe is the ancilla's spot +
--   kAncilla_Yoffs / Xoffs[ancilla_dir] (lo / hi byte tables, literals
--   0x080C0018 / 0x080C002A for y, 0x080C0048 / 0x080C005A for x), the
--   attribute of the ancilla's floor (0x080C781C), then the class
--   kAncilla_TileCollClass[attr] (literal 0x080C011A, `ldr r1`):
--     0 no collision; 1 collision; 2 the slope test (0x080C7948);
--     3 collision only while ancilla +0x1860 (its "over a pit" byte) is set;
--     4 (ledges 0x28-0x2F, 0x4C-0x4F): +0x1860 clear -> the ancilla's
--       +0xA74 floor flag is set, no collision.
--   So 0x02 (the low walls and rails) is class 0: thrown things pass over.
--
-- Ported: the class table and the probe offsets (read at import), the
-- thrown bomb's flight uses them (G:bombFrame / G:carryBlocked wrapped).
-- OURS: the probe point stays the port's (the bomb's x, y + 4, ahead by
-- the cartridge's offset for its direction); class 2 counts as a wall,
-- class 3 as free (+0x1860 is not kept); the other ancillae keep their
-- own tests.

local bit = require("bit")
local band = bit.band

local M = {}

M.BOMB_FN, M.CHECK_FN, M.ONE_FLOOR_FN = 0x0811AC24, 0x080BFE6C, 0x080BFFFC
M.SITES = { bombCall = 0x0811ACF4, oneFloorCall = 0x080BFF70, classLit = 0x080C011A,
            yLo = 0x080C0018, yHi = 0x080C002A, xLo = 0x080C0048, xHi = 0x080C005A }

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function lit(at) local v, form = RT.codeImm(rom, at); if form ~= "ldr" then return nil end return v end
  local t = {}
  local cl = lit(S.classLit)
  if cl then t.class = rom:bytesU8(cl - 0x08000000, 256) end
  local function offs(lo, hi)
    local a, b = lit(lo), lit(hi)
    if not (a and b) then return nil end
    local l, h = rom:bytesU8(a - 0x08000000, 4), rom:bytesU8(b - 0x08000000, 4)
    local o = {}
    for i = 1, 4 do local v = l[i] + h[i] * 256; if v >= 0x8000 then v = v - 0x10000 end o[i] = v end
    return o
  end
  t.yOff, t.xOff = offs(S.yLo, S.yHi), offs(S.xLo, S.xHi)
  local calls = RT.blTarget(rom, S.bombCall) == M.CHECK_FN and RT.blTarget(rom, S.oneFloorCall) == M.ONE_FLOOR_FN
  check(calls and t.class and t.yOff and t.xOff and t.class[1] == 0 and t.class[2] ~= 0
        and t.yOff[1] < 0 and t.yOff[2] > 0 and t.xOff[3] < 0 and t.xOff[4] > 0,
        "the ancilla tile collision class table and probe offsets")
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.anc65 end
M.tab = tab

-- the cartridge's class for an attribute (nil without the table)
function M.class(T, attr) return T.class[band(attr or 1, 0xFF) + 1] end

-- does an ancilla at (x, y) moving (vx, vy) meet a tile? (indoors)
function M.blocked(game, T, x, y, vx, vy)
  local inside = game.interior
  local d = (vy < 0 and 1) or (vy > 0 and 2) or (vx < 0 and 3) or (vx > 0 and 4) or nil
  local px, py = x, y
  if d then px, py = x + T.xOff[d], y + T.yOff[d] end
  local a = inside:attrAt(px, py)
  local c = M.class(T, a)
  return c == 1 or c == 2
end

function M.install(G)
  local bf0 = G.bombFrame
  if bf0 then
    function G:bombFrame(a)
      self._anc65 = a.fly and a or nil
      local r = bf0(self, a)
      self._anc65 = nil
      return r
    end
  end
  local cb0 = G.carryBlocked
  function G:carryBlocked(x, y)
    local a, T = self._anc65, tab(self)
    if a and a.fly and T and self.state == "room" and self.interior then
      self.ancColl65 = (self.ancColl65 or 0) + 1
      return M.blocked(self, T, x, y, a.fly.vx or 0, a.fly.vy or 0)
    end
    return cb0(self, x, y)
  end
end

return M
