-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 74: a revealed hidden chest seen again.
--
-- A room whose hidden chests were revealed (Chest70: mem.chestShown, the
-- cartridge's room flag that 0x0807D3E4 uses to clear the hiding tag at
-- load) gets its chest attributes back at load, but the pre-rendered maps
-- hold no chest picture there: the port showed an invisible chest that
-- opens (Misery Mire's 0xC2 key chest after a checkpoint / a revisit).
-- The closed chest's four words go into the map as
-- RoomTag_OperateChestReveal (0x0807A478) writes them. No ROM reads: the
-- words are Extract's (data.t.items.chestClosed).

local M = {}

function M.redraw(inside)
  local it = inside.data and inside.data.t and inside.data.t.items
  local o = it and it.chestClosed
  if not o then return 0 end
  local n = 0
  for _, c in ipairs(inside.chests or {}) do
    if not c.lock and not c.opened and c.w ~= 4 then
      local patch = (c.lower and inside.patch1) or inside.patch
      if patch then
        patch[c.y * 64 + c.x] = o[1]
        patch[(c.y + 1) * 64 + c.x] = o[2]
        patch[c.y * 64 + c.x + 1] = o[3]
        patch[(c.y + 1) * 64 + c.x + 1] = o[4]
        n = n + 1
      end
    end
  end
  inside.chestsRedrawn74 = n
  return n
end

return M
