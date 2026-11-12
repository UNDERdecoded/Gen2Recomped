-- Round 18: bombs and what they blow open.
--
-- ItemBomb (item/itemBomb.c sub_08075FF8): not jumping or attacking, fewer
--   than 3 PLAYER_ITEM_BOMBs out (1 for remote bombs), a bomb at Link +
--   gUnk_0811BDAC[animationState & 6] (N (0,-8), E (4,-1), S (0,2),
--   W (-4,-1)), ModBombs(-1), SFX_PLACE_OBJ.  (No bombs left: the item does
--   nothing, itemUtils.c.)
-- PlayerItemBomb (playerItem/playerItemBomb.c): gPlayerItemDefinitions[2]
--   = palette 1, sprite 166, common OBJ tiles 192, hurtType $16, hitType
--   $A9; animation 5; timer 150 (counted while unk_68 == 7, the bombs'
--   behaviour id), then subtimer 80: sub_0801B3A4 blinks it (palette 0 on
--   (subtimer & 8), from 40 on (subtimer & 4) and the affine pulse
--   0x130 - (unk_68 & $F0)); at the end: action 3 (15 frames, not drawn),
--   SMOKE_PARTICLE and sub_0801B418: DoTileInteraction(3) on the 3 x 3
--   tiles around it.
-- SMOKE_PARTICLE ($20, object/smokeParticle.c): ResolveCollisionLayer,
--   hitType $A9, hurtType $16, animation 1, SFX_ITEM_BOMB_EXPLODE;
--   sub_080878CC on the 3 x 3 tiles: ACT_TILE_46 (a bombable wall) ->
--   tile types $367 / $368 interact, others become SPECIAL_TILE_34; other
--   tiles DoTileInteraction(3).  Its hitbox follows the animation's frame
--   byte (< 5: gUnk_08120A54[frame] = 6, 6, 16, 12, 12 px), then off.
-- BOMBABLE_WALL tile entities (room.c LoadBombableWallTile) start a
--   BombableWallManager (manager/bombableWallManager.c): the wall's type
--   from its tile type, destroyed at once when its local flag is set; while
--   the tile's act stays ACT_TILE_46 it waits; then DestroyWall0..4 lays
--   the opening (tile types per side), SetLocalFlag, 90 frames, SFX_SECRET.
-- DESTRUCTIBLE_TILE tile entities (room.c LoadDestructibleTile): flag set
--   -> the stored tile type; else DestructibleTileObserveManager sets the
--   flag once the tile has that type.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift
local Anim = require("src.zelda.tmc.Anim")

local B = {}

B.ITEM_BOMBS, B.ITEM_REMOTE, B.ITEM_BOMBBAG = 0x07, 0x08, 0x65
local OFFS = { [0] = { 0, -8 }, [2] = { 4, -1 }, [4] = { 0, 2 }, [6] = { -4, -1 } } -- gUnk_0811BDAC
local SPRITE, GFX, PAL = 166, 192, 1
local HURT_TYPE, HIT_TYPE = 0x16, 0xA9
local OBJ_SMOKE, OBJ_ARCHWAY = 0x20, 0x4F
local ACT_46 = 0x2E
local SP34 = 0x4000 + 34
local SFX_PLACE, SFX_EXPLODE, SFX_SECRET = 0x104, 0xFD, 0x72
local SMOKE_BOX = { [0] = 6, 6, 16, 12, 12 } -- gUnk_08120A54
local BAG_SIZES = { [0] = 10, 30, 50, 99 }  -- gBombBagSizes

function B.bagSize(f) return BAG_SIZES[f.save.stats.bombBagType or 0] or 10 end

-- ModBombs
function B.mod(f, n)
  local st = f.save.stats
  local c = (st.bombCount or 0) + n
  local size = B.bagSize(f)
  if c < 0 then c = 0 elseif c > size then c = size end
  st.bombCount = c
  st.bombMax = size
end

-- GiveItem (itemUtils.c) case 8 (ITEM_BOMBBAG): the first bag puts
-- ITEM_BOMBS on a button, a later one grows the bag; ModBombs(99)
function B.giveBag(f)
  local st = f.save.stats
  if (f.save.items[B.ITEM_BOMBBAG] or 0) == 0 then
    f.save.items[B.ITEM_BOMBBAG] = 1
    f.save.items[B.ITEM_BOMBS] = 1
    require("src.zelda.tmc.Ceremony").putItemOnSlot(f, B.ITEM_BOMBS)
  else
    st.bombBagType = math.min(3, (st.bombBagType or 0) + 1)
  end
  B.mod(f, 99)
end

-- DoTileInteraction(filter) with the entry's object (as Objects:cut)
local function interact(f, filter, x, y, layer)
  local O = f:objects()
  local entry, cx, cy = O:tileInteraction(filter, x, y, layer)
  if not entry then return false end
  local OBJ = require("src.zelda.tmc.Objects").OBJ
  local Drops = require("src.zelda.tmc.Drops")
  if entry.obj == OBJ.SPECIAL_FX then
    local t = Drops.fxVariant(f, entry.objType)
    f:addFx(cx, cy, entry.obj, t)
    Drops.fxDrop(f, { x = cx, y = cy }, t, O)
  elseif entry.obj == OBJ.GROUND_ITEM then
    O:groundItem(entry.objType, 0, cx, cy, { drop = true })
  elseif entry.obj ~= 0xFF then
    f:addFx(cx, cy, entry.obj, entry.objType)
  end
  return true
end
B.interact = interact

local function actAt(f, tx, ty, layer)
  local tt = f.room:tileType(layer, tx, ty)
  if not tt or tt >= 0x4000 then return nil, tt end
  return f.assets.actTile[tt], tt
end

-- ---------------------------------------------------------------------------
-- the item
-- ---------------------------------------------------------------------------
function B.count(f)
  local n = 0
  for _, e in ipairs(f.entities) do if e.bomb and not e.deleted and e.action ~= 3 then n = n + 1 end end
  return n
end

function B.use(p, item)
  if item ~= B.ITEM_BOMBS then return false end
  local f = p.field
  if p.minish or p.state ~= "normal" or (p.z or 0) > 0 then return false end
  if (f.save.stats.bombCount or 0) <= 0 then return false end
  if B.count(f) >= 3 then return true end
  local o = OFFS[band(p.animationState or 4, 6)] or OFFS[4]
  B.spawn(f, p.x + o[1], p.y + o[2], p.layer)
  B.mod(f, -1)
  f:sound(SFX_PLACE)
  return true
end

function B.spawn(f, x, y, layer)
  local A = f.assets
  local b = { kind = 8, id = 2, bomb = true, x = x, y = y, z = 0, layer = layer or 1, action = 1,
              timer = 150, subtimer = 0, unk68 = 7, sprite = SPRITE, gfx = { vram = GFX },
              palette = A:objPalette(PAL), flashPal = A:objPalette(0), anim = Anim.new(),
              field82 = 0, interactType = 0, literalAnim = true, objAnim = 5, animIndex = 5, scale = 1 }
  b.anim:set(A:sprite(SPRITE), 5, true)
  b.drawGhost = function(me, field, camX, camY) B.drawBomb(field, me, camX, camY) end
  b.extUpdate = function(_, me) B.updateBomb(f, me) end
  f.entities[#f.entities + 1] = b
  f._dungeon:track(b)
  return b
end

-- round 20: lifting and throwing a placed bomb (PlayerItemBomb_Action1's
-- RegisterCarryEntity; the carry's subactions: 0 lifted, 1 held over Link's
-- head, 2 thrown, 3 landed -> back to action 1 with timer <= 60).  It keeps
-- ticking while held; going off in Link's hands clears heldObject.
-- (round 21: the throw is PlayerItemHeldObject's: speed $400, zVelocity 0,
-- gravity 32 (Q8.8), one bounce at half speed.)  SIMPLIFIED: a wall stops it
-- where it is (ProcessMovement10 / ACT_TILE_116 not ported); remote bombs are
-- not ported.
local SFX_LIFT = 0x7E
function B.tryLift(f, p)
  if p.minish or p.state ~= "normal" or p.carried or (p.z or 0) > 0 then return false end
  local fx, fy = p:frontPoint(8)
  for _, b in ipairs(f.entities) do
    if b.bomb and not b.deleted and b.action == 1 and math.abs(b.x - fx) < 10 and math.abs(b.y - fy) < 10 then
      b.action, b.carrySub = 2, 1
      p.carried = { bomb = b }
      p.state = "carry"
      p:setAnim(p.hasCap and 0x338 or 0x928, true) -- ANIM_PICKUP / _NOCAP
      f:sound(SFX_LIFT)
      return true
    end
  end
  return false
end

function B.throw(f, p)
  local c = p.carried
  p.carried = nil
  local b = c and c.bomb
  if not b or b.deleted or b.action == 3 then return end
  local s = p.animationState
  -- round 21: sub_080AD27C (playerItemHeldObject.c): a bomb's carryFlags 0 ->
  -- speed gUnk_081320CC[0] = $400, zVelocity gUnk_081320D4[0] = 0, z 8 px
  -- lower than carried; SFX_PLY_VO5
  b.vx = (s == 2 and 1 or s == 6 and -1 or 0) * 4
  b.vy = (s == 4 and 1 or s == 0 and -1 or 0) * 4
  b.z, b.zv, b.carrySub, b.bounced = 14 - 8, 0, 2, nil
  f:sound(0x79)
end

function B.drop(f, p)
  local c = p.carried
  p.carried = nil
  local b = c and c.bomb
  if not b or b.deleted or b.action == 3 then return end
  b.x, b.y, b.z = p.x, p.y, 0
  b.action, b.carrySub = 1, nil
  if b.timer > 60 then b.timer = 60 end
end

B.FX_GREEN_SPLASH = 0x52
-- round 22: IsTileCollision(.., collisionType 10) at (x, y)
local T10_NONE = { [0x20] = true, [0x21] = true, [0x22] = true, [0x25] = true, [0x28] = true, [0x2A] = true,
                   [0x2C] = true, [0x2D] = true, [0x2E] = true, [0x2F] = true, [0x30] = true, [0x31] = true }
local T10_CORNER = { [0x19] = { 0, 0 }, [0x1A] = { 1, 0 }, [0x1B] = { 0, 1 }, [0x1C] = { 1, 1 } } -- NW NE SW SE
function B.type10Solid(f, x, y, layer)
  local r = f.room
  if not (r.coll and r.tw) then return r:isSolid(x, y, layer) end
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return true end
  local v = r.coll[(layer == 2) and 2 or 1][ty * r.tw + tx] or 0xFF
  if v == 0 then return false end
  if v < 0x0F then
    -- collisionLookup[20] = $FF: the tile's quarter bits
    local t = v
    if band(math.floor(y), 8) == 0 then t = rshift(t, 2) end
    if band(math.floor(x), 8) == 0 then t = rshift(t, 1) end
    return band(t, 1) == 1
  end
  if v == 0x0F or v == 0xFF or v > 0x6F then return true end
  if T10_NONE[v] or (v >= 0x33 and v <= 0x3F) or (v >= 0x50 and v <= 0x5F) then return false end
  local c = T10_CORNER[v]
  if c then
    local qx, qy = band(math.floor(x), 8) ~= 0 and 1 or 0, band(math.floor(y), 8) ~= 0 and 1 or 0
    return qx == c[1] and qy == c[2]
  end
  return true
end

local function carryFrame(f, b)
  local p = f.player
  if b.carrySub == 1 then
    if p.carried and p.carried.bomb == b then
      b.x, b.y, b.z = p.x, p.y + 1, 14
    else
      b.action, b.carrySub, b.z = 1, nil, 0
    end
  elseif b.carrySub == 2 then
    local nx, ny = b.x + b.vx, b.y + b.vy
    -- round 22: ProcessMovement10 = IsTileCollision(collisionType 10): pits
    -- ($20-$22), water and low collision codes do not stop a thrown bomb
    if B.type10Solid(f, nx, ny, b.layer or 1) then b.vx, b.vy = 0, 0 else b.x, b.y = nx, ny end
    -- round 21: PlayerItemHeldObject_SubAction2: GravityUpdate(Q_8_8(32)) =
    -- 0.125 a frame; the first landing bounces (zVelocity 1.0, speed / 2,
    -- SFX_PLACE_OBJ), the second ends the throw
    b.z = b.z + b.zv
    b.zv = b.zv - 0.125
    -- round 22: landing on ACT_TILE_13 / 16 / 17 / 19 / 90 the bomb is gone
    -- (FX_FALL_DOWN / FX_WATER_SPLASH / FX_GREEN_SPLASH / FX_LAVA_SPLASH)
    local FALLS = { [0x0D] = 0x00, [0x10] = 0x0B, [0x11] = 0x0B, [0x13] = B.FX_GREEN_SPLASH, [0x5A] = 0x0C }
    local landAct = b.z + b.zv <= 0 and f.room.tileType and actAt(f, math.floor(b.x / 16), math.floor(b.y / 16), b.layer or 1)
    if landAct and FALLS[landAct] then
      f:addFx(b.x, b.y, 0x0F, FALLS[landAct])
      local p = f.player
      if p and p.carried and p.carried.bomb == b then p.carried = nil end
      b.deleted = true
      return
    end
    if b.z <= 0 and not b.bounced then
      b.z, b.zv, b.bounced = 0, 1.0, true
      b.vx, b.vy = b.vx / 2, b.vy / 2
      f:sound(0x104)
    elseif b.z <= 0 then
      b.z = 0
      -- PlayerItemBomb_SubAction3
      b.action, b.carrySub = 1, nil
      if b.timer > 60 then b.timer = 60 end
    end
  end
end

function B.updateBomb(f, b)
  if b.action == 3 then
    b.timer = b.timer - 1
    if b.timer < 0 then b.deleted = true end
    return
  end
  if b.action == 2 then carryFrame(f, b) end -- round 20
  b.anim:update(1)
  if b.timer ~= 0 then
    if b.unk68 == 7 then b.timer = b.timer - 1 end
    if b.timer == 0 then
      b.subtimer = 80
      b.unk68 = 0
      b.scale = 1
    end
  elseif b.subtimer ~= 0 then
    local s = b.subtimer
    b.subtimer = s - 1
    if s == 1 then
      local p = f.player
      if p and p.carried and p.carried.bomb == b then p.carried = nil; if p.state == "carry" then p.state = "normal" end end -- round 20: gPlayerState.heldObject = 0
      b.z = 0
      B.explode(f, b)
    else
      -- sub_0801B3A4
      local tmp
      if b.subtimer > 40 then tmp = 8
      else
        tmp = 4
        if band(b.unk68, 0x8000) ~= 0 then b.unk68 = b.unk68 - 0x10 else b.unk68 = b.unk68 + 0x10 end
        if (band(b.unk68, 0xF0) - 1) % 0x100000000 > 0x7F then b.unk68 = bxor(b.unk68, 0x8000) end
        b.scale = 0x100 / (0x130 - band(b.unk68, 0xF0))
      end
      b.flash = band(b.subtimer, tmp) == 0
    end
  end
end

function B.drawBomb(f, b, camX, camY)
  if b.action == 3 or b.hidden then return end
  local frame = b.anim.frame
  if not frame or frame == 0xFF then return end
  local pal = b.flash and b.flashPal or b.palette
  local img, ox, oy = f.assets:spriteFrame(SPRITE, frame, pal, b.flash and "bombF" or "bomb", b.gfx)
  if not img then return end
  local s = b.scale or 1
  local x, y = math.floor(b.x - camX), math.floor(b.y - camY - (b.z or 0))
  local flip = b.anim.hflip and b.anim:hflip()
  if flip then love.graphics.draw(img, x - ox * s, y + oy * s, 0, -s, s)
  else love.graphics.draw(img, x + ox * s, y + oy * s, 0, s, s) end
end

function B.explode(f, b)
  b.action = 3
  b.timer = 15
  b.flash = false
  -- sub_0801B418: the 3 x 3 tiles, filter 3
  for _, dy in ipairs({ 16, 0, -16 }) do
    for _, dx in ipairs({ 16, 0, -16 }) do interact(f, 3, b.x + dx, b.y + dy, b.layer) end
  end
  B.smoke(f, b.x, b.y, b.layer)
end

-- ---------------------------------------------------------------------------
-- SMOKE_PARTICLE: the blast
-- ---------------------------------------------------------------------------
function B.smoke(f, x, y, layer)
  local O = f:objects()
  local d = O:def(OBJ_SMOKE, 0)
  local e = { kind = 6, id = OBJ_SMOKE, form = 0, x = x, y = y, z = 0, layer = layer or 1, animationState = 0,
              field82 = 0, interactType = 0, anim = Anim.new(), smoke = true, hitW = SMOKE_BOX[0], hitList = {} }
  if d then O:dress(e, d, 1); e.objAnim = 1; e.fx = true else e.drawGhost = function() end end
  f.entities[#f.entities + 1] = e
  f._dungeon:track(e)
  e.extUpdate = function(_, me) B.updateSmoke(f, me) end
  f:sound(SFX_EXPLODE)
  -- sub_080878CC
  local r = f.room
  for _, ix in ipairs({ -16, 0, 16 }) do
    for _, iy in ipairs({ -16, 0, 16 }) do
      local px, py = x + ix, y + iy
      local tx, ty = math.floor(px / 16), math.floor(py / 16)
      if tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then
        local a, tt = actAt(f, tx, ty, e.layer)
        if a == ACT_46 then
          if tt == 0x367 or tt == 0x368 then interact(f, 3, px, py, e.layer)
          else r:setTile(e.layer, tx, ty, SP34) end
        else
          interact(f, 3, px, py, e.layer)
        end
      end
    end
  end
  B.blast(f, e)
  if not d then e.deleted = true end
  return e
end

-- what the blast's box touches this frame
function B.blast(f, e)
  local w = e.hitW
  if not w then return end
  local en = f:enemies()
  for _, t in ipairs(f.entities) do
    if t.mz and t.boss and not t.deleted and not e.hitList[t] then -- round 26A wiring: Mazaal's parts take the blast through BossMazaal.hit
      local hb = t.hitbox or { x = 0, y = 0, w = 6, h = 6 }
      if math.abs((t.x + (hb.x or 0)) - e.x) < w + (hb.w or 6) and math.abs((t.y + (hb.y or 0)) - e.y) < w + (hb.h or 6) then
        e.hitList[t] = true
        require("src.zelda.tmc.BossMazaal").hit(en, t, HURT_TYPE, e.x, e.y, 0)
      end
    end
    if t.enemy and not t.dying and not t.deleted and not t.boss and not t.hidden and not e.hitList[t] then
      local hb = t.hitbox or { x = 0, y = 0, w = 6, h = 6 }
      if math.abs((t.x + hb.x) - e.x) < w + hb.w and math.abs((t.y + hb.y) - e.y) < w + hb.h then
        e.hitList[t] = true
        en:hit(t, HURT_TYPE, e.x, e.y)
      end
    end
  end
  local p = f.player
  if p and not e.hitList[p] and p.state ~= "dead" and not p.tunnel then
    if math.abs(p.x - e.x) < w + 6 and math.abs((p.y - 3) - e.y) < w + 6 and (p.z or 0) < 10 then
      e.hitList[p] = true
      local HBm = require("src.zelda.tmc.Hitboxes")
      local s = en:settings(HIT_TYPE, HBm.hurtType(p))
      local dmg = s and s.tgtDmg or 4
      if dmg > 0 and p:hurt(dmg, e.x, e.y) then
        if s then
          p.invuln = math.max(s.orgIfr or 30, 30)
          p.timer = math.max(s.orgKbDur or 8, 4)
        end
      end
    end
  end
end

function B.updateSmoke(f, e)
  if e.deleted then return end
  local fl = e.anim.flags or 0
  if band(fl, 0x80) ~= 0 then e.hitW = nil return end
  if fl < 5 then e.hitW = SMOKE_BOX[fl] else e.hitW = nil end
  B.blast(f, e)
end

-- ---------------------------------------------------------------------------
-- room load: BOMBABLE_WALL / DESTRUCTIBLE_TILE tile entities
-- ---------------------------------------------------------------------------
-- BombableWallManager_GetBombableType
local WALL_TYPE = { [236] = 1, [191] = 4, [175] = 0, [204] = 2, [223] = 3, [255] = 0, [277] = 1, [264] = 2, [272] = 3, [261] = 4 }
-- DestroyWall0..4: { tiles on the wall's layer {dx, dy, type}, centre (dungeon/enemies, plain),
--   top-layer tiles, archway { dx, dy, type2 } }
local WALLS = {
  [0] = { side = { { -1, -1, 177 }, { 0, -1, 178 }, { 1, -1, 179 }, { -1, 0, 180 }, { 1, 0, 183 } }, c1 = 181, c2 = 182,
          top = { { -1, -1, 184 }, { 0, -1, 185 }, { 1, -1, 186 } }, arch = { 8, -8, 0 } },
  [1] = { side = { { 0, -1, 241 }, { 1, -1, 245 }, { 1, 0, 246 }, { 0, 1, 244 }, { 1, 1, 247 } }, c1 = 242, c2 = 243,
          top = { { 1, -1, 248 }, { 1, 0, 249 }, { 1, 1, 250 } }, arch = { 0x18, 8, 1 } },
  [2] = { side = { { -1, 0, 209 }, { 1, 0, 212 }, { -1, 1, 213 }, { 0, 1, 214 }, { 1, 1, 215 } }, c1 = 210, c2 = 211,
          top = { { -1, 1, 216 }, { 0, 1, 217 }, { 1, 1, 218 } }, arch = { 8, 0x20, 2 } },
  [3] = { side = { { -1, -1, 225 }, { 0, -1, 228 }, { -1, 0, 226 }, { -1, 1, 227 }, { 0, 1, 231 } }, c1 = 229, c2 = 230,
          top = { { -1, -1, 232 }, { -1, 0, 233 }, { -1, 1, 234 } }, arch = { -0x10, 8, 3 } },
  [4] = { side = { { -1, -1, 193 }, { 0, -1, 194 }, { 1, -1, 195 }, { -1, 0, 196 }, { 1, 0, 199 } }, c1 = 197, c2 = 198,
          top = { { -1, -1, 200 }, { 0, -1, 201 }, { 1, -1, 202 } }, arch = { 8, -0x10, 0 } },
}
B.WALLS, B.WALL_TYPE = WALLS, WALL_TYPE

local function areaFlags(f)
  local info = f.room and f.room.areaInfo
  return info and info.flags or 0
end
local function isDungeon(f) return band(rshift(areaFlags(f), 2), 1) == 1 end
local function hasEnemies(f) return band(rshift(areaFlags(f), 4), 1) == 1 end

function B.destroyWall(f, m)
  local W = WALLS[m.type]
  if not W then return end
  local O = f:objects()
  local tx, ty, layer = m.tx, m.ty, m.layer
  for _, s in ipairs(W.side) do O:setTileType(layer, tx + s[1], ty + s[2], s[3]) end
  if layer == 1 then
    if hasEnemies(f) then
      f:spawn({ kind = 6, id = OBJ_ARCHWAY, paramA = 0x0E, paramB = W.arch[3], pool = 0x0F,
                x = tx * 16 + W.arch[1], y = ty * 16 + W.arch[2], paramC = 0, collision = 1 })
      O:setTileType(1, tx, ty, W.c1)
    elseif isDungeon(f) then O:setTileType(1, tx, ty, W.c1)
    else O:setTileType(1, tx, ty, W.c2) end
    for _, s in ipairs(W.top) do O:setTileType(2, tx + s[1], ty + s[2], s[3]) end
  else
    O:setTileType(2, tx, ty, W.c1)
    -- (the dungeon archway on the top layer: getArchwayType by dungeon; not
    -- on the Crenel path)
  end
end

function B.updateWall(f, m)
  if m.action == 1 then
    local a = actAt(f, m.tx, m.ty, m.layer)
    if a ~= ACT_46 then
      m.action, m.timer = 2, 90
      B.destroyWall(f, m)
      f:setFlag("local", m.flag, true)
    end
  elseif m.action == 2 then
    m.timer = m.timer - 1
    if m.timer == 0 then f:sound(SFX_SECRET); m.deleted = true end
  end
end

-- a BOMBABLE_WALL_MANAGER placed by an entity list (RegisterRoomEntity copies
-- the EntityData to the manager's +$30: layer = type2 byte 1 (+$35),
-- x / y (+$38 / +$3A), flag = paramC high half (+$3E))
function B.addWall(f, x, y, layer, flag)
  local m = { wallMgr = true, tx = band(rshift(x, 4), 0x3F), ty = band(rshift(y, 4), 0x3F), layer = (layer == 2) and 2 or 1,
              flag = flag, action = 1, timer = 0, x = x, y = y }
  local tt = f.room:tileType(m.layer, m.tx, m.ty)
  m.type = WALL_TYPE[tt or -1] or 0xFF
  if f:flag("local", m.flag) then
    B.destroyWall(f, m)
  else
    m.extUpdate = function(_, me) B.updateWall(f, me) end
    f.bombWalls = f.bombWalls or {}
    f.bombWalls[#f.bombWalls + 1] = m
    f._dungeon:track(m)
  end
  return m
end
function B.wallManager(f, m)
  B.addWall(f, m.x, m.y, m.b1, m.c1)
  return true
end

function B.roomLoaded(f)
  f.bombWalls = {} -- a new room (its list managers append after this)
  local destructible = {}
  for _, t in ipairs(f.room.tileEntities or {}) do
    if t.type == 4 then
      -- LoadBombableWallTile: x = tilePos (a pixel x), y = _6.._7, layer _2
      B.addWall(f, t.pos, t.c + t.d * 256, t.a, t.flag)
    elseif t.type == 10 then
      -- LoadDestructibleTile: flag (u16 at _2) set -> SetTileType(_6, tilePos, layer = localFlag)
      local flag = t.a + t.b * 256
      local ttype = t.c + t.d * 256
      local tx, ty = t.pos % 64, math.floor(t.pos / 64)
      local layer = (t.flag == 2) and 2 or 1
      if f:flag("local", flag) then f:objects():setTileType(layer, tx, ty, ttype)
      else destructible[#destructible + 1] = { flag = flag, type = ttype, tx = tx, ty = ty, layer = layer } end
    end
  end
  if #destructible > 0 then
    -- DestructibleTileObserveManager
    local m = { observe = destructible }
    m.extUpdate = function()
      for _, d in ipairs(destructible) do
        if not f:flag("local", d.flag) and f.room:tileType(d.layer, d.tx, d.ty) == d.type then f:setFlag("local", d.flag, true) end
      end
    end
    f._dungeon:track(m)
  end
end

return B
