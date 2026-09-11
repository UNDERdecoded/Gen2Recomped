-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S POKe MART.
--
-- Reported from play: "the pokemart menu isn't gen3's pokemart menu for buy
-- or sell, it's falling back to gen1".  It was, in two separate ways, and the
-- words were only the first of them.
--
-- src/ui/ShopMenu.lua is pokered's DisplayPokemartDialogue_ -- a Game Boy list
-- in a 160x144 letterbox, asking game.data.text for `_Pokemart*` keys that no
-- Emerald dataset carries.  Those keys now resolve to the clerk's own script
-- (RomExtractorGen3:itemMenuActions writes constants.gen3MartText), which
-- fixed the sentences.  This fixes the screen: a 240x160 GBA counter with the
-- money in the corner, the stock down the right with its prices, and the
-- clerk talking in the panel underneath.
--
-- ONE SCREEN, TWO DIRECTIONS.  Buying and selling wear the same furniture on
-- the cartridge -- the same three panels, the same list, the same quantity
-- selector -- and differ only in what fills the list and what the clerk says.
-- So this is one screen with a `mode`, rather than two that have to be kept
-- looking alike.
--
-- WHAT IS DERIVED AND WHAT IS NOT.  Every word on it is the cartridge's, down
-- to the currency glyph -- the port had been printing Hoenn's prices with
-- Kanto's yen sign.  The PANEL GEOMETRY is not derived: it is measured off
-- the screen, and it deliberately matches src/ui/Gen3BagMenu.lua, because the
-- cartridge builds both out of the same furniture and a mart that does not
-- line up with the bag is wrong in a way a screenshot shows immediately.

local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3ShopMenu = {}
Gen3ShopMenu.__index = Gen3ShopMenu
Gen3ShopMenu.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the three panels, matched to the bag's.
local MONEY_BOX = { tx = 0, ty = 0, tw = 11, th = 4 }
local INBAG_BOX = { tx = 0, ty = 4, tw = 11, th = 4 }
local LIST_BOX  = { tx = 11, ty = 0, tw = 19, th = 13 }
local DESC_BOX  = { tx = 0, ty = 13, tw = 30, th = 7 }
local ROW_PITCH = 16
local VISIBLE_ROWS = 6
local CURSOR_INSET = 4

function Gen3ShopMenu:uiSize() return GBA_W, GBA_H end
function Gen3ShopMenu:wantsFillScale() return true end

function Gen3ShopMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- ---------------------------------------------------------------------------
-- THE CLERK'S OWN WORDS
-- ---------------------------------------------------------------------------
local function mart(game)
  return (game.data.constants or {}).gen3MartText or {}
end

local function fill(text, vars)
  return (text:gsub("{(VAR%d)}", function(key)
    return tostring((vars or {})[key] or "")
  end))
end

local function line(game, key, fallback, vars)
  local text = mart(game)[key]
  if type(text) == "string" then return fill(text, vars) end
  return fallback
end

local function price(game, amount)
  local money = mart(game).money
  if type(money) == "string" then
    return fill(money, { VAR1 = tostring(amount) })
  end
  return ("\194\165%d"):format(amount)
end
Gen3ShopMenu.price = price

-- ---------------------------------------------------------------------------
-- THE LIST
-- ---------------------------------------------------------------------------
-- What a Pokemon Centre pays for an item: half its price, which is the rule
-- every generation of this cartridge line uses.
local function sellPriceOf(def)
  return math.floor((tonumber(def and def.price) or 0) / 2)
end

local function unsellable(game, id, def)
  if not def then return true end
  if def.keyItem then return true end
  local ok, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  if ok and ItemEffects.alias(id, def):find("^HM_") then return true end
  return false
end

function Gen3ShopMenu:rebuild()
  local game = self.game
  local rows = {}
  if self.mode == "sell" then
    for _, id in ipairs(Bag.order(game.save)) do
      local def = game.data.items and game.data.items[id]
      rows[#rows + 1] = {
        id = id,
        label = (def and def.name) or id,
        right = Strings("x%d", (game.save.inventory or {})[id] or 1),
        description = def and (def.description or def.desc),
        unit = sellPriceOf(def),
        blocked = unsellable(game, id, def),
      }
    end
  elseif self.kind == "decoration" then
    -- THE FURNITURE COUNTER.  Same list, same prices in the same place -- at
    -- 0x00E0164 the cartridge reads the cost straight out of
    -- gDecorations[id].price and prints it with the same "P{VAR1}" it uses
    -- for an item -- and a different catalogue behind it.
    local Decor = require("src.world.Gen3Decorations")
    for _, id in ipairs(self.stock or {}) do
      local def = Decor.byId(game.data, id)
      if def then
        rows[#rows + 1] = {
          id = id,
          decoration = true,
          label = def.name or tostring(id),
          right = price(game, def.price or 0),
          description = def.description,
          unit = tonumber(def.price) or 0,
        }
      end
    end
  else
    for _, id in ipairs(self.stock or {}) do
      local def = game.data.items and game.data.items[id]
      if def then
        rows[#rows + 1] = {
          id = id,
          label = def.name or id,
          right = price(game, def.price or 0),
          description = def.description or def.desc,
          unit = tonumber(def.price) or 0,
        }
      end
    end
  end
  -- the cartridge ends every one of these lists with a way out
  rows[#rows + 1] = { close = true,
                      label = line(game, "quitShopping", Strings("CANCEL")) }
  self.rows = rows
  self.index = math.min(self.index or 1, #rows)
  self.top = math.max(1, math.min(self.top or 1, #rows - VISIBLE_ROWS + 1))
end

function Gen3ShopMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3ShopMenu)
  self.game = game
  self.mode = (opts.mode == "sell") and "sell" or "buy"
  -- "decoration" is the cartridge's shop mode 1 or 2 rather than 0: the same
  -- counter, stocked out of gDecorations.  `shopMode` is which of the two,
  -- and it is worth exactly one line -- see repeatLine below.
  self.kind = (opts.kind == "decoration") and "decoration" or "item"
  self.shopMode = tonumber(opts.shopMode) or 1
  self.stock = opts.stock or {}
  self.onQuit = opts.onQuit
  self.index, self.top = 1, 1
  self.say = nil
  self:rebuild()
  return self
end

function Gen3ShopMenu:selected() return self.rows[self.index] end

-- "MONEY", as the cartridge spells it.  The trainer card's label block
-- already carries it, so this reads that rather than writing the word down a
-- second time; a dataset without the block gets no label rather than an
-- invented one.
function Gen3ShopMenu:moneyLabel()
  local screens = (self.game.data.constants or {}).gen3Screens or {}
  local card = screens.trainerCard and screens.trainerCard.items
  if type(card) ~= "table" then return nil end
  for _, word in ipairs(card) do
    if type(word) == "string" and word:find("MONEY", 1, true) then
      return word
    end
  end
  return nil
end

function Gen3ShopMenu:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onQuit then self.onQuit() end
end

function Gen3ShopMenu:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.index = (self.index - 1 + delta) % n + 1
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + VISIBLE_ROWS - 1 then
    self.top = self.index - VISIBLE_ROWS + 1
  end
  self.say = nil
end

-- ---------------------------------------------------------------------------
-- BUYING AND SELLING
--
-- The order the cartridge asks in: how many, then the price, then yes or no.
-- ---------------------------------------------------------------------------
function Gen3ShopMenu:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end
  if self.mode == "sell" then return self:sell(row) end
  return self:buy(row)
end

-- WHAT THE CLERK SAYS AFTER A SALE, and the only thing the two decoration
-- modes disagree about.  At 0x00DFD0E the shop compares its mode against 2
-- and picks 0x085E95C7 -- "Can I help you with anything else?" -- over
-- 0x085E959B, "Is there anything else I can help you with?", which is the
-- line the mart text block already carries as `anythingElse`.  With only the
-- one line in the dataset both modes say it; with the second read they say
-- what the cartridge says.
function Gen3ShopMenu:repeatLine()
  local words = mart(self.game)
  if self.kind == "decoration" and self.shopMode == 2 and words.anythingElse2 then
    return words.anythingElse2
  end
  return words.anythingElse
end

-- BUYING A PIECE OF FURNITURE.
--
-- One at a time, and that is a reading rather than a simplification: at
-- 0x00E012A the shop asks whether its mode is 0 and only THEN goes down the
-- quantity path (0x00E0130, the "how many" buffer).  A decoration counter
-- takes the branch at 0x00E0164, which formats the price and asks yes or no.
function Gen3ShopMenu:buyDecoration(row)
  local game = self.game
  local Decor = require("src.world.Gen3Decorations")
  local TextBox = require("src.render.TextBox")
  local cost = math.max(0, row.unit or 0)
  if (tonumber(game.save.money) or 0) < cost then
    self.say = line(game, "noMoney", Strings("You don't have\nenough money."))
    return
  end
  local ask = line(game, "buyTotal",
                   Strings("%s? That will be %s.", row.label,
                           price(game, cost)),
                   { VAR1 = row.label, VAR2 = "1", VAR3 = tostring(cost) })
  game.stack:push(TextBox.new(game, ask, nil, {
    choice = function(yes)
      if not yes then return end
      if (tonumber(game.save.money) or 0) < cost then
        self.say = line(game, "noMoney",
                        Strings("You don't have\nenough money."))
        return
      end
      if not Decor.roomFor(game.data, game.save, row.id) then
        self.say = line(game, "spaceFull",
                        Strings("The space for %s is full.", row.label),
                        { VAR1 = row.label })
        return
      end
      Decor.give(game.save, row.id, 1)
      game.save.money = (tonumber(game.save.money) or 0) - cost
      require("src.core.Sound").play(game.data, "Purchase")
      self.say = self:repeatLine()
                 or line(game, "boughtBag", Strings("Here you are!\nThank you!"))
    end,
  }))
end

function Gen3ShopMenu:buy(row)
  if row.decoration then return self:buyDecoration(row) end
  local game = self.game
  local unit = math.max(0, row.unit or 0)
  local money = tonumber(game.save.money) or 0
  if unit > 0 and money < unit then
    self.say = line(game, "noMoney", Strings("You don't have\nenough money."))
    return
  end
  local most = (unit > 0) and math.min(99, math.floor(money / unit)) or 99
  local QuantityBox = require("src.ui.QuantityBox")
  local TextBox = require("src.render.TextBox")
  game.stack:push(QuantityBox.new(game, {
    max = math.max(1, most),
    unitPrice = unit,
    onDone = function(qty)
      if not qty then return end
      local cost = unit * qty
      local ask = line(game, "buyTotal",
                       Strings("%s? That will be %s.", row.label,
                               price(game, cost)),
                       { VAR1 = row.label, VAR2 = tostring(qty),
                         VAR3 = tostring(cost) })
      -- `choice` is the callback TextBox hands the answer to, not a flag
      game.stack:push(TextBox.new(game, ask, nil, {
        choice = function(yes)
          if not yes then return end
          if (tonumber(game.save.money) or 0) < cost then
            self.say = line(game, "noMoney",
                            Strings("You don't have\nenough money."))
            return
          end
          if not Bag.add(game.save, row.id, qty, game.data) then
            self.say = line(game, "bagFull",
                            Strings("You can't carry\nany more items."))
            return
          end
          game.save.money = (tonumber(game.save.money) or 0) - cost
          require("src.core.Sound").play(game.data, "Purchase")
          self.say = line(game, "boughtBag",
                          Strings("Here you are!\nThank you!"))
        end,
      }))
    end,
  }))
end

function Gen3ShopMenu:sell(row)
  local game = self.game
  if row.blocked then
    self.say = line(game, "cantBuy", Strings("I can't put a\nprice on that."),
                    { VAR1 = row.label, VAR2 = row.label })
    return
  end
  local unit = math.max(0, row.unit or 0)
  local held = (game.save.inventory or {})[row.id] or 1
  local QuantityBox = require("src.ui.QuantityBox")
  local TextBox = require("src.render.TextBox")
  game.stack:push(QuantityBox.new(game, {
    max = math.max(1, held),
    unitPrice = unit,
    onDone = function(qty)
      if not qty then return end
      local paid = unit * qty
      local ask = line(game, "sellPrice",
                       Strings("I can pay you\n%s for that.",
                               price(game, paid)),
                       { VAR1 = tostring(paid) })
      game.stack:push(TextBox.new(game, ask, nil, {
        choice = function(yes)
          if not yes then return end
          game.save.money = (tonumber(game.save.money) or 0) + paid
          Bag.remove(game.save, row.id, qty)
          self:rebuild()
          self.say = line(game, "sold", Strings("Thank you!"),
                          { VAR1 = tostring(paid), VAR2 = row.label })
        end,
      }))
    end,
  }))
end

function Gen3ShopMenu:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

function Gen3ShopMenu:keypressed(key)
  if key == "down" then return self:moveCursor(1) end
  if key == "up" then return self:moveCursor(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

-- ---------------------------------------------------------------------------
-- DRAWING IT
-- ---------------------------------------------------------------------------
local function drawRows(self)
  local x = (LIST_BOX.tx + 1) * 8 + CURSOR_INSET + 8
  local right = (LIST_BOX.tx + LIST_BOX.tw - 1) * 8
  for i = 0, VISIBLE_ROWS - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = (LIST_BOX.ty + 1) * 8 + i * ROW_PITCH
    Font.draw(row.label, x, y)
    if row.right then
      Font.draw(row.right, right - Font.width(row.right), y)
    end
    if self.top + i == self.index then
      Font.drawCode(Theme.cursor, (LIST_BOX.tx + 1) * 8 + CURSOR_INSET, y)
    end
  end
end

function Gen3ShopMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)

  -- THE MONEY.  The word over it is the cartridge's own -- the trainer card
  -- already had to find it, and there is no second "MONEY" in Hoenn.
  Font.drawBox(MONEY_BOX.tx, MONEY_BOX.ty, MONEY_BOX.tw, MONEY_BOX.th)
  local label = self:moneyLabel()
  if label then Font.draw(label, (MONEY_BOX.tx + 1) * 8, (MONEY_BOX.ty + 1) * 8) end
  local amount = price(self.game, tonumber(self.game.save.money) or 0)
  Font.draw(amount, (MONEY_BOX.tx + MONEY_BOX.tw - 1) * 8 - Font.width(amount),
            (MONEY_BOX.ty + 2) * 8)

  Font.drawBox(LIST_BOX.tx, LIST_BOX.ty, LIST_BOX.tw, LIST_BOX.th)
  drawRows(self)

  Font.drawBox(DESC_BOX.tx, DESC_BOX.ty, DESC_BOX.tw, DESC_BOX.th)
  local row = self:selected()
  -- WHAT THE PANEL SAYS.  The clerk's last line while there is one, and the
  -- item's own description otherwise, which is what the cartridge shows while
  -- the cursor is just moving.
  local text = self.say or (row and not row.close and row.description) or ""
  local y = (DESC_BOX.ty + 1) * 8
  for chunk in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(chunk, (DESC_BOX.tx + 1) * 8, y)
    y = y + 14
  end

  -- HOW MANY YOU ALREADY HAVE, which is the one number the cartridge puts on
  -- this screen that the bag does not.
  if row and not row.close then
    Font.drawBox(INBAG_BOX.tx, INBAG_BOX.ty, INBAG_BOX.tw, INBAG_BOX.th)
    local have
    if row.decoration then
      have = require("src.world.Gen3Decorations").count(self.game.save, row.id)
    else
      have = (self.game.save.inventory or {})[row.id] or 0
    end
    local text2 = line(self.game, "inBag", Strings("IN BAG: %d", have),
                       { VAR1 = tostring(have) })
    Font.draw(text2, (INBAG_BOX.tx + 1) * 8, (INBAG_BOX.ty + 1) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ShopMenu
