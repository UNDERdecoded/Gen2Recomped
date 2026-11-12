-- Round 12: Link's push animation and the pushes that wait for its frame
-- flag (playerUtils.c sub_080790E4 / sub_080793E4, beanstalkSubtask.c
-- UpdatePlayerCollision / sub_0801A4F8, pot.c Pot_Action1 / Pot_Action4).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Walking (ANIM_WALK) with the facing direction held against a solid
--     tile: on the 7th frame (entity subtimer > 5) the animation becomes
--     ANIM_PUSH (ANIM_PUSH_NOCAP), PL_STATE_PUSH.
--   * UpdatePlayerCollision moves a pushable thing in front (a block tile, a
--     statue, a pot's SPECIAL_TILE_0) only on a frame where Link's current
--     keyframe has flag bit 0 set (sub_0801A4F8, full size), and only when
--     the tile beyond is free (sub_0801A458: not stairs $52/$26/$27/$29/
--     $74, collision not $28 and not 1-$F).
--   * A pushed pot (Pot_Action1 SPECIAL_TILE_1-4 -> Pot_Action4): slides at
--     speed $80 for 32 frames (16 px), pushing Link out of its hitbox
--     (sub_0800445C), SFX_10F; then it sits on its new tile (SPECIAL_TILE_0).
-- `p.pushFrame` is true on the frames a push may start (PushBlock.lua,
-- Dungeon.lua statues and Lever.lua read it).
local bit = require("bit")
local band = bit.band

local PA = {}

local ANIM_PUSH, ANIM_PUSH_NOCAP = 0x33C, 0x93C
local SFX_10F = 0x10F
local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }

-- the animation to walk / stand with this frame (Player:update)
function PA.anim(p)
  if p.pushing then return p.hasCap and ANIM_PUSH or ANIM_PUSH_NOCAP end
end

local function heldFacing(p, dx, dy)
  local s = p.animationState or 4
  return (s == 0 and dy < 0) or (s == 4 and dy > 0) or (s == 2 and dx > 0) or (s == 6 and dx < 0)
end

-- after the walk: count frames leaning on a wall, set the push frame flag
function PA.update(p, dx, dy, x0, y0)
  p.pushFrame = false
  if p.minish or p.state ~= "normal" or (p.z or 0) ~= 0 then p.pushT, p.pushing = 0, false return end
  local blocked = (dx ~= 0 or dy ~= 0) and heldFacing(p, dx, dy) and p.x == x0 and p.y == y0
  if not blocked then p.pushT, p.pushing = 0, false return end
  p.pushT = (p.pushT or 0) + 1
  if p.pushT <= 6 then return end
  if not p.pushing then
    p.pushing = true
    p:setAnim(PA.anim(p), true)
  end
  p.pushFrame = band(p.anim.flags or 0, 1) ~= 0
  if p.pushFrame then PA.pot(p) end
  if p.pushFrame and p.state == "normal" then require("src.zelda.tmc.PushableRock").tryPush(p) end -- round 22: SPECIAL_TILE_27
end

-- sub_0801A458: the tile beyond is free for a pushed thing
function PA.beyondFree(f, layer, tx, ty)
  local r = f.room
  local tt = r:tileType(layer or 1, tx, ty)
  local act = tt and tt < 0x4000 and f.assets.actTile[tt] or 0
  if act == 0x52 or act == 0x26 or act == 0x27 or act == 0x29 or act == 0x74 then return false end
  local c = r.coll and r.coll[(layer == 2) and 2 or 1]
  local v = c and c[ty * r.tw + tx] or 0xFF
  if v == 0x28 or (v >= 1 and v <= 0xF) then return false end
  if r:isSolid(tx * 16 + 8, ty * 16 + 8, layer or 1) then return false end
  for _, o in ipairs(f.entities) do
    if (o.liftable or o.statue) and not o.deleted and math.floor(o.x / 16) == tx and math.floor(o.y / 16) == ty then return false end
  end
  return true
end

local function slide(f, e)
  e.x = e.x + e.pdx * 0.5
  e.y = e.y + e.pdy * 0.5
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = 0, y = 0, w = 6, h = 6 })
  e.pushT = e.pushT - 1
  if e.pushT <= 0 then e.pushT = nil; e.x, e.y = math.floor(e.x / 16) * 16 + 8, math.floor(e.y / 16) * 16 + 8 + (e.potYOff or 0) end
end

-- a pot in front (SPECIAL_TILE_0) moves a tile
function PA.pot(p)
  local f = p.field
  local d = DV[p.animationState or 4]
  if not d then return end
  local fx, fy = p:frontPoint(8)
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  for _, o in ipairs(f.entities) do
    if o.liftable and o.id == 0x05 and not o.deleted and not o.pushT and math.floor(o.x / 16) == tx and math.floor(o.y / 16) == ty then
      if PA.beyondFree(f, p.layer, tx + d[1], ty + d[2]) then
        o.potYOff = o.potYOff or (o.y - (ty * 16 + 8))
        o.pdx, o.pdy, o.pushT = d[1], d[2], 32
        f:sound(SFX_10F)
      end
      return
    end
  end
end

-- every frame (Field:update): pots sliding
function PA.tick(f)
  for _, o in ipairs(f.entities) do
    if o.pushT then slide(f, o) end
  end
end

return PA
