-- Round 17: the element's glow and the white flash (src/object/fourElements.c,
-- src/object/elementsBackground.c).
--
-- CARTRIDGE BEHAVIOUR
--   * FourElements_Init creates ELEMENTS_BACKGROUND ($AD, type = element -
--     $40) under the element: frame 4 of its sprite (frameIndex 4, no
--     animation), OBJ priority 7 (under every other sprite), semi-transparent
--     (spriteRendering.alphaBlend), at the element's x / y with z 0.
--   * sub_080A04E8 each frame: affine scale s = |element z| + $100 (both
--     axes; $100 = 1x, so 0.57x while the element is at z -192, ~1x at the
--     bob), and BLDALPHA: EVA = ((($1C0 - s) * 10) / s), EVB = 16 - EVA (the
--     Earth / Fire / Ocean types; the Wind element ($41) caps EVA * 2 at 12
--     and keeps EVB = 16 - EVA) -- the glow fades in as the element comes
--     down.  BLDCNT $640: the OBJ over BG1 / BG2.
--   * Touched (FourElements_Action2): the background is deleted,
--     SetFade(FADE_BLACK_WHITE | FADE_INSTANT, 2): every palette goes to
--     white at once and fades back by 2/256 a frame (128 frames,
--     src/fade.c FadeMain / sub_080501C0); FourElements_Action4 waits for
--     the fade before Action5's $1A4 frames, so the item text comes 128 +
--     $1A4 frames after the touch (Action3's 45 frames end inside the fade).
local bit = require("bit")
local Assets = require("src.zelda.tmc.Assets")

local FX = {}
FX.ELEMENTS_BACKGROUND = 0xAD
FX.FADE_FRAMES = 128

-- s and EVA (0..16) for an element at height z (z > 0 is up in the port)
function FX.blend(z, type_)
  local s = math.abs(z) + 0x100
  local eva = math.floor(((0x1C0 - s) * 10) / s)
  if type_ == 0x41 then eva = math.min(12, eva * 2) end
  if eva < 0 then eva = 0 end
  if eva > 16 then eva = 16 end
  return s, eva
end

local function drawBg(bg, field, camX, camY)
  local el = bg.parent
  if not el or el.deleted or el.got then return end
  local A = field.assets
  local img, ox, oy = A:spriteFrame(bg.sprite, 4, bg.palette, "elementsBg", bg.gfx)
  if not img then return end
  local s, eva = FX.blend(el.z or 0, el.form)
  bg.scale, bg.eva = s, eva
  if eva <= 0 then return end
  local w, h = img:getWidth(), img:getHeight()
  local f = 256 / s
  local x, y = math.floor(bg.x - camX), math.floor(bg.y - camY)
  -- an affine OBJ scales about its centre
  love.graphics.setColor(1, 1, 1, eva / 16)
  love.graphics.draw(img, x + ox + w / 2, y + oy + h / 2, 0, f, f, w / 2, h / 2)
  love.graphics.setColor(1, 1, 1, 1)
end

-- the background object under the element entity `e` (once)
function FX.attach(d, e)
  if e.elementBg ~= nil then return e.elementBg end
  local f = d.field
  local objs = f:objects()
  local def = objs:def(FX.ELEMENTS_BACKGROUND, (e.form or 0x40) - 0x40)
  if not def or not def.sprite then e.elementBg = false return false end
  local bg = { kind = 6, id = FX.ELEMENTS_BACKGROUND, form = (e.form or 0x40) - 0x40, x = e.x, y = e.y, z = 0,
               parent = e, spritePriority = 7, elementBg = true, literalAnim = true, objAnim = 0, anim = require("src.zelda.tmc.Anim").new(),
               sprite = def.sprite, gfx = Assets.gfxSource(def.gfxType, def.gfx), layer = e.layer,
               palette = f.assets:objPalette(def.palette, f.room.atlas and f.room.atlas.palettes) }
  bg.drawGhost = function(self, field, camX, camY) drawBg(self, field, camX, camY) end
  f.entities[#f.entities + 1] = bg
  e.elementBg = bg
  return bg
end

-- the touch: the background goes, the white flash starts
function FX.touched(d, e)
  local bg = e.elementBg
  if bg then bg.deleted = true end
  local f = d.field
  f.fadeLevel = 1          -- FADE_INSTANT: full white at once
  f:fade("in", true, 2)    -- then back by 2/256 a frame
end

return FX
