-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 44: THE CURTAIN DOOR CUT WITH THE SWORD (kDoorType_Slashable 0x32;
-- Agahnim's tower).
--
-- Traced on the GBA (0x08086218, zelda3's door part of the sword's tile
-- check): with B down (+0x16E8 & 0x80) and button_b_frames (+0x16EA) == 4,
-- the cell at (link_y + player_oam_y_offset (+0x16F6), link_x +
-- player_oam_x_offset (+0x16F7)) and its right / lower / lower-right
-- neighbours are tested in the room's attribute table (0x0200CBA0); an
-- attribute 0xF0 + k (a door slot's mark) whose door_type_and_slot[k]
-- (+0x18B0) & 0xFE is 0x32 opens: dung_door_opened and the adjacent mask
-- (+0xBFE / +0xAA6) |= kUpperBitmasks[k] (0x081676B2), the door's open
-- picture and attributes (0x08086140 = Dungeon_LoadToggleDoorAttr_OtherEntry),
-- sound 0x7B. The port kept the curtain shut ("other" lock): no way on.
--
-- OURS: the 0x6C branch of the same routine (slashable floor tiles) is not
-- part of this module; no sound.

local bit = require("bit")
local band = bit.band

local M = { NAME = "curt44" }
M.TYPE = 0x32
M.FRAME = 4

function M.extract() return {} end

local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end

-- the probe spot of the swing step (link + player_oam offsets)
function M.spot(game, step)
  local lk = game.link
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local offs = game.data.t and game.data.t.playerOamOffs
  local ox, oy = 0, 0
  if offs and cb and cb.swordOamY then
    local i = (offs[math.floor(lk.facing / 2) * 40 + 39 + 1] or 0) + step
    ox, oy = wrap8(cb.swordOamX[i + 1] or 0), wrap8(cb.swordOamY[i + 1] or 0)
  end
  return lk.x + ox, lk.y + oy
end

function M.check(game, step)
  local inside = game.interior
  if not inside or step ~= M.FRAME then return false end
  local x, y = M.spot(game, step)
  local pos = band(math.floor(y / 8), 63) * 64 + band(math.floor(x / 8), 63)
  for _, c in ipairs({ pos, pos + 1, pos + 64, pos + 65 }) do
    local a = inside.attrs[band(c, 0xFFF)] or 0
    if band(a, 0xF0) == 0xF0 then
      for _, l in ipairs(inside.locks or {}) do
        if not l.open and l.type == M.TYPE then
          for _, w in ipairs(l.closeW) do
            if band(w[1], 0xFFF) == band(c, 0xFFF) then
              inside:openLock(l)
              if inside.mem and inside.mem.doors then inside.mem.doors[l.index] = true end
              game.roomImages = nil
              game.curtainsCut = (game.curtainsCut or 0) + 1
              return true
            end
          end
        end
      end
      return false
    end
  end
  return false
end

function M.install(G)
  local A = require("src.zelda.alttp.Actors")
  local sh0 = A.swordHit
  function A:swordHit(x, y, w, h, how)
    local game = self.game
    if game and game.interior and self.room ~= -1 and how and how.sword and not how.held and how.bFrames == M.FRAME then
      M.check(game, how.bFrames)
    end
    return sh0(self, x, y, w, h, how)
  end
end

return M
