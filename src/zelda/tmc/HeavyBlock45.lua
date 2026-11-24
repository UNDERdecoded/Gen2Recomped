-- Round 45: the big blocks only Link and his clones can push together
-- (ACT_TILE_114, tile types $369-$376: 2 x 2, 3 x 3 and 4 x 4 blocks).
--
-- CARTRIDGE BEHAVIOUR (src/beanstalkSubtask.c UpdatePlayerCollision case
-- ACT_TILE_114 and sub_0801A570; src/object/playerClone.c sub_08084CAC;
-- src/object/blockPushed.c types 1-3; src/player.c PlayerPush type 0):
--   * Link leaning on the block (the moving check, a keyframe with flag bit
--     0): sub_0801A570(Link, 1) walks from the tile 10 px ahead to the
--     block's corner ($370 bottom-left going left / down for north / east,
--     $36F top-right going right / up for south / west), then along the
--     edge ($374 left-middle / $372 top-middle) counting its size n (2 + the
--     middle tiles) to the top-left tile; that tile must be $369 (any way)
--     or the one-way corner for the push ($36A north, $36D east, $36B south,
--     $36C west) and the n tiles of collision beyond the block's far side
--     all 0.  Else nothing.
--   * n - 1 clones must lean on the same block: each clone (sub_08084CAC,
--     every frame) marks whether the tile at its own gUnk_080B4468 probe is
--     ACT_TILE_114, and sub_0801A570(clone, 0) (no checks) must give the
--     same top-left tile.
--   * Then PUSHED_BLOCK type n - 1 at the top-left tile centre + (n - 1) * 8
--     (the block's centre), its tile type remembered, every block tile
--     TILE_TYPE_32 (vertical push) / 33 (horizontal) ($2E / $2F on the top
--     layer), SFX_10F; it moves at $80 for 32 frames (16 px) pushing Link out
--     of gUnk_0811F64C[type], then lays the block at its new top-left: the
--     remembered corner, $36F, $370, $371 (2 x 2) / with $372 $374 $375 $376
--     $373 for the larger ones.
--   * Link: pushedObject $A0, PLAYER_PUSH type 0: kPushSpeed ($80) along his
--     facing for $20 frames, then PlayerPushEnd (subtimer 6, the walk).
-- One hook in PushAnim.update (on a push frame, as the other block pushes).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.ACT = 0x72 -- ACT_TILE_114
M.T = { TL = 0x369, TL_N = 0x36A, TL_S = 0x36B, TL_W = 0x36C, TL_E = 0x36D, TR = 0x36F, BL = 0x370, BR = 0x371,
        TOP = 0x372, BOTTOM = 0x373, LEFT = 0x374, RIGHT = 0x375, MID = 0x376 }
local T = M.T
local OBJ_PUSHED_BLOCK = 0x07
local SFX_10F = 0x10F
local PUSH_FRAMES, PUSH_SPEED = 0x20, 0x80
local BOX = require("src.zelda.tmc.RomTables").t("HeavyBlock45.BOX") -- gUnk_0811F62C.. by type
local PROBE = require("src.zelda.tmc.RomTables").t("Player.PROBE") -- gUnk_080B4468
local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }

local function ttype(r, L, tx, ty) return r:tileType(L, tx, ty) end
local function collAt(r, L, tx, ty)
  local c = r.coll and r.coll[(L == 2) and 2 or 1]
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return 0xFF end
  return c and c[ty * r.tw + tx] or 0xFF
end

-- sub_0801A570: the block's top-left tile and size seen from (x, y) facing
-- s; check = false returns the tile without the checks (the clones' test)
function M.locate(r, L, x, y, s, check)
  local tx, ty
  local cs = rshift(band(s or 4, 6), 1)
  if cs == 0 then tx, ty = math.floor(x / 16), math.floor((y - 10) / 16)
  elseif cs == 1 then tx, ty = math.floor((x + 10) / 16), math.floor(y / 16)
  elseif cs == 2 then tx, ty = math.floor(x / 16), math.floor((y + 10) / 16)
  else tx, ty = math.floor((x - 10) / 16), math.floor(y / 16) end
  local n = 2
  if cs == 0 or cs == 1 then
    -- find the bottom-left corner: left (north) / down (east)
    for _ = 1, 4 do
      if ttype(r, L, tx, ty) == T.BL then break end
      if cs == 0 then tx = tx - 1 else ty = ty + 1 end
    end
    ty = ty - 1
    while n < 4 and ttype(r, L, tx, ty) == T.LEFT do n = n + 1; ty = ty - 1 end
  else
    -- find the top-right corner: right (south) / up (west)
    for _ = 1, 4 do
      if ttype(r, L, tx, ty) == T.TR then break end
      if cs == 2 then tx = tx + 1 else ty = ty - 1 end
    end
    tx = tx - 1
    while n < 4 and ttype(r, L, tx, ty) == T.TOP do n = n + 1; tx = tx - 1 end
  end
  if not check then return tx, ty, n end
  local tl = ttype(r, L, tx, ty)
  local okCorner = ({ [0] = T.TL_N, T.TL_E, T.TL_S, T.TL_W })[cs]
  if tl ~= T.TL and tl ~= okCorner then return nil end
  for i = 0, n - 1 do
    local cx, cy
    if cs == 0 then cx, cy = tx + i, ty - 1
    elseif cs == 1 then cx, cy = tx + n, ty + i
    elseif cs == 2 then cx, cy = tx + i, ty + n
    else cx, cy = tx - 1, ty + i end
    if collAt(r, L, cx, cy) ~= 0 then return nil end
  end
  return tx, ty, n
end

-- sub_08084CAC: the clone leans on a heavy block (its probe tile is ACT_TILE_114)
local function cloneOn(f, c, s)
  local pr = PROBE[s] or PROBE[4]
  local tx, ty = math.floor((c.x + pr[1]) / 16), math.floor((c.y + pr[2]) / 16)
  local tt = f.room:tileType(c.layer or 1, tx, ty)
  local act = tt and tt < 0x4000 and f.assets.actTile[tt] or nil
  return act == M.ACT
end

-- the block's tiles after the move (blockPushed.c sub_080830B8)
local function layTiles(n, corner)
  if n == 2 then return { { corner, T.TR }, { T.BL, T.BR } } end
  local rows = {}
  for j = 0, n - 1 do
    local row = {}
    for i = 0, n - 1 do
      local v
      if j == 0 then v = (i == 0 and corner) or (i == n - 1 and T.TR) or T.TOP
      elseif j == n - 1 then v = (i == 0 and T.BL) or (i == n - 1 and T.BR) or T.BOTTOM
      else v = (i == 0 and T.LEFT) or (i == n - 1 and T.RIGHT) or T.MID end
      row[#row + 1] = v
    end
    rows[#rows + 1] = row
  end
  return rows
end
M.layTiles = layTiles

local function blockUpdate(d, e)
  local f = d.field
  e.x = e.x + e.mdx * PUSH_SPEED / 256
  e.y = e.y + e.mdy * PUSH_SPEED / 256
  local b = BOX[e.form] or BOX[1]
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = b.x, y = b.y, w = b.w, h = b.h })
  e.timer = e.timer - 1
  if e.timer <= 0 then
    local off = e.form * 8
    local tx, ty = math.floor((e.x - off) / 16), math.floor((e.y - off) / 16)
    local rows = layTiles(e.form + 1, e.corner)
    local O = f:objects()
    for j, row in ipairs(rows) do for i, v in ipairs(row) do O:setTileType(e.layer, tx + i - 1, ty + j - 1, v) end end
    e.deleted = true
  end
end

local function pushUpdate(p)
  local ps = p.heavyPush
  local v = DV[ps.dir]
  p:moveBy(v[1] * PUSH_SPEED / 256, v[2] * PUSH_SPEED / 256)
  if p.anim then p.anim:update(1) end
  ps.left = ps.left - 1
  if ps.left <= 0 then
    p.heavyPush = nil; p.extUpdate = nil; p.state = "normal"
    p.pushT, p.pushing = 0, false
  end
end

-- PushAnim.update on a push frame (UpdatePlayerCollision, ACT_TILE_114)
function M.tryPush(p)
  local f = p.field
  if p.minish or p.state ~= "normal" or not p.probe or not (f and f.room and f.room.tileType) then return false end
  local s = p.animationState or 4
  local fx, fy = p:probe()
  local r = f.room
  local L = p.layer or 1
  local tt = r:tileType(L, math.floor(fx / 16), math.floor(fy / 16))
  local act = tt and tt < 0x4000 and f.assets.actTile[tt] or nil
  if act ~= M.ACT then return false end
  local x, y = math.floor(p.x), math.floor(p.y)
  local tx, ty, n = M.locate(r, L, x, y, s, true)
  if not tx then return false end
  local need, have = n - 1, 0
  local cl = rawget(f, "playerClones")
  for _, c in ipairs(type(cl) == "table" and cl or {}) do
    if not c.deleted and c.action == 2 and cloneOn(f, c, s) then
      local cx, cy = M.locate(r, c.layer or L, c.x, c.y, s, false)
      if cx == tx and cy == ty then have = have + 1 end
    end
  end
  if have < need then return false end
  -- PUSHED_BLOCK type n - 1
  local v = DV[s]
  local corner = r:tileType(L, tx, ty)
  local horiz = v[1] ~= 0
  local O = f:objects()
  for j = 0, n - 1 do for i = 0, n - 1 do
    O:setTileType(L, tx + i, ty + j, (L == 2) and (horiz and 0x2F or 0x2E) or (horiz and 0x21 or 0x20))
  end end
  local form = n - 1
  local e = { kind = 6, id = OBJ_PUSHED_BLOCK, form = form, x = tx * 16 + 8 + form * 8, y = ty * 16 + 8 + form * 8, z = 0,
              layer = L, mdx = v[1], mdy = v[2], timer = 32, corner = corner, heavyBlock = true, pushedBlock = true }
  local def = O:def(OBJ_PUSHED_BLOCK, form)
  if def then O:dress(e, def, 0) end
  e.extUpdate = blockUpdate
  f.entities[#f.entities + 1] = e
  f._dungeon:track(e)
  f:sound(SFX_10F)
  -- Link: PLAYER_PUSH type 0, pushedObject $A0
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  p.heavyPush = { left = PUSH_FRAMES, dir = s }
  p.extUpdate = pushUpdate
  return true
end

return M
