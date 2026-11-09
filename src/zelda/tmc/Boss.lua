-- Deepwood Shrine's two bosses, simplified from src/enemy/madderpillar.c
-- (645 lines) and src/enemy/chuchuBoss.c (1857 lines).  What is kept: the
-- rules that decide how the fight is won, the cartridge's sprites, the
-- collision matrix for touching Link, and the fight managers that wrap
-- them (their completion flags open doors and spawn the heart container).
--
-- MADDERPILLAR ($18): a head trailing six segments around the room; only
--   the tail segment is hurt by the sword (its health reaching 0 kills the
--   head, madderpillar.c around line 536); hit, the body curls up and stops
--   for a moment.  Tail health 8 = four Smith's Sword hits.
-- BIG GREEN CHUCHU ($13): hops towards Link; the Gust Jar held on its base
--   for 60 frames topples it; while it lies stretched (150 frames) sword
--   hits land; three topples' worth of hits (health 12) finish it.

local bit = require("bit")
local band = bit.band
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local Boss = {}
Boss.__index = Boss
Boss.MADDERPILLAR, Boss.CHUCHU_BOSS = 0x18, 0x13

function Boss.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, Boss)
end

function Boss:make(dat, def, health)
  local e = {
    kind = 3, id = dat.id, form = dat.paramA, x = dat.x, y = dat.y, z = 0, zv = 0, boss = true, enemy = true,
    health = health, hitType = def and def.damageType or 25, hitbox = def and def.hitbox or { x = 0, y = 0, w = 10, h = 10 },
    sprite = def and def.sprite, palette = self.A:objPalette(def and def.palette or 0, self.field.room.atlas and self.field.room.atlas.palettes),
    gfx = def and Assets.gfxSource("enemy", def.gfx), anim = Anim.new(), literalAnim = true, animationState = 4,
    action = 0, timer = 30, iframes = 0, kbt = 0, kbx = 0, kby = 0, field82 = 0, interactType = 0, def = def or {},
  }
  e.anim:set(e.sprite and self.A:sprite(e.sprite), 0, true)
  return e
end

function Boss:spawn(dat, def)
  if dat.id == Boss.MADDERPILLAR then
    local e = self:make(dat, def, 8)
    e.trail = {}
    for i = 1, 6 * 8 do e.trail[i] = { e.x, e.y } end
    e.dir = 2
    return e
  elseif dat.id == Boss.CHUCHU_BOSS then
    local e = self:make(dat, def, 12)
    e.hitbox = { x = 0, y = -8, w = 16, h = 12 }
    e.gust = 0
    return e
  end
  return nil
end

local DIRS = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

function Boss:update(e)
  local f = self.field
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if e.id == Boss.MADDERPILLAR then
    if e.curl and e.curl > 0 then e.curl = e.curl - 1
    else
      -- walk the grid; turn at walls and at random tile corners
      local d = DIRS[e.dir]
      local nx, ny = e.x + d[1] * 1, e.y + d[2] * 1
      local blocked = f.room:isSolid(nx + d[1] * 8, ny + d[2] * 8, 1)
      if blocked or (e.x % 16 == 8 and e.y % 16 == 8 and math.random(0, 5) == 0) then
        e.dir = (e.dir + (math.random(0, 1) == 0 and 1 or 3)) % 4
      else
        e.x, e.y = nx, ny
        table.insert(e.trail, 1, { e.x, e.y })
        e.trail[#e.trail] = nil
      end
    end
    e.anim:update(1)
  else
    local p = f.player
    -- the Gust Jar on its base (Link facing it, close, sucking)
    if e.down then
      e.down = e.down - 1
      if e.down <= 0 then e.down = nil e.gust = 0 end
    elseif p.state == "gust" and math.abs(p.x - e.x) < 48 and math.abs(p.y - e.y) < 48 then
      e.gust = e.gust + 1
      if e.gust >= 60 then e.down = 150 f:sound(0x18A) end
    else
      e.gust = math.max(0, e.gust - 1)
      e.timer = e.timer - 1
      if e.timer <= 0 and e.z == 0 then
        e.timer = 50
        e.zv = 2.5
        local dx, dy = p.x - e.x, p.y - e.y
        local dd = math.max(1, math.sqrt(dx * dx + dy * dy))
        e.vx, e.vy = dx / dd * 1.2, dy / dd * 1.2
      end
      if e.zv ~= 0 or e.z > 0 then
        e.z = e.z + e.zv
        e.zv = e.zv - 0.125
        local nx, ny = e.x + (e.vx or 0), e.y + (e.vy or 0)
        if not f.room:isSolid(nx, ny, 1) then e.x, e.y = nx, ny end
        if e.z <= 0 then e.z, e.zv = 0, 0 f:sound(0x82) end
      end
    end
    e.anim:update(1)
  end
  -- touching Link
  local p = f.player
  if p.state ~= "dead" and p.invuln == 0 and (e.z or 0) < 8 then
    local touch = math.abs(e.x - p.x) < 14 and math.abs(e.y - p.y) < 12
    if e.trail and not touch then
      for i = 8, #e.trail, 8 do
        local s = e.trail[i]
        if math.abs(s[1] - p.x) < 10 and math.abs(s[2] - p.y) < 10 then touch = true break end
      end
    end
    if touch then p:hurt(4, e.x, e.y) end
  end
end

-- the sword hits the box {x, y, w, h}; true when it landed
function Boss:swordHit(e, box)
  local f = self.field
  if e.iframes > 0 then return false end
  if e.id == Boss.MADDERPILLAR then
    local tail = e.trail[#e.trail]
    if math.abs(tail[1] - box.x) < 8 + box.w and math.abs(tail[2] - box.y) < 8 + box.h then
      e.health = e.health - 2
      e.iframes = 30
      e.curl = 60
      f:sound(0xFE)
      if e.health <= 0 then self.en:kill(e) end
      return true
    end
    if math.abs(e.x - box.x) < 10 + box.w and math.abs(e.y - box.y) < 10 + box.h then
      f:sound(0x118) -- clink off the head
    end
    return false
  end
  if e.down and math.abs(e.x - box.x) < 16 + box.w and math.abs((e.y - 8) - box.y) < 14 + box.h then
    e.health = e.health - 2
    e.iframes = 20
    f:sound(0xFE)
    if e.health <= 0 then self.en:kill(e) end
    return true
  end
  return false
end

function Boss:draw(e, camX, camY)
  local A = self.A
  local frame = e.anim.frame
  if not e.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "boss" .. e.id, e.gfx)
  if not img then return end
  if e.iframes > 0 and e.iframes % 4 < 2 then return end
  if e.trail then
    for i = #e.trail, 8, -8 do
      local s = e.trail[i]
      love.graphics.draw(img, math.floor(s[1] - camX + ox), math.floor(s[2] - camY + oy))
    end
  end
  local sy = e.down and 0.6 or 1
  love.graphics.draw(img, math.floor(e.x - camX + ox), math.floor(e.y - camY - (e.z or 0) + oy * sy), 0, 1, sy)
end

local _ = band
return Boss
