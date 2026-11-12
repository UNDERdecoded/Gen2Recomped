-- Mine carts (round 7): src/object/minecart.c and the player's minecart
-- states (PL_ENTER_MINECART / PL_IN_MINECART in player.c).
--
-- The carts' places live in gRoomTransition.minecart_data[4] {tilePos, room,
-- animationState, type2}, reset from sMinecartData ($080FCAF8, read from the
-- player's ROM: MENU_DATA `minecartData`) whenever Link enters the Cave of
-- Flames from outside (sub_0805329C). An object MINECART names its entry by
-- its timer; the cart only appears in that entry's room.
--
--   Action1  standing; Link pushing against it for more than 8 frames (not
--            Minish, not holding anything) jumps in: zVelocity 2.0, speed 1.
--            The Cane of Pacci's hit (contact $1D) hops it over (Action7:
--            zVelocity 2.625, type2 ^= 4 on landing). type2 4 = upside down,
--            it cannot be ridden.
--   Action2  Link lands in it once falling: PL_IN_MINECART, SFX_137.
--   Action3  riding at speed $700 on the frames Link's ANIM_MINECART frame
--            byte is not 0 in its low nibble; the act tile 7 px ahead must be
--            one the direction allows (gUnk_081223D8 lists) or it turns
--            back; corner tiles 103-106 turn it (Action4); ACT_TILE_100 is
--            the end: Link jumps out forward (zVelocity 2.0, speed 2), the
--            cart turns round and stays there (Action6, its data updated).
--            8 px ahead outside the room: the room changes with Link in it
--            (Action5, the cart persists).
local bit = require("bit")
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local Minecart = {}

local OBJ_MINECART = 0x55
local AREA_COF = 0x50
local DATA = 0x080FCAF8
local ANIM_MINECART, ANIM_JUMP = 0x710, 0x810

-- gUnk_081223D8: the act tiles a cart may roll onto, per animationState
local ALLOWED = {
  [0] = { [242] = true, [101] = true, [104] = true, [106] = true, [100] = true, [41] = true },
  [1] = { [243] = true, [102] = true, [104] = true, [105] = true, [100] = true, [41] = true },
  [2] = { [242] = true, [101] = true, [103] = true, [105] = true, [100] = true, [41] = true },
  [3] = { [243] = true, [102] = true, [106] = true, [103] = true, [100] = true, [41] = true },
}
local AHEAD = { [0] = { 0, -7 }, { 7, 0 }, { 0, 7 }, { -7, 0 } }   -- offsetCoords
local EDGE = { [0] = { 0, -8 }, { 8, 0 }, { 0, 8 }, { -8, 0 } }    -- gUnk_081223D0
local VEC = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local CORNER = { [103] = true, [104] = true, [105] = true, [106] = true,
                 [108] = true, [109] = true, [110] = true, [111] = true }

-- sMinecartData from the ROM
function Minecart.reset(f)
  local A = f.assets
  local e = A.manifest and A.manifest.menuData and A.manifest.menuData.minecartData
  local data = {}
  if e then
    A.menuBlob = A.menuBlob or A.store:read("menudata.bin") or ""
    local function u8(i) return A.menuBlob:byte(e[2] + i + 1) or 0 end
    for i = 0, 3 do
      local o = i * 8
      data[i] = { tilePos = u8(o) + 256 * u8(o + 1), room = u8(o + 4), animationState = u8(o + 5), type2 = u8(o + 6) }
    end
  end
  f.minecartData = data
end

local function dataFor(f, i)
  if not f.minecartData then Minecart.reset(f) end
  return f.minecartData[i]
end

local function act(f, x, y, layer)
  local d = f._dungeon
  -- round 24: a turning rail's SPECIAL_TILE_24 / 25 (gMapSpecialTileToActTile: 242 / 243)
  local t = f.room and f.room.tileType and f.room:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
  if t and t >= 0x4000 then return require("src.zelda.tmc.CoFRails").SPECIAL_ACT[t] end
  return d and d:actAt(x, y, layer) or nil
end

local function setAnim(f, e, idx)
  e.cartAnim = idx
  local spr = f.assets:sprite(e.sprite)
  e.anim:set(spr, idx, true)
end

-- the object spawns (Dungeon -> Crenel.spawnObject)
function Minecart.spawn(dungeon, e)
  local f = dungeon.field
  if f.cartRide then return nil end -- PL_IN_MINECART: the riding cart came along
  local data = dataFor(f, e.timer0 or 0)
  if not data or data.room ~= f.room.room then return nil end
  local def = f:objects():def(OBJ_MINECART, e.form or 0)
  if not def then return nil end
  f:objects():dress(e, def, 0)
  e.literalAnim = nil
  e.forceAnim = nil
  e.cart = true
  e.data = data
  e.x = band(data.tilePos, 0x3F) * 16 + 8
  e.y = rshift(band(data.tilePos, 0xFC0), 6) * 16 + 8
  e.animationState = data.animationState
  e.type2 = data.type2
  e.action = 1
  e.timer = 0
  e.solid = true
  e.z, e.zv = 0, 0
  -- the cart's collision layer: the one its rails are on
  for _, L in ipairs({ e.layer or 1, 2, 1 }) do
    local a = act(f, e.x, e.y, L) or 0
    if (a >= 100 and a <= 111) or a == 242 or a == 243 then e.layer = L break end
  end
  setAnim(f, e, e.type2 + 4 + e.animationState)
  e.extUpdate = function(_, me, input) Minecart.update(f, me, input) end
  dungeon:track(e)
  return e
end

-- the Cane of Pacci's projectile touched it ((contactFlags & $7F) == $1D)
function Minecart.pacciHit(f, e)
  if e.action ~= 1 then return false end
  e.zv = 2.625
  e.action = 7
  setAnim(f, e, e.type2 + 4 + e.animationState)
  f:sound(0x13B)
  return true
end

local function pushing(f, e, input)
  local p = f.player
  if p.state ~= "normal" or p.minish or p.carried or (p.z or 0) ~= 0 then return false end
  local dx, dy = e.x - p.x, e.y - p.y
  if math.abs(dx) > 13 or math.abs(dy) > 13 then return false end
  local s = p.animationState
  local held = (s == 0 and input.down("up") and dy < 0) or (s == 4 and input.down("down") and dy > 0)
    or (s == 2 and input.down("right") and dx > 0) or (s == 6 and input.down("left") and dx < 0)
  return held
end

-- Link's jump in / out: his own z and speed while the cart drives him
local function linkJump(f, p)
  p.zv = (p.zv or 0) - 0.125 -- kGravityRate $2000
  p.z = (p.z or 0) + p.zv
  if p.z <= 0 then p.z = 0 return false end
  return true
end

local function enterUpdate(f, e)
  local p = f.player
  -- Action2: toward the cart until within 2 px, then down into it
  local dx, dy = e.x - p.x, e.y - p.y
  if math.abs(dx) <= 2 and math.abs(dy) <= 2 then
    p.x, p.y = e.x, e.y
    if p.zv < 0 and p.z < 16 then
      p.animationState = e.animationState * 2
      p.z, p.zv = 0, 0
      p.inCart = true
      e.action = 3
      e.subtimer = 1
      e.hidden = true -- drawn under Link from now on
      p.layer = e.layer or p.layer
      f:sound(0x137)
      p:setAnim(ANIM_MINECART, true)
      return
    end
  else
    local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.x, p.y = p.x + dx / d, p.y + dy / d
  end
  linkJump(f, p)
end

local function exitCart(f, e)
  local p = f.player
  p.inCart = nil
  e.action = 6
  e.solid = true
  e.hidden = false
  p.state = "ext"
  p.zv = 2.0
  p.z = 0.01
  p.animationState = e.animationState * 2
  e.x = math.floor(e.x / 16) * 16 + 8
  e.y = math.floor(e.y / 16) * 16 + 8
  setAnim(f, e, e.animationState + 0xC)
  f:sound(0x78) -- SFX_PLY_VO4
  f:sound(0x139)
  local v = VEC[e.animationState]
  p.extUpdate = function(pl)
    pl.x, pl.y = pl.x + v[1] * 2, pl.y + v[2] * 2 -- speed $200
    if not linkJump(f, pl) then
      pl.state = "normal"
      pl.extUpdate, pl.drawUnder = nil, nil
      f.cartRide = nil
    end
  end
  p:setAnim(ANIM_JUMP, true)
  p.drawUnder = nil
end

local function ride(f, e)
  local p = f.player
  local flags = p.anim.flags or 0
  if band(flags, 0xF) == 0 then
    -- the pause frame: the cart stays where Link is
    e.spriteOY = band(flags, 0xF0) == 0x10 and 1 or 0
    return
  end
  local v = VEC[e.animationState]
  -- LinearMoveUpdate, then sub_08091DDC
  e.x, e.y = e.x + v[1] * 7, e.y + v[2] * 7 -- speed $700
  p.x, p.y = e.x, e.y
  -- sub_08091DDC: the room edge 8 px ahead takes Link and the cart along
  local ex, ey = e.x + EDGE[e.animationState][1], e.y + EDGE[e.animationState][2]
  local r = f.room
  if ex < 0 or ey < 0 or ex >= r.width or ey >= r.height then
    local dir = ({ [0] = 0, 1, 2, 3 })[e.animationState]
    local exit = r:borderExit(dir, p.x, p.y) or f:adjacentRoom(dir)
    if exit then
      f.cartRide = { animationState = e.animationState, index = e.timer0 or 0, type2 = e.type2 }
      f:startTransition(exit, dir)
      return
    end
  end
  -- the riding cart hits what it meets (hitType $97, damage 8)
  for _, en in ipairs(f.entities) do
    if en.enemy and not en.dying and not en.deleted and math.abs(en.x - e.x) < 12 and math.abs(en.y - e.y) < 12 then
      f:enemies():hit(en, 0x97, e.x, e.y, 8)
    end
  end
  if f.frame % 16 == 0 then f:sound(0x138) end
  e.subtimer = (e.subtimer or 0) - 1
  if e.subtimer < 0 then f:sound(0x7B) e.subtimer = 60 end -- SFX_PLY_VO7
  local a = act(f, e.x + AHEAD[e.animationState][1], e.y + AHEAD[e.animationState][2], e.layer or 1) or 0
  if not ALLOWED[e.animationState][a] then
    e.animationState = bxor(e.animationState, 2)
  elseif a == 100 then
    return exitCart(f, e)
  elseif CORNER[a] and a == (act(f, e.x, e.y, e.layer or 1) or 0) then
    -- Action4: snap to the tile and turn
    e.x = math.floor(e.x / 16) * 16 + 8
    e.y = math.floor(e.y / 16) * 16 + 8
    local s = e.animationState
    if a == 103 then s = (s == 3) and 0 or 1
    elseif a == 104 then s = (s == 1) and 2 or 3
    elseif a == 105 then s = (s == 1) and 0 or 3
    elseif a == 106 then s = (s == 3) and 2 or 1 end
    e.animationState = s
    p.x, p.y = e.x, e.y
  end
  p.animationState = e.animationState * 2
  p:setAnim(ANIM_MINECART)
  if e.cartAnim ~= e.animationState then setAnim(f, e, e.animationState) else e.anim:update(1) end
end

function Minecart.update(f, e, input)
  local p = f.player
  if e.action == 1 then
    if e.type2 == 0 and pushing(f, e, input) then e.timer = e.timer + 1 else e.timer = 0 end
    if e.timer > 8 then
      -- jump in (jump_status $81, zVelocity 2.0, speed 1)
      e.action = 2
      e.solid = false
      p.state = "ext"
      p.z, p.zv = 0.01, 2.0
      p:setAnim(ANIM_JUMP, true)
      f:sound(0x7C) -- SFX_PLY_JUMP
      p.extUpdate = function(pl) pl.anim:update(1) end
      f.cartEntity = e
    end
  elseif e.action == 2 then
    enterUpdate(f, e)
    if e.action == 3 then
      p.drawUnder = function(pl, x, y) Minecart.drawCart(f, e, x, y) end
      p.extUpdate = function(pl) pl.anim:update(1) end
    end
  elseif e.action == 3 then
    ride(f, e)
  elseif e.action == 6 then
    e.anim:update(1)
    if p.state ~= "ext" then
      -- Action6: turned round, its place remembered
      e.action = 1
      e.animationState = bxor(e.animationState, 2)
      local d = e.data
      d.tilePos = math.floor(e.y / 16) * 64 + math.floor(e.x / 16)
      d.room = f.room.room
      d.animationState = e.animationState
      setAnim(f, e, e.animationState + 0x10)
    end
  elseif e.action == 7 then
    if e.zv < 0 then e.anim:update(1) end
    e.zv = e.zv - 0.125
    e.z = e.z + e.zv
    if e.z <= 0 then
      e.z, e.zv = 0, 0
      e.type2 = bxor(e.type2, 4)
      e.action = 1
      e.data.type2 = e.type2
      f:sound(0x13C)
      setAnim(f, e, e.type2 + 4 + e.animationState)
    end
  end
end

function Minecart.drawCart(f, e, x, y)
  local A = f.assets
  local frame = e.anim.frame
  if not frame or frame == 0xFF then return end
  local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "cart", e.gfx)
  if not img then return end
  y = y + (e.spriteOY or 0)
  if e.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

-- Field:enterRoom: a ride that crossed the room edge continues here
function Minecart.onEnterRoom(f)
  local area = f.room and f.room.area
  if f.lastCartArea ~= area then
    if area == AREA_COF and f.lastCartArea ~= nil and f.lastCartArea ~= 0x51 then Minecart.reset(f) end
    f.lastCartArea = area
  end
  local r = f.cartRide
  if not r then return end
  local p = f.player
  local d = f._objects and f._objects:def(OBJ_MINECART, 0)
  if not d then f.cartRide = nil return end
  local e = { kind = 6, id = OBJ_MINECART, form = 0, x = p.x, y = p.y, z = 0, timer0 = r.index,
              animationState = r.animationState, type2 = r.type2, layer = p.layer, field80 = 0, field82 = 0, interactType = 0 }
  f:objects():dress(e, d, 0)
  e.literalAnim, e.forceAnim = nil, nil
  e.cart, e.dungeon, e.action, e.subtimer = true, true, 3, 1
  e.data = dataFor(f, r.index)
  e.hidden = true
  setAnim(f, e, e.animationState)
  e.extUpdate = function(_, me, input) Minecart.update(f, me, input) end
  f.entities[#f.entities + 1] = e
  f._dungeon:track(e)
  p.state = "ext"
  p.inCart = true
  p.animationState = e.animationState * 2
  p:setAnim(ANIM_MINECART, true)
  p.extUpdate = function(pl) pl.anim:update(1) end
  p.drawUnder = function(pl, x, y) Minecart.drawCart(f, e, x, y) end
  f.cartRide = nil
end

return Minecart
