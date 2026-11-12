-- Link's items in use (src/playerItem/*.c).
--
-- SWORD (playerItemSword.c): the swing is Link's own sword animation; the
-- blade sprite is drawn by Player:drawSword.
--   * each keyframe's flags & $F (1-based) pick a tile probe from
--     gUnk_08129072 ({x, y}, x mirrored when the frame is flipped) and the
--     tile there gets DoTileInteraction(filter 0): grass and bushes are cut
--     (sub_080A7A84);
--   * the sword's hitbox for Link's current sprite frame is
--     gUnk_08129096[frameIndex - $6A] ({x, y, w, h}, half extents)
--     (sub_080A7A54); enemies inside take the collision matrix's damage.
-- GUST JAR: GustJar.lua (round 13, itemGustJar.c / playerItemGust*.c).

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
  -- round 11: Minish Link's swing (itemSword.c sub_08075338, PL_MINISH)
  -- creates no PLAYER_ITEM_SWORD: no tile probe, no hitbox
  if p.minish then return end
  -- bug round: the probe mirrors on Link's entity flipX (facing left,
  -- sub_080A7A84), not on the keyframe flip, which is set for both sides
  -- (cutting to the right probed the left); the hitbox table already has
  -- the side frames facing left, so it mirrors only for a right swing
  local flip = p.entFlip or false
  local boxFlip = flip ~= (band(p.animationState or 0, 2) ~= 0)
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
    local bx = boxFlip and -b[1] or b[1]
    self.field:enemies():swordHits({ x = p.x + bx, y = p.y + b[2], w = b[3], h = b[4] })
    self.field.swordBoxNow = { x = p.x + bx, y = p.y + b[2], w = b[3], h = b[4], t = self.field.frame } -- round 22: objects hit by the sword (LightableSwitch)
  end
end

-- round 13: the Gust Jar is GustJar.lua (ported from the decomp; the
-- round-2 cone is gone)
function Items:gustStart(p) require("src.zelda.tmc.GustJar").start(self.field, p) end
function Items:gustFrame(p) require("src.zelda.tmc.GustJar").frame(self.field, p) end
function Items:gustRelease(p) require("src.zelda.tmc.GustJar").release(self.field, p) end

return Items
