-- Round 31: Minish Link pushes pots (the full-size push is PushAnim.lua).
-- One hook at the top of PushAnim.update.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * beanstalkSubtask.c UpdatePlayerCollision, case SPECIAL_TILE_0 (a pot's
--     tile, gUnk_080B4468 = the tile in front): sub_0801A458 -- the push
--     test sub_0801A4F8 and the tile beyond free -- then the pot's tile
--     becomes SPECIAL_TILE_1 + animationState / 2 (Pot_Action1 slides the
--     pot 16 px, PushAnim.lua) and gPlayerState.pushedObject = $C0 for
--     Minish Link ($A0 full size), PLAYER_PUSH, PL_BUSY.
--   * sub_0801A4F8 for PL_MINISH: GetInventoryValue(ITEM_POWER_BRACELETS)
--     == 1, the stick held (not DIR_NOT_MOVING), held direction = Link's
--     direction, and Link's collisions bit on that side (he is against
--     it).  No push animation frame is waited for (that is the full-size
--     rule: frame & 1).
--   * player.c PlayerPushInit: speed kPushSpeed / 2 for Minish Link ($40 =
--     0.25 px a frame); PlayerPushUpdate counts pushedObject & $7F down
--     ($40 frames, 16 px) moving him behind the pot; PlayerPushEnd.
local bit = require("bit")
local M = {}

M.ITEM_POWER_BRACELETS = 0x45
M.SPECIAL_TILE_0 = 0x4000
local DV = require("src.zelda.tmc.RomTables").t("Push31.DV")
local SFX_10F = 0x10F

local function heldFacing(p, dx, dy)
  local s = p.animationState or 4
  return (s == 0 and dy < 0) or (s == 4 and dy > 0) or (s == 2 and dx > 0) or (s == 6 and dx < 0)
end

-- the tile in front of Minish Link's box (HW 2, top -2, bottom +1)
function M.front(p)
  local s = p.animationState or 4
  if s == 0 then return p.x, p.y - 4 end
  if s == 4 then return p.x, p.y + 3 end
  if s == 2 then return p.x + 3, p.y end
  return p.x - 4, p.y
end

local function pushUpdate(p)
  local ps = p.minishPush31
  local v = DV[ps.dir]
  if v then p:moveBy(v[1] * 0.25, v[2] * 0.25) end
  ps.left = ps.left - 1
  if ps.left <= 0 then p.minishPush31 = nil; p.extUpdate = nil; p.state = "normal" end
end

-- PushAnim.update for Minish Link (dx, dy = the attempted move; x0, y0 =
-- where he stood before it)
function M.update(p, dx, dy, x0, y0)
  local f = p.field
  if not p.minish or p.state ~= "normal" or (p.z or 0) ~= 0 then return false end
  if (f:inventory(M.ITEM_POWER_BRACELETS) or 0) ~= 1 then return false end
  if (dx == 0 and dy == 0) or not heldFacing(p, dx, dy) then return false end
  local d = DV[p.animationState or 4]
  if not d then return false end
  -- the collisions bit on the pushing side: no progress on that axis
  if (d[1] ~= 0 and p.x ~= x0) or (d[2] ~= 0 and p.y ~= y0) then return false end
  local fx, fy = M.front(p)
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local L = p.layer or 1
  if f.room:tileType(L, tx, ty) ~= M.SPECIAL_TILE_0 then return false end
  local PA = require("src.zelda.tmc.PushAnim")
  for _, o in ipairs(f.entities) do
    if o.liftable and o.id == 0x05 and not o.deleted and not o.pushT and math.floor(o.x / 16) == tx and math.floor(o.y / 16) == ty then
      if not PA.beyondFree(f, L, tx + d[1], ty + d[2]) then return false end
      o.potYOff = o.potYOff or (o.y - (ty * 16 + 8))
      o.pdx, o.pdy, o.pushT = d[1], d[2], 32
      f:sound(SFX_10F)
      p.state = "ext"
      p.x, p.y = math.floor(p.x), math.floor(p.y)
      p.minishPush31 = { left = 0x40, dir = p.animationState }
      p.extUpdate = pushUpdate
      return true
    end
  end
  return false
end

-- UpdatePlayerCollision case SPECIAL_TILE_62 (a grave, full size): Link
-- facing north (animationState 0), moving, his frame's bit 1 set, the tile
-- in front SPECIAL_TILE_62 -> SPECIAL_TILE_63 (pushableGrave.c Action1
-- slides it), pushedObject $82 (two frames of PLAYER_PUSH)
function M.full(p)
  if p.minish or p.state ~= "normal" or (p.animationState or 4) ~= 0 then return false end
  if bit.band(p.anim and p.anim.flags or 0, 2) == 0 then return false end
  local f = p.field
  local fx, fy = p.x, p.y - 5 - 2
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local L = p.layer or 1
  if f.room:tileType(L, tx, ty) ~= 0x403E then return false end
  f.room:setTile(L, tx, ty, 0x403F)
  return true
end

return M
