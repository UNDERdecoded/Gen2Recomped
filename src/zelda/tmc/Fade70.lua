-- Round 70: the fade mask (script SetFadeMask, gFadeControl.mask: bits 0-15 the BG palettes, 16-31 the OBJ
-- palettes that a fade touches).
--
-- CARTRIDGE BEHAVIOUR
--   * script_KingGustafHologram (Lake Hylia after the Temple of Droplets): SetFadeMask $00007FFF, SetFade5 -- the BG
--     palettes 0-14 fade to black while the OBJ palettes (King Gustaf's hologram, Link) and BG palette 15 (the
--     text window) keep their colours; then SetFadeMask $FFFFFFFF, SetFade4 brings everything back.
--   * The port faded the whole screen (the textbox too): TEXT_GUSTAF 1 / 2 were read on a black screen.
-- PORTED: Script C[$39] keeps the mask (Field.fadeMask70, for the room it was set in); while the mask leaves every
--   OBJ palette out, the fade is drawn in the world pass between the BG layers and the sprites (Priority.compose)
--   and not over the HUD / text (Field:drawOverlay).
-- SIMPLIFIED: during such a fade the sprites are drawn after all BG layers (a BG of a higher priority does not cover
--   them); a mask with only some OBJ or BG palettes is treated as all / none.
local bit = require("bit")
local band = bit.band

local M = {}

-- the BG-only case (no OBJ palette in the mask, some BG palette in it), set in this room
function M.maskBgOnly(m)
  if not m then return false end
  return band(m, 0xFFFF0000) == 0 and band(m, 0xFFFF) ~= 0
end
function M.bgOnly(f)
  if not f or f.fadeMask70Room ~= f.room then return false end
  return M.maskBgOnly(f.fadeMask70)
end

-- Priority.compose hook: nil = compose as usual
function M.compose(f, r, opts, P)
  if (opts and (opts.noSprites or opts.f70)) or not M.bgOnly(f) or (f.fadeLevel or 0) <= 0 then return nil end
  local g = love.graphics
  P.compose(f, r, { noSprites = true, f70 = true })
  local c = f.fadeWhite and 1 or 0
  g.setColor(c, c, c, f.fadeLevel)
  g.rectangle("fill", -4096, -4096, 8192, 8192) -- (whatever transform the world pass draws with)
  g.setColor(1, 1, 1, 1)
  local list = f:drawEntities("sort")
  local buckets = { [0] = {}, {}, {}, {} }
  for _, e in ipairs(list) do local b = buckets[P.oam(e)] or buckets[2]; b[#b + 1] = e end
  for p = 3, 0, -1 do if #buckets[p] > 0 then f:drawSpriteList(buckets[p]) end end
  return list
end

return M
