-- Round 73: the small-key block (ACT_TILE_113, e.g. TILE_TYPE_870 $366) -- the Royal Crypt's hall $68:04 has two
-- between its statues.  Not ported: A / R against it did nothing, so the way north stayed shut.
--
-- CARTRIDGE BEHAVIOUR (src/beanstalkSubtask.c, the tile-in-front interaction; src/room.c sub_0804B388):
--   * ACT_TILE_113 at the tile in front of Link: no dungeon small key -> nothing; else (R_ACTION_OPEN) A or R pressed
--     -> mobility 1 and sub_0804B388(position, Link's collision layer).
--   * sub_0804B388: SetTileType(layer 1 ? TILE_TYPE_38 : TILE_TYPE_52, position, layer); a SPECIAL_FX FX_DEATH at
--     the tile (sub_0806F704: its centre), ModDungeonKeys(-1).
-- The block's own room tile entity (DESTRUCTIBLE_TILE, Bombs.lua's observe manager) keeps it open after a reload.
-- Tile types / act numbers are the cartridge's enums; the act of a tile type is read from the player's ROM
-- (manifest actTile).
local M = {}

M.ACT_TILE_113 = 0x71
M.TILE_TYPE_38, M.TILE_TYPE_52 = 38, 52
M.SPECIAL_FX, M.FX_DEATH = 0x0F, 2
M.ITEM_SMALL_KEY = 0x53

-- one line in Objects:tryAction (A and R): true when a block was opened
function M.try(f, p, tx, ty)
  if p.minish then return false end
  local O = f:objects()
  local r = f.room
  local layer = p.layer == 2 and 2 or 1
  local tt = r:tileType(layer, tx, ty)
  local act = tt and tt < 0x4000 and O.A.actTile[tt] or nil
  if act ~= M.ACT_TILE_113 then return false end
  local D = f:dungeon()
  if (D:inventory(M.ITEM_SMALL_KEY) or 0) <= 0 then return false end
  O:setTileType(layer, tx, ty, layer == 1 and M.TILE_TYPE_38 or M.TILE_TYPE_52)
  if f.addFx then f:addFx(tx * 16 + 8, ty * 16 + 8, M.SPECIAL_FX, M.FX_DEATH) end
  local st = D:state()
  st.keys = math.max(0, (st.keys or 0) - 1)
  return true
end

return M
