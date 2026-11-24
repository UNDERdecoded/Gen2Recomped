-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 43: THE BOSS PRIZE'S SPOT AND FALL (zelda3 names).
--
-- RoomTag_GetHeartForPrize (Palace.roomTags) drops the palace's prize: the
-- GBA's AncillaAdd_FallingPrize is 0x080ADD38 (traced this round; the
-- ancilla is added by 0x080AB89C, finished by 0x080ABA78). With i =
-- kBossFinishedFallingItem[palace >> 1] (DesertPalace's bossFall):
--   * i == 0 or 5: the spot is Link's (0x080ADE36: RAM +0x16C0 / +0x16C4,
--     link_y / link_x -> the ancilla's y / x);
--   * the Tower of Hera (cur_palace_index_x2 +0xAB2 == 0x14, 0x080ADE88):
--     the room's middle: the high byte of Link's y / x with bit 0 cleared,
--     + 1, low byte 0 -- (link & 0xFE00) + 0x100;
--   * else (0x080ADEE4): y = BG2VOFS_copy2 (+0x958) + kFallingItem_Y[i]
--     (0x16E5E2, 7 u16), x = BG2HOFS_copy2 (+0x952) + kFallingItem_X[i]
--     (0x16E5F0, 7 u16). The GBA's own tables (the SNES's are 0x78 / 0x78
--     for the pendants; the GBA moved the first two up and left for its
--     240 x 160 screen). Read at import.
--   z = kFallingItem_Z[i] (0x16E5DB), z speed 0xD0 (-48, 1/16 px).
-- The fall (Ancilla29_MilestoneItemReceipt; the same rule Ending27 runs for
-- the crystal): 128 frames still (byte_7E04C2 = 128 in RoomTag_GetHeartFor
-- Prize), then z falls at -48 / 16; below 0 -> step 1, z speed 0x18, z 0,
-- the speed loses 1 a frame; below 0 again -> step 2, at rest. Link takes
-- it while z < 24 (Ancilla_CheckLinkCollision) -- Palace.takePrize.
-- Not traced on the GBA: the update routine (zelda3's, as Ending27's
-- crystal); OURS: the picture is the item's menu icon (as before).

local bit = require("bit")
local rshift = bit.rshift

local M = { NAME = "prize43" }

M.OFF = { fallY = 0x16E5E2, fallX = 0x16E5F0, fallZ = 0x16E5DB }
M.HERA = 0x14          -- cur_palace_index_x2 compared at 0x080ADE8E
M.WAIT = 128           -- byte_7E04C2
M.ZV, M.BOUNCE, M.TAKE_Z = -48, 0x18, 24

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { y = rom:bytesU16(O.fallY, 7), x = rom:bytesU16(O.fallX, 7), z = rom:bytesU8(O.fallZ, 7) }
  check(t.y[1] == 0x48 and t.x[1] == 0x78 and t.y[6] == 0x68 and t.x[6] == 0x80 and t.z[1] == 0x60
        and t.z[2] == 0x80, "falling prize spot tables")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.prize43 end
M.tabs = T

local function DPm() return require("src.zelda.alttp.DesertPalace") end
local function P() return require("src.zelda.alttp.Palace") end

-- the falling item index i of this palace (nil without the tables)
function M.itemIndex(game, pid)
  local tb = DPm().tabs(game)
  if not tb or not pid or pid == 0xFF then return nil end
  return tb.bossFall[rshift(pid, 1) + 1]
end

-- the prize's spot: x, y, z (nil when the tables are missing)
function M.spot(game, inside, lk)
  local tb = T(game)
  local pid = P().palaceId(game)
  local i = M.itemIndex(game, pid)
  if not tb or not i then return nil end
  local z = tb.z[i + 1]
  if i == 0 or i == 5 then return lk.x, lk.y, z end
  if pid == M.HERA then
    return math.floor(lk.x / 512) * 512 + 0x100, math.floor(lk.y / 512) * 512 + 0x100, z
  end
  local cx, cy = 0, 0
  if inside.camera then cx, cy = inside:camera(lk.x, lk.y, 240, 160) end
  return cx + tb.x[i + 1], cy + tb.y[i + 1], z
end

-- Ancilla29_MilestoneItemReceipt (not the crystal: Ending27 runs that one)
function M.fall(self, a, lk)
  local game = self.game
  if not a.p43 then
    a.p43 = true
    a.wait, a.step, a.zs = M.WAIT, 0, 0
    a.vz = M.ZV
  end
  if (a.wait or 0) > 0 then a.wait = a.wait - 1 return end
  if (a.z or 0) < M.TAKE_Z and P()._h.touchLink(self, a, lk) and not game.textBox then
    a.dead = true
    return P().takePrize(game, a)
  end
  if a.step ~= 2 then
    if a.step ~= 0 then a.vz = a.vz - 1 end
    local zz = (a.z or 0) * 16 + a.zs + a.vz
    a.z, a.zs = math.floor(zz / 16), zz % 16
    if a.z < 0 then a.step, a.vz, a.z, a.zs = a.step + 1, M.BOUNCE, 0, 0 end
  end
end

function M.install(G)
  local Pal = P()
  local pu = Pal.update
  function Pal.update(self, a, lk)
    if a.type == 0xEB and not a.crystal and T(self.game) then
      local pid = Pal.palaceId(self.game)
      local _, item = DPm().prizeOf(self.game, pid)
      if item ~= 0x20 then
        a.item = a.item or item
        return M.fall(self, a, lk)
      end
    end
    return pu(self, a, lk)
  end
  local pd = Pal.draw
  function Pal.draw(spr, a, x, y, frame, game)
    if a.type == 0xEB and not a.crystal and a.item and a.game and a.game.drawItemIcon then
      a.game:drawItemIcon(a.item, x, y - (a.z or 0))
      return true
    end
    return pd(spr, a, x, y, frame, game)
  end
end

return M
