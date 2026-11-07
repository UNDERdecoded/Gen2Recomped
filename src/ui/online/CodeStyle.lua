-- Drawing for the online code screens (LongCodeEntry, ShowCode), in one of
-- two looks:
--
--   "game"     the loaded game's own font and window frame (Font.draw /
--              Font.drawBox), so the screen reads like the cartridge it was
--              opened from: Red's tiles, Emerald's proportional face, a
--              Platinum frame.  Font already falls back to LÖVE's own font
--              when a dataset has none.
--   "neutral"  plain LÖVE primitives and the default TrueType font, for
--              places with no game loaded (launcher, hub, tests).
--
-- Every coordinate is in pixels on the screen's own surface (uiSize).  Boxes
-- in the game look snap to 8-pixel tiles because the cartridge frames are
-- tile art.
--
-- Nothing here touches love at require time.

local CodeStyle = {}
CodeStyle.__index = CodeStyle

local INK = { 0, 0, 0, 1 }
local PAPER = { 1, 1, 1, 1 }
local SOFT = { 0.82, 0.88, 1, 1 }      -- highlighted key
local GOOD = { 0.10, 0.50, 0.18, 1 }
local BAD = { 0.75, 0.10, 0.10, 1 }
local DIM = { 0.38, 0.38, 0.42, 1 }

CodeStyle.colors = { ink = INK, paper = PAPER, soft = SOFT, good = GOOD, bad = BAD, dim = DIM }

local neutralFont

function CodeStyle.new(kind)
  local self = setmetatable({}, CodeStyle)
  self.kind = kind == "neutral" and "neutral" or "game"
  if self.kind == "game" then
    self.Font = require("src.render.Font")
  end
  return self
end

-- the look a screen should use when its caller did not say
function CodeStyle.defaultKind(game)
  if game and game.data and game.data.font then return "game" end
  return "neutral"
end

local function g() return love.graphics end

function CodeStyle:setColor(c)
  g().setColor(c[1], c[2], c[3], c[4] or 1)
end

function CodeStyle:font()
  if not neutralFont then
    neutralFont = g().newFont(10)
    neutralFont:setFilter("nearest", "nearest")
  end
  return neutralFont
end

function CodeStyle:lineHeight()
  if self.kind == "game" then
    local h = self.Font.glyphHeight and self.Font.glyphHeight() or 8
    return math.max(8, h)
  end
  return self:font():getHeight()
end

function CodeStyle:width(text)
  if self.kind == "game" then return self.Font.width(text) end
  return self:font():getWidth(text)
end

-- the widest symbol in `charset`: the cell every code character is centred in
function CodeStyle:cellWidth(charset)
  local w = 0
  for i = 1, #charset do
    local cw = self:width(charset:sub(i, i))
    if cw > w then w = cw end
  end
  return math.max(6, w)
end

function CodeStyle:text(text, x, y, color)
  self:setColor(color or INK)
  if self.kind == "game" then
    -- a cartridge font page carries its own colours; recolour it (letter
    -- in the colour, shadow a pale tint of it) only when asked to
    local toned = color and color ~= INK and self.Font.beginTwoTone
      and self.Font.beginTwoTone(color, { 0.7 + color[1] * 0.3, 0.7 + color[2] * 0.3, 0.7 + color[3] * 0.3, 1 })
    if toned then g().setColor(1, 1, 1, 1) end
    self.Font.draw(text, math.floor(x), math.floor(y))
    if toned then self.Font.endTwoTone() end
  else
    g().setFont(self:font())
    g().print(text, math.floor(x), math.floor(y))
  end
  g().setColor(1, 1, 1, 1)
end

function CodeStyle:textCentered(text, cx, y, color)
  self:text(text, cx - self:width(text) / 2, y, color)
end

-- word-wrapped lines of `text` within `maxW` pixels
function CodeStyle:wrap(text, maxW)
  local lines, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if self:width(try) <= maxW or line == "" then
      line = try
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function CodeStyle:clear(w, h)
  self:setColor(PAPER)
  g().rectangle("fill", 0, 0, w, h)
  g().setColor(1, 1, 1, 1)
end

function CodeStyle:rect(mode, x, y, w, h, color)
  self:setColor(color or INK)
  g().rectangle(mode, x, y, w, h)
  g().setColor(1, 1, 1, 1)
end

-- a framed window; in the game look, snapped to whole tiles
function CodeStyle:box(x, y, w, h)
  if self.kind == "game" then
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local tw = math.max(2, math.ceil((x + w) / 8) - tx)
    local th = math.max(2, math.ceil((y + h) / 8) - ty)
    self.Font.drawBox(tx, ty, tw, th)
    g().setColor(1, 1, 1, 1)
    return
  end
  self:rect("fill", x, y, w, h, PAPER)
  self:rect("line", x + 0.5, y + 0.5, w - 1, h - 1, INK)
end

-- a key / button: highlighted fill when selected, outline always
function CodeStyle:key(x, y, w, h, selected, pressed)
  if selected or pressed then self:rect("fill", x, y, w, h, SOFT) end
  self:setColor(selected and INK or DIM)
  g().setLineWidth(1)
  g().rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  if selected then g().rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3) end
  g().setColor(1, 1, 1, 1)
end

-- draw `fn` scaled by `s` around the origin (x, y)
function CodeStyle:scaled(x, y, s, fn)
  g().push()
  g().translate(math.floor(x), math.floor(y))
  g().scale(s, s)
  fn()
  g().pop()
end

-- the screen-space rectangle a window pointer lands in, or nil when the
-- point is outside the UI surface (Renderer.uiPresentation, as the Gen 4
-- naming screen maps its taps)
function CodeStyle.toSurface(px, py)
  local ok, Renderer = pcall(require, "src.render.Renderer")
  local r = ok and Renderer and Renderer.uiPresentation
  if not r then return px, py end
  if px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return nil end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

-- the surface a screen is laid out on: the caller's, else the theme's
-- (160x144 on Game Boy games, 240x160 on GBA, 256x192 on DS)
function CodeStyle.surface(opts)
  if opts and opts.width and opts.height then return opts.width, opts.height end
  local ok, Theme = pcall(require, "src.ui.Theme")
  if ok and Theme and Theme.uiSize then
    local okSize, w, h = pcall(Theme.uiSize)
    if okSize and w and h then
      local GameVersion = package.loaded["src.core.GameVersion"]
      if GameVersion and GameVersion.isDualScreen then
        local okDs, ds = pcall(GameVersion.isDualScreen)
        if okDs and ds and w < 256 then return 256, 192 end
      end
      return w, h
    end
  end
  return 160, 144
end

return CodeStyle
