-- Round 8: the Business Scrub (enemy $16, src/enemy/businessScrub.c) and its
-- Deku seed (DEKU_SEED_PROJECTILE $04, dekuSeedProjectile.c).
--
-- Action0  the offer (gUnk_080CC954[type]; a sold-out offer with bit 1 of
--          byte 0 moves on to entry [local_flag]); a scrub whose flag is set
--          (or offer bit 0) stands out friendly (action 4), else hides.
-- Action1  hidden (sprite $A7 in the ground, fixed tiles $E8, palette 2,
--          SPECIAL_TILE_34 on its tile): Link inside 0x50 of it but not
--          inside 0x28 -> it pops out (LoadFixedGFX $72, palette $6E,
--          sprite $D0).
-- Action2  0: popping out; 1: 60 frames turning to Link every 16; 2: the
--          shake (sub_080290FC) and the seed on frame bit 0; 3: back; 4: 80
--          frames, then again or hide.  Link leaving 0x58 (or coming inside
--          0x28) sends it back under.
-- OnCollision  its own seed bounced back by the shield (contact $42):
--          action 3, FX_BUSH, SFX_EM_DEKUSCRUB_HIT, animation 4 then 5, the
--          stars, SetFlag(flag) -> friendly.
-- Action4/5/6/7  talking: the offer's text with gMessage.rupees = price;
--          "yes" with the rupees buys it (item get; the bottle sets
--          AKINDO_BOTTLE_SELL), too few rupees -> text $03, a full bag $04,
--          after the item get text $02.
-- Animations: (direction >> 3) | gUnk_080CCA04[n].  Tables read from the
-- player's ROM (MENU_DATA scrubTables).
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local S = {}
S.__index = S
S.ID = 0x16

local A_SALES, A_KIN, A_ANIM = 0x080CC954, 0x080CC9C0, 0x080CCA04
local ITEM_BOW, ITEM_GRIP_RING, ITEM_BOTTLE1, ITEM_KINSTONE, ITEM_BOMBS10, ITEM_ARROWS30 = 0x09, 0x44, 0x1C, 0x5C, 0x6C, 0x6F
local AKINDO_BOTTLE_SELL = 0x5A -- flags.h (global)
local SFX_HIT, SFX_SEED, SFX_BOUNCE, SFX_86 = 0x1BB, 0x18D, 0x118, 0x86
local FX_BUSH, FX_STARS = 3, 0x1C
local DIRV = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function tables(f)
  f._scrubT = f._scrubT or require("src.zelda.tmc.Ppu").table({ A = f.assets }, "scrubTables") or false
  return f._scrubT or nil
end

-- one SalesOffering (12 bytes)
function S.offer(t, i)
  local a = A_SALES + 12 * i
  return { kind = t.u8(a), price = t.u16(a + 2), text = t.u16(a + 4), textSold = t.u16(a + 6),
           item = t.u8(a + 8), sub = t.u8(a + 9), localFlag = t.u16(a + 10), index = i }
end

function S.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, S)
end

-- sub_08029198: sold out?
function S:soldOut(o)
  local f = self.field
  local v
  if band(o.kind, 0xFC) ~= 0xC then
    if o.item == ITEM_BOTTLE1 then v = f:flag("global", AKINDO_BOTTLE_SELL)
    elseif o.item == ITEM_BOW or o.item == ITEM_GRIP_RING then v = (f:inventory(o.item) or 0) > 0
    else return false end
  else
    v = f:flag("local", o.localFlag)
  end
  return v and true or false
end

-- sub_0802915C: still for sale
function S:forSale(o)
  local f = self.field
  if o.item == ITEM_GRIP_RING then return (f:inventory(ITEM_GRIP_RING) or 0) == 0 end
  if o.item == ITEM_BOTTLE1 then return not f:flag("global", AKINDO_BOTTLE_SELL) end
  return o.item == ITEM_KINSTONE or o.item == ITEM_BOMBS10 or o.item == ITEM_ARROWS30
end

function S:pickOffer(e)
  local t = e.t
  local o = S.offer(t, e.form or 0)
  if self:soldOut(o) and band(o.kind, 2) ~= 0 then o = S.offer(t, o.localFlag) end
  e.offer = o
end

function S:anim(e, n)
  local idx = bor(rshift(e.direction, 3), e.t.u8(A_ANIM + n))
  e.animIndex = idx
  e.anim:set(self.A:sprite(e.sprite), idx, true)
end

function S:spawn(dat, def)
  local f = self.field
  local t = tables(f)
  if not t then return nil end
  local e = {
    kind = 3, id = dat.id, form = dat.paramA or 0, x = dat.x, y = dat.y, z = 0, boss = true, enemy = true, impl = self,
    hitType = def and def.damageType or 1, hitbox = def and def.hitbox or { x = 0, y = 0, w = 6, h = 6 },
    def = def or {}, health = def and def.health or 1, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0,
    action = 0, subAction = 0, timer = 0, subtimer = 0, iframes = 0, direction = 0x10, animationState = 0,
    flag = band(rshift(dat.paramC or 0, 16), 0xFFFF), t = t, homeX = dat.x, homeY = dat.y, layer = 1,
  }
  e.tileX, e.tileY = math.floor(e.x / 16), math.floor(e.y / 16)
  self:pickOffer(e)
  if band(e.offer.kind, 1) ~= 0 or (e.flag ~= 0 and f:flag("local", e.flag)) then
    self:out(e)
    e.action, e.timer = 4, 120
    self:anim(e, 0)
    e.talkable = true
  else
    self:hide(e)
  end
  return e
end

-- sub_08028FFC: under the ground
function S:hide(e)
  e.action, e.subAction, e.timer, e.subtimer = 1, 0, 80, 0
  e.collide = false
  e.sprite = 0xA7
  e.gfx = { vram = 0xE8 }
  e.palette = self.A:objPalette(2)
  e.x, e.y = e.homeX, e.homeY
  e.animIndex = 0
  e.anim:set(self.A:sprite(e.sprite), 0, true)
end

-- sub_08029078: out (LoadFixedGFX $72, LoadObjPalette $6E, sprite $D0)
function S:out(e)
  e.collide = true
  e.sprite = 0xD0
  e.gfx = Assets.gfxSource("enemy", (e.def.gfx or 0x72))
  e.palette = self.A:objPalette(0x6E, self.field.room.atlas and self.field.room.atlas.palettes)
end

-- sub_08028F98: Link in the ring between 0x28 and 0x50 / 0x58
function S:inRange(e, mode)
  local p = self.field.player
  local dx, dy = math.abs(p.x - e.x), math.abs(p.y - e.y)
  if dx < 0x28 and dy < 0x28 then return false end
  if mode ~= 2 then
    local d = mode ~= 0 and 0x58 or 0x50
    if not (dx < d and dy < d) then return false end
  end
  return true
end

-- sub_08028FDC: face Link (4 directions); true when it turned
function S:face(e)
  local p = self.field.player
  local dx, dy = p.x - e.x, p.y - e.y
  local d
  if math.abs(dx) > math.abs(dy) then d = dx > 0 and 0x08 or 0x18 else d = dy > 0 and 0x10 or 0x00 end
  if d == e.direction then return false end
  e.direction = d
  e.animationState = rshift(d, 3) * 2
  return true
end

function S:seed(e)
  local f = self.field
  local def = f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[4]
  if def and def.multi then def = def.forms[0] end
  if not def then return end
  local v = DIRV[rshift(e.direction, 3)]
  local s = { kind = 4, id = 4, x = e.x, y = e.y, z = 4, vx = v[1], vy = v[2], speed = (def.speed or 0x180) / 256,
              timer = 48, action = 1, parent = e, sprite = def.sprite, gfx = Assets.gfxSource("enemy", def.gfx),
              palette = self.A:objPalette(def.palette or 0, f.room.atlas and f.room.atlas.palettes),
              anim = Anim.new(), literalAnim = true, hitType = def.damageType or 0x68, field82 = 0, interactType = 0, layer = 1 }
  -- gfx 0 in its definition: the seed shares its scrub's tiles and palette
  if (def.gfx or 0) == 0 then s.gfx, s.palette = e.gfx, e.palette end
  s.anim:set(self.A:sprite(s.sprite), 0x18, true)
  s.objAnim, s.animIndex = 0x18, 0x18 -- the tracked-object animator keeps objAnim
  s.extUpdate = function(_, me) S.updateSeed(f, me) end
  s.drawGhost = function(me, _, camX, camY) S.drawSeed(f, me, camX, camY) end
  s.kind = 8
  f.entities[#f.entities + 1] = s
  f._dungeon:track(s)
  f:sound(SFX_SEED)
end

function S.updateSeed(f, s)
  s.anim:update(1)
  if s.action == 3 then
    if s.anim.done then s.deleted = true end
    return
  end
  if s.action == 4 then
    -- the drop after its 48 frames (BounceUpdate, simplified to one bounce)
    s.zv = (s.zv or 0) - 0.25
    s.z = s.z + s.zv
    if s.z <= 0 then s.deleted = true end
    return
  end
  s.x, s.y = s.x + s.vx * s.speed, s.y + s.vy * s.speed
  if f.room:isSolid(s.x, s.y, 1) and s.action == 1 then
    s.action = 3
    s.anim:set(f.assets:sprite(s.sprite), 0x19, true)
    s.objAnim, s.animIndex = 0x19, 0x19
    return
  end
  if s.action == 2 then
    s.timer = s.timer - 1
    if s.timer <= 0 then s.action = 1; s.timer = 256 end -- action 1's u8 timer wraps from 0
    return
  end
  s.timer = s.timer - 1
  if s.timer <= 0 then s.action = 4 s.zv = 0 return end
  local p = f.player
  -- bounced back: its scrub
  if s.reflected then
    local e = s.parent
    if e and not e.deleted and e.collide and math.abs(e.x - s.x) < 8 and math.abs(e.y - s.y) < 8 then
      s.deleted = true
      S.onCollision(f, e)
    end
    return
  end
  if p.state ~= "dead" and math.abs(p.x - s.x) < 6 and math.abs((p.y - 4) - s.y) < 8 then
    if p:blocksFrom(s.x, s.y) then
      -- the shield (contact $82 / $83): back the way it came
      s.vx, s.vy = -s.vx, -s.vy
      s.action, s.timer, s.reflected = 2, 3, true
      f:sound(SFX_BOUNCE)
      s.timer2 = 48
      return
    end
    if p.invuln == 0 then
      local st = f:enemies():settings(s.hitType, 0)
      p:hurt(st and math.max(st.tgtDmg, 1) or 2, s.x, s.y)
      if s.hitType == 0x68 then f:sound(SFX_86) end
    end
    s.deleted = true
  end
end

function S.drawSeed(f, s, camX, camY)
  local frame = s.anim.frame
  if not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(s.sprite, frame, s.palette, "seed", s.gfx)
  if img then love.graphics.draw(img, math.floor(s.x - camX + ox), math.floor(s.y - camY - (s.z or 0) + oy)) end
end

-- BusinessScrub_OnCollision with its own seed
function S.onCollision(f, e)
  local self = e.impl
  e.action, e.subAction, e.timer = 3, 0, 40
  e.collide = false
  self:anim(e, 4)
  f:addFx(e.x, e.y - 8, 0x0F, FX_BUSH)
  f:sound(SFX_HIT)
end

function S:talk(e)
  local f = self.field
  local o = e.offer
  e.interactType = 0
  self:face(e)
  self:anim(e, 3)
  e.talked, e.timer, e.subtimer = true, 32, 0
  local text
  if self:soldOut(o) then text = o.textSold
  else
    e.action = band(o.kind, 0xFC) ~= 0xC and 5 or 7
    text = o.text
    e.lockPlayer = true
  end
  f.messageRupees = o.price
  f:message(text, e)
end

function S:update(e)
  local f = self.field
  local a = e.action
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if a == 1 then
    e.anim:update(1)
    if e.timer > 0 then e.timer = e.timer - 1
    elseif self:inRange(e, 0) then
      self:out(e)
      e.action = 2
      self:face(e)
      self:anim(e, 1)
      e.subAction, e.subtimer = 0, 1
    end
  elseif a == 2 then
    e.anim:update(1)
    local unk = 1
    local s = e.subAction
    local fl = e.anim.flags or 0
    if s == 0 then
      if e.anim.done then e.subAction, e.timer, e.subtimer = 1, 60, 16; self:face(e); self:anim(e, 1) end
    elseif s == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.subAction, e.timer, e.subtimer = 2, 32, 0; self:face(e); self:anim(e, 2)
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then if self:face(e) then self:anim(e, 1) end e.subtimer = 16 end
      end
    elseif s == 2 then
      -- sub_080290FC: the shake before the shot
      if e.timer > 0 then
        e.timer = e.timer - 1
        if e.timer < 16 and band(e.timer, 1) == 0 then
          local sv = band(e.direction, 0x10) ~= 0 and -1 or 1
          local d = band(e.timer, 8) ~= 0
          if band(e.direction, 0x08) ~= 0 then e.x = e.x + (d and -sv or sv) else e.y = e.y + (d and sv or -sv) end
        end
      end
      if band(fl, 1) ~= 0 and not e.fired then e.fired = true; self:seed(e); e.subAction = 3 end
    elseif s == 3 then
      unk = 2
      e.fired = nil
      if e.anim.done then e.subAction, e.timer = 4, 80; self:anim(e, 1) end
    elseif s == 4 then
      unk = 2
      e.timer = e.timer - 1
      if e.timer == 0 then
        if self:inRange(e, 0) then e.subAction, e.timer, e.subtimer = 1, 60, 16; self:face(e)
        else self:hide(e) end
        return
      end
    end
    if e.action == 2 and not self:inRange(e, unk) then self:hide(e) end
  elseif a == 3 then
    if e.subAction == 0 then
      if e.timer == 0 then
        if e.anim.done then e.subAction = 1; self:face(e); self:anim(e, 5) end
      else e.timer = e.timer - 1 end
    elseif e.anim.done then
      e.action, e.subAction, e.timer, e.subtimer = 4, 0, 30, 5
      self:anim(e, 0)
      f:addFx(e.x, e.y - 12, 0x0F, FX_STARS)
      if e.flag ~= 0 then f:setFlag("local", e.flag, true) end
      e.talkable = true
    end
    e.anim:update(1)
  elseif a == 4 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.timer = 48
      if e.subtimer > 0 then e.subtimer = e.subtimer - 1
      elseif self:face(e) or e.talked then e.talked = nil; self:anim(e, 0) end
    end
    e.anim:update(1)
    if e.interactType ~= 0 then self:talk(e) end
  elseif a == 5 then
    if f:messageActive() then return end
    local o = e.offer
    local yes = (f.textResult or 0) == 0
    e.lockPlayer = nil
    if yes and self:forSale(o) then
      local st = f.save.stats
      if o.price <= (st.rupees or 0) then
        if o.item == ITEM_BOMBS10 and (st.bombCount or 0) >= (st.bombMax or 10) then
          f:message(bor(band(o.text, 0xFF00), 0x04), e)
        else
          f:modStat("rupees", -o.price)
          local sub = o.sub
          if o.item == ITEM_KINSTONE and sub == 0xFF then sub = e.t.u8(A_KIN + math.random(0, 7)) end
          if o.item == ITEM_BOTTLE1 then f:setFlag("global", AKINDO_BOTTLE_SELL, true) end
          f:giveItem(o.item, sub ~= 0xFF and sub or nil)
          e.action, e.timer = 6, 4
          self:anim(e, 3)
          return
        end
      else
        f:message(bor(band(o.text, 0xFF00), 0x03), e)
      end
    end
    e.action, e.timer = 4, 48
    self:anim(e, 0)
  elseif a == 6 then
    if f.player.state == "itemget" or f:messageActive() then return end
    f:message(bor(band(e.offer.text, 0xFF00), 0x02), e)
    e.action, e.timer = 4, 1
    -- sub_08028EDC: a sold-out offer moves on
    local o = e.offer
    if self:soldOut(o) and band(o.kind, 2) ~= 0 then e.offer = S.offer(e.t, o.localFlag) end
    e.anim:update(1)
  elseif a == 7 then
    if f:messageActive() then return end
    e.action, e.timer = 4, 1
    if not f:flag("local", e.offer.localFlag) then f:setFlag("local", e.offer.localFlag, true) end
  end
end

-- the sword does nothing to it (its matrix hit type); only its seed does
function S:swordHit(e, box) return false end

function S:draw(e, camX, camY)
  local frame = e.anim.frame
  if not e.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = self.A:spriteFrame(e.sprite, frame, e.palette, "scrub" .. e.sprite, e.gfx)
  if not img then return end
  local x, y = math.floor(e.x - camX), math.floor(e.y - camY - (e.z or 0))
  if e.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

return S
