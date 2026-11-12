-- Round 18: LADDER_UP ($41, object/ladderUp.c), the ladders out of caves.
--
-- Init: action 1 when its timer is set (it falls from z -$80, then
--   FX_GIANT_EXPLOSION, a 30-frame shake, SFX_10B, 60 frames, SFX_SECRET_BIG),
--   else action 3; spriteOffsetY + 8, animation 10; type2 0: y snapped to
--   (y & ~$F) + $C and SPECIAL_TILE_35 (object top) on its tile.
-- Action 3 (type2 0): Link below it -> its tile SPECIAL_TILE_23 (ladder) and
--   the tile under it SPECIAL_TILE_23 (type 0) / SPECIAL_TILE_20 (type 1,
--   the ladder-top transition); Link above it and not on a ladder ->
--   SPECIAL_TILE_35 again and the tile under it restored
--   (RestorePrevTileEntity).
local L = {}

local SP20, SP23, SP35 = 0x4014, 0x4017, 0x4023
local SFX_10B, SFX_SECRET_BIG = 0x10B, 0x73
local FX_GIANT_EXPLOSION = 0x46

local function tileOf(e) return math.floor(e.x / 16), math.floor(e.y / 16) end

function L.spawn(dungeon, e)
  local f = dungeon.field
  local def = f:objects():def(0x41, e.form or 0)
  if def then f:objects():dress(e, def, 10) end
  e.objAnim, e.literalAnim = 10, true
  e.spriteOY = (e.spriteOY or 0) + 8
  e.ladderUp = true
  e.action = (e.timer0 or 0) ~= 0 and 1 or 3
  if e.action == 1 then e.z, e.zv = 0x80, 0 end
  if (e.type2 or 0) == 0 then
    e.y = math.floor(e.y / 16) * 16 + 0xC
    local tx, ty = tileOf(e)
    f.room:setTile(e.layer or 1, tx, ty, SP35)
  end
  e.extUpdate = function(_, me) L.update(f, me) end
  dungeon:track(e)
  return e
end

function L.update(f, e)
  local r = f.room
  local layer = e.layer or 1
  local tx, ty = tileOf(e)
  if e.action == 1 then
    -- GravityUpdate(Q_8_8(16)): z falls at 1/16 px per frame squared
    e.zv = (e.zv or 0) + 16 / 256
    e.z = e.z - e.zv
    if e.z <= 0 then
      e.z = 0
      f:addFx(e.x, e.y + 8, 0x0F, FX_GIANT_EXPLOSION)
      if f.shake then f:shake(30, 0) end
      f:sound(SFX_10B)
      e.action, e.timer = 2, 60
    end
    return
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer > 0 then return end
    e.action = 3
    f:sound(SFX_SECRET_BIG)
    return
  end
  if (e.type2 or 0) ~= 0 then return end
  local p = f.player
  -- the way out at the ladder's top (SIMPLIFIED: the cartridge's
  -- UpdateDoorTransition fires on the door / ladder-top act tiles; in the
  -- port's maps the cave's back wall above the ladder is act $2A, so Link
  -- stops a pixel short of the exit's 12 x 12 rect).  Link on the ladder
  -- at its top, pushing up: the area exit right above it.
  local py = math.floor(p.y)
  if math.abs(math.floor(p.x) - e.x) <= 6 and py <= e.y - 12 and py >= e.y - 20 and (p.climbing or p.moving) and not f.transition then
    for _, ex in ipairs(r.exits or {}) do
      if ex.warpType == 1 and math.abs(ex.startX - e.x) <= 6 and ex.startY < e.y and e.y - ex.startY <= 32 then
        f:startTransition(ex)
        return
      end
    end
    -- a ladder up to the room's top edge: its north border exit
    if e.y <= 0x30 then
      local bx = r.borderExit and r:borderExit(0, p.x, p.y)
      if bx then f:startTransition(bx, 0) return end
    end
  end
  local cur = r:tileType(layer, tx, ty)
  if math.floor(p.y) < math.floor(e.y) then
    if not p.climbing and cur == SP23 then
      r:setTile(layer, tx, ty, SP35)
      if e.prevBelow then r:setTile(layer, tx, ty + 1, e.prevBelow) end
    end
  elseif cur ~= SP23 then
    r:setTile(layer, tx, ty, SP23)
    local below = r:tileType(layer, tx, ty + 1)
    if below ~= SP23 and below ~= SP20 then
      local name = layer == 2 and "top" or "bottom"
      e.prevBelow = r.maps[name][(ty + 1) * r.tw + tx]
    end
    r:setTile(layer, tx, ty + 1, (e.form or 0) == 0 and SP23 or SP20)
  end
end

return L
