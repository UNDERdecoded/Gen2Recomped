-- Round 30: object collision the cartridge does with tiles, where the port
-- used an entity box.  Called every frame from Field:update (one line).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * src/object/chestSpawner.c sub_080842D8 (a big chest shown, closed or
--     opened): SetMultipleTiles(gUnk_0811F898[(x & 8 ? 1 : 0) + (y & 8 ? 2
--     : 0)], COORD_TO_TILE(super), layer) -- SPECIAL_TILE_34..42 around the
--     chest's tile, solid by the special collision table.  The port kept the
--     chest as an entity box (10 x 7 around its origin), so Link walked 8 px
--     into the chest's sides and top (sweep r30/sw_walk1.txt).
local M = {}

-- gUnk_0811F854 / 866 / 880 / 88A ({tile, offset in a 64-wide map}),
-- written out in chestSpawner.c
M.BIG_CHEST_TILES = require("src.zelda.tmc.RomTables").t("Collide30.BIG_CHEST_TILES")

local function split(off)
  local dy = math.floor((off + 32) / 64)
  return off - dy * 64, dy
end
M.split = split

-- sub_080842D8
function M.bigChestTiles(f, e)
  local r = f.room
  local x, y = math.floor(e.x), math.floor(e.y)
  local idx = ((x % 16 >= 8) and 1 or 0) + ((y % 16 >= 8) and 2 or 0)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  local L = (e.layer == 2) and 2 or 1
  for _, t in ipairs(M.BIG_CHEST_TILES[idx]) do
    local dx, dy = split(t[2])
    local cx, cy = tx + dx, ty + dy
    if cx >= 0 and cy >= 0 and cx < r.tw and cy < r.th then r:setTile(L, cx, cy, t[1]) end
  end
end

function M.sync(f)
  if not f.room then return end
  require("src.zelda.tmc.Collide31").sync(f) -- round 31: furniture / acorn / twig / oven / cart tiles
  for _, e in ipairs(f.entities) do
    if e.big and e.shown and not e.deleted and e.tiles30 ~= f.room then
      M.bigChestTiles(f, e)
      e.tiles30 = f.room
      e.solid = false -- the tiles stop Link now (Field:entityBlocks)
    end
  end
end

return M
