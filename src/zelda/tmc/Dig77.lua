-- Round 77: the Mole Mitts' edge blending after a soft wall is dug
-- (src/playerUtils.c sub_0807B600's tail, sub_0807B55C and sub_0807B480),
-- which ItemMitts.digWall left out.
--
-- PORTED (decomp):
--   sub_0807B600, once the dug tile has its TILE_TYPE_754 / 756: when the top
--     tile above it (tilePos - 0x40) was an ACT_TILE_86 soft wall, after it is
--     cleared, sub_0807B55C runs on the bottom layer at tilePos + 1, tilePos - 1
--     and tilePos - 0x40 with gUnk_0811C2AC; then sub_0807B480 runs on the top
--     layer at tilePos2 + 1 (bit 3), tilePos2 - 1 (bit 1), tilePos2 + 0x40
--     (bit 0) and tilePos2 - 0x40 (bit 2), tilePos2 = tilePos - 0x40.
--   sub_0807B55C(pos, layer, table): an ACT_TILE_86 tile takes
--     table[N | E << 1 | S << 2 | W << 3] (each bit = that neighbour on the
--     same layer is ACT_TILE_86 too) -- a soft wall beside the new tunnel gets
--     the edge piece (and the collision) that opens toward it.
--   sub_0807B480(pos, bit): an ACT_TILE_86 top tile: the same four
--     neighbour bits on the top layer, OR the bottom tiles at pos + (1, 1)
--     (bit 1) and pos + (-1, 1) (bit 3), and with a top tile below, the
--     bottom tile at pos + (0, 2) (bit 2); the new type is gUnk_0811C2CC[bits]
--     unless gUnk_0811C2EC (rows {type, edges, bits}, 0-ended) has a row for
--     the tile's own edges with `bit` cleared and these bits.
-- The three tables are read from the ROM (RomTablesCat: Dig77.*).
-- Positions outside the room read as no tile (the cartridge reads gMap's
-- 64-wide grid; the rooms here are bordered by walls).
local M = {}

local RT = require("src.zelda.tmc.RomTables")
M.BOTTOM_EDGE = RT.t("Dig77.EDGE_BOTTOM") -- gUnk_0811C2AC (u16[16])
M.TOP_EDGE = RT.t("Dig77.EDGE_TOP")       -- gUnk_0811C2CC (u16[16])
M.TOP_ROWS = RT.t("Dig77.TOP_ROWS")       -- gUnk_0811C2EC ({type, edges, bits}, 0-ended)
M.ACT_SOFT = 0x56 -- ACT_TILE_86

local function tileType(f, layer, tx, ty)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return 0 end
  return r:tileType(layer, tx, ty) or 0
end

-- sub_0807B464
local function soft(f, layer, tx, ty)
  local tt = tileType(f, layer, tx, ty)
  if tt == 0 or tt >= 0x4000 then return false end
  return (f.assets.actTile and f.assets.actTile[tt]) == M.ACT_SOFT
end
M.soft = soft

local function set(f, layer, tx, ty, t)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  f:objects():setTileType(layer, tx, ty, t)
end

local function b(v, n) return v and 2 ^ n or 0 end

-- sub_0807B55C(pos, layer, table)
function M.edge55C(f, tx, ty, layer, tbl)
  if not soft(f, layer, tx, ty) then return end
  local m = b(soft(f, layer, tx, ty - 1), 0) + b(soft(f, layer, tx + 1, ty), 1)
          + b(soft(f, layer, tx, ty + 1), 2) + b(soft(f, layer, tx - 1, ty), 3)
  local t = (tbl or M.BOTTOM_EDGE)[m]
  if t then set(f, layer, tx, ty, t) end
end

local function orb(a, n) -- a | (1 << n) with a < 16
  if math.floor(a / 2 ^ n) % 2 == 1 then return a end
  return a + 2 ^ n
end

-- sub_0807B480(pos, bit)
function M.edge480(f, tx, ty, bitn)
  if not soft(f, 2, tx, ty) then return end
  local m = b(soft(f, 2, tx, ty - 1), 0) + b(soft(f, 2, tx + 1, ty), 1)
          + b(soft(f, 2, tx, ty + 1), 2) + b(soft(f, 2, tx - 1, ty), 3)
  if soft(f, 1, tx + 1, ty + 1) then m = orb(m, 1) end
  if soft(f, 1, tx - 1, ty + 1) then m = orb(m, 3) end
  if tileType(f, 2, tx, ty + 1) ~= 0 and soft(f, 1, tx, ty + 2) then m = orb(m, 2) end
  local t2 = M.TOP_EDGE[m]
  local own = tileType(f, 2, tx, ty)
  local e = 0
  for _, row in ipairs(M.TOP_ROWS) do
    if row.type == own then e = row.edges break end
  end
  if math.floor(e / 2 ^ bitn) % 2 == 1 then e = e - 2 ^ bitn end
  for _, row in ipairs(M.TOP_ROWS) do
    if row.edges == e and row.bits == m then t2 = row.type break end
  end
  if t2 then set(f, 2, tx, ty, t2) end
end

-- sub_0807B600's tail (the plain soft-wall branch), called by ItemMitts.digWall
-- once the dug tile (tx, ty) has its new type; topCleared = the top tile above
-- was a soft wall and was cleared
function M.after(f, tx, ty, topCleared)
  if topCleared then
    M.edge55C(f, tx + 1, ty, 1)
    M.edge55C(f, tx - 1, ty, 1)
    M.edge55C(f, tx, ty - 1, 1)
  end
  local y2 = ty - 1
  M.edge480(f, tx + 1, y2, 3)
  M.edge480(f, tx - 1, y2, 1)
  M.edge480(f, tx, y2 + 1, 0)
  M.edge480(f, tx, y2 - 1, 2)
end

return M
