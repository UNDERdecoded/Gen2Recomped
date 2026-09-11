-- One place that knows what things look like.
local Theme = {}

Theme.bg        = { 0.086, 0.094, 0.106 }
Theme.panel     = { 0.129, 0.141, 0.157 }
Theme.panelAlt  = { 0.157, 0.173, 0.192 }
Theme.line      = { 0.239, 0.259, 0.286 }
Theme.text      = { 0.878, 0.894, 0.910 }
Theme.dim       = { 0.573, 0.604, 0.639 }
Theme.faint     = { 0.373, 0.404, 0.439 }
Theme.accent    = { 0.376, 0.678, 0.965 }
Theme.accentDim = { 0.220, 0.404, 0.580 }
Theme.good      = { 0.400, 0.800, 0.520 }
Theme.warn      = { 0.960, 0.760, 0.360 }
Theme.bad       = { 0.937, 0.451, 0.451 }
Theme.grid      = { 1, 1, 1, 0.10 }
Theme.gridCell  = { 1, 1, 1, 0.28 }
Theme.sel       = { 0.376, 0.678, 0.965, 0.35 }

-- Heights get a colour ramp so a sculpt reads as a shape rather than as a
-- field of numbers.  Cold is low, warm is high; water is its own colour
-- because a recess is not a short wall.
function Theme.heightColor(h, maxH)
  if h < 0 then return 0.25, 0.55, 0.85 end
  maxH = math.max(maxH or 32, 1)
  local t = math.max(0, math.min(1, h / maxH))
  return 0.15 + 0.85 * t, 0.35 + 0.45 * (1 - math.abs(t - 0.5) * 2), 0.85 - 0.7 * t
end

Theme.fonts = {}
Theme.scale = 1

-- ONE SCALE, APPLIED TO THE TYPE AND TO EVERY LAYOUT NUMBER.
--
-- A 1080p desktop is not a smaller version of a 1440p one: it has room for
-- fewer controls, not for the same controls drawn smaller and then clipped.
-- So the scale shrinks the type AND the metrics together (see Theme.m), and
-- the layout asks for fewer columns rather than narrower ones when even that
-- does not fit.
--
-- Sizes are rounded to whole pixels.  A 10.5px font renders blurry at this
-- kind of density and the blur is worse than the half pixel is worth.
function Theme.load(scale)
  scale = math.max(0.7, math.min(1.6, tonumber(scale) or Theme.scale or 1))
  if Theme.fonts.body and math.abs(scale - Theme.scale) < 0.001 then return end
  Theme.scale = scale
  local function size(n)
    return math.max(8, math.floor(n * scale + 0.5))
  end
  Theme.fonts.body = love.graphics.newFont(size(13))
  Theme.fonts.small = love.graphics.newFont(size(11))
  Theme.fonts.big = love.graphics.newFont(size(16))
  Theme.fonts.mono = love.graphics.newFont(size(12))
  Theme.rowH = size(19)
  Theme.btnH = size(21)
end

-- A metric in scaled pixels.  Every hard-coded gap, button height and panel
-- width in the layout goes through here, so one number moves all of them.
function Theme.m(n)
  return math.floor(n * Theme.scale + 0.5)
end

return Theme
