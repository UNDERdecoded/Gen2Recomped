-- Round 92: Dark Hyrule Castle 1F, the cannon statues' room ($88:26), checked against the cartridge.
--
-- CARTRIDGE BEHAVIOUR (projectile/cannonballProjectile.c, object/playerClone.c, collision.c):
--   * CannonballProjectile_OnCollision: any player item that hits the ball (iframes < -4) sends it back:
--     action 2, direction = knockbackDirection (from the item that hit it to the ball), snapped to its way home
--     (type ^ 2) << 3 when `direction - home + 1 < 3` -- an UNSIGNED test: home 16 snaps 15 / 16 / 17, home 0
--     snaps 0 / 1 only (31 + 1 = 32 is not below 3).
--   * Each Four Sword clone (PLAYER_CLONE) swings its own PLAYER_ITEM_SWORD, a player item like Link's: a clone's
--     swing sends a cannonball back exactly as Link's does.  The room needs it: the four statues fire together
--     every 180 frames and AngryStatueManager_Action1 wants all four knocked out at once (their bits $F inside
--     the 30 frames a hit statue stays down) -- the four Links on the four clone tiles under them, one swing.
--   * The ball moves by ProcessMovement3: sub_080AF0C8 (tile types $87 .. $8A stop a move into them), then
--     CalculateEntityTileCollisions(direction, 3) at its CURRENT spot, then ProcessMovementInternal (the
--     corner slides of MoveNorth ...).  Collision type 3 is IsTileCollision's projectile row: a partial tile
--     (value 1 .. $E) is FilledNone, $F FilledAll, $FF (tileCollisionFunctions) FilledNone -- a cannonball flies
--     over the room's low rails (values $0C / $03) and hits the statues' SPECIAL_TILE_34 ($F).  Action 1: no
--     move -> FX_DEATH; action 2: no statue met (sub_080AB634) and collisions != 0 -> FX_DEATH.
-- Port gaps fixed here (DHCObjects' ballUpdate calls M.snap / M.cloneHit / M.pm3, anchored lines):
--   * the snap was a 5-bit wrap (home 0 also snapped 31);
--   * only Link's own sword box sent a ball back (the clones' swords went through it);
--   * the ball moved by EnemyDHC's ProcessMovement0 box test (Room:isSolid, the new spot tested):
--     the rails stopped every ball, and a ball sent back died one step short of its statue's hitbox (12.5 px
--     from it on the cartridge, 15 here) -- no statue could be knocked out.
-- SIMPLIFIED: the shape values $10 .. $FE take the walker's shape test (Room:isSolid), not collision type 3's
--   own row of IsTileCollision's lookup; the hitbox probe distances (unk2) are EnemyFoW's defaults.
local bit = require("bit")

local M = {}

-- `direction - home + 1 < 3` as the cartridge's u32 compare
function M.snap(direction, home)
  local v = (direction or 0) - home + 1
  if v >= 0 and v < 3 then return home end
  return direction
end

-- a clone's sword box (Link's box at the clone, Clone79.boxes) on the ball: the clone's position for the
-- knockback direction.  Returns the clone that hit, or nil.  `t` is the box's frame stamp window (the
-- ball's own test takes Link's box from this frame or the one before).
function M.cloneHit(f, c)
  local b = f.swordBoxNow
  if not b or not b.t or b.t < (f.frame or 0) - 1 or b.fromClone or b.t == c.cloneSwordT then return nil end
  local p = f.player
  local cl = rawget(f, "playerClones")
  if type(cl) ~= "table" or not p then return nil end
  local hb = c.hitbox or { x = 0, y = 0, w = 6, h = 6 }
  for _, k in ipairs(cl) do
    if k.action == 2 and not k.deleted then
      local dx, dy = k.x - math.floor(p.x), k.y - math.floor(p.y)
      if math.abs(b.x + dx - (c.x + (hb.x or 0))) < b.w + hb.w and math.abs(b.y + dy - (c.y + (hb.y or 0))) < b.h + hb.h then
        c.cloneSwordT = b.t
        return k
      end
    end
  end
  return nil
end

-- the send-back (CannonballProjectile_OnCollision) from (fx, fy)
function M.sendBack(c, fx, fy, dirTo)
  c.action = 2
  c.direction = dirTo(fx, fy, c.x, c.y)
  c.direction = M.snap(c.direction, bit.lshift(bit.bxor(c.form or 0, 2), 3))
  c.speed = 0x280
end

-- IsTileCollision(..., collisionType 3) on the room's layer
function M.solid3(room, x, y, layer, shapeSolid)
  x, y = math.floor(x), math.floor(y)
  if x < 0 or y < 0 or x >= room.width or y >= room.height then return true end
  local c = room.coll[layer == 2 and 2 or 1] or room.coll[1]
  local v = c[bit.rshift(y, 4) * room.tw + bit.rshift(x, 4)] or 0
  if v == 0 then return false end
  if v < 0x0F then return false end -- FilledNone
  if v == 0x0F then return true end -- FilledAll
  if v == 0xFF then return false end -- collisionFunctionLookup[3] = FilledNone
  return (shapeSolid or room.isSolid)(room, x, y, layer) -- (SIMPLIFIED: the shapes)
end

-- sub_080AF0C8: a tile type $87 .. $8A under the entity bars moves toward its side
local SIDE = { [0x87] = { 7, 0x000E }, [0x8A] = { -1, 0xE000 }, [0x88] = { -9, 0x00E0 }, [0x89] = { -0x11, 0x0E00 } }
function M.edgeStop(f, e)
  local tt = f.room:tileType((e.layer == 2) and 2 or 1, math.floor(e.x / 16), math.floor(e.y / 16))
  local s = tt and SIDE[tt]
  if s and bit.band((e.direction or 0) + s[1], 0x1F) < 0x10 then e.collisions = s[2] return true end
  return false
end

-- ProcessMovement3 for entity e (its .direction / .speed unless given); true when it moved
function M.pm3(E, e, dir, speed)
  dir = dir or e.direction
  if not dir or bit.band(dir, 0x80) ~= 0 or dir >= 0x20 then return false end
  local f = E.field
  if M.edgeStop(f, e) then return false end
  local FW = require("src.zelda.tmc.EnemyFoW")
  local room, layer = f.room, (e.layer == 2) and 2 or 1
  local own, isSolid0 = rawget(room, "isSolid"), room.isSolid
  -- CalculateEntityTileCollisions(.., 3): EnemyFoW's probe points with collision type 3's test
  room.isSolid = function(r, x, y) return M.solid3(r, x, y, layer, isSolid0) end
  local ok, res = pcall(function()
    e.collisions = FW.calcCollisions(E, e, dir)
    return require("src.zelda.tmc.Move91").internal(E, e, dir, speed or e.speed or 0)
  end)
  room.isSolid = own
  if not ok then error(res, 0) end
  return res
end

return M
