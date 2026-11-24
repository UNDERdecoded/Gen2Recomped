-- Round 33: the tile side of the Kinstone world events (src/kinstone.c
-- sub_0801876C and its helpers), for the field (one line in
-- Kinstone:applyWorldEvents) and for the world-event view (Fusion32.lua).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc), sub_0801876C(worldEventId, fused):
--   * type 2, fused: sub_08018BB4 -- the TileEntity gUnk_080FEAC8[id] at the
--     event's tile, LoadSmallChestTile2 (a small chest: the item _2 / _3,
--     its local flag), TILE_TYPE_115 (a closed chest) on layer _6 & 1 ? 2 : 1
--     unless the flag is set (sub_0804B16C then shows it open).  The 25
--     Kinstone chests were missing from the field.
--   * type 4, not fused: sub_08018A58 -- TILE_TYPE_562.. 7 x 4 from (x - 3,
--     y - 1), bottom (what the fusion clears away).
--   * type 5, fused: sub_08018B50 -- TILE_TYPE_512.. (entity & $80:
--     TILE_TYPE_537..) 5 x 5 from (x - 2, y - 2), bottom.
--   * type 6, not fused: sub_08018AB4 -- 3 rows of 4: TILE_TYPE_488.. on the
--     bottom, TILE_TYPE_500.. one row up on the top layer.
--   * type 7 with entity $80, not fused: sub_080189EC -- TILE_TYPE_479.. (top,
--     row y - 1), TILE_TYPE_483.. (top) and TILE_TYPE_475.. (bottom) on row
--     y, from x - 2.
--   * (types 1, 3, 7, 8, 9, 15, 17, 24, 25 were already in
--     Kinstone:applyWorldEvents.)
local bit = require("bit")
local band = bit.band

local M = {}
M.TILE_ENTITIES = 0x080FEAC8 -- gUnk_080FEAC8 (TileEntity[], 8 bytes, by world event)
local TT = { CHEST = 115, CHEST_OPEN = 0x74 }

-- SetTileType on any room (Objects:setTileType's reverse lookup)
function M.setTT(r, layer, tx, ty, ttype)
  if not r or tx < 0 or ty < 0 or tx >= (r.tw or 0) or ty >= (r.th or 0) then return false end
  local name = layer == 2 and "top" or "bottom"
  local atlas = r.atlas
  if not atlas then return false end
  atlas.reverse = atlas.reverse or {}
  local rev = atlas.reverse[name]
  if not rev then
    rev = {}
    local types = atlas.types[name] or {}
    for i = 0x7FF, 0, -1 do rev[types[i] or 0] = i end
    atlas.reverse[name] = rev
  end
  local mt = rev[ttype]
  if mt then r:setTile(layer, tx, ty, mt) return true end
  return false
end

-- gUnk_080FEAC8[id] (entities.bin covers the table)
function M.tileEntity(A, id)
  local reg = A.manifest and A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local o = M.TILE_ENTITIES + 8 * id - reg.base
  local b = A.entityBlob
  if o < 0 or o + 8 > #b then return nil end
  local function u8(i) return b:byte(o + i + 1) end
  return { type = u8(0), flag = u8(1), a = u8(2), b = u8(3), pos = u8(4) + 256 * u8(5), c = u8(6), d = u8(7) }
end

-- the tile writes of sub_0801876C for one event; `flagSet(flag)` reads a
-- local flag of the event's area.  Returns the chest tile entity (type 2).
function M.tiles(A, r, id, we, fused, flagSet)
  local t = we.type
  local tx, ty = math.floor(we.x / 16) % 64, math.floor(we.y / 16) % 64
  if t == 2 and fused then
    local te = M.tileEntity(A, id)
    if not te then return nil end
    te.pos, te.type = tx + ty * 64, 2 -- (gSmallChests)
    local layer = band(te.c, 1) == 0 and 1 or 2
    if not (flagSet and flagSet(te.flag)) then M.setTT(r, layer, tx, ty, TT.CHEST) end
    return te
  elseif t == 4 and not fused then
    local k = 562
    for j = 0, 3 do for i = 0, 6 do M.setTT(r, 1, tx - 3 + i, ty - 1 + j, k); k = k + 1 end end
  elseif t == 5 and fused then
    local k = band(we.entity, 0x80) == 0 and 512 or 537
    for j = 0, 4 do for i = 0, 4 do M.setTT(r, 1, tx - 2 + i, ty - 2 + j, k); k = k + 1 end end
  elseif t == 6 and not fused then
    local b, u = 488, 500
    for j = 0, 2 do
      for i = 0, 3 do
        M.setTT(r, 1, tx + i, ty + j, b); b = b + 1
        M.setTT(r, 2, tx + i, ty + j - 1, u); u = u + 1
      end
    end
  elseif t == 7 and not fused and we.entity == 0x80 then
    for i = 0, 3 do M.setTT(r, 2, tx - 2 + i, ty - 1, 479 + i) end
    for i = 0, 3 do
      M.setTT(r, 2, tx - 2 + i, ty, 483 + i)
      M.setTT(r, 1, tx - 2 + i, ty, 475 + i)
    end
  end
  return nil
end

-- Kinstone:applyWorldEvents (the room just loaded is the event's room)
function M.apply(f, id, we, fused)
  local r = f.room
  local te = M.tiles(f.assets, r, id, we, fused, function(flag) return f:flag("local", flag) end)
  if te then
    -- LoadSmallChestTile: the room's chest list (a copy: the header's list is shared)
    local list = {}
    for _, t in ipairs(r.tileEntities or {}) do
      if t.pos ~= te.pos then list[#list + 1] = t end
    end
    list[#list + 1] = te
    r.tileEntities = list
  end
end

return M
