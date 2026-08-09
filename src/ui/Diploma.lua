-- The dex-completion diploma (engine/events/diploma.asm DisplayDiploma /
-- diploma2.asm DisplayDiplomaTop): a bordered certificate page with the
-- player's name, shown by the Celadon Mansion 3F game designer once 150
-- species are owned.  Diploma.render also backs the Yellow-only printed
-- copy (engine/printer/printer.asm PrintDiploma -> src/core/Printer.lua).

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true

function Diploma.new(game, onDone)
  return setmetatable({ game = game, onDone = onDone }, Diploma)
end

function Diploma:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

-- the DisplayDiplomaTop layout, hlcoord tiles kept as x*8 / y*8 pixels
function Diploma.render(game)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", 2.5, 2.5, 155, 139)
  Font.draw(Strings("<Diploma>"), 40, 16)                -- hlcoord 5,2
  Font.draw(Strings("Player"), 24, 32)                   -- hlcoord 3,4
  Font.draw(game.save.player.name or "RED", 80, 32)      -- hlcoord 10,4
  local congrats = {                                     -- hlcoord 2,6
    "Congrats! This", "diploma certifies", "that you have",
    "completed your", "POKéDEX.",
  }
  for i, line in ipairs(congrats) do
    Font.draw(Strings(line), 16, 48 + (i - 1) * 10)
  end
  Font.draw(Strings("GAME FREAK"), 72, 128)              -- hlcoord 9,16
  love.graphics.setColor(1, 1, 1, 1)
end

function Diploma:draw()
  Diploma.render(self.game)
end

return Diploma
