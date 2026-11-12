-- The Bow and the Light Arrow bow (round 26, team A).
--
-- Ported from the decomp (zeldaret/tmc):
--   src/item/itemBow.c   ItemBow: sub_08075DF4 (use, bow_state 1,
--                        ANIM_BOW_PULLOUT), sub_08075E40 (the pull-out until
--                        Link's frame bit $80; with arrows Link may move),
--                        ItemBowShoot (held with arrows: drawn; released or
--                        no arrows: ANIM_BOW_SHOOT), sub_08075F38 (until
--                        frame bit 1), sub_08075F84 (until frame bit $80; the
--                        Arrow Butterfly ($70) skips 5 frames at a time)
--   src/player.c         sub_080085B0's speed: bow_state -> kWalkSpeedShield
--   src/playerUtils.c    sub_080797EC / the idle choice: ANIM_BOW_WALK /
--                        ANIM_BOW_CHARGE while the bow is drawn
--   src/playerItem/playerItemBow.c
--                        PlayerItemBow_Init (type 0: the bow in Link's hands,
--                        frame = Link's frameIndex (+60 light bow, +$2A with
--                        no arrows); type 1: the arrow from gUnk_080B3E40,
--                        sprite $A6, speed $300 (light $400), 106 frames,
--                        SFX_FC), _Action1 (type 0: the light bow charges
--                        bow_state to $78 -> hurtType $0E; Link's frame bit 1
--                        with arrows -> an arrow, ModArrows(-1); type 1: the
--                        flight, blink under 24 frames, DoTileInteractionOffset
--                        filter 4 (light 1: passes through), FX_SPARKLE2 every
--                        8 frames (light), the wall: stuck 30 frames, anim +2
--                        (light: +$F and FX_REFLECT5), SFX_18A; contact: gone),
--                        _Action2 (stuck, frozen under $F), sub_08019468
--   src/playerItemDefinitions.c  PlayerItemBow { palette 1, damage 3,
--                        hurtType $15 (the arrow's type2), hitType $AB,
--                        SPRITE_21, VRAM 203 }
--   src/itemUtils.c      GiveItem cases $0A (quiver: quiverType+1, max 3,
--                        ModArrows(99)), $0B (bow: ITEM_LARGE_QUIVER set,
--                        ModArrows(99)), $0C (ModArrows(param), SFX_103),
--                        ModArrows (0 .. gQuiverSizes[quiverType])
--
-- Ammo: f.save.stats.arrowCount (the field Menu / Drops / Objects use);
-- arrowMax mirrors gQuiverSizes[quiverType] for the menu.
--
-- SIMPLIFIED: the arrow's hitboxes (gUnk_080B3E70/78) and the enemies' are a
--   10 px box (as Pacci.lua); the wall test (sub_080B1BA4 / sub_080040D8) is
--   GustJar.wall (type-1 tile collision: pits / water pass; gUnk_08003E44
--   is a .bin) at the arrow (round 26A; the eye switches / Mazaal get the
--   decomp's 4 x 6 / 6 x 4 arrow box); Link's frame bit 1 fires one arrow per shot
--   (a latch; the cartridge's attack_status $80); the bow draws over Link
--   (sub_08078E84's priority not ported); the light bow's SWORD_PARTICLE at
--   pull-out is not created; the contact $42 bounce (_Action3) is unreachable
--   in the C ((contactFlags & $3F) == $42 never holds) and is not ported.
local bit = require("bit")
local band = bit.band

local M = {}

M.ITEM_BOW, M.ITEM_LIGHT_ARROW = 0x09, 0x0A
M.ITEM_LARGE_QUIVER, M.ITEM_ARROW_BUTTERFLY = 0x66, 0x70
M.ANIM_BOW_PULLOUT, M.ANIM_BOW_SHOOT, M.ANIM_BOW_CHARGE, M.ANIM_BOW_WALK = 0x21C, 0x27C, 0x280, 0x284
M.HURT_ARROW, M.HURT_LIGHT = 0x15, 0x0E
M.SPRITE_BOW, M.SPRITE_ARROW, M.VRAM_ARROW = 21, 0xA6, 203
M.SFX_FC, M.SFX_18A, M.SFX_103 = 0xFC, 0x18A, 0x103
M.FX_SPARKLE2, M.FX_REFLECT5, M.SPECIAL_FX = 0x14, 0x50, 0x0F
M.QUIVER = { [0] = 30, 50, 70, 99 } -- gQuiverSizes
M.SHIELD_SPEED = 0xC0 / 256 -- kWalkSpeedShield
-- gUnk_080B3E40: x, y, flipX, flipY, tile offset x, y, animIndex
M.ARROW = { [0] = { -3, -12, false, false, 0, -5, 2 }, { 8, -4, true, false, 5, 0, 1 },
            { 0, 1, false, true, 0, 5, 2 }, { -8, -4, false, false, -5, 0, 1 } }

-- ModArrows
function M.modArrows(f, n)
  local s = f.save.stats
  local max = M.QUIVER[s.quiverType or 0] or 30
  local c = (s.arrowCount or 0) + n
  if c < 0 then c = 0 elseif c > max then c = max end
  s.arrowCount = c
  s.arrowMax = max
end

local function arrows(f) return f.save.stats.arrowCount or 0 end

-- ------------------------------------------------------------------ arrows
local function setAnim(f, a, idx)
  a.anim:set(f.assets:sprite(M.SPRITE_ARROW), idx, true)
  a.animIndex = idx
end

local function reflectFx(f, a) -- sub_08019468
  if a.hurtType == M.HURT_LIGHT then f:addFx(a.x, a.y, M.SPECIAL_FX, M.FX_REFLECT5) end
end

local function moveArrow(a)
  local ang = a.dir / 32 * 2 * math.pi
  local s = a.speed / 256
  a.x, a.y = a.x + math.sin(ang) * s, a.y - math.cos(ang) * s
end

local function collide(f, a)
  -- round 26A wiring: the FORTRESS eye switches open only to an arrow
  -- (FoWObjects.arrowHit), Mazaal's parts are hit through BossMazaal.hit
  -- (only arrows knock a hand down; Enemies:hit is masked off for them)
  local okF, FoW = pcall(require, "src.zelda.tmc.FoWObjects")
  local vert = band(a.dir or 0, 8) == 0 -- gUnk_080B3E70 / 78: the arrow's hitbox, 4 x 6 flying north / south, 6 x 4 east / west
  local aw, ah = vert and 4 or 6, vert and 6 or 4
  if okF and FoW.arrowHit and FoW.arrowHit(f, a.x, a.y, a.hurtType, a.dir, aw, ah) then a.contact = true return end
  for _, e in ipairs(f.entities) do
    if e.mz and e.boss and e.impl and not e.deleted and (e.collide or e.collide == nil)
       and math.abs(e.x + ((e.hitbox and e.hitbox.x) or 0) - a.x) < ((e.hitbox and e.hitbox.w) or 8) + 2
       and math.abs(e.y + ((e.hitbox and e.hitbox.y) or 0) - a.y) < ((e.hitbox and e.hitbox.h) or 8) + 2 then
      if require("src.zelda.tmc.BossMazaal").hit(f:enemies(), e, a.hurtType, a.x, a.y, a.dir) then a.contact = true return end
    end
  end
  for _, e in ipairs(f.entities) do
    if e ~= a and e.enemy and not e.deleted and not e.dying and not e.hidden
       and math.abs(e.x - a.x) < 10 and math.abs(e.y - a.y) < 10 and (e.iframes or 0) == 0 then
      f:enemies():hit(e, a.hurtType, a.x, a.y)
      a.contact = true
      return
    end
  end
end

-- PlayerItemBow_Action1 (type 1) / _Action2
function M.updateArrow(f, a)
  if a.action == 2 then
    if a.timer < 0xF then setAnim(f, a, a.animIndex) else a.anim:update(1) end
    a.timer = a.timer - 1
    if a.timer < 0 then a.deleted = true end
    return
  end
  local contact = a.contact
  a.contact = nil
  a.life = a.life - 1
  if a.life == 0 then reflectFx(f, a); a.deleted = true return end
  a.anim:update(1)
  if a.life < 24 then a.hidden = not a.hidden end
  moveArrow(a)
  local light = a.hurtType == M.HURT_LIGHT
  local tmp2 = false
  local O = f.objects and f:objects()
  if O and O.tileInteraction
     and require("src.zelda.tmc.Bombs").interact(f, light and 1 or 4, a.x + a.tox, a.y + a.toy, a.layer) then
    if not light then a.deleted = true return end
    tmp2 = true
  end
  if light then
    a.timer = a.timer + 1
    if band(a.timer, 7) == 0 then f:addFx(a.x, a.y, M.SPECIAL_FX, M.FX_SPARKLE2) end
  end
  if not tmp2 and (f.room.coll and f.room.tw and require("src.zelda.tmc.GustJar").wall(f, a.x, a.y, a.layer) or (not (f.room.coll and f.room.tw) and f.room:isSolid(a.x, a.y, a.layer))) then -- round 26A: the type-1 tile collision (pits / water do not stop an arrow; gUnk_08003E44 is a .bin)
    a.timer = 30
    a.action = 2
    if light then reflectFx(f, a); setAnim(f, a, a.animIndex + 0xF) else setAnim(f, a, a.animIndex + 2) end
    a.collision = false
    a.speed = 0
    if a.x < 0 then a.x = 0 end
    if a.y < 0 then a.y = 0 end
    f:sound(M.SFX_18A)
    return
  end
  if contact and not tmp2 then
    reflectFx(f, a)
    a.action, a.timer, a.hidden, a.collision = 2, 1, true, false
    return
  end
  if a.collision then collide(f, a) end
end

function M.drawArrow(f, a, camX, camY)
  if a.hidden then return end
  local fr = a.anim.frame
  if not fr or fr == 0xFF then return end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(M.SPRITE_ARROW, fr, A:objPalette(1), "arrow", { vram = a.vram })
  if not img then return end
  local x, y = math.floor(a.x - camX), math.floor(a.y - camY)
  local fx = a.flipX ~= a.anim:hflip()
  local fy = a.flipY ~= a.anim:vflip()
  love.graphics.draw(img, x + (fx and -ox or ox), y + (fy and -oy or oy), 0, fx and -1 or 1, fy and -1 or 1)
end

-- PlayerItemBow_Init, type 1
function M.spawnArrow(f, p, hurtType)
  local s = math.floor(p.animationState / 2)
  local t = M.ARROW[s]
  local light = hurtType == M.HURT_LIGHT
  local a = { kind = 8, id = 4, arrow = true, action = 1, x = math.floor(p.x) + t[1], y = math.floor(p.y) + t[2], z = 0,
              layer = p.layer, hurtType = hurtType, speed = light and 0x400 or 0x300, dir = s * 8,
              life = 106, timer = 0, flipX = t[3], flipY = t[4], tox = t[5], toy = t[6],
              vram = light and 0 or M.VRAM_ARROW, collision = true, field82 = 0, interactType = 0,
              anim = require("src.zelda.tmc.Anim").new() }
  setAnim(f, a, t[7] + (light and 6 or 0))
  a.extUpdate = function(_, me) M.updateArrow(f, me) end
  a.drawGhost = function(me, field, camX, camY) M.drawArrow(field, me, camX, camY) end
  f.entities[#f.entities + 1] = a
  if f._dungeon then f._dungeon:track(a) end
  f:sound(M.SFX_FC)
  return a
end

-- ------------------------------------------------------------------ the bow
local function finish(pl)
  pl.state = "normal"
  pl.extUpdate = nil
  pl.animId = -1
  pl._r26bow = nil
end

local function dirInput(f, input)
  if not input or (f.inputLocked and f:inputLocked()) then return 0, 0 end
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

local function bowFrame(pl, input)
  local f = pl.field
  local bw = pl._r26bow
  local fl
  -- the item behavior (ItemBow's states)
  if bw.st == 1 then
    pl.anim:update(1)
    if band(pl.anim.flags or 0, 0x80) ~= 0 then
      bw.st = 2
      bw.canMove = arrows(f) ~= 0 -- animPriority 0, field_0xa cleared
    end
  elseif bw.st == 2 then
    if input and input.down(bw.button) and arrows(f) ~= 0 then
      if bw.canMove then
        local dx, dy = dirInput(f, input)
        pl.lockFacing = true -- keepFacing
        pl:walk(dx, dy, M.SHIELD_SPEED, M.ANIM_BOW_WALK, M.ANIM_BOW_CHARGE)
        pl.lockFacing = nil
        pl.anim:update(1)
      end
    else
      pl:setAnim(M.ANIM_BOW_SHOOT, true)
      bw.st = 3
    end
  elseif bw.st == 3 then
    pl.anim:update(1)
    if band(pl.anim.flags or 0, 1) ~= 0 then bw.st = 4 end
  elseif bw.st == 4 then
    if (f.save.items[M.ITEM_ARROW_BUTTERFLY] or 0) == 1 then pl.anim:update(5) else pl.anim:update(1) end
    if band(pl.anim.flags or 0, 0x80) ~= 0 then
      fl = true
    end
  end
  -- the bow (PlayerItemBow_Action1, type 0)
  if bw.light and bw.bowState ~= 0 then
    if bw.bowState < 0x78 then bw.bowState = bw.bowState + 1 else bw.hurtType = M.HURT_LIGHT end
  end
  if band(pl.anim.flags or 0, 1) ~= 0 and arrows(f) ~= 0 and not bw.fired then
    bw.fired = true
    M.spawnArrow(f, pl, bw.hurtType)
    M.modArrows(f, -1)
  end
  if fl then finish(pl) end
end

function M.use(p, item, button, input)
  if item ~= M.ITEM_BOW and item ~= M.ITEM_LIGHT_ARROW then return nil end
  if p.minish or p.state ~= "normal" then return nil end -- isUseableAsMinish FALSE
  p.state = "ext"
  p._r26bow = { st = 1, button = button, light = item == M.ITEM_LIGHT_ARROW, bowState = 1,
                hurtType = M.HURT_ARROW, unk78 = item == M.ITEM_LIGHT_ARROW and 60 or 0, fired = false }
  p:setAnim(M.ANIM_BOW_PULLOUT, true)
  p.extUpdate = bowFrame
  return true
end

-- Link left the bow state some other way (hurt, a cutscene): bow_state 0
function M.frame(p, input)
  if p._r26bow and (p.state ~= "ext" or p.extUpdate ~= bowFrame) then p._r26bow = nil end
  return nil
end

-- the bow in Link's hands: SPRITE_21, Link's frameIndex + unk_78 (+$2A empty)
function M.draw(p, x, y)
  local bw = p._r26bow
  if not bw or p.state ~= "ext" then return nil end
  local f = p.field
  local fr = p.anim.frame
  if not fr or fr == 0xFF then return nil end
  fr = fr + bw.unk78
  if arrows(f) == 0 then fr = fr + 0x2A end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(M.SPRITE_BOW, band(fr, 0xFF), A:objPalette(1), "bow", nil)
  if not img then return nil end
  local flip = M.ARROW[math.floor(p.animationState / 2)][3] ~= p.anim:hflip()
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  return nil
end

-- GiveItem cases $0A / $0B / $0C
local META = { [0x09] = { unk1 = 0x0B, param = 0x63 }, [0x0A] = { unk1 = 0x0B, param = 0x63 },
               [0x5E] = { unk1 = 0x0C, param = 5 }, [0x66] = { unk1 = 0x0A, param = 0x63 },
               [0x6E] = { unk1 = 0x0C, param = 10 }, [0x6F] = { unk1 = 0x0C, param = 30 } } -- gItemMetaData (fallback)
function M.giveItem(f, item, param)
  local mm = f.assets and f.assets.manifest and f.assets.manifest.itemMeta
  local meta = (mm and mm[item]) or META[item]
  if not meta then return nil end
  local c = meta.unk1
  local s = f.save.stats
  if c == 0x0B then
    if (f.save.items[M.ITEM_LARGE_QUIVER] or 0) == 0 then f.save.items[M.ITEM_LARGE_QUIVER] = 1 end
    M.modArrows(f, 99)
  elseif c == 0x0A then
    s.quiverType = math.min(3, (s.quiverType or 0) + 1)
    M.modArrows(f, 99)
  elseif c == 0x0C then
    M.modArrows(f, meta.param or 0)
    f:sound(M.SFX_103)
  end
  return nil
end

return M
