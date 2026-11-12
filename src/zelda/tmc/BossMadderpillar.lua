-- Madderpillar ($18), src/enemy/madderpillar.c, ported whole.
--
-- The head (type 0) walks the tile grid at speed $A0 and, on each tile
-- (sub_08029F48), picks the next direction from gUnk_080CCDC8 (forward /
-- the two sides, a random start and step, a free tile, never two turns the
-- same way in a row).  Six segments (types 1-5, tail 6) follow: each frame
-- an entity writes its pixel step into its child's 14-entry ring
-- (sub_08029FB4, (dx + 8) | (dy + 8) << 4) and replays the step written
-- 13 frames earlier into its own (sub_08029FE4).
--
-- A sword on the head (OnCollision, action 1): the head stops (action 2,
-- hit type $6B, palette $7F, SFX_HIT) and a wave runs down the body (each
-- segment greys after gUnk_080CCDA0[type] frames); the tail waits 71
-- frames, opens (animation $C + state), and for 120 frames has hit type
-- $6C -- the only time the sword hurts it.  It closes (animation $10),
-- the head turns angry (action 3: speed $108, animations + 4, 360 frames
-- of palette flicker gUnk_080CCDD4, SFX_19D) and the body follows it.
-- The tail's health at 0: the head stops colliding, the segments blow up
-- one by one (90 - type * 15 frames, the tail at once), the head after 105.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local M = {}
M.__index = M

-- the cartridge's tables, read from the cache (Layout.MENU_DATA madderTables)
local A_WAVE, A_TURNS, A_FLICKER = 0x080CCDA0, 0x080CCDC8, 0x080CCDD4
local STEP = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
M.TAIL_HITBOX = 0x080FD298                                            -- gUnk_080FD298
local SFX_HIT, SFX_MENU_CANCEL, SFX_6B, SFX_19D, SFX_182, SFX_PLACE_OBJ, SFX_12E = 0xFE, 0x6C, 0x6B, 0x19D, 0x182, 0x104, 0x12E
local SPECIAL_FX, FX_GIANT_EXPLOSION3 = 0x0F, 0x48 -- round 17: was $49 (FX_GREEN_ORB)

function M.new(field, enemies)
  local self = setmetatable({ field = field, en = enemies, A = field.assets }, M)
  self.t = require("src.zelda.tmc.Ppu").table({ A = field.assets }, "madderTables")
  return self
end

-- gUnk_080CCDC8[dir * 3 + k], gUnk_080CCDA0[type], gUnk_080CCDD4[i]
function M:turn(d, k) return self.t and self.t.u8(A_TURNS + d * 3 + k) or 0 end
function M:wave(ty) return self.t and self.t.u8(A_WAVE + ty) or 1 end
function M:flickerPal(i) return self.t and self.t.u16(A_FLICKER + 2 * i) or 0x77 end

function M:pal(seg, id)
  seg.palId = id
  seg.palette = self.A:objPalette(id)
end

function M:setAnim(seg, index)
  seg.anim:set(self.A:sprite(self.sprite), index, true)
end

local function newRing()
  local r = {}
  for i = 0, 13 do r[i] = 0x88 end
  return r
end

-- spawn: the head entity carries the body (one room entity for the fight
-- manager, as the head is the one the cartridge kills last)
function M:spawn(dat, def)
  local A = self.A
  local e = {
    kind = 3, id = dat.id, form = 0, x = dat.x, y = dat.y + 6, z = 0, boss = true, enemy = true, impl = self,
    health = 0xFF, hitType = 0x6A, hitbox = def and def.hitbox or { x = 0, y = 0, w = 8, h = 8 },
    sprite = def and def.sprite, gfx = def and Assets.gfxSource("enemy", def.gfx), def = def or {},
    anim = Anim.new(), action = 1, timer = 0, iframes = 0, kbt = 0, kbx = 0, kby = 0, field82 = 0, interactType = 0,
  }
  self.sprite, self.gfx = e.sprite, e.gfx
  e.x256, e.y256 = e.x * 256, e.y * 256
  e.direction = band(math.random(0, 255), 0x18)
  e.speed = 0xA0
  e.animationState = 0xFF
  e.unk74, e.unk75, e.unk77, e.counter = 0xFF, 0, 1, 0
  e.palId = 0x77; self:pal(e, 0x77)
  e.segs = {}
  local tailDef = self.en:def(dat.id, 6) or def
  for t = 1, 6 do
    local s = { type = t, x = e.x, y = e.y, ring = newRing(), anim = Anim.new(), action = 1, timer = 0,
                hitType = 0x6A, animationState = 0, iframes = 0 }
    self:pal(s, 0x77)
    self:setAnim(s, t < 2 and 0 or (t == 6 and 8 or 4))
    e.segs[t] = s
  end
  e.tail = e.segs[6]
  e.tail.health = (tailDef and tailDef.health) or 8
  -- the open tail's hitbox (gUnk_080FD298: s8 x, s8 y, 4 bytes, w, h)
  local t = require("src.zelda.tmc.Ppu").table({ A = A }, "madderHitbox")
  if t then
    e.tail.openBox = { x = t.s8(M.TAIL_HITBOX), y = t.s8(M.TAIL_HITBOX + 1), w = t.u8(M.TAIL_HITBOX + 6), h = t.u8(M.TAIL_HITBOX + 7) }
  else
    e.tail.openBox = { x = 0, y = 0, w = 6, h = 6 }
  end
  self:chooseDir(e)
  self:headAnim(e)
  return e
end

-- sub_08029EEC
function M:headAnim(e)
  local s = rshift(e.direction, 3) + e.unk75
  if s ~= e.animationState then
    e.animationState = s
    self:setAnim(e, s)
  end
end

-- the tile under a pixel is free (GetCollisionDataAtTilePos == 0)
function M:free(x, y)
  local r = self.field.room
  return not r:isSolid(x, y, 1)
end

-- sub_08029E0C + sub_08029F0C
function M:chooseDir(e)
  local dd = rshift(e.direction, 3)
  local step = math.random(0, 1) * 2 - 1
  local k = math.random(0, 15) % 3
  local tx, ty = math.floor(e.x / 16) * 16 + 8, math.floor(e.y / 16) * 16 + 8
  local pick, last
  local i = 0
  while i < 3 do
    local dir = self:turn(dd, k)
    local d = STEP[rshift(dir, 3)]
    if self:free(tx + d[1] * 16, ty + d[2] * 16) then
      last = dir
      if e.direction - e.unk74 ~= dir - e.direction then pick = dir break end
    end
    k = (k + step + 3) % 3
    i = i + 1
  end
  pick = pick or last or e.direction
  if e.unk74 ~= e.direction then e.unk74 = e.direction end
  e.direction = pick
  local d = rshift(pick, 3)
  if d == 0 then e.target = e.y - 16 elseif d == 1 then e.target = e.x + 16
  elseif d == 2 then e.target = e.y + 16 else e.target = e.x - 16 end
end

-- sub_08029F48
local function reached(e)
  local d = rshift(e.direction, 3)
  if d == 0 and e.y <= e.target then e.y = e.target; e.y256 = e.y * 256 return true end
  if d == 1 and e.x >= e.target then e.x = e.target; e.x256 = e.x * 256 return true end
  if d == 2 and e.y >= e.target then e.y = e.target; e.y256 = e.y * 256 return true end
  if d == 3 and e.x <= e.target then e.x = e.target; e.x256 = e.x * 256 return true end
  return false
end

-- sub_08029FB4: record a step into the child's ring
local function record(e, child, dx, dy)
  if child then child.ring[e.counter % 14] = bor(band(dx + 8, 0xF), lshift(band(dy + 8, 0xF), 4)) end
end

-- sub_0802A098: the head's step
function M:headMove(e)
  e.counter = e.counter + 1
  if e.counter % 14 == 0 then e.counter = 0 end
  local x0, y0 = e.x, e.y
  local d = STEP[rshift(e.direction, 3)]
  e.x256, e.y256 = e.x256 + d[1] * e.speed, e.y256 + d[2] * e.speed
  e.x, e.y = math.floor(e.x256 / 256), math.floor(e.y256 / 256)
  if reached(e) then
    self:chooseDir(e)
    self:headAnim(e)
    self.field:sound(SFX_PLACE_OBJ)
  end
  record(e, e.segs[1], e.x - x0, e.y - y0)
end

-- sub_08029FE4: replay the step from 13 frames ago; true when the facing changed
function M:follow(e, s)
  local v = s.ring[(e.counter + 1) % 14]
  local dx, dy = band(v, 0xF) - 8, rshift(v, 4) - 8
  s.x, s.y = s.x + dx, s.y + dy
  s.anim:update(1)
  local st = 0xFF
  if dx ~= 0 then st = dx > 0 and 1 or 3 end
  if dy ~= 0 then st = dy > 0 and 2 or 0 end
  if st ~= 0xFF and st ~= s.animationState then s.animationState = st; return true, dx, dy end
  return false, dx, dy
end

function M:flicker(e, s) self:pal(s, self:flickerPal(band(rshift(e.unk7a or 0, 2), 3))) end

-- one body segment (types 1-5: sub_08029B90 .. sub_08029C6C)
function M:segment(e, s)
  local child = e.segs[s.type + 1]
  local a = s.action
  local function step()
    local turned, dx, dy = self:follow(e, s)
    if turned then self:setAnim(s, s.animationState + (s.type < 2 and 0 or 4)) end
    record(e, child, dx, dy)
  end
  if a == 1 then step()
  elseif a == 2 then
    s.action, s.timer, s.hitType = 3, self:wave(s.type), 0x6B
    child.action = 2
  elseif a == 3 then
    s.timer = s.timer - 1
    if s.timer == 0 then s.action = 4; self:pal(s, 0x7F); self.field:sound(SFX_MENU_CANCEL) end
  elseif a == 4 then
    if e.unk77 ~= 0 then s.action, s.hitType = 5, 0x6A end
  elseif a == 5 then
    step()
    if e.action ~= 3 then s.action = 1; self:pal(s, 0x77) else self:flicker(e, s) end
  end
end

-- the tail (type 6: sub_08029CCC .. sub_08029DE4)
function M:tailUpdate(e, s)
  local a = s.action
  local function move()
    local turned = self:follow(e, s)
    if turned then self:setAnim(s, s.animationState + 8) end
  end
  if a == 1 then move()
  elseif a == 2 then s.action, s.timer = 3, 71
  elseif a == 3 then
    if s.timer ~= 0 then
      s.timer = s.timer - 1
      if s.timer == 0 then
        self:setAnim(s, s.animationState + 0xC)
        self:pal(s, 0x7F)
        self.field:sound(SFX_MENU_CANCEL)
      end
    else
      s.anim:update(1)
      if s.anim.done then
        s.action, s.timer, s.hitType = 4, 120, 0x6C
        s.open = true
        self.field:sound(SFX_6B)
      end
    end
  elseif a == 4 then
    -- sub_0802A0F8: the health at 0 ends the fight
    if s.health <= 0 then
      e.dead, e.subtimer = true, 105
      return
    end
    s.timer = s.timer - 1
    if s.timer == 0 then
      s.action, s.hitType, s.open = 5, 0x6A, false
      self:setAnim(s, s.animationState + 0x10)
    end
  elseif a == 5 then
    s.anim:update(1)
    if s.anim.done then
      s.action = 6
      e.unk77 = 1
      self:setAnim(s, s.animationState + 8)
    end
  elseif a == 6 then s.action = 7
  elseif a == 7 then
    move()
    if e.action ~= 3 then s.action = 1; self:pal(s, 0x77) else self:flicker(e, s) end
  end
end

function M:update(e)
  local f = self.field
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  for _, s in ipairs(e.segs) do if s.iframes > 0 then s.iframes = s.iframes - 1 end end
  if e.dead then
    -- the segments blow up one by one (sub_08029B2C), the head after 105
    for t = 1, 6 do
      local s = e.segs[t]
      if not s.gone then
        if t == 6 then s.gone = true; f:addFx(s.x, s.y, SPECIAL_FX, FX_GIANT_EXPLOSION3)
        else
          s.boom = s.boom or (90 - t * 15)
          s.boom = s.boom - 1
          if s.boom <= 0 then s.gone = true; f:addFx(s.x, s.y, SPECIAL_FX, FX_GIANT_EXPLOSION3) end
        end
      end
    end
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 and not e.dying then self.en:kill(e) end
    return
  end
  -- the head (sub_08029A94 / sub_08029AA4 / sub_08029AE0)
  if e.action == 1 then
    e.anim:update(1)
    self:headMove(e)
  elseif e.action == 2 then
    if e.unk77 ~= 0 then
      e.action, e.speed, e.hitType, e.unk7a, e.unk75 = 3, 0x108, 0x6A, 0x168, 4
      self:headAnim(e)
      f:sound(SFX_19D)
    end
  elseif e.action == 3 then
    e.anim:update(1)
    self:flicker(e, e)
    self:headMove(e)
    e.unk7a = e.unk7a - 1
    if e.unk7a == 0 then
      e.action, e.speed, e.unk75 = 1, 0xA0, 0
      self:headAnim(e)
      self:pal(e, 0x77)
      f:sound(SFX_182)
    end
  end
  for t = 1, 5 do self:segment(e, e.segs[t]) end
  self:tailUpdate(e, e.tail)
  -- touching Link (the collision matrix: hit type vs the player)
  local p = f.player
  if p.state ~= "dead" and p.invuln == 0 then
    local function touch(x, y)
      return math.abs(x - p.x) < 12 and math.abs(y - (p.y - 3)) < 12
    end
    local hit = touch(e.x, e.y) and e or nil
    for _, s in ipairs(e.segs) do if not hit and touch(s.x, s.y) then hit = s end end
    if hit then
      local st = self.en:settings(hit.hitType or 0x6A, 0)
      local dmg = st and math.max(st.tgtDmg, 1) or 4
      if p:hurt(dmg, hit.x, hit.y) and st then
        p.invuln = math.max(st.orgIfr, 30)
        p.timer = math.max(st.orgKbDur, 4)
      end
    end
  end
end

-- the sword's box {x, y, w, h}: true when it landed
function M:swordHit(e, box)
  local f = self.field
  if e.dead then return false end
  local function over(x, y, hb)
    return math.abs((x + (hb.x or 0)) - box.x) < (hb.w or 8) + box.w and math.abs((y + (hb.y or 0)) - box.y) < (hb.h or 8) + box.h
  end
  local tail = e.tail
  if tail.open and tail.iframes == 0 and over(tail.x, tail.y, tail.openBox) then
    local st = self.en:settings(0x6C, 4)
    local dmg = st and st.orgDmg or 2
    tail.health = tail.health - math.max(dmg, 1)
    tail.iframes = (st and st.tgtIfr and st.tgtIfr > 0) and st.tgtIfr or 24
    -- the iframes go to the whole body (sub_0802A0F8)
    e.iframes = tail.iframes
    for _, s in ipairs(e.segs) do s.iframes = tail.iframes end
    f:sound(SFX_HIT)
    return true
  end
  if e.action == 1 and e.iframes == 0 and over(e.x, e.y, e.hitbox) then
    -- Madderpillar_OnCollision
    e.action, e.timer, e.hitType, e.unk77 = 2, 0, 0x6B, 0
    self:pal(e, 0x7F)
    f:sound(SFX_HIT)
    e.segs[1].action = 2
    return true
  end
  -- a clink on a hard segment (sub_0802A18C)
  for _, s in ipairs(e.segs) do
    if over(s.x, s.y, { w = 8, h = 8 }) then f:sound(SFX_12E) return false end
  end
  return false
end

local function drawOne(self, s, camX, camY)
  local frame = s.anim.frame
  if not frame or frame == 0xFF or not self.sprite then return end
  if s.iframes > 0 and s.iframes % 4 < 2 then return end
  local img, ox, oy = self.A:spriteFrame(self.sprite, frame, s.palette, "madder" .. (s.palId or 0), self.gfx)
  if not img then return end
  local x, y = math.floor(s.x - camX), math.floor(s.y - camY)
  if s.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
end

function M:draw(e, camX, camY)
  -- the tail at the back, the head in front (entity order)
  for t = 6, 1, -1 do local s = e.segs[t] if not s.gone then drawOne(self, s, camX, camY) end end
  if not e.dying then drawOne(self, e, camX, camY) end
end

return M
