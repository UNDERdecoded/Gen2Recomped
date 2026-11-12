-- Round 8: Gleerok (enemy $24, src/enemy/gleerok.c, gleerokProjectile.c),
-- SIMPLIFIED.  The cartridge's 1588 lines drive a head on a five-segment
-- neck whose shape comes from per-segment angles (sub_0802E7E4 /
-- sub_0802EB08), a shell drawn on BG1, a plug on the shell the Cane of
-- Pacci knocks out (contact $1D, type 3 -> 4 -> particles) and Link riding
-- the neck (field_0x14 / spriteOffsetY).  What this port keeps:
--   - the parts and their cartridge art: head (type 0, animation $4C),
--     neck segments (type 1, $24), the neck's root (type 2, sprite
--     GLEEROK_0), the plug (type 3, $4F); palettes $C9 / $CA (hit flash);
--   - Gleerok_OnTick's frame: Link held still on arrival, placed at
--     origin + ($98, $D8) facing up, the camera on the boss;
--   - the fight's rules: the head breathes lobbed fireballs at Link
--     (GLEEROK_PROJECTILE type 0: animation $51, SFX_1B5, aimed with the
--     lob gUnk sub_080041DC; phase 2 adds type-1 spread shots); after its
--     breaths it tires and lays its neck across the lava to the platform
--     (Link may walk on the segments: field_0x14); the Cane's bolt on the
--     plug knocks it out (SFX_BUTTON_PRESS, zVelocity 3.0); with the plug
--     out the sword on the exposed core (the plug's spot) hurts it; the
--     neck pulls back after a while, the plug grows back (types 5 / 6 / 3).
--     Two phases of 4 core hits; then OnDeath type 0 (SFX_BOSS_DIE, the
--     neck segments explode one by one, FX_GIANT_EXPLOSION3) and the fight
--     manager's flag (the Fire Element and the heart container follow from
--     the room's lists, as in Deepwood).
-- What is NOT the cartridge's: the neck's motion (a sway around the root
-- instead of the angle chain), the timings of the phases, the core's hit
-- count, and the shell's BG1 animation.
local bit = require("bit")
local band = bit.band
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local G = {}
G.__index = G
G.ID = 0x24

local SFX_FIRE, SFX_BOSS_DIE, SFX_BUTTON_PRESS, SFX_HIT, SFX_150 = 0x1B5, 0x128, 0x10C, 0xFE, 0x150
local FX_GIANT_EXPLOSION3 = 0x48
local CORE_HITS = 4

function G.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, G)
end

local function part(self, form, anim)
  local en = self.en
  local d = en:def(G.ID, form) or {}
  local p = { form = form, sprite = d.sprite, anim = Anim.new(), x = 0, y = 0, z = 0,
              gfx = Assets.gfxSource("enemy", d.gfx or 0), palId = d.palette or 0xC9 }
  p.palette = self.A:objPalette(p.palId, self.field.room.atlas and self.field.room.atlas.palettes)
  if p.sprite then p.anim:set(self.A:sprite(p.sprite), anim, true) end
  p.animIndex = anim
  return p
end

function G:spawn(dat, def)
  local f = self.field
  if f:flag("global", 0x03) then return nil end -- LV2_CLEAR: gone (sub_0802D3B8)
  local e = {
    kind = 3, id = dat.id, form = 0, x = dat.x, y = dat.y, z = 0, boss = true, enemy = true, impl = self,
    health = 255, hitType = def and def.damageType or 63, hitbox = { x = 0, y = 0, w = 10, h = 10 },
    def = def or {}, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, iframes = 0,
    action = 0, timer = 60, phase = 1, hits = 0, breaths = 0, layer = 1,
  }
  -- type 0 is the shell (the body, fixed in the lava), type 2 the head at
  -- the neck's end (ent2), the plug (type 3) sits on the shell
  e.rootX, e.rootY = dat.x, dat.y
  e.root = part(self, 0, 0x4C)
  e.neck = {}
  for i = 1, 5 do e.neck[i] = part(self, 1, 0x24) end
  e.head = part(self, 2, 0)
  e.plug = part(self, 3, 0x4F)
  e.plugIn = true
  e.sprite = e.head.sprite -- (Field draws entities that have one)
  e.headX, e.headY = dat.x, dat.y + 72
  -- sub_0802D170: Link onto the platform, facing up, held until the boss rises
  local p = f.player
  p.x, p.y, p.animationState = 0x98, 0xD8, 0
  self:layout(e)
  return e
end

-- the neck from the root to the head
function G:layout(e)
  local hx, hy = e.headX, e.headY
  e.head.x, e.head.y = hx, hy
  for i = 1, 5 do
    local t = i / 6
    local n = e.neck[i]
    n.x = hx + (e.rootX - hx) * t
    n.y = hy + (e.rootY - hy) * t + (e.tired and 0 or math.sin(t * math.pi) * -6)
  end
  e.root.x, e.root.y = e.rootX, e.rootY
  e.plug.x, e.plug.y = e.rootX, e.rootY
  e.x, e.y = hx, hy
end

function G:fire(e, spread)
  local f = self.field
  local defs = f.assets.manifest.projectileDefs
  local d = defs and defs[0x0A]
  if d and d.multi then d = d.forms[0] end
  if not d then return end
  local p = f.player
  for k = -spread, spread do
    local dx, dy = p.x - e.head.x, p.y - e.head.y
    local ang = math.atan2(dy, dx) + k * 0.35
    local dist = math.max(32, math.sqrt(dx * dx + dy * dy))
    local frames = math.max(20, math.floor(dist / 2))
    local s = { kind = 8, id = 0x0A, x = e.head.x, y = e.head.y, z = 16, vx = math.cos(ang) * dist / frames, vy = math.sin(ang) * dist / frames,
                t = frames, sprite = d.sprite, gfx = Assets.gfxSource("enemy", d.gfx or 0),
                palette = self.A:objPalette(d.palette or 0xC9, f.room.atlas and f.room.atlas.palettes),
                anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, layer = 1 }
    if (d.gfx or 0) == 0 then s.gfx, s.palette = e.head.gfx, e.head.palette end
    s.zv = (16 / frames) * 0 + 1.5
    s.anim:set(self.A:sprite(s.sprite), 0x51, true)
    s.objAnim, s.animIndex = 0x51, 0x51
    s.extUpdate = function(_, me) G.updateFire(f, me) end
    s.drawGhost = function(me, _, camX, camY) G.drawPart(f, me, camX, camY) end
    f.entities[#f.entities + 1] = s
    f._dungeon:track(s)
  end
  f:sound(SFX_FIRE)
end

function G.updateFire(f, s)
  s.anim:update(1)
  if s.landed then
    if s.anim.done then s.deleted = true end
    return
  end
  s.x, s.y = s.x + s.vx, s.y + s.vy
  s.t = s.t - 1
  s.z = math.max(0, 16 * s.t / math.max(1, s.t + 1) * (s.t / 30))
  local p = f.player
  if s.t <= 0 then
    s.landed = true
    s.z = 0
    s.anim:set(f.assets:sprite(s.sprite), 0x53, true)
    s.objAnim, s.animIndex = 0x53, 0x53
    if math.abs(p.x - s.x) < 10 and math.abs(p.y - s.y) < 10 and p.invuln == 0 then p:hurt(4, s.x, s.y) end
  end
end

function G.drawPart(f, s, camX, camY)
  local frame = s.anim.frame
  if not s.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(s.sprite, frame, s.palette, "gleerok" .. s.sprite, s.gfx)
  if not img then return end
  local x, y = math.floor(s.x - camX), math.floor(s.y - camY - (s.z or 0))
  if s.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

local function setAnim(self, pt, idx)
  if pt.animIndex ~= idx then pt.animIndex = idx; pt.anim:set(self.A:sprite(pt.sprite), idx, true) end
end

function G:update(e)
  local f = self.field
  local p = f.player
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  for _, pt in ipairs({ e.head, e.root, e.plug }) do pt.anim:update(1) end
  for i = 1, 5 do e.neck[i].anim:update(1) end
  -- the hit flash: palette $CA while iframes run
  local pal = e.iframes > 0 and 0xCA or 0xC9
  if pal ~= e.palNow then
    e.palNow = pal
    local P = self.A:objPalette(pal, f.room.atlas and f.room.atlas.palettes)
    e.head.palette = P
    for i = 1, 5 do e.neck[i].palette = P end
  end
  if e.dyingG then return self:death(e) end
  e.timer = e.timer - 1
  local a = e.action
  if a == 0 then
    -- rising: Link held still
    p.state, p.extUpdate = "ext", function() end
    e.headY = e.y
    if e.timer <= 0 then
      p.state, p.extUpdate, p.animId = "normal", nil, -1
      e.action, e.timer = 1, 90
    end
  elseif a == 1 then
    -- swaying, breathing fire
    local t = (e.swayT or 0) + 1
    e.swayT = t
    e.headX = e.rootX + math.sin(t / 40) * 56
    e.headY = e.rootY + 56 + math.cos(t / 27) * 10
    if e.timer <= 0 then
      e.breaths = e.breaths + 1
      self:fire(e, e.phase == 2 and 1 or 0)
      e.timer = e.phase == 2 and 70 or 100
      if e.breaths >= (e.phase == 2 and 5 or 3) then e.action, e.timer = 2, 60 end
    end
  elseif a == 2 then
    -- tired: the head comes down onto the platform's edge
    e.tired = true
    local tx, ty = e.rootX, e.rootY + 0x40
    e.headX = e.headX + (tx - e.headX) * 0.08
    e.headY = e.headY + (ty - e.headY) * 0.08
    if e.timer <= 0 then e.action, e.timer = 3, e.phase == 2 and 300 or 360; f:sound(SFX_150) end
  elseif a == 3 then
    -- lying: the neck is a bridge, the plug can be knocked out
    if e.timer <= 0 then
      e.tired = nil
      e.action, e.timer, e.breaths = 1, 90, 0
      if not e.plugIn then e.plugIn = true; e.plug.z = 0; setAnim(self, e.plug, 0x4F) end
    end
  end
  self:layout(e)
  -- Link on the neck (field_0x14): the lava under it holds him
  f.bossSupport = function(x, y)
    if e.action ~= 3 or e.deleted then return false end
    if math.abs(e.head.x - x) < 12 and math.abs(e.head.y - y) < 12 then return true end
    for i = 1, 5 do
      local n = e.neck[i]
      if math.abs(n.x - x) < 10 and math.abs(n.y - y) < 10 then return true end
    end
    return math.abs(e.root.x - x) < 16 and math.abs(e.root.y - y) < 14
  end
  -- the Cane's bolt on the plug (contact $1D)
  if e.plugIn and e.action == 3 then
    for _, o in ipairs(f.entities) do
      if o.bolt and not o.deleted and o.action == 1 and math.abs(o.x - e.plug.x) < 10 and math.abs(o.y - e.plug.y) < 10 then
        e.plugIn = false
        e.plug.zv = 3
        f:sound(SFX_BUTTON_PRESS)
        o.life = 0
      end
    end
  end
  if not e.plugIn and e.plug.zv then
    e.plug.z = e.plug.z + e.plug.zv
    e.plug.zv = e.plug.zv - 0.1875
    if e.plug.z <= 0 then e.plug.z, e.plug.zv = 0, nil; e.plugGone = true end
  end
  -- touching the head hurts Link
  if p.invuln == 0 and e.action ~= 3 and math.abs(e.head.x - p.x) < 12 and math.abs(e.head.y - p.y) < 10 then p:hurt(4, e.head.x, e.head.y) end
end

-- the sword: the exposed core only
function G:swordHit(e, box)
  if e.dyingG or e.iframes > 0 or e.plugIn or e.action ~= 3 then return false end
  if math.abs(e.plug.x - box.x) < 10 + box.w and math.abs(e.plug.y - box.y) < 10 + box.h then
    local f = self.field
    e.hits = e.hits + 1
    e.iframes = 30
    f:sound(SFX_HIT)
    if e.hits >= CORE_HITS then
      e.hits = 0
      if e.phase == 1 then
        e.phase = 2
        e.tired, e.action, e.timer, e.breaths = nil, 1, 60, 0
        e.plugIn = true; setAnim(self, e.plug, 0x4F)
      else
        e.dyingG, e.dieT = true, 0
        f:sound(SFX_BOSS_DIE)
      end
    end
    return true
  end
  return false
end

-- OnDeath (type 0): the segments blow up one by one, then the fight ends
function G:death(e)
  local f = self.field
  e.dieT = e.dieT + 1
  local p = f.player
  if e.dieT == 1 then p.state, p.extUpdate = "ext", function() end end
  if e.dieT % 16 == 0 then
    local i = 6 - math.floor(e.dieT / 16)
    local n = e.neck[i]
    if n and not n.gone then n.gone = true; f:addFx(n.x, n.y, 0x0F, FX_GIANT_EXPLOSION3) end
  end
  -- type 2's OnDeath: SFX_EVAPORATE and BG1 (the lava) blends away
  -- (alphaBlend $10 -> $1000, one step every 16 frames), SFX_APPARATE
  if e.dieT == 120 then f:sound(0xF6) end
  if e.dieT >= 120 then f.room.topAlpha = math.max(0, 1 - (e.dieT - 120) / 256) end
  if e.dieT >= 376 then
    f.room.topUnder, f.room.hideTop, f.room.topAlpha = nil, true, nil
    p.state, p.extUpdate, p.animId = "normal", nil, -1
    f.bossSupport = nil
    e.dyingG = nil
    self.en:kill(e)
  end
end

function G:draw(e, camX, camY)
  local f = self.field
  if e.iframes > 0 and e.iframes % 4 < 2 then return end
  G.drawPart(f, e.root, camX, camY)
  if not e.plugGone or e.plugIn then G.drawPart(f, e.plug, camX, camY) end
  for i = 5, 1, -1 do if not e.neck[i].gone then G.drawPart(f, e.neck[i], camX, camY) end end
  G.drawPart(f, e.head, camX, camY)
end

local _ = band
return G
