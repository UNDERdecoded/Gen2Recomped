-- The Boomerang and the Magic Boomerang (round 26, team A).
--
-- Ported from the decomp (zeldaret/tmc):
--   src/item/itemBoomerang.c       ItemBoomerang, sub_08075D2C (use: one
--                                  boomerang at a time), sub_08075D88 (the
--                                  throw animation; the magic one holds Link
--                                  on the frame-bit-2 keyframe while the
--                                  button is held)
--   src/playerItem/playerItemBoomerang.c
--                                  PlayerItemBoomerang (affine spin +-$2000,
--                                  SFX_FB every 16 frames), _Init (speed $200
--                                  / 30 frames, magic $280 / 60, the d-pad
--                                  direction or the facing), _Action1 (in
--                                  Link's hand: frame = Link's frame >> 4
--                                  (+6 magic); launched on Link's frame bit 1
--                                  at gUnk_080B7826, sprite $A6 anim 0, VRAM
--                                  $D5), _Action2 (the flight: magic steering
--                                  +-$40 a frame toward the d-pad while held,
--                                  DoTileInteractionOffset filter 2 at
--                                  gUnk_080B782E (the plain boomerang turns
--                                  back on it), walls, slowdown -$10 under 12
--                                  frames, contact), _Action3 (hover 12 / 30
--                                  frames, or 1 after a wall; home on Link
--                                  from $1C0, +8 up to $280, deleted within
--                                  2 px: sub_0800419C), sub_0801B804 (the
--                                  magic boomerang's button hold),
--                                  sub_0801B864 (the tile interaction)
--   src/playerItemDefinitions.c    PlayerItemBoomerang { palette 0, damage
--                                  3, hurtType $14, hitType $76, SPRITE_22 }
--   src/object/itemOnGround.c      contact $14: the item rides the boomerang
--                                  (ItemOnGround_Action3: its position, z-1),
--                                  released at Link (ItemOnGround_Kind1_Init),
--                                  deleted when the boomerang is gone
--   src/itemUtils.c GiveItem case $12: getting one boomerang clears the other
--
-- SIMPLIFIED: the hitboxes (gUnk_081271CC, the items' and enemies') are a
--   10 px box (enemies, as Pacci.lua) / 8 px (ground items, as Objects);
--   sub_080B1BA4 / sub_080040E2 (the wall test) is GustJar.wall (type-1
--   tile collision, pits pass; round 26A) at the
--   boomerang's position; sub_0800451C (layer by tile) and the sprite
--   priority of sub_08078E84 are not ported (the hand boomerang draws over
--   Link); GetFacingDirection is atan2 rounded to the 32 directions; a carried
--   item is released at Link and Objects:updateGround collects it the next
--   frame (sub_08081598 ran on the same frame).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.ITEM_BOOMERANG, M.ITEM_MAGIC_BOOMERANG = 0x0B, 0x0C
M.ANIM_BOOMERANG, M.ANIM_BOOMERANG_MAGIC = 0x818, 0x704
M.HURT_TYPE = 0x14
M.SPRITE_HAND, M.SPRITE_FLY, M.VRAM_FLY = 22, 0xA6, 0xD5
M.SFX_FB = 0xFB
M.LAUNCH = { [0] = { 0, -8 }, { 8, -4 }, { 0, 8 }, { -8, -4 } } -- gUnk_080B7826 (animationState >> 1)
M.TILE_OFF = { [0] = { 0, -6 }, { 4, -4 }, { 4, 0 }, { 4, 4 }, { 0, 4 }, { -4, 4 }, { -4, 0 }, { -4, 0 }, { 0, 0 } } -- gUnk_080B782E (direction >> 2)

local function dirOf(input)
  if not input then return 0x80 end
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  if dx == 0 and dy == 0 then return 0x80 end -- DIR_NOT_MOVING_CHECK
  local a = math.atan2(dx, -dy) -- 0 = north, clockwise
  return band(math.floor(a / (2 * math.pi) * 32 + 0.5), 0x1F)
end
M.dirOf = dirOf

-- LinearMoveUpdate: speed (Q8.8 px a frame) along direction (0..31)
local function move(e)
  local a = e.dir / 32 * 2 * math.pi
  local s = e.speed / 256
  e.x, e.y = e.x + math.sin(a) * s, e.y - math.cos(a) * s
end
M.move = move

-- GetFacingDirection
local function facing(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return band(math.floor(a / (2 * math.pi) * 32 + 0.5), 0x1F)
end
M.facing = facing

-- sub_0801B864: DoTileInteractionOffset(this, 2, gUnk_080B782E[direction >> 2])
local function tileHit(f, b)
  local o = M.TILE_OFF[rshift(b.dir, 2)] or M.TILE_OFF[8]
  local O = f.objects and f:objects()
  if not (O and O.tileInteraction) then return false end
  return require("src.zelda.tmc.Bombs").interact(f, 2, b.x + o[1], b.y + o[2], b.layer)
end

-- sub_0801B804: the magic boomerang's button (IsItemEquipped(MAGIC))
local function holdCheck(f, b, input)
  local slot
  if f:equipped("a") == M.ITEM_MAGIC_BOOMERANG then slot = "a" elseif f:equipped("b") == M.ITEM_MAGIC_BOOMERANG then slot = "b" end
  if not (slot and input and input.down(slot)) then
    b.released = true -- unk_80
    b.hold = false    -- gPlayerState.field_0xa / keepFacing & $80
  else
    b.hold = true
  end
end

local function setAnim(f, e, idx)
  e.anim:set(f.assets:sprite(M.SPRITE_FLY), idx, true)
  e.animIndex = idx
end

local function deleteBoom(f, b)
  b.deleted = true
  local p = f.player
  if p and p._r26boom == b then p._r26boom = nil end
  -- ItemOnGround_Action3: the child is gone -> SetFlagAndDelete(FALSE)
  for _, e in ipairs(b.carried or {}) do
    if e.carrier == b then e.deleted = true; e.carrier = nil end
  end
end

-- the collision pass (ram_CollideAll): enemies (hurtType $14) and ground
-- items (contact 20); contactFlags are seen by the next update
local function collide(f, b)
  for _, e in ipairs(f.entities) do
    if e ~= b and not e.deleted and not e.hidden then
      if e.enemy and not e.dying and math.abs(e.x - b.x) < 10 and math.abs(e.y - b.y) < 10 then
        local ready = (e.iframes or 0) == 0
        f:enemies():hit(e, M.HURT_TYPE, b.x, b.y)
        if ready then b.contact = true end
      elseif e.ground and e.act == 2 and not e.carrier and not e.pickedUp
             and math.abs(e.x - b.x) <= 8 and math.abs(e.y - b.y) <= 8 then
        e.act, e.carrier, e.hidden = 3, b, false
        b.carried = b.carried or {}
        b.carried[#b.carried + 1] = e
      end
    end
  end
end

-- ItemOnGround_Action3: the items ride along; at Link: ItemOnGround_Kind1_Init
local function carry(f, b)
  if not b.carried then return end
  local p = f.player
  for _, e in ipairs(b.carried) do
    if e.carrier == b and not e.deleted then
      e.x, e.y = b.x, b.y
      e.cz, e.z = -65536, 1 -- z.HALF.HI--
      if math.abs(math.floor(p.x) - e.x) <= 8 and math.abs(math.floor(p.y) - e.y) <= 8 then
        e.carrier = nil
        e.act, e.cz, e.czv, e.z = 2, 0, 0, 0
        e.x, e.y = math.floor(p.x), math.floor(p.y)
      end
    end
  end
end

-- PlayerItemBoomerang_Action1: in Link's hand
local function action1(f, b, input)
  holdCheck(f, b, input)
  local p = f.player
  if p.state ~= "ext" or p._r26boom ~= b then return deleteBoom(f, b) end
  local fl = p.anim.flags or 0
  if band(fl, 1) == 0 then
    b.handFrame = rshift(fl, 4) + (b.magic and 6 or 0)
    b.x, b.y = p.x, p.y
  else
    b.action = 2
    local o = M.LAUNCH[rshift(b.animationState, 1)]
    b.x, b.y = p.x + o[1], p.y + o[2]
    setAnim(f, b, 0)
    b.collision = true
  end
end

-- PlayerItemBoomerang_Action2: the flight
local function action2(f, b, input)
  holdCheck(f, b, input)
  if b.magic and not b.released then
    local d = dirOf(input)
    if band(d, 0x80) == 0 then
      local hi = rshift(b.dirw, 8)
      if band(hi - d, 0x1F) > 0x10 then b.dirw = b.dirw + 0x40 else b.dirw = b.dirw - 0x40 end
      b.dirw = band(b.dirw, 0x1FFF) -- unk_82.HALF.HI &= $1F (u16 HWORD)
      b.dir = rshift(b.dirw, 8)
    end
  end
  move(b)
  local stop = false
  if tileHit(f, b) and not b.magic then stop = true end
  if not stop and (f.room.coll and f.room.tw and require("src.zelda.tmc.GustJar").wall(f, b.x, b.y, b.layer) or (not (f.room.coll and f.room.tw) and f.room:isSolid(b.x, b.y, b.layer))) then stop = true end -- round 26A: type-1 tile collision (pits do not stop it)
  if not stop then
    b.timer = b.timer - 1
    if b.timer < 0xC then b.speed = b.speed - 0x10 end
    if b.timer == 0 then stop = true end
    if b.contact then stop = true end
    if not stop then return end
    b.timer = b.magic and 30 or 12
  else
    b.timer = 1
  end
  b.action = 3
  b.speed = 0x1C0
end

-- PlayerItemBoomerang_Action3: back to Link
local function action3(f, b, input)
  holdCheck(f, b, input)
  if b.timer ~= 0 then b.timer = b.timer - 1 return end
  tileHit(f, b)
  if b.speed < 0x280 then b.speed = b.speed + 8 end
  local p = f.player
  b.dir = facing(b.x, b.y, p.x, p.y)
  move(b)
  carry(f, b)
  -- sub_0800419C(this, player, 2, 2)
  if math.abs(math.floor(b.x) - math.floor(p.x)) <= 2 and math.abs(math.floor(b.y) - math.floor(p.y)) <= 2 then
    return deleteBoom(f, b)
  end
end

function M.update(f, b, input)
  local act = b.action
  if act == 1 then action1(f, b, input)
  elseif act == 2 then action2(f, b, input)
  else action3(f, b, input) end
  b.contact = nil -- ItemUpdate: contactFlags &= ~CONTACT_NOW after the update
  if b.deleted then return end
  if act == 2 then carry(f, b) end -- (action 3 carries before its arrival test)
  -- the spin (SetAffineInfo) once launched (animIndex ~= 11)
  if b.animIndex ~= 11 then
    if b.animationState == 6 then b.angle = band(b.angle + 0x2000, 0xFFFF) else b.angle = band(b.angle - 0x2000, 0xFFFF) end
    b.anim:update(1)
  end
  b.subtimer = band(b.subtimer - 1, 0xFF)
  if band(b.subtimer, 0xF) == 0 then f:sound(M.SFX_FB) end
  if b.collision then collide(f, b) end
end

function M.drawFly(f, b, camX, camY)
  if b.action == 1 then return end
  local fr = b.anim.frame
  if not fr or fr == 0xFF then return end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(M.SPRITE_FLY, fr, A:objPalette(0), "boomerang", { vram = M.VRAM_FLY })
  if not img then return end
  local x, y = math.floor(b.x - camX), math.floor(b.y - camY)
  -- GBA affine: a positive angle turns counter-clockwise on screen
  local r = -b.angle / 65536 * 2 * math.pi
  love.graphics.draw(img, x, y, r, 1, 1, -ox, -oy)
end

-- the use (sub_08075D2C + PlayerItemBoomerang_Init)
function M.use(p, item, button, input)
  if item ~= M.ITEM_BOOMERANG and item ~= M.ITEM_MAGIC_BOOMERANG then return nil end
  if p.minish or p.state ~= "normal" then return nil end -- isUseableAsMinish FALSE
  local f = p.field
  if p._r26boom and not p._r26boom.deleted then return true end -- FindPlayerItemForItem: nothing happens
  local magic = item == M.ITEM_MAGIC_BOOMERANG
  p.state = "ext"
  p:setAnim(magic and M.ANIM_BOOMERANG_MAGIC or M.ANIM_BOOMERANG, true)
  local d = dirOf(input)
  local dir = band(d, 0x80) == 0 and d or p.animationState * 4
  local b = { kind = 8, id = 3, boomerang = true, magic = magic, item = item, action = 1,
              x = p.x, y = p.y, z = 0, layer = p.layer, animationState = band(p.animationState, 6),
              speed = magic and 0x280 or 0x200, timer = magic and 60 or 30, dir = dir, dirw = dir * 256,
              animIndex = 11, angle = 0, subtimer = 0, handFrame = nil, useButton = button, -- (not "button": Dungeon:update treats e.button as a floor switch)
              anim = require("src.zelda.tmc.Anim").new(), field82 = 0, interactType = 0 }
  b.extUpdate = function(_, me, inp) M.update(f, me, inp) end
  b.drawGhost = function(me, field, camX, camY) M.drawFly(field, me, camX, camY) end
  f.entities[#f.entities + 1] = b
  if f._dungeon then f._dungeon:track(b) end
  p._r26boom = b
  -- the item behavior (sub_08075D88), Link's side
  p.extUpdate = function(pl, inp)
    if b.magic and b.hold and band(pl.anim.flags or 0, 2) ~= 0 then return end -- ResetPlayerVelocity
    pl.anim:update(1)
    if band(pl.anim.flags or 0, 0x80) ~= 0 or pl.anim.done then
      pl.state = "normal"
      pl.extUpdate = nil
      pl.animId = -1
    end
  end
  action1(f, b, input) -- _Init ends with _Action1
  return true
end

-- the hand boomerang over Link (sub_080042D0 with SPRITE_22's frame)
function M.draw(p, x, y)
  local b = p._r26boom
  if not b or b.deleted or b.action ~= 1 or p.state ~= "ext" or not b.handFrame then return nil end
  local A = p.field.assets
  local img, ox, oy = A:spriteFrame(M.SPRITE_HAND, b.handFrame, A:objPalette(0), "boomhand", nil)
  if not img then return nil end
  -- _Init: sideways, flipX = ~Link's flipX
  local flip = band(b.animationState, 2) ~= 0 and not (p.entFlip or false)
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  return nil
end

-- GiveItem case $12
local META = { [0x0B] = { unk1 = 0x12, param = 0 }, [0x0C] = { unk1 = 0x12, param = 0 } } -- gItemMetaData (fallback)
function M.giveItem(f, item, param)
  if item ~= M.ITEM_BOOMERANG and item ~= M.ITEM_MAGIC_BOOMERANG then return nil end
  local mm = f.assets and f.assets.manifest and f.assets.manifest.itemMeta
  local meta = (mm and mm[item]) or META[item]
  if meta.unk1 ~= 0x12 then return nil end
  local other = item == M.ITEM_BOOMERANG and M.ITEM_MAGIC_BOOMERANG or M.ITEM_BOOMERANG
  if f.setInventory then f:setInventory(other, 0) else f.save.items[other] = nil end
  return nil
end

return M
