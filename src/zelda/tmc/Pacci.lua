-- The Cane of Pacci (round 7): item/itemPacciCane.c, playerItem/
-- playerItemPacciCane.c, playerItem/playerItemPacciCaneProjectile.c and the
-- player's spring out of a charged hole (player.c PlayerInHole*).
--
--   Swing   ANIM_CANE ($628 + facing); the cane sprite (20, swap gfx, OBJ
--           palette 4) shows frame Link's frameIndex + $6F while his frame
--           byte's low nibble is not $F; frame bit $40 fires the projectile.
--   Bolt    sprite 166, common OBJ tiles from 57, palette 4, animation 17
--           (vertical) / 18 (horizontal) with the per-direction flips; starts
--           18 / 14 px ahead of Link, 2 px a frame for $40 frames; touching
--           an entity hits it with hurtType $1D (a mine cart hops over); an
--           ACT_TILE_25 hole takes it: it sits there (SPECIAL_TILE_32) for
--           up to $1E0 frames and ends with animation $13, SFX_199.
--   Spring  Link stepping into a charged hole sinks (40 frames), then jumps:
--           over the ledge ahead when there is one (zVelocity n - 1/4,
--           1 px a frame, n tiles), else straight up (3.5625) and back.
local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local Pacci = {}

local ITEM_PACCI_CANE = 0x12
local ANIM_CANE, ANIM_JUMP = 0x628, 0x810
local START = { [0] = { 0, -18 }, { 14, 0 }, { 0, 14 }, { -14, 0 } } -- gUnk_0811B9A0 (by animationState / 2)
local VEC = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
-- gUnk_0811B9A8: flipX, flipY, animation
local LOOK = { [0] = { false, false, 17 }, { true, false, 18 }, { false, true, 17 }, { false, false, 18 } }
local ACT_HOLE = 25

local function tileKey(x, y) return math.floor(x / 16) .. ":" .. math.floor(y / 16) end

-- the bolt
local function spawnBolt(f, p)
  local s = p.animationState / 2
  local st, lk = START[s], LOOK[s]
  local A = f.assets
  local spr = A:sprite(166)
  local b = { kind = 8, id = 0x16, bolt = true, x = p.x + st[1], y = p.y + st[2], z = 0, dir = s,
              layer = p.layer, life = 0x40, life2 = 0x1E0, sprite = 166, gfx = { vram = 57 },
              palette = A:objPalette(4), anim = require("src.zelda.tmc.Anim").new(),
              flipX = lk[1], flipY = lk[2], field82 = 0, interactType = 0, action = 1 }
  b.anim:set(spr, lk[3], true)
  b.literalAnim, b.objAnim, b.animIndex = true, lk[3], lk[3]
  b.drawGhost = function(me, field, camX, camY) Pacci.drawBolt(field, me, camX, camY) end
  b.extUpdate = function(_, me) Pacci.updateBolt(f, me) end
  f.entities[#f.entities + 1] = b
  f._dungeon:track(b)
  f:sound(0x1DD)
  return b
end

local function boltEnd(f, b)
  b.action = 2
  if b.hole then f.pacciHoles[b.hole] = nil end
  b.anim:set(f.assets:sprite(166), 0x13, true)
  b.objAnim, b.animIndex = 0x13, 0x13
  f:sound(0x199)
end

function Pacci.updateBolt(f, b)
  b.anim:update(1)
  if b.action == 2 then
    if b.anim.done then b.deleted = true end
    return
  end
  if b.action == 4 then
    -- sitting in a hole: until Link uses it or time runs out
    b.life2 = b.life2 - 1
    if b.life2 < 0 or not f.pacciHoles[b.hole] then boltEnd(f, b) end
    return
  end
  b.life, b.life2 = b.life - 1, b.life2 - 1
  if b.life < 0 or b.life2 < 0 then return boltEnd(f, b) end
  local v = VEC[b.dir]
  b.x, b.y = b.x + v[1] * 2, b.y + v[2] * 2
  -- walls stop it
  if f.room:isSolid(b.x, b.y, b.layer) and (f._dungeon:actAt(b.x, b.y, b.layer) or 0) ~= ACT_HOLE then return boltEnd(f, b) end
  if (f._dungeon:actAt(b.x, b.y, b.layer) or 0) == ACT_HOLE then
    b.action = 4
    b.x = math.floor(b.x / 16) * 16 + 8
    b.y = math.floor(b.y / 16) * 16 + 8
    b.hole = tileKey(b.x, b.y)
    f.pacciHoles = f.pacciHoles or {}
    f.pacciHoles[b.hole] = b
    b.anim:set(f.assets:sprite(166), 0x14, true)
    b.objAnim, b.animIndex = 0x14, 0x14
    return
  end
  -- what it touches: hurtType $1D
  for _, e in ipairs(f.entities) do
    if e ~= b and not e.deleted and not e.hidden and math.abs(e.x - b.x) < 10 and math.abs(e.y - b.y) < 10 then
      if e.onPacciObj and e.onPacciObj(f, e, b) then return boltEnd(f, b) -- round 25: lava platforms (contact $1D)
      elseif e.cart then
        require("src.zelda.tmc.Minecart").pacciHit(f, e)
        return boltEnd(f, b)
      elseif e.kind == 6 and e.id == 0x05 and e.liftable and not e.thrown then
        -- round 10: pot.c Pot_Action1 contact $1D: the pot hops (zVelocity
        -- 2.625, GravityUpdate Q_8_8(32) = 1/8 px), turns upside down on
        -- the way down (flipY) and breaks where it lands (BreakPot)
        e.liftable, e.solid = false, false
        e.thrown, e.potFlip = true, true
        e.vx, e.vy, e.z, e.zv, e.grav = 0, 0, 0, 2.625, 0.125
        e.form = e.form or 0
        return boltEnd(f, b)
      elseif e.enemy and not e.dying then
        f:enemies():hit(e, 0x1D, b.x, b.y)
        if e.onPacci then e.onPacci(e, f) end
        return boltEnd(f, b)
      end
    end
  end
end

function Pacci.drawBolt(f, b, camX, camY)
  local frame = b.anim.frame
  if not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(166, frame, b.palette, "pacci", b.gfx)
  if not img then return end
  local x, y = math.floor(b.x - camX), math.floor(b.y - camY)
  local sx, sy = b.flipX and -1 or 1, b.flipY and -1 or 1
  love.graphics.draw(img, x + (b.flipX and -ox or ox), y + (b.flipY and -oy or oy), 0, sx, sy)
end

-- the swing (Crenel.useItem)
function Pacci.use(p, item, button)
  if item ~= ITEM_PACCI_CANE or p.minish or p.state ~= "normal" then return false end
  local f = p.field
  p.state = "ext"
  p:setAnim(ANIM_CANE, true)
  f:sound(0x10E)
  local fired = false
  p.drawOver = function(pl, x, y)
    local fl = pl.anim.flags or 0
    if band(fl, 0xF) == 0xF then return end
    local fr = band((pl.anim.frame or 0) + 0x6F, 0xFF) -- u8: Link's cane frames start at $91
    local img, ox, oy = f.assets:spriteFrame(20, fr, f.assets:objPalette(4), "cane", nil)
    if not img then return end
    local flip = pl.anim:hflip()
    if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  end
  p.extUpdate = function(pl)
    pl.anim:update(1)
    local fl = pl.anim.flags or 0
    if band(fl, 0x40) ~= 0 and not fired then fired = true; spawnBolt(f, pl) end
    if band(fl, 0x80) ~= 0 or pl.anim.done then
      if not fired then fired = true; spawnBolt(f, pl) end
      pl.state = "normal"
      pl.extUpdate, pl.drawOver = nil, nil
      pl.animId = -1
    end
  end
  return true
end

-- how many tiles of ledge lie ahead (sub_0807A2F8, simplified: solid
-- bottom-layer tiles followed by open floor, up to 2)
local function ledgeAhead(f, p)
  local v = VEC[p.animationState / 2]
  for n = 1, 3 do
    local x, y = p.x + v[1] * 16 * n, p.y + v[2] * 16 * n
    if not f.room:isSolid(x, y, 1) and (f._dungeon:actAt(x, y, 1) or 0) ~= ACT_HOLE then
      return n > 1 and (n - 1) or 0, x, y
    end
  end
  return 0
end

-- Dungeon:checkFall: Link on a hole
function Pacci.holeLaunch(dungeon, p)
  local f = dungeon.field
  local key = tileKey(p.x, p.y - 1)
  local b = f.pacciHoles and f.pacciHoles[key]
  if not b then return false end
  -- PlayerInHoleInit: centred, sinking
  p.state = "ext"
  p.x = math.floor(p.x / 16) * 16 + 8
  p.y = math.floor((p.y - 1) / 16) * 16 + 10
  f:sound(0x81)
  local t = 0
  p.extUpdate = function(pl)
    t = t + 1
    pl.anim:update(1)
    if t < 40 then return end
    if t == 40 then
      -- the spring: SPECIAL_TILE_33, the bolt is used up
      f.pacciHoles[key] = nil
      local n = ledgeAhead(f, pl)
      local v = VEC[pl.animationState / 2]
      if n > 0 then pl.zv, pl.spd = n + 1, 1 else pl.zv, pl.spd = 3.5625, 0.25 end
      pl.vx, pl.vy = v[1] * pl.spd, v[2] * pl.spd
      pl.z = 0.01
      pl:setAnim(ANIM_JUMP, true)
      f:sound(0x7C)
      return
    end
    pl.x, pl.y = pl.x + pl.vx, pl.y + pl.vy
    pl.zv = pl.zv - 0.125
    pl.z = pl.z + pl.zv
    if pl.z <= 0 then
      pl.z = 0
      pl.state = "normal"
      pl.extUpdate = nil
      pl.animId = -1
      dungeon.safe = nil
    end
  end
  return true
end

return Pacci
