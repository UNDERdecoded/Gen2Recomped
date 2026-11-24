-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 44: WHERE A HURTING PIT PUTS LINK BACK (zelda3 names).
--
-- Traced on the GBA: ResetThenCacheRoomEntryProperties (0x08070A80, called
-- by DungeonTransition_Subtile_TriggerShutters 0x0806D264 at the end of a
-- transition inside a room, and by the room-to-room transition's end) runs
-- CacheRoomEntryProperties (0x0808B1FC), which keeps link_y (+0x16C0) and
-- link_x (+0x16C4) with the camera. DungeonPitDoDamage + Module07_14
-- (RecoverPositionAfterDrowning) puts Link back on that kept spot -- where he
-- stood when the room or the quadrant was entered. The port put him back on
-- last spot off the pit before the fall (Dungeons26's pitSafe, OURS; the
-- pit's pull starts next to it): in Agahnim's tower's room
-- 0xC0 (pits that hurt) the pit's pull took him in again and again until the
-- game was over.
--
-- OURS: the spot is kept when the port's transition ends (its scroll, the
-- stairs, the room's entry); the camera is the port's own for that spot.

local M = { NAME = "rc44" }

function M.extract() return {} end

function M.cache(game)
  local inside = game.interior
  if not inside then return end
  game.entryCache = { room = inside.room, x = game.link.x, y = game.link.y, lower = inside.lower }
end

function M.install(G)
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    local r = enter0(self, e)
    M.cache(self)
    return r
  end
  local srs = G.startRoomScroll
  function G:startRoomScroll(dir, leavesRoom, stairRoom)
    local r = srs(self, dir, leavesRoom, stairRoom)
    if not self.roomScroll then M.cache(self) end
    return r
  end
  local urs = G.updateRoomScroll
  function G:updateRoomScroll()
    local had = self.roomScroll ~= nil
    local r = urs(self)
    if had and self.roomScroll == nil then M.cache(self) end
    return r
  end
  -- the pit's recovery spot
  local D = require("src.zelda.alttp.Dungeons26")
  local pf0 = D.pitFrame
  function D.pitFrame(game)
    local pf, c = game.pitFall, game.entryCache
    if pf and not pf.rc44 and c and game.interior and c.room == game.interior.room then
      pf.rc44 = true
      pf.prevX, pf.prevY = c.x, c.y
    end
    return pf0(game)
  end
end

return M
