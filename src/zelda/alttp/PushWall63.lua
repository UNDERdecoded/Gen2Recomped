-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 63: room tag 0x20 (RoomTag_PushSwitchExplodingWall): Link on a floor
-- switch blows the room's type-0x30 wall open, the opener of round 62
-- (Blast62) with another trigger. On this cartridge one room carries it
-- (0x7C, Ganon's Tower).
--
-- GBA, read at import from the code below:
--   * the tag table (`ldr` 0x0807B564): the tag whose routine is 0x0807B61C:
--     bl 0x080798DC (RoomTag_CheckForPressedSwitch), `cmp r0, #1`, then
--     bl 0x0807A178 (the opener, Blast62);
--   * 0x080798DC: nothing while Link is held (+0x1770) or in an aux state
--     (+0x1702); the tile p = ((link_x - `subs #n` 0x08079890) & 0x1F8) >> 3
--     | ((link_y + `adds #n` 0x080798A8) & 0x1F8) << 3 (the lower level's
--     table when +0xA10); the attribute pair at p, p + 64, p + 1, p + 65
--     (that order) both `cmp #n` 0x08079906 or both `cmp #n` 0x08079914;
--     then the pair one row below must repeat the left or the right
--     attribute (0x0807999E..B6); a hit returns 1 and keeps p in +0xB5E.
--
-- OURS: Link's "held" / aux state are the port's wallHold / hop / recoil.

local M = {}

local bit = require("bit")
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift

M.TAG_TABLE_LIT = 0x0807B564
M.TAG_FN = 0x0807B61C
M.CHECK_FN = 0x080798DC
M.OPEN_FN = 0x0807A178
M.SITES = { xSub = 0x08079890, yAdd = 0x080798A8, swA = 0x08079906, swB = 0x08079914,
            callCheck = 0x0807B61E, cmpOne = 0x0807B626, callOpen = 0x0807B62A }

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at, want)
    local v, form = RT.codeImm(rom, at)
    if want and form ~= want then return nil end
    return v
  end
  local t = {}
  local tagTab = imm(M.TAG_TABLE_LIT, "ldr")
  if tagTab then
    for i = 0, 0x3F do
      if rom:u32(tagTab - 0x08000000 + i * 4) == M.TAG_FN + 1 then t.tag = i break end
    end
  end
  t.xSub, t.yAdd = imm(S.xSub, "subs"), imm(S.yAdd, "adds")
  t.swA, t.swB = imm(S.swA, "cmp"), imm(S.swB, "cmp")
  local one = imm(S.cmpOne, "cmp")
  local calls = RT.blTarget(rom, S.callCheck) == M.CHECK_FN and RT.blTarget(rom, S.callOpen) == M.OPEN_FN
  check(t.tag ~= nil and calls and one == 1 and t.xSub and t.yAdd and t.swA and t.swB and t.swA ~= t.swB,
        "push-switch wall tag (tag %s)", tostring(t.tag))
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.push63 end
M.tab = tab

-- 0x080798DC on the room's attribute table; returns the tile or nil
function M.pressed(inside, lk, t)
  local A = (inside.lower and inside.attrsLo) or inside.attrs
  if not A then return nil end
  local p = rshift(band(lk.x - t.xSub, 0x1F8), 3) + lshift(band(lk.y + t.yAdd, 0x1F8), 3)
  for _, q in ipairs({ p, p + 64, p + 1, p + 65 }) do
    local a, b = A[q], A[q + 1]
    if a and a == b and (a == t.swA or a == t.swB) then
      if A[q + 64] == a or A[q + 65] == b then return q end
      return nil
    end
  end
  return nil
end

-- the tag: a switch pressed starts Blast62's opener once
function M.roomTags(actors, lk)
  local game, inside = actors.game, actors.inside
  local t = tab(game)
  local BL = require("src.zelda.alttp.Blast62")
  local bt = BL.tab(game)
  if not (t and t.tag and bt and inside and inside.hdr) then return end
  if inside.blast62 or (inside.mem and inside.mem.blast62) or inside.blast62done then return end
  local hdr = inside.hdr
  if hdr[6] ~= t.tag and hdr[7] ~= t.tag then return end
  if game.wallHold or lk.hop or game.recoil then return end   -- +0x1770 / +0x1702
  if not M.pressed(inside, lk, t) then return end
  local slot, d = BL.door(inside.data, inside.room, bt)
  if not slot then return end
  inside.blast62done = true
  game.pushWalls63 = (game.pushWalls63 or 0) + 1
  BL.startBlast(game, inside, bt, slot, d)
end

-- ------------------------------------------------------------ install
function M.install(G)
  if G.push63Installed then return end
  G.push63Installed = true
  local Pm = require("src.zelda.alttp.Palace")
  local rt0 = Pm.roomTags
  function Pm.roomTags(self, lk)
    local r = rt0(self, lk)
    M.roomTags(self, lk)
    return r
  end
end

return M
