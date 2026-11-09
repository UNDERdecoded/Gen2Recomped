-- Link's items in use (src/playerItem/*.c).
--
-- SWORD (playerItemSword.c): the swing is Link's own sword animation.
--   * each keyframe's flags & $F (1-based) pick a tile probe from
--     gUnk_08129072 ({x, y}, x mirrored when the frame is flipped) and the
--     tile there gets DoTileInteraction(filter 0): grass and bushes are cut
--     (sub_080A7A84);
--   * the sword's hitbox for Link's current sprite frame is
--     gUnk_08129096[frameIndex - $6A] ({x, y, w, h}, half extents)
--     (sub_080A7A54); enemies inside take the collision matrix's damage.
-- GUST JAR (playerItemGustJar.c, simplified): while held, tiles 16 and 32
--   px ahead get DoTileInteraction(filter 5) (dust, gust-able leaves),
--   enemies ahead are pulled in and stunned; a small one that reaches Link
--   is caught, and blown out on release as a shot that hits the first
--   enemy in line.

local bit = require("bit")
local band = bit.band

local Items = {}
Items.__index = Items

function Items.new(field)
  return setmetatable({ field = field, m = field.assets.manifest }, Items)
end

function Items:swordStart(p)
  p.swordProbed = {}
  self.field:sound(0x75) -- SFX_PLY_VO1, Link's swing cry
end

function Items:swordFrame(p)
  local sw = self.m.sword
  if not sw then return end
  local flip = p.anim:hflip()
  -- tile probe
  local fl = band(p.anim.flags or 0, 0xF)
  if fl ~= 0 and not p.swordProbed[p.anim.key] then
    p.swordProbed[p.anim.key] = true
    local pr = sw.probes[fl - 1]
    if pr then
      local px = flip and -pr[1] or pr[1]
      self.field:objects():cut(p.x + px, p.y + pr[2], p.layer)
    end
  end
  -- hitbox
  local fi = p.anim.frame
  local b = fi and sw.boxes[fi - 0x6A]
  if b and b[3] > 0 then
    local bx = flip and -b[1] or b[1]
    self.field:enemies():swordHits({ x = p.x + bx, y = p.y + b[2], w = b[3], h = b[4] })
  end
end

function Items:gustStart(p)
  p.gustCaught = nil
  self.field:sound(0x14B) -- SFX_14B
end

function Items:gustFrame(p)
  local f = self.field
  p.timer = (p.timer or 0) + 1
  for _, d in ipairs({ 16, 32 }) do
    local x, y = p:frontPoint(d)
    if p.timer % 8 == 0 then f:objects():tileInteraction(5, x, y + 2, p.layer) end
  end
  -- light objects in front slide towards the jar (pots: the gustJarFlags
  -- objects); they stop a tile short of Link
  local s = p.animationState
  local ax = (s == 2 and 1) or (s == 6 and -1) or 0
  local ay = (s == 4 and 1) or (s == 0 and -1) or 0
  for _, o in ipairs(f.entities) do
    if o.liftable and not o.deleted then
      local dx, dy = o.x - p.x, o.y - p.y
      local along = dx * ax + dy * ay
      local side = math.abs(dx * ay) + math.abs(dy * ax)
      if along > 14 and along < 64 and side < 10 then
        local nx, ny = o.x - ax, o.y - ay
        if not f.room:isSolid(nx - ax * 6, ny - ay * 6, 1) then o.x, o.y = nx, ny end
      end
    end
  end
  if not p.gustCaught then
    local cx, cy = p:frontPoint(24)
    local caught = f:enemies():gustPull(p, cx, cy, 24)
    if caught then
      caught.deleted = true
      p.gustCaught = caught
      f:sound(0xFE)
    end
  end
end

function Items:gustRelease(p)
  local e = p.gustCaught
  p.gustCaught = nil
  if not e then return end
  -- blown out: the first enemy in line within 64 px takes the hit, the
  -- caught one is finished either way
  local f = self.field
  local done = false
  for d = 8, 64, 8 do
    local x, y = p:frontPoint(d)
    for _, o in ipairs(f.entities) do
      if o.enemy and not o.dying and math.abs(o.x - x) < 10 and math.abs(o.y - y) < 10 then
        f:enemies():hit(o, 4, p.x, p.y, 2)
        done = true
        break
      end
    end
    if done then break end
  end
  e.deleted = false
  e.x, e.y = p:frontPoint(16)
  f.entities[#f.entities + 1] = e
  f:enemies():kill(e)
end

return Items
