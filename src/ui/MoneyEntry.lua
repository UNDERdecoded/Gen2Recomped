-- The six-digit money box (MoneyTransferFunction, engine/events/mom.asm).
--
-- Up and down step the digit under the cursor, left and right move between
-- digits, A confirms and B cancels -- and the value is clamped to `max` as it
-- is edited, exactly like the ROM refusing to let the cursor push the amount
-- past what is available.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")

local MoneyEntry = {}
MoneyEntry.__index = MoneyEntry

local DIGITS = 6

function MoneyEntry.new(game, opts)
  local self = setmetatable({}, MoneyEntry)
  opts = opts or {}
  self.game = game
  self.max = math.max(0, math.min(999999, math.floor(tonumber(opts.max) or 0)))
  self.onDone = opts.onDone
  self.cursor = DIGITS         -- the ROM opens on the rightmost digit
  self.value = 0
  return self
end

local function place(value, index)
  return 10 ^ (DIGITS - index)
end

function MoneyEntry:step(delta)
  local unit = place(self.value, self.cursor)
  local digit = math.floor(self.value / unit) % 10
  local next_ = (digit + delta) % 10
  local value = self.value + (next_ - digit) * unit
  if value > self.max then value = self.max end
  if value < 0 then value = 0 end
  self.value = value
end

function MoneyEntry:update()
  local input = self.game.input
  if input:wasPressed("up") then
    self:step(1)
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("down") then
    self:step(-1)
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("left") then
    self.cursor = self.cursor > 1 and self.cursor - 1 or DIGITS
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("right") then
    self.cursor = self.cursor < DIGITS and self.cursor + 1 or 1
    Sound.play(self.game.data, "Tink")
  elseif input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.onDone then self.onDone(self.value) end
  elseif input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.onDone then self.onDone(nil) end
  end
end

function MoneyEntry:draw()
  local x, y, w, h = 72, 16, 80, 32
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(string.format("¥%06d", self.value), x + 8, y + 8)
  -- the caret under the digit the d-pad is editing
  love.graphics.setColor(0, 0, 0, 1)
  local cx = x + 8 + (self.cursor) * 8
  love.graphics.rectangle("fill", cx, y + 18, 8, 2)
  love.graphics.setColor(1, 1, 1, 1)
end

return MoneyEntry
