-- Round 31: the solid tiles objects put down in their Init (the collision
-- sweep's second half).  The port drew these objects but never wrote their
-- tiles, so Link walked through most of the furniture of the houses, the
-- Minish-size giant acorns / twigs and the oven; the mine cart was an entity
-- box.  Called every frame from Collide30.sync (one line).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * src/object/furniture.c FurnitureInit: tilePos = COORD_TO_TILE; by
--     cfg flags & $7FFF: $100 -> layer 2; $20 / $200 nothing; $40 -> y =
--     (y & ~15) | 4, SPECIAL_TILE_23 (ladder) at the two tiles above; $80 ->
--     y = (y & ~15) | 6, SPECIAL_TILE_38 at its tile; $400 -> FLAME, type2
--     != 0 makes it 48 wide, then (as every other value) sub_08090B6C: the
--     width's row of SPECIAL_TILE_34 with half tiles 36 / 37 at the ends
--     (sub_08090CDC merges two halves into 34 / 43).  height != 16: height
--     & $70 = $30 -> the row above too, $30 / $20 -> the row below too.
--     flags $2 (shelves): SPECIAL_TILE_38 on both layers over the row above
--     (3 wide, 2 for type 26).  WOODEN_TABLE: SPECIAL_TILE_35 x3 above;
--     LOW_BOOKSHELF: SPECIAL_TILE_34 at +65; STAIRCASE: 116 above, 23 at
--     its tile and below.  FurnitureUpdate $80: Link above y + 8 and off
--     the ladder with SPECIAL_TILE_23 here -> 38 here, 61 x2 above; Link
--     below -> layer 1, 23 / 23 / 20 back.
--   * cabinFurniture.c CabinFurniture_Init (types 0-2), bakerOven.c
--     sub_0809CDF0 (type 0), macroAcorn.c sub_0809E5F0 (types 0-3),
--     giantTwig.c sub_08093A1C (types 0 / 1 / 3) and sub_08093984 (type 2:
--     SPECIAL_TILE_116 x19), macroShoe.c MacroShoe_Init (type2 1).
--   * pushableGrave.c: Grave31.lua (dispatched from M.sync).
--   * minecart.c: SetTile(SPECIAL_TILE_34) at Init and when it stops
--     (Action6 -> 1); RestorePrevTileEntity when Link lands in it (Action2).
-- (round 34: SetActTileAtTilePos -- shelves' row below, the staircase top --
--   through Push34.actTile, read by Climb.actAt.)
-- SIMPLIFIED: the flame of a $400 furniture is not created; giantTwig
--   type 0's held-object tile swap (sub_08093C70) is not run.
local bit = require("bit")
local band = bit.band

local M = {}

local ST = function(n) return 0x4000 + n end
local S20, S23, S34, S35, S36, S37, S38, S39 = ST(20), ST(23), ST(34), ST(35), ST(36), ST(37), ST(38), ST(39)
local S41, S42, S43, S44, S45, S46, S47 = ST(41), ST(42), ST(43), ST(44), ST(45), ST(46), ST(47)
local S61, S108, S109, S110, S111, S116 = ST(61), ST(108), ST(109), ST(110), ST(111), ST(116)

M.FURNITURE, M.CABIN_FURNITURE, M.BAKER_OVEN, M.HUGE_ACORN = 0x4D, 0x8A, 0x92, 0x9A
M.GIANT_TWIG, M.HUGE_SHOES, M.MINECART = 0x62, 0x7C, 0x55
local WOODEN_TABLE, LOW_BOOKSHELF, STAIRCASE = 0x3B, 0x3C, 0x1F

-- write a tile at a 64-wide tile position offset from (tx, ty)
local function put(r, L, tx, ty, dx, dy, mt)
  local x, y = tx + dx, ty + dy
  if x < 0 or y < 0 or x >= r.tw or y >= r.th then return end
  r:setTile(L, x, y, mt)
end
local function get(r, L, x, y)
  if x < 0 or y < 0 or x >= r.tw or y >= r.th then return nil end
  return r.maps[L == 2 and "top" or "bottom"][y * r.tw + x]
end
M.put = put

-- sub_08090CDC: a half tile, merged with the half already there
local MERGE = {
  [S37] = { [S36] = S34, [S44] = S34 },
  [S45] = { [S44] = S43, [S36] = S34 },
  [S36] = { [S37] = S34, [S45] = S34 },
  [S44] = { [S45] = S43, [S37] = S34 },
}
local function half(r, L, x, y, mt)
  local cur = get(r, L, x, y)
  if not cur then return end
  if cur < 0x4000 then r:setTile(L, x, y, mt) return end
  local m = MERGE[cur]
  if m and m[mt] then r:setTile(L, x, y, m[mt]) end
end
M.half = half

-- sub_08090B6C: the furniture's width as a row of tiles at (tx, ty)
function M.widthRow(r, L, tx, ty, width, px)
  width = band(width or 0, 0xFF)
  if width == 0 then return end
  local w2 = math.floor(width / 8)
  local hi = band(px, 8) ~= 0
  local s = function(i, mt) put(r, L, tx, ty, i, 0, mt) end
  local h = function(i, mt) half(r, L, tx + i, ty, mt) end
  local c = band(w2, 3)
  local i
  if c == 0 then
    local num = math.floor(w2 / 8)
    if w2 == 0xC then num = 2 end
    for k = -num, num do s(k, S34) end
    i = num + 1
    if hi then h(-i, S36); h(i, S37) else s(-i, S34) end
  elseif c == 1 then
    local num = math.floor(w2 / 8)
    for k = -num, num do s(k, S34) end
    i = num + 1
    if hi then h(-i, S36); s(i, S34) else s(-i, S34); h(i, S37) end
  elseif c == 2 then
    local num = math.floor(w2 / 4)
    for k = -num, num - 1 do s(k, S34) end
    i = num
    if hi then s(i, S34) else h(-i - 1, S36); h(i, S37) end
  else
    local num = math.floor(w2 / 4)
    for k = -num, num do s(k, S34) end
    i = num + 1
    if hi then h(i, S37) else h(-i, S36) end
  end
end

local function cell(e)
  return math.floor(e.x / 16), math.floor(e.y / 16), (e.layer == 2) and 2 or 1
end

-- FurnitureInit (the tile part)
function M.furnitureInit(f, e)
  local r = f.room
  local fu = e.furniture
  if not fu then return end
  local typ, type2 = e.form or 0, band(e.param or 0, 0xFF)
  local flags = band(fu.flags or 0, 0x7FFF)
  local width = fu.w
  local tx, ty, L = cell(e)
  local px = band(math.floor(e.x), 15)
  if flags == 0x100 then
    e.layer = 2
  elseif flags == 0x20 or flags == 0x200 then
    -- nothing
  elseif flags == 0x40 then
    e.y = math.floor(e.y / 16) * 16 + 4
    put(r, 1, tx, ty, 0, -2, S23); put(r, 1, tx, ty, 0, -1, S23)
  elseif flags == 0x80 then
    e.y = math.floor(e.y / 16) * 16 + 6
    tx, ty, L = cell(e)
    put(r, L, tx, ty, 0, 0, S38)
    e.furnLadder31 = { tx, ty, L }
  else
    if flags == 0x400 and type2 ~= 0 then width = 48 end
    M.widthRow(r, L, tx, ty, width, px)
  end
  if fu.h ~= 16 then
    local hh = band(fu.h, 0x70)
    if hh == 0x30 then M.widthRow(r, L, tx, ty - 1, width, px) end
    if hh == 0x30 or hh == 0x20 then M.widthRow(r, L, tx, ty + 1, width, px) end
  end
  if flags == 0x2 then
    local cnt = typ ~= 26 and 3 or 2
    for i = 0, cnt - 1 do
      put(r, 2, tx, ty, i - 1, -2, S38)
      put(r, 1, tx, ty, i - 1, -2, S38)
      require("src.zelda.tmc.Push34").actTile(r, 1, tx + i - 1, ty - 1, 0) -- round 34: SetActTileAtTilePos(ACT_TILE_0, +(0, 1))
    end
  end
  if typ == STAIRCASE then
    e.layer = 1
    put(r, 1, tx, ty, 0, -1, S116); put(r, 1, tx, ty, 0, 0, S23); put(r, 1, tx, ty, 0, 1, S23)
    require("src.zelda.tmc.Push34").actTile(r, 1, tx, ty - 1, 0x3F) -- round 34: SetActTileAtTilePos(ACT_TILE_63) (the stairs' top)
  elseif typ == WOODEN_TABLE then
    put(r, L, tx, ty, -1, -1, S35); put(r, L, tx, ty, 0, -1, S35); put(r, L, tx, ty, 1, -1, S35)
  elseif typ == LOW_BOOKSHELF then
    put(r, L, tx, ty, 1, 1, S34)
  elseif typ == 0x1E then
    -- round 45: SHOE_DESK: sub_0807B7D8(774, tilePos + 65, LAYER_TOP) -- the
    -- Minish hole in Rem's desk (SetTileType mirrors its collision $62 into
    -- the bottom map in these rooms: Objects:setTileType)
    f:objects():setTileType(2, tx + 1, ty + 1, 774)
  end
end

-- FurnitureUpdate $80 (a piece Link climbs onto by its ladder)
function M.furnitureUpdate(f, e)
  local lad = e.furnLadder31
  if not lad then return end
  local r, p = f.room, f.player
  local tx, ty, L = lad[1], lad[2], lad[3]
  if p.y < e.y + 8 then
    if not p.climbing and get(r, L, tx, ty) == S23 then
      put(r, L, tx, ty, 0, 0, S38); put(r, L, tx, ty, 0, -1, S61); put(r, L, tx, ty, 0, -2, S61)
    end
  else
    if p.layer == 2 then p.layer = 1 end
    if get(r, L, tx, ty) ~= S23 then
      put(r, L, tx, ty, 0, 0, S23); put(r, L, tx, ty, 0, -1, S23); put(r, L, tx, ty, 0, -2, S20)
    end
  end
end

-- CabinFurniture_Init
function M.cabinInit(f, e)
  local r = f.room
  local tx, ty, L = cell(e)
  local t = e.form or 0
  local p = function(dx, dy, mt) put(r, L, tx, ty, dx, dy, mt) end
  if t == 0 then
    p(-1, 0, S34); p(0, 0, S34); p(1, 0, S34); p(-1, 1, S34); p(0, 1, S34); p(1, 1, S34)
    p(-1, -1, S61); p(0, -1, S61); p(1, -1, S38); p(-1, -2, S38); p(0, -2, S38)
  elseif t == 1 then
    p(0, 0, S34); p(0, 1, S34); p(1, 1, S37)
    p(1, 0, f:dungeon():check(0x4F) and S45 or S47)
  elseif t == 2 then
    p(-1, -1, S34); p(0, -1, S34); p(-1, 0, S34); p(0, 0, S34)
  end
end

-- BakerOven_Init type 0 -> sub_0809CDF0
function M.ovenInit(f, e)
  if (e.form or 0) ~= 0 then return end
  local r = f.room
  local tx, ty, L = cell(e)
  local p = function(dx, dy, mt) put(r, L, tx, ty, dx, dy, mt) end
  p(-1, 0, S46); p(0, 0, S34); p(1, 0, S34)
  p(-1, -1, S38); p(0, -1, S38); p(1, -1, S36)
  p(-1, -2, S38); p(0, -2, S38)
end

-- MacroAcorn sub_0809E5F0 (layer bottom)
function M.acornInit(f, e)
  local t = e.form or 0
  if t == 0xFF then return end
  local r = f.room
  local tx, ty = cell(e)
  local p = function(dx, dy, mt) put(r, 1, tx, ty, dx, dy, mt) end
  if t == 2 or t == 0 then
    if t == 2 then p(3, -1, S34); p(4, -1, S109) end
    p(-2, -1, S108); p(-1, -1, S34); p(0, -1, S34); p(1, -1, S34)
    p(-2, 0, S34); p(-1, 0, S34); p(0, 0, S34); p(1, 0, S34)
    p(-2, 1, S110); p(-1, 1, S34); p(0, 1, S34); p(1, 1, S111)
  elseif t == 3 or t == 1 then
    if t == 3 then p(-4, -1, S34); p(-5, -1, S108) end
    p(-2, -1, S34); p(-1, -1, S34); p(0, -1, S34); p(1, -1, S109)
    p(-2, 0, S34); p(-1, 0, S34); p(0, 0, S34); p(1, 0, S34)
    p(-2, 1, S110); p(-1, 1, S34); p(0, 1, S34); p(1, 1, S111)
  end
end

-- GiantTwig sub_08093A1C / sub_08093984
local TWIG2 = {
  [1] = { { -2, -2 }, { -1, -2 }, { 0, -2 }, { 1, -2 }, { -2, -1 }, { -1, -1 }, { 0, -1 }, { 1, -1 }, { 2, -1 }, { -2, 0 },
          { -1, 0 }, { 0, 0 }, { 1, 0 }, { 2, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
  [0] = { { -1, -2 }, { 0, -2 }, { 1, -2 }, { 2, -2 }, { -2, -1 }, { -1, -1 }, { 0, -1 }, { 1, -1 }, { 2, -1 }, { -2, 0 },
          { -1, 0 }, { 0, 0 }, { 1, 0 }, { 2, 0 }, { -3, 1 }, { -2, 1 }, { -1, 1 }, { 0, 1 }, { 1, 1 } },
}
function M.twigInit(f, e)
  local r = f.room
  local t, t2 = e.form or 0, band(e.param or 0, 0xFF)
  local tx, ty, L = cell(e)
  local p = function(dx, dy, mt) put(r, L, tx, ty, dx, dy, mt) end
  if t == 0 then
    p(-4, 1, S36); p(-3, 1, S34); p(-2, 1, S34); p(-4, 2, S41); p(-3, 2, S38); p(-2, 2, S38)
    p(0, 1, S61); p(0, 2, S61); p(1, 1, S39); p(2, 1, S35); p(3, 1, S109)
    p(1, 2, S41); p(2, 2, S38); p(3, 2, S38)
  elseif t == 1 then
    if band(t2, 1) ~= 0 then
      p(-1, -2, S109); p(-1, -1, S34); p(-2, 0, S41); p(-1, 0, S38); p(0, 0, S34); p(1, 0, S109)
      p(0, 1, S110); p(1, 1, S34); p(2, 1, S109)
    else
      p(1, -2, S108); p(1, -1, S34); p(-1, 0, S108); p(0, 0, S34); p(1, 0, S38); p(2, 0, S42)
      p(-2, 1, S108); p(-1, 1, S34); p(0, 1, S111)
    end
  elseif t == 2 then
    for _, o in ipairs(TWIG2[t2 ~= 0 and 1 or 0]) do put(r, 1, tx, ty, o[1], o[2], S116) end
  elseif t == 3 then
    p(0, 0, S34)
  end
end

-- MacroShoe_Init: type2 1 puts three tiles at the fixed tile (16..18, 16)
function M.shoeInit(f, e)
  if band(e.param or 0, 0xFF) ~= 1 then return end
  local r = f.room
  put(r, 1, 16, 16, 0, 0, S36); put(r, 1, 17, 16, 0, 0, S38); put(r, 1, 18, 16, 0, 0, S37)
end

M.INIT = {
  [M.FURNITURE] = M.furnitureInit, [M.CABIN_FURNITURE] = M.cabinInit, [M.BAKER_OVEN] = M.ovenInit,
  [M.HUGE_ACORN] = M.acornInit, [M.GIANT_TWIG] = M.twigInit, [M.HUGE_SHOES] = M.shoeInit,
}

-- the mine cart standing (Action1 / the Cane hop): SPECIAL_TILE_34 under
-- it; riding: the old tile back
local function cartSync(f, e)
  local r = f.room
  local want = (e.action == 1 or e.action == 7) and not e.deleted and not e.hidden
  local t = e.cartTile31
  if t and (t.room ~= r or not want or t[1] ~= math.floor(e.x / 16) or t[2] ~= math.floor(e.y / 16)) then
    if t.room == r and get(r, t[3], t[1], t[2]) == S34 then r:setTile(t[3], t[1], t[2], t.old) end
    e.cartTile31, t = nil, nil
  end
  if want and not t then
    local tx, ty, L = cell(e)
    local old = get(r, L, tx, ty)
    if old then
      e.cartTile31 = { tx, ty, L, old = old, room = r }
      r:setTile(L, tx, ty, S34)
    end
  end
  if e.cartTile31 then e.solid = false end -- the tile stops Link (Field:entityBlocks)
end

function M.sync(f)
  local r = f.room
  if not r then return end
  for _, e in ipairs(f.entities) do
    if e.kind == 6 and not e.deleted then
      local fn = M.INIT[e.id]
      if fn and e.tiles31 ~= r and not e.unplaced then
        e.tiles31 = r
        fn(f, e)
      end
      if e.furnLadder31 and e.tiles31 == r then M.furnitureUpdate(f, e) end
      if e.id == 0x71 and not e.unplaced then -- PUSHABLE_GRAVE (Grave31.lua)
        local G = require("src.zelda.tmc.Grave31")
        if e.grave31 ~= r then e.grave31 = r; G.init(f, e) else G.update(f, e) end
      end
      if e.cart and e.id == M.MINECART then cartSync(f, e) end
    end
  end
end

return M
