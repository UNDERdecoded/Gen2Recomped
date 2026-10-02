-- Camera centered on the player.  At the default 160x144 view this is
-- the original framing (player sprite at screen tile (8,8) -> pixel
-- (64, 60) after the -4px sprite offset); wider/taller world-pass views
-- (window-filling survey on phones, wheel zoom-out) keep the player at
-- the same relative center.

local Camera = {}
Camera.__index = Camera

function Camera.new()
  return setmetatable({ x = 0, y = 0 }, Camera)
end

-- ...AND ON A GROUND THAT IS FORESHORTENED, THE VERTICAL HALF IS NOT THE ONE
-- THE SCREEN ASKS FOR.
--
-- A Gen 4 map is drawn at a pitch, so a map pixel of DEPTH is `sin(pitch)`
-- screen pixels -- and the walker is drawn at `(py - cam.y) * sin` too (see
-- `riseOf`).  Centring on `py - (viewH/2 - 8)` therefore puts the player at
-- `(viewH/2 - 8) * sin` down the screen rather than at `viewH/2 - 8`: at
-- Twinleaf's 59 degrees that is 75 pixels instead of 88, and the lower the
-- pitch the further off it gets.  Reported from play: *"my player isn't
-- centered on the screen"*.
--
-- Dividing by the same scale is the whole correction, and it cancels exactly:
-- the player ends at `((viewH/2 - 8) / sin) * sin`.
--
-- `groundScale` is nil on every other generation and defaults to 1, so Gen 1,
-- Gen 2, Gen 3 and every hack of them keep the framing they had, to the pixel.
function Camera:follow(px, py, viewW, viewH)
  viewW, viewH = viewW or 160, viewH or 144
  local sin = tonumber(self.groundScale) or 1
  if not (sin > 0) then sin = 1 end
  local centerX = self.spriteCenterX or 16
  local centerY = self.spriteCenterY or 8
  self.x = px + centerX - viewW / 2
  self.y = py - (viewH / 2 - centerY) / sin
end

return Camera
