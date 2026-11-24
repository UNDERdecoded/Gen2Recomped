-- Round 71: King Gustaf's hologram blend (kingGustaf.c, NPC KING_GUSTAF $42).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Init: spriteRendering.alphaBlend = 1 (a semi-transparent OBJ), layerFXControl $3F40 (blend, every layer a
--     second target), alphaBlend $1000 (EVA 0, EVB 16: not visible), this->speed = $1000, zVelocity = 0.
--   * Each frame after the script: s = ($100 * speed + zVelocity) >> 16, clamped to 4 .. 16;
--     alphaBlend = (s << 8) | (16 - s) (EVB = s, EVA = 16 - s); speed = alphaBlend.  The script's
--     SetEntityVelocity (zVelocity) moves s: -$8000 fades the hologram in by 1/2 a frame down to s = 4
--     (EVA 12 / EVB 4), +$10000 fades it out by 1 a frame.
--   * The OBJ is drawn as OBJ * EVA / 16 + below * EVB / 16; EVA + EVB = 16, so a plain alpha of EVA / 16.
-- The port draws the sprite with e.drawAlpha (Field's sprite draw).  Before this round it was drawn opaque.
local bit = require("bit")
local M = {}

local function s32(v)
  v = v or 0
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
M.s32 = s32

-- one frame of KingGustaf's blend (after its script ran); returns the alphaBlend value
function M.update(f, e)
  if not e.gustaf71 then
    e.gustaf71 = { speed = 0x1000 }
    e.zVelocity = e.zVelocity or 0
  end
  local g = e.gustaf71
  local s = math.floor((0x100 * g.speed + s32(e.zVelocity)) / 0x10000)
  if s > 0x10 then s = 0x10 end
  if s < 4 then s = 4 end
  local ab = bit.bor(bit.lshift(s, 8), 0x10 - s)
  g.speed = ab
  g.alphaBlend = ab
  e.drawAlpha = (0x10 - s) / 16
  return ab
end

return M
