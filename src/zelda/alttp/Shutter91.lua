-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 91: a room tag does not shut the shutter Link is still walking in
-- through.
--
-- GBA, RoomTag_TorchPuzzleDoor (tag 0x33, 0x08079F04): counts the lit
-- torches; "trapdoors down" = (lit <= 3) (`cmp r0, #3` / `ble`); when that
-- differs from +0xB10 (dung_flag_trapdoors_down) it stores it and starts
-- submodule 5 (ControlShutters, `movs r0, #5` -> +0x9AD). The room tags run
-- from submodule 0, after the inter-room transition: its walk-in has carried
-- Link through the door and its end (the trapdoors put down) has already set
-- +0xB10, so the tag finds nothing to change and the door Link came through
-- closes behind him, not on him.
--
-- The port's torch tag (Items.torchTags) starts from no state and closes
-- every open shutter on the room's first frame (G:closeShutters), the one
-- Link stands in included: going back up from Ganon's Tower 0x9D into 0x8D
-- (torch door S8, torches out) left Link inside the shut door, unable to
-- move. Here closeShutters leaves a shutter whose cells Link's body still
-- overlaps open and marks it as his entry (Escape closes an entry shutter
-- once he is past it, as for the trapdoors).
--
-- No ROM data: nothing is read (extract returns an empty table).

local M = { NAME = "shutter91" }

M.SITES = { torchTag = 0x08079F04, flag = 0xB10 }

-- the way Link walks in through a door on that wall (the lock's dir: 0 top,
-- 1 bottom, 2 left, 3 right)
M.ENTRY = { [0] = "down", [1] = "up", [2] = "right", [3] = "left" }

function M.extract(rom, R, check) return {} end

-- Link's body (x .. x + 15, y + 8 .. y + 23) over one of the lock's cells
function M.overlaps(l, lk)
  for _, cell in ipairs(l.cells or {}) do
    local cx, cy = (cell % 64) * 8, math.floor(cell / 64) * 8
    if cx + 8 > lk.x and cx < lk.x + 16 and cy + 8 > lk.y + 8 and cy < lk.y + 24 then return true end
  end
  return false
end

function M.install(G)
  if G.shutter91Installed then return end
  G.shutter91Installed = true
  local close0 = G.closeShutters
  function G:closeShutters()
    local inside, lk = self.interior, self.link
    local kept
    if inside and lk then
      for _, l in ipairs(inside.locks or {}) do
        if l.kind == "shutter" and l.open and (l.entry or M.overlaps(l, lk)) then
          l.entry = l.entry or M.ENTRY[l.dir or -1]
          if l.entry then
            kept = kept or {}
            kept[#kept + 1] = l
            l.open = false   -- hidden from the close below, put back after
          end
        end
      end
    end
    local r = close0(self)
    for _, l in ipairs(kept or {}) do l.open = true end
    if kept then self.shutterKeeps91 = (self.shutterKeeps91 or 0) + #kept end
    return r
  end
end

return M
