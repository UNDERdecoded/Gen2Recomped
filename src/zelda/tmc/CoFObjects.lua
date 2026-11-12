-- Round 25: three Cave of Flames objects, ported from the decomp.
--
-- LAVA_PLATFORM $59 (src/object/lavaPlatform.c):
--   Type 0 (the room's list entry, type2 = room property index): Init makes
--     one type-1 platform per LavaPlatformEntry of GetCurrentRoomProperty
--     (16 bytes: u32 rail, s16 x, s16 y, u8 layer, u8 type2, u16 wobble,
--     u16 respawn; type2 $FF ends), each with direction $FF, speed 0, the
--     spawner as parent, then UpdateRailMovement.  Afterwards the spawner is
--     the flip animation: when a platform hands itself over (timer byte
--     set, sub_08092620) it is drawn on the platform, zVelocity 2.75,
--     SFX_LAVA_TILE_FLIP, animation = the platform's state, the platform
--     shows animation 3; GravityUpdate(36/256) -- under 1.5 it steps the
--     animation -- landed: hidden, the platform's own animation back,
--     spriteOffsetY 0, FX_LAVA_SPLASH_HUGE.
--   Type 1 (the platform): Init: animationState = type2, priority 7, hit
--     type by state (sub_0809264C: odd = upside down, action 7, hit type
--     $AC; even = action 2, hit type 1), drawn at spriteOffsetY -3.
--     Action1 (flipping, while the spawner's copy is in the air): first
--     frame toggles state bit 0 and its animation; then spriteOffsetY
--     counts down to -3 and sub_0809264C.  Action2: the Cane's bolt
--     (contact $1D) flips it; Link (full size, on the ground, not busy)
--     within 16 px -> action 3 (20 frames, Link drawn 3 px up), then 4:
--     animation 2 and SFX_LAVA_TILE_STEP; under $8D frames of wobbleTime
--     the animation runs (frame bit 0: SFX_LAVA_TILE_WOBBLE, bit 1:
--     SFX_LAVA_TILE_SINK); done = sunk: hidden for respawnTime (action 5),
--     then animation state + 4 rises (action 6: frame bit 0 = solid again,
--     hit type $AC), done -> sub_0809264C.  Action7 (upside down): only the
--     Cane flips it.  Every frame: SyncPlayerToPlatform (Link carried along
--     its rail while on it), the rail's next leg when unk_76 runs out.
--   Link on a platform: field_0x14 = 1 -- the lava under it does not burn
--     (Dungeon.checkFall asks CoFObjects.supports).
-- OBJECT_ON_PILLAR $6D (src/object/objectOnPillar.c): a block on a pillar
--   top.  Its tile becomes SPECIAL_TILE_54 (the old metatile remembered).
--   Link pushing it (UpdatePlayerCollision, SPECIAL_TILE_54: the tile
--   beyond free for collision type $B, PLAYER_PUSH $20 frames at kPushSpeed)
--   turns the tile into SPECIAL_TILE_55 + facing / 2; the object's Action1
--   sees it (sub_08097008): the old tile back, SFX_10F, $20 frames at $80
--   that way (Action3, pushing Link out; spriteOffsetY 2 over ACT_TILE_25
--   or toward tile types $77 / $79).  Stopped: over tile type $71 / $72 /
--   SPECIAL_TILE_32 -> its flag, SFX_10B, sub_080971E0 by type (0: tile 0,
--   1: a small chest tile ($73) where an unopened chest is listed, 2 / 3: a
--   HITTABLE_LEVER type 0 / 1 with its hit flag); else it sits there (tile
--   54 again).  Any other tile under it than $78 / $7A / 54-58 (it was
--   pushed off the pillars): FX_ROCK and it is gone.  R grabs it (carry
--   flag 1) and pulling moves it toward Link the same way.  With its flag
--   set at Init it goes straight to sub_080971E0 at the spot stored in its
--   data (+$7C..+$7F).
-- MINISH_PORTAL_STONE $74 (src/object/minishPortalStone.c): flag $FFFF or
--   set -> drawn and its portal tiles (SPECIAL_TILE_64..72, gUnk_08123344 /
--   gUnk_0812336A for a tile-aligned x) put down (action 4).  Else hidden
--   until the flag: Link held (CONTROL_1) while it fades in (alpha step every
--   8 frames, sparkles), SFX_14A, then SFX_SECRET, the tiles, global flag
--   TINY_ENTRANCE.  Until then the room's MINISH_PORTAL_MANAGER there has
--   no portal tiles: Link cannot use it (Objects.portalNear asks here).
-- SIMPLIFIED: FX_DASH / FX_ROCK / FX_LAVA_SPLASH_HUGE are the port's
--   addFx; the stone's alpha blend is a fade of its sprite; sub_0800442E
--   (an entity over a pit) is not modelled for the pillar object.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local O = {}
O.LAVA_PLATFORM, O.OBJECT_ON_PILLAR, O.MINISH_PORTAL_STONE = 0x59, 0x6D, 0x74
local SFX_LAVA_TILE_FLIP, SFX_LAVA_TILE_STEP, SFX_LAVA_TILE_WOBBLE, SFX_LAVA_TILE_SINK = 0x17E, 0x17B, 0x17C, 0x17D
local SFX_10F, SFX_10B, SFX_14A, SFX_SECRET = 0x10F, 0x10B, 0x14A, 0x72
local SPECIAL_FX, FX_LAVA_SPLASH_HUGE, FX_ROCK, FX_DASH = 0x0F, 0x36, 0x04, 0x11
local SP54, SP55, SP32 = 0x4036, 0x4037, 0x4020
local TINY_ENTRANCE = 0x63
local VEC = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local PILLAR_FRAME = { [0] = 0, 2, 4, 3, 7, 5, 0, 0 } -- gUnk_08123264
O.PILLAR_FRAME = PILLAR_FRAME

local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
  e.flagKey = nil
end
-- the frame byte's flags of the current keyframe; `take` clears them (the
-- cartridge writes super->frame back) until the next keyframe
local function fflags(e)
  if not e.anim then return 0 end
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim and e.anim.key end
local function sfx(d, id) d.field:sound(id) end
local function dress(d, e, id, form)
  local def = d.field:objects():def(id, form or 0)
  if def then d.field:objects():dress(e, def, 0) end
  return def
end

-- ---------------------------------------------------------------------------
-- room property data (the entity region) and rails
-- ---------------------------------------------------------------------------
local function region(f)
  local A = f.assets
  local reg = A.manifest.entityRegion
  if not reg then return nil end
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  return A.entityBlob, reg.base
end
local function rdU8(f, a) local b, base = region(f) if not b then return nil end return b:byte(a - base + 1) end
local function rdU16(f, a) local lo, hi = rdU8(f, a), rdU8(f, a + 1) if not lo or not hi then return nil end return lo + 256 * hi end
local function rdU32(f, a) local lo, hi = rdU16(f, a), rdU16(f, a + 2) if not lo or not hi then return nil end return lo + 65536 * hi end
local function s16(v) if v and v >= 0x8000 then return v - 0x10000 end return v end
O._rd = { u8 = rdU8, u16 = rdU16, u32 = rdU32 }

-- LavaPlatformEntry list at room property k
function O.platformEntries(f, k)
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return {} end
  local out = {}
  for i = 0, 31 do
    local q = addr + 16 * i
    local t2 = rdU8(f, q + 9)
    if not t2 or t2 == 0xFF then break end
    out[#out + 1] = { rail = rdU32(f, q), x = s16(rdU16(f, q + 4)), y = s16(rdU16(f, q + 6)), layer = rdU8(f, q + 8),
                      type2 = t2, wobble = rdU16(f, q + 10), respawn = rdU16(f, q + 12) }
  end
  return out
end

-- UpdateRailMovement: {direction, frames, speed} u16 triplets, $FE jumps
-- back ptr[1] triplets, $FF stops; a null pointer changes nothing
function O.railNext(f, e)
  local p = e.railPtr
  if not p or p == 0 then return end
  local v = rdU16(f, p)
  if v == 0xFE then p = p - 6 * (rdU16(f, p + 2) or 0); v = rdU16(f, p) end
  if v == nil then e.railPtr = nil return end
  if v == 0xFF then e.direction, e.speed = 0xFF, 0
  else e.direction, e.speed = band(v, 0xFF), rdU16(f, p + 4) or 0 end
  e.u76 = rdU16(f, p + 2) or 0
  e.railPtr = p + 6
end

-- LinearMoveUpdate (8.8 speed, 32 directions)
local function linear(e)
  local dir = e.direction or 0xFF
  if band(dir, 0x80) ~= 0 or (e.speed or 0) == 0 then return 0, 0 end
  local a = (dir % 32) / 32 * 2 * math.pi
  local dx, dy = math.sin(a) * e.speed / 256, -math.cos(a) * e.speed / 256
  e.x, e.y = e.x + dx, e.y + dy
  return dx, dy
end

-- ---------------------------------------------------------------------------
-- LAVA_PLATFORM
-- ---------------------------------------------------------------------------
function O.linkOffset(f, v) f.player.spriteOY, f.player.spriteOYFrame = v, f.frame end -- gPlayerState.spriteOffsetY this frame

local function playerOn(d, e) -- LavaPlatform_IsPlayerOnPlatform
  local p = d.field.player
  if p.minish or p.state == "dead" then return false end
  if math.abs(p.x - e.x) > 0x10 or math.abs(p.y - e.y) > 0x10 then return false end
  if p.state ~= "normal" and p.state ~= "shield" and p.state ~= "gust" then return false end -- PlayerCanBeMoved
  e.field14 = true
  if (p.z or 0) == 0 then e.subtimer = 1 return true end
  return false
end

local function settle(d, e) -- sub_0809264C
  if band(e.animationState, 1) ~= 0 then e.action, e.hitType = 7, 0xAC
  else e.action, e.hitType = 2, 1 end
  e.collide = true
  e.hidden = false
  e.spriteOY = -3
  anim(d, e, e.animationState)
end

local function handOver(d, e) -- sub_08092620: the spawner shows the flip
  local par = e.parent
  if par and (par.flipT or 0) == 0 then
    par.flipT = 1
    par.child = e
    par.x, par.y = e.x, e.y
    e.action, e.subAction, e.hitType = 1, 0, 0xAC
  end
end

-- the Cane's bolt (Pacci.lua: onPacciObj)
local function platformCane(f, e)
  if e.collide and (e.action == 2 or e.action == 7) then handOver(f._dungeon, e) return true end
  return false
end

local function platformUpdate(d, e)
  local f = d.field
  e.subtimer = 0
  e.field14 = nil
  local a = e.action
  if a == 1 then
    if e.animIndex ~= 3 then
      if e.subAction == 0 then
        e.subAction = 1
        e.animationState = bxor(e.animationState, 1)
        anim(d, e, e.animationState)
      end
      e.spriteOY = (e.spriteOY or 0) - 1
      if e.spriteOY == -3 then settle(d, e) end
    end
  elseif a == 2 then
    if playerOn(d, e) then
      e.action, e.collide, e.timer = 3, false, 20
      O.linkOffset(f, -3)
    end
  elseif a == 3 then
    if playerOn(d, e) then O.linkOffset(f, -3) end
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action = 4
      e.ptimer = e.wobble or 0
      e.spriteOY = 0
      anim(d, e, 2)
      sfx(d, SFX_LAVA_TILE_STEP)
    end
  elseif a == 4 then
    playerOn(d, e)
    if e.ptimer ~= 0 then e.ptimer = e.ptimer - 1 end
    if e.ptimer < 0x8D then
      e.anim:update(1)
      local fl = fflags(e)
      if band(fl, 0x80) ~= 0 then
        e.action = 5
        e.ptimer = e.respawn or 0
        e.hidden = true
      elseif band(fl, 1) ~= 0 then take(e); sfx(d, SFX_LAVA_TILE_WOBBLE)
      elseif band(fl, 2) ~= 0 then take(e); sfx(d, SFX_LAVA_TILE_SINK) end
    end
  elseif a == 5 then
    e.ptimer = e.ptimer - 1
    if e.ptimer <= 0 then
      e.action = 6
      e.animationState = e.type2
      e.hidden = false
      e.spriteOY = 0
      anim(d, e, e.animationState + 4)
      if e.animationState == 0 then playerOn(d, e) end
    end
  elseif a == 6 then
    local on = e.animationState == 0 and playerOn(d, e) or false
    e.anim:update(1)
    local fl = fflags(e)
    if band(fl, 1) ~= 0 then take(e); e.collide = true; e.hitType = 0xAC
    elseif band(fl, 0x80) ~= 0 then
      settle(d, e)
      if on then O.linkOffset(f, -3) end
    end
  end
  -- sub_080926E4: SyncPlayerToPlatform, the spawner follows, the rail
  local ox, oy = e.x, e.y
  linear(e)
  local dx, dy = math.floor(e.x) - math.floor(ox), math.floor(e.y) - math.floor(oy)
  if (dx ~= 0 or dy ~= 0) and e.subtimer ~= 0 then f.player:moveBy(dx, dy) end
  if e.action == 1 and e.parent then e.parent.x, e.parent.y = e.x, e.y end
  e.u76 = (e.u76 or 0) - 1
  if e.u76 == 0 then O.railNext(f, e) end
end

local function spawnerUpdate(d, e)
  local f = d.field
  if e.action == 1 then
    if (e.flipT or 0) ~= 0 and e.child then
      e.action = 2
      e.czv = 2.75
      e.cz = 0
      e.hidden = false
      e.layer = e.child.layer
      anim(d, e, e.child.animationState)
      sfx(d, SFX_LAVA_TILE_FLIP)
      anim(d, e.child, 3)
    end
  elseif e.action == 2 then
    -- GravityUpdate(Q_8_8(36)): z up by zVelocity, zVelocity down 36/256
    e.cz = e.cz + e.czv
    e.czv = e.czv - 36 / 256
    if e.cz <= 0 then
      e.cz, e.czv = 0, 0
      e.action = 1
      e.hidden = true
      e.flipT = 0
      e.child.spriteOY = 0
      anim(d, e.child, e.child.animationState)
      f:addFx(e.x, e.y, SPECIAL_FX, FX_LAVA_SPLASH_HUGE)
    elseif e.czv < 1.5 and band(fflags(e), 0x80) == 0 then
      e.anim:update(1)
    end
    e.z = e.cz
  end
end

function O.spawnPlatformSpawner(d, e)
  local f = d.field
  if not dress(d, e, O.LAVA_PLATFORM, 0) then return false end
  e.hidden = true
  e.action = 1
  e.flipT = 0
  e.spritePriority = 7
  e.lavaSpawner = true
  e.extUpdate = function(dd, me) spawnerUpdate(dd, me) end
  d:track(e)
  -- LavaPlatform_SpawnPlatforms
  for _, en in ipairs(O.platformEntries(f, e.type2 or 0)) do
    local pl = { kind = 6, id = O.LAVA_PLATFORM, form = 1, type2 = en.type2, x = en.x, y = en.y, z = 0,
                 animationState = en.type2, field80 = 0, field82 = 0, interactType = 0, dungeon = true,
                 layer = en.layer == 2 and 2 or 1, direction = 0xFF, speed = 0, parent = e,
                 wobble = en.wobble, respawn = en.respawn, railPtr = en.rail, u76 = 0 }
    dress(d, pl, O.LAVA_PLATFORM, 1)
    pl.spritePriority = 7
    pl.lavaPlatform = true
    pl.hitbox = { x = 0, y = 0, w = 8, h = 8 }
    pl.onPacciObj = platformCane
    settle(d, pl)
    O.railNext(f, pl)
    pl.extUpdate = function(dd, me) platformUpdate(dd, me) end
    f.entities[#f.entities + 1] = pl
    d:track(pl)
  end
  return e
end

-- Link carried by a platform (field_0x14): the lava under him does not count
function O.supports(f, x, y)
  for _, e in ipairs(f.entities) do
    if e.lavaPlatform and not e.deleted and e.field14 then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- OBJECT_ON_PILLAR
-- ---------------------------------------------------------------------------
local function mapName(layer) return layer == 2 and "top" or "bottom" end
local function tileAt(f, layer, tx, ty) return f.room:tileType(layer, tx, ty) end
local function actAtE(f, e)
  local tt = f.room:tileType(e.layer, math.floor(e.x / 16), math.floor(e.y / 16))
  if not tt or tt >= 0x4000 then return tt end
  return f.assets.actTile and f.assets.actTile[tt]
end

local function pillarPlace(d, e) -- sub_080970F4
  local r = d.field.room
  e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.tileIndex = r.maps[mapName(e.layer)][e.ty * r.tw + e.tx]
  r:setTile(e.layer, e.tx, e.ty, SP54)
end

local function pillarStart(d, e) -- sub_08097098
  local f = d.field
  e.u76 = 0x20
  sfx(d, SFX_10F)
  if e.tileIndex then f.room:setTile(e.layer, e.tx, e.ty, e.tileIndex) end
  local v = VEC[rshift(e.direction, 3)]
  local tt = tileAt(f, e.layer, e.tx + v[1], e.ty + v[2])
  if tt == 0x79 or tt == 0x77 then e.spriteOY = 2 end
end

local function pillarConvert(d, e) -- sub_080971E0
  local f = d.field
  f:addFx(e.x - 8, e.y + 2, SPECIAL_FX, FX_DASH)
  f:addFx(e.x + 8, e.y + 2, SPECIAL_FX, FX_DASH)
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local t = e.form or 0
  if t == 1 then
    -- sub_08097348: a listed small chest at this tile -> its flag; none: FALSE
    local opened = false
    for _, te in ipairs(f.room.tileEntities or {}) do
      if te.type == 2 and te.pos == tx + ty * 64 then opened = f:flag("local", te.flag) break end
    end
    if not opened then f:objects():setTileType(e.layer, tx, ty, 0x73) end
  elseif t == 2 or t == 3 then
    local lv = { kind = 6, id = 0x2F, form = t - 2, x = tx * 16 + 8, y = ty * 16 + 8, z = 0, layer = e.layer,
                 flag = e.flags, animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true }
    -- the lever's EntityData flag field is +$86: hitFlag (+$84 of this one) is copied there
    local le = require("src.zelda.tmc.CoFRails").spawnLever(d, lv)
    if le then f.entities[#f.entities + 1] = le end
  else
    f.room:setTile(e.layer, tx, ty, 0)
  end
  e.deleted = true
end

local PILLAR_KIND = { [0x4037] = 1, [0x4038] = 1, [0x4039] = 1, [0x403A] = 1, [0x7A] = 2, [0x78] = 2 } -- gUnk_0812327C
local function pillarSees(d, e) -- sub_08097008
  local f = d.field
  local tt = tileAt(f, e.layer, e.tx, e.ty)
  if tt == SP54 then return false end
  local k = PILLAR_KIND[tt]
  if k == 1 then
    e.direction = band(tt - 0x37, 3) * 8
    pillarStart(d, e)
    return true
  elseif k == 2 then
    e.tileIndex = select(2, f.room:tileType(e.layer, e.tx, e.ty))
  else
    f:addFx(e.x, e.y, SPECIAL_FX, FX_ROCK)
    e.deleted = true
  end
  return false
end

local function pillarDrops(d, e) -- sub_08097194
  local f = d.field
  local tt = f.room:tileType(e.layer, math.floor(e.x / 16), math.floor(e.y / 16))
  if tt == 0x71 or tt == 0x72 or tt == SP32 then
    d:set(e.flag)
    sfx(d, SFX_10B)
    pillarConvert(d, e)
    return true
  end
  return false
end

local function pillarMove(d, e) -- sub_08097144
  local f = d.field
  linear(e)
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = 0, y = 0, w = 6, h = 6 })
  if actAtE(f, e) == 0x19 then e.spriteOY = 2 end -- ACT_TILE_25
  e.u76 = e.u76 - 1
  if e.u76 == 0 and not pillarDrops(d, e) then
    e.x, e.y = math.floor(e.x / 16) * 16 + 8, math.floor(e.y / 16) * 16 + 8
    e.spriteOY = 4
    pillarPlace(d, e)
    return true
  end
  return false
end

local function pillarUpdate(d, e, input)
  if e.deleted then return end
  if e.action == 1 then
    if e.moving and e.moving > 0 then -- grabbed and pulled (StatuePull's hold)
      local p = d.field.player
      e.direction = bxor(p.animationState, 4) * 4
      e.action = 3
      pillarStart(d, e)
      return
    end
    if not pillarDrops(d, e) then
      if pillarSees(d, e) then e.action = 3
      else
        -- RegisterCarryEntity: R grabs it, pulling slides it (StatuePull.lua)
        require("src.zelda.tmc.StatuePull").update(d, e, input)
      end
    end
  elseif e.action == 3 then
    if e.moving and e.moving > 0 then e.moving = e.moving - 1 end
    if pillarMove(d, e) then e.action = 1; e.moving = nil end
  end
end

function O.spawnPillar(d, e)
  local f = d.field
  local raw = e.data and e.data.paramB or 0
  local b7c, b7d, b7e, b7f = band(raw, 0xFF), band(rshift(raw, 8), 0xFF), band(rshift(raw, 16), 0xFF), band(rshift(raw, 24), 0xFF)
  dress(d, e, O.OBJECT_ON_PILLAR, e.form or 0)
  e.pillarObj = true
  e.extUpdate = function(dd, me, input) pillarUpdate(dd, me, input) end
  if not d:check(e.flag) then
    e.action = 1
    e.speed = 0x80
    e.spritePriority = 4
    e.spriteOY = 4
    e.layer = rshift(b7d, 4) == 2 and 2 or 1
    pillarPlace(d, e)
    e.staticFrame = PILLAR_FRAME[e.form or 0] or 0
    d:track(e)
    return e
  end
  e.x = bor(b7c, band(b7d, 0xF) * 256)
  e.y = bor(b7e, band(b7f, 0xF) * 256)
  e.layer = rshift(b7f, 4) == 2 and 2 or 1
  pillarConvert(d, e)
  return nil
end

-- Link's push against SPECIAL_TILE_54 (UpdatePlayerCollision): the push
-- of PLAYER_PUSH type 0 -- $20 frames at kPushSpeed
local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
local function pushUpdate(p)
  local ps = p.pillarPush
  p.anim:update(1)
  ps.left = ps.left - 1
  local v = DV[p.animationState] or DV[4]
  p:moveBy(v[1] * 0.5, v[2] * 0.5)
  if ps.left <= 0 then p.pillarPush = nil; p.extUpdate = nil; p.state = "normal" end
end
function O.tryPush(p)
  local f = p.field
  if p.minish or p.state ~= "normal" or not p.probe then return false end
  local v = DV[p.animationState]
  if not v then return false end
  local fx, fy = p:probe()
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local layer = p.layer or 1
  if f.room:tileType(layer, tx, ty) ~= SP54 then return false end
  if not require("src.zelda.tmc.PushableRock").beyondFree(f, layer, tx + v[1], ty + v[2]) then return false end
  f.room:setTile(layer, tx, ty, SP55 + p.animationState / 2)
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  p.pillarPush = { left = 0x20 }
  p.extUpdate = pushUpdate
  return true
end

-- ---------------------------------------------------------------------------
-- MINISH_PORTAL_STONE
-- ---------------------------------------------------------------------------
local PORTAL_TILES = { 0x4040, -65, 0x4041, -64, 0x4042, -63, 0x4043, -1, 0x4044, 0, 0x4045, 1, 0x4046, 63, 0x4047, 64, 0x4048, 65 } -- gUnk_08123344
local PORTAL_TILES_ALIGNED = { 0x4041, -65, 0x4041, -64, 0x4044, -1, 0x4044, 0, 0x4047, 63, 0x4047, 64 } -- gUnk_0812336A
O.PORTAL_TILES, O.PORTAL_TILES_ALIGNED = PORTAL_TILES, PORTAL_TILES_ALIGNED
local function stoneTiles(d, e) -- sub_08097CFC
  local r = d.field.room
  local list = band(math.floor(e.x), 0xF) == 0 and PORTAL_TILES_ALIGNED or PORTAL_TILES
  local pos = math.floor(e.x / 16) + math.floor(e.y / 16) * 64
  for i = 1, #list, 2 do
    local q = pos + list[i + 1]
    local tx, ty = q % 64, math.floor(q / 64)
    if tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then r:setTile(e.layer, tx, ty, list[i]) end
  end
  e.portalOpen = true
end

local function stoneUpdate(d, e)
  local f = d.field
  local p = f.player
  if e.action == 1 then
    if d:check(e.flag) then
      p.state, p.extUpdate = "ext", function() end -- SetPlayerControl(CONTROL_1)
      e.action = 3
      e.hidden = false
      e.alpha = 0
      e.timer, e.subtimer = 30, 0
      sfx(d, SFX_14A)
    end
  elseif e.action == 3 then
    if math.random(0, 7) == 0 then f:addFx(e.x + math.random(-15, 15), e.y + math.random(-15, 4), SPECIAL_FX, 0x26) end -- CreateMagicSparklesFxAt (FX_SPARKLE4)
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = 8
      e.subtimer = e.subtimer + 1
      e.alpha = e.subtimer / 16
      if e.subtimer >= 16 then
        p.state, p.extUpdate, p.animId = "normal", nil, -1
        stoneTiles(d, e)
        e.action = 4
        e.alpha = nil
        sfx(d, SFX_SECRET)
        f:setFlag("global", TINY_ENTRANCE, true)
      end
    end
  end
end

function O.spawnStone(d, e)
  dress(d, e, O.MINISH_PORTAL_STONE, e.form or 0)
  e.spritePriority = 7
  e.portalStone = true
  e.action = 1
  if e.flag == 0xFFFF or d:check(e.flag) then
    e.hidden = false
    e.action = 4
    stoneTiles(d, e)
  else
    e.hidden = true
  end
  e.extUpdate = function(dd, me) stoneUpdate(dd, me) end
  d:track(e)
  return e
end

-- a portal whose stone has not appeared yet has no portal tiles
function O.portalBlocked(f, portal)
  for _, e in ipairs(f.entities) do
    if e.portalStone and not e.deleted and not e.portalOpen and math.abs(e.x - portal.x) <= 16 and math.abs(e.y - portal.y) <= 16 then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- hooks (installed once, the first time a Cave of Flames room loads one)
-- ---------------------------------------------------------------------------
function O.install()
  if O._installed then return end
  O._installed = true
  local Dungeon = require("src.zelda.tmc.Dungeon")
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    local f = self.field
    if O.supports(f) then return end -- field_0x14: on a lava platform
    return checkFall(self, ...)
  end
  local Objects = require("src.zelda.tmc.Objects")
  local portalNear = Objects.portalNear
  Objects.portalNear = function(self, pl)
    local p = portalNear(self, pl)
    if p and O.portalBlocked(self.field, p) then return nil end
    return p
  end
  local PR = require("src.zelda.tmc.PushableRock")
  local tryPush = PR.tryPush
  PR.tryPush = function(p) return tryPush(p) or O.tryPush(p) end
end

-- the object chain (Dungeon:spawnObject)
function O.spawn(d, e)
  if e.id == O.LAVA_PLATFORM then O.install(); if (e.form or 0) == 0 then return O.spawnPlatformSpawner(d, e) end return false end
  if e.id == O.OBJECT_ON_PILLAR then O.install(); return O.spawnPillar(d, e) end
  if e.id == O.MINISH_PORTAL_STONE then O.install(); return O.spawnStone(d, e) end
  return nil
end

return O
