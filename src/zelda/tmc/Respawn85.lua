-- Round 85: the port's respawn-spot search (Dungeon:respawnSpot, used by Field:safeContinue when the saved spot is
-- solid -- e.g. Link saved or continued standing in a side door's tile) must not pick a tile the cartridge's player
-- could never stand on.
--
-- FOUND ($70:07, Palace of Winds 5F, entered from the west door at (8,410)): the door tile tests solid, the nearest
-- "good" tile centre was (8,440) -- column 0, outside the room's wall frame; its bottom tile type ($0310) carries
-- the surface flag 4, so sub_0807A8D8 (Layers.surface, every frame) put Link on layer 2, where the room's top map
-- is empty: no collision at all, Link walked through the walls and out of the room.
--
-- The search now skips
--   * the room's outer ring of tiles (row 0 / column 0 / the last row / column: outside the walls, or a room edge
--     that would start a transition), and
--   * a tile whose bottom-layer flags would move Link to layer 2 (bit 4, without bit 2) where the top layer has no
--     tile (tile type 0): the surface check would leave him on an empty map.
local bit = require("bit")
local band = bit.band

local R = {}

-- flags of a tile type (sub_080B1B84 -> manifest r23), nil-safe
local function flagsOf(f, tt)
  if not tt or not f.assets or not f.assets.manifest then return 0 end
  local ok, fl = pcall(require("src.zelda.tmc.ExtractR23").flags, f.assets.manifest, tt)
  return ok and fl or 0
end
R.flagsOf = flagsOf

function R.edge(r, tx, ty)
  if not r.tw or not r.th then return false end
  return tx <= 0 or ty <= 0 or tx >= (r.tw or 0) - 1 or ty >= (r.th or 0) - 1
end

-- true when Layers.surface on (tx, ty) would put Link on an empty top layer
function R.emptyTop(f, tx, ty)
  local r = f.room
  if not r or not r.tileType then return false end
  local fl = flagsOf(f, r:tileType(1, tx, ty))
  if band(fl, 2) ~= 0 or band(fl, 4) == 0 then return false end
  local t2 = r:tileType(2, tx, ty)
  return t2 == nil or t2 == 0
end

-- Dungeon:respawnSpot's candidate filter
function R.reject(f, tx, ty)
  local r = f and f.room
  if not r then return false end
  if R.edge(r, tx, ty) then return true end
  return R.emptyTop(f, tx, ty)
end

return R
