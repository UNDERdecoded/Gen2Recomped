-- The mod's screens, drawn through the engine's CodeStyle in the loaded
-- game's own font and frame (src/ui/online/CodeStyle.lua): one screen type,
-- a title, some lines of text and a list of rows.
--
--   Screens.list(game, { title=, lines={...} | fn() -> {...}, rows={ {label=, run=fn} } })

local Screens = {}

local List = {}
List.__index = List
List.isOpaque = true

function Screens.list(game, opts)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local self = setmetatable({ game = game, opts = opts, index = 1, scroll = 0 }, List)
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = CodeStyle.defaultKind(game)
  game.stack:push(self)
  return self
end

function List:uiSize() return self.width, self.height end

function List:close()
  local stack = self.game.stack
  if stack:top() == self then stack:pop() end
end

function List:lines()
  local l = self.opts.lines
  if type(l) == "function" then return l() or {} end
  return l or {}
end

function List:rows() return self.opts.rows or {} end

function List:press(b)
  local rows = self:rows()
  if b == "up" then
    if #rows > 0 then self.index = (self.index - 2) % #rows + 1 end
  elseif b == "down" then
    if #rows > 0 then self.index = self.index % #rows + 1 end
  elseif b == "left" then self.scroll = math.max(0, self.scroll - 4)
  elseif b == "right" then self.scroll = self.scroll + 4
  elseif b == "a" then
    local row = rows[self.index]
    if row and row.run then row.run(self) end
  elseif b == "b" and not self.opts.modal then
    self:close()
    if self.opts.onBack then self.opts.onBack() end
  end
end

function List:update()
  local input = self.game.input
  if not input then return end
  for _, b in ipairs({ "up", "down", "left", "right", "a", "b" }) do
    if input:wasPressed(b) then return self:press(b) end
  end
end

function List:onKeyPressed(key)
  local input = self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function List:draw()
  local CodeStyle = require("src.ui.online.CodeStyle")
  local style = self.style or CodeStyle.new(self.styleKind)
  self.style = style
  local C = CodeStyle.colors
  local W, H = self.width, self.height
  local lh = style:lineHeight()
  style:clear(W, H)
  style:text(self.opts.title or "NUZLOCKE", 8, 2)
  local rows = self:rows()
  -- the row box in whole tiles, so the game's frame and the text agree
  local rowsH = math.ceil((#rows * (lh + 2) + 16) / 8) * 8
  local rowsY = H - rowsH
  -- the text, wrapped, scrolled with left/right
  local wrapped = {}
  for _, line in ipairs(self:lines()) do
    for _, w in ipairs(style:wrap(line, W - 16)) do wrapped[#wrapped + 1] = w end
  end
  local room = math.max(1, math.floor((rowsY - lh - 6) / lh))
  self.scroll = math.max(0, math.min(self.scroll, math.max(0, #wrapped - room)))
  local y = lh + 4
  for i = self.scroll + 1, math.min(#wrapped, self.scroll + room) do
    style:text(wrapped[i], 8, y, C.ink)
    y = y + lh
  end
  if #wrapped > room then style:text("<>", W - 8 - style:width("<>"), 2, C.dim) end
  if #rows > 0 then
    style:box(0, rowsY, W, rowsH)
    for i, r in ipairs(rows) do
      local ry = rowsY + 8 + (i - 1) * (lh + 2)
      if i == self.index then style:text(">", 6, ry) end
      style:text(r.label, 14, ry)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

Screens.List = List
return Screens
