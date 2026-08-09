-- Exact-colour probe over the presented frame, for the palette drivers
-- (#279, #301, #322).  The colours those fixes argue about are exact byte
-- triples out of data/generated/palettes.lua and the shade-remap shader writes
-- them verbatim, so counting exact matches puts a number in the log.  grab()
-- is a coroutine helper (captureScreenshot only lands at the next present) and
-- returns nil where capture is unavailable, so callers WARN instead of failing.

local Probe = {}

-- Grab the presented frame as ImageData, or nil if capture is unavailable.
function Probe.grab(maxFrames)
  if not (love.graphics and love.graphics.captureScreenshot) then return nil end
  local shot = nil
  local ok = pcall(love.graphics.captureScreenshot, function(id) shot = id end)
  if not ok then return nil end
  for _ = 1, maxFrames or 180 do
    if shot then break end
    coroutine.yield()
  end
  return shot
end

local function byteAt(shot, x, y)
  local r, g, b = shot:getPixel(x, y)
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
         math.floor(b * 255 + 0.5)
end

-- Count exact matches for a { name = {r, g, b} } table.  `step` subsamples both
-- axes (default 3), `rect` limits the scan to { x0, y0, x1, y1 } in 0..1
-- fractions of the frame.  Returns the counts and the pixels sampled.
-- The window blit can be filtered, so glyph and sprite EDGES blend into inexact
-- triples: ask about flat interiors, never a whole-frame exact match.
function Probe.count(shot, wanted, step, rect)
  local out = {}
  for name in pairs(wanted) do out[name] = 0 end
  if not shot then return out, 0 end
  step = step or 3
  local w, h = shot:getDimensions()
  local x0, y0, x1, y1 = 0, 0, w - 1, h - 1
  if rect then
    x0 = math.floor(rect[1] * (w - 1))
    y0 = math.floor(rect[2] * (h - 1))
    x1 = math.floor(rect[3] * (w - 1))
    y1 = math.floor(rect[4] * (h - 1))
  end
  local total = 0
  for y = y0, y1, step do
    for x = x0, x1, step do
      local r, g, b = byteAt(shot, x, y)
      total = total + 1
      for name, c in pairs(wanted) do
        if r == c[1] and g == c[2] and b == c[3] then out[name] = out[name] + 1 end
      end
    end
  end
  return out, total
end

-- The n most common exact colours, biggest first, as
-- { { r, g, b, count = n, share = 0..1 }, ... }.  For claims about the SIZE of
-- the palette on screen rather than one named colour being present.
function Probe.top(shot, n, step, rect)
  if not shot then return {} end
  step = step or 3
  local w, h = shot:getDimensions()
  local x0, y0, x1, y1 = 0, 0, w - 1, h - 1
  if rect then
    x0 = math.floor(rect[1] * (w - 1))
    y0 = math.floor(rect[2] * (h - 1))
    x1 = math.floor(rect[3] * (w - 1))
    y1 = math.floor(rect[4] * (h - 1))
  end
  local seen, order, total = {}, {}, 0
  for y = y0, y1, step do
    for x = x0, x1, step do
      local r, g, b = byteAt(shot, x, y)
      local key = r * 65536 + g * 256 + b
      local e = seen[key]
      if not e then
        e = { r, g, b, count = 0 }
        seen[key] = e
        order[#order + 1] = e
      end
      e.count = e.count + 1
      total = total + 1
    end
  end
  table.sort(order, function(a, b) return a.count > b.count end)
  local out = {}
  for i = 1, math.min(n or 6, #order) do
    order[i].share = total > 0 and order[i].count / total or 0
    out[i] = order[i]
  end
  return out, total
end

function Probe.fmt(list)
  local parts = {}
  for _, c in ipairs(list) do
    parts[#parts + 1] = ("(%d,%d,%d)=%.1f%%")
      :format(c[1], c[2], c[3], (c.share or 0) * 100)
  end
  return table.concat(parts, "  ")
end

return Probe
