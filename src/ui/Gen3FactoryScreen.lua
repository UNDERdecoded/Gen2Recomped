-- THE BATTLE FACTORY'S RENTAL AND SWAP SCREENS (pokeemerald
-- battle_factory_screen.c's select and swap halves), as two lists.
--
-- SELECT: six Pokemon on offer; A picks (the order picked is the party
-- order), A on a picked one puts it back, and with three picked the screen
-- asks "Are these three Pokemon OK?". The cartridge's ball rack and summary
-- page are drawn here as a list and a panel of the highlighted one's held
-- item and moves -- the same facts, laid out plainly.
--
-- SWAP: first which of your three to give (B: keep your team), then which of
-- the beaten trainer's three to take; the swap is asked once more before it
-- is made.
--
-- opts = { mode = "select" | "swap", mons, theirs, onDone }
--   select hands back { i1, i2, i3 } (indexes into mons)
--   swap hands back { give = i, take = j }, or nil to keep

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local S = {}
S.__index = S
S.isOpaque = true

function S.new(game, opts)
  local self = setmetatable({ game = game, data = game.data, mode = opts.mode, mons = opts.mons or {},
    theirs = opts.theirs or {}, onDone = opts.onDone, index = 1, picks = {}, phase = "pick" }, S)
  if self.mode == "swap" then self.phase = "give" end
  return self
end

local function speciesName(data, mon)
  local d = mon and data.pokemon and data.pokemon[mon.species]
  return (mon and mon.nickname) or (d and d.name) or tostring(mon and mon.species or "?")
end
local function itemName(data, item)
  local d = item and data.items and data.items[item]
  return d and d.name or (item and tostring(item)) or "NONE"
end
local function moveName(data, id)
  local d = id and data.moves and data.moves[id]
  return d and d.name or tostring(id or "-")
end

function S:list()
  if self.mode == "select" then return self.mons end
  if self.phase == "take" then return self.theirs end
  return self.mons
end

function S:finish(result)
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onDone then self.onDone(result) end
end

function S:pickedAt(i)
  for k, v in ipairs(self.picks) do if v == i then return k end end
  return nil
end

function S:confirmNow()
  local game = self.game
  local text = (self.mode == "select") and Strings("Are these three POKéMON OK?")
               or Strings("Swap %s for %s?", speciesName(self.data, self.mons[self.give]),
                          speciesName(self.data, self.theirs[self.take]))
  self.asking = true
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, nil, { choice = function(yes)
    self.asking = false
    if yes then
      if self.mode == "select" then self:finish({ self.picks[1], self.picks[2], self.picks[3] })
      else self:finish({ give = self.give, take = self.take }) end
    else
      if self.mode == "select" then table.remove(self.picks)
      else self.phase, self.take = "take", nil end
    end
  end }))
  local _ = ChoiceBox
end

function S:update()
  if self.asking or self.closed then return end
  local input = self.game.input
  if not input then return end
  local list = self:list()
  local n = #list
  -- A LIST TOO SHORT TO FINISH FROM must not hold the player in the screen:
  -- SELECT only ends with three picks and SWAP with a pair, so an empty (or
  -- short) offer -- a Factory challenge resumed with no rentals on the save --
  -- had no way out at all.  Hand back "nothing chosen" and the caller falls
  -- back to its defaults (fr_bf_app reads a missing result as slots 1..n).
  if n == 0 then return self:finish(nil) end
  local needed = (self.mode == "select") and math.min(3, n) or 1
  if input:wasPressed("up") then
    self.index = (self.index - 2) % math.max(1, n) + 1
    Sound.play(self.data, "Press_AB")
  elseif input:wasPressed("down") then
    self.index = self.index % math.max(1, n) + 1
    Sound.play(self.data, "Press_AB")
  elseif input:wasPressed("a") then
    Sound.play(self.data, "Press_AB")
    if self.mode == "select" then
      local at = self:pickedAt(self.index)
      if at then table.remove(self.picks, at)
      elseif list[self.index] and #self.picks < needed then
        self.picks[#self.picks + 1] = self.index
        if #self.picks == needed then self:confirmNow() end
      end
    elseif self.phase == "give" then
      if list[self.index] then self.give = self.index; self.phase = "take"; self.index = 1 end
    else
      if list[self.index] then self.take = self.index; self:confirmNow() end
    end
  elseif input:wasPressed("b") then
    Sound.play(self.data, "Press_AB")
    if self.mode == "select" then
      if #self.picks > 0 then table.remove(self.picks) end
    elseif self.phase == "take" then
      self.phase, self.give, self.index = "give", nil, 1
    else
      self:finish(nil)
    end
  end
end

function S:draw()
  local g = love.graphics
  local data = self.data
  g.setColor(0.36, 0.52, 0.72, 1)
  g.rectangle("fill", 0, 0, 240, 160)
  g.setColor(1, 1, 1, 1)
  local title
  if self.mode == "select" then title = Strings("Choose three rental POKéMON.")
  elseif self.phase == "give" then title = Strings("Which POKéMON will you give?")
  else title = Strings("Which POKéMON will you take?") end
  Font.drawBox(0, 0, 30, 4)
  g.setColor(0, 0, 0, 1)
  Font.draw(title, 8, 8)
  g.setColor(1, 1, 1, 1)
  local list = self:list()
  Font.drawBox(0, 4, 12, math.max(4, #list * 2 + 2))
  g.setColor(0, 0, 0, 1)
  for i, mon in ipairs(list) do
    local y = 40 + (i - 1) * 16
    local mark = ""
    if self.mode == "select" then
      local at = self:pickedAt(i)
      if at then mark = tostring(at) .. " " end
    elseif self.phase == "take" and self.give == nil then
      mark = ""
    end
    Font.draw(mark .. speciesName(data, mon), 16, y)
    if i == self.index then Font.drawCode(Theme.cursor, 8, y) end
  end
  g.setColor(1, 1, 1, 1)
  local mon = list[self.index]
  Font.drawBox(12, 4, 18, 16)
  g.setColor(0, 0, 0, 1)
  if mon then
    Font.draw(speciesName(data, mon) .. "  Lv" .. tostring(mon.level or "?"), 104, 40)
    Font.draw(Strings("Item: %s", itemName(data, mon.item)), 104, 56)
    for k, mv in ipairs(mon.moves or {}) do
      Font.draw(moveName(data, mv.id), 104, 64 + k * 14)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return S
