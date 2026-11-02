-- A PIXEL PICTURE DRAWN SMALLER WITHOUT LOSING ITS EDGES.
--
-- Shrinking pixel art straight to 0.7 with nearest filtering drops whole rows
-- and columns, and with linear filtering blurs it. Upscaling it first by a
-- whole number with nearest (every source pixel a clean 4x4 block) and then
-- sampling that down with linear filtering keeps the outline crisp and the
-- shrink smooth -- what the single-screen titles want for their logos.

local SmoothScale = {}

SmoothScale.FACTOR = 4
local cache = setmetatable({}, { __mode = "k" })

local function upscaled(image)
  local c = cache[image]
  if c ~= nil then return c or nil end
  local g = love.graphics
  local f = SmoothScale.FACTOR
  -- dpiscale 1: a canvas otherwise takes the window's density, and on a
  -- high-DPI phone (3x) the 4x logo became a 3072x3072 texture -- 36 MB of
  -- VRAM for one title picture, drawn back down to the same size anyway
  local ok, canvas = pcall(g.newCanvas, image:getWidth() * f, image:getHeight() * f, { dpiscale = 1 })
  if not ok or not canvas then cache[image] = false return nil end
  local filterMin, filterMag = image:getFilter()
  image:setFilter("nearest", "nearest")
  g.push("all")
  g.origin(); g.setScissor(); g.setShader()
  g.setCanvas(canvas)
  g.clear(0, 0, 0, 0)
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("alpha", "premultiplied")
  g.draw(image, 0, 0, 0, f, f)
  g.pop()
  image:setFilter(filterMin, filterMag)
  canvas:setFilter("linear", "linear")
  cache[image] = canvas
  return canvas
end

-- draw(image, x, y, scale [, alpha]): the picture at `scale` of its own size
function SmoothScale.draw(image, x, y, scale, alpha)
  if not image then return end
  local g = love.graphics
  local canvas = upscaled(image)
  g.setColor(1, 1, 1, alpha or 1)
  if canvas then
    g.draw(canvas, x, y, 0, scale / SmoothScale.FACTOR, scale / SmoothScale.FACTOR)
  else
    g.draw(image, x, y, 0, scale, scale)
  end
end

return SmoothScale
