-- Usable window rect for mobile chrome (notch / Dynamic Island / home
-- indicator / Android display cutouts).  Wraps love.window.getSafeArea when
-- the engine provides it; otherwise the full graphics window.
--
-- Desktop and headless stubs return the full window, so callers can always
-- layout against this rect without platform branches.  Interactive chrome
-- (touch overlay, launcher) should prefer this over getDimensions; the game
-- canvas may still letterbox into the full framebuffer for immersion.

local SafeArea = {}

function SafeArea.rect()
  local ww, wh = 0, 0
  if love and love.graphics and love.graphics.getDimensions then
    ww, wh = love.graphics.getDimensions()
  end
  if ww <= 0 then ww = 1 end
  if wh <= 0 then wh = 1 end

  if not (love and love.window and love.window.getSafeArea) then
    return 0, 0, ww, wh
  end

  local x, y, w, h = love.window.getSafeArea()
  if type(x) ~= "number" or type(y) ~= "number"
     or type(w) ~= "number" or type(h) ~= "number"
     or w <= 0 or h <= 0 then
    return 0, 0, ww, wh
  end

  -- Clamp to the drawable window so a bad / mid-rotation backend cannot
  -- push layout outside the surface.
  x = math.max(0, math.min(x, ww))
  y = math.max(0, math.min(y, wh))
  w = math.max(1, math.min(w, ww - x))
  h = math.max(1, math.min(h, wh - y))
  return x, y, w, h
end

return SafeArea
