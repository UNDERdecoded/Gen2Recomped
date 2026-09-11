-- Mart shop (engine/events/pokemart.asm DisplayPokemartDialogue_):
-- the BUY/SELL/QUIT menu loops until QUIT -- BUY and SELL keep it on
-- the stack underneath their list, and QUIT hands control back to the
-- caller (open_mart resumes its yielded script runner there).  Both
-- lists run in dialogue mode: the clerk speaks the real _Pokemart*
-- strings in the bottom text box with the money box top-right, then
-- the 1-99 quantity selector (DisplayChooseQuantityMenu) and a YES/NO
-- price confirm.  Key items and HMs can't be sold (.unsellableItem).

local Bag = require("src.inventory.Bag")
local ChoiceBox = require("src.ui.ChoiceBox")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local QuantityBox = require("src.ui.QuantityBox")
local Strings = require("src.core.Strings")

local ShopMenu = {}

local function txt(game, key, fallback)
  return game.data.text[key] or fallback
end

-- ---------------------------------------------------------------------------
-- HOENN'S CLERK.
--
-- Reported from play: "the pokemart menu isn't gen3's pokemart menu for buy
-- or sell, it's falling back to gen1".  It was.  Everything below asks
-- game.data.text for a `_Pokemart*` key, which only a Gen 1 or Gen 2 dataset
-- has, so on Emerald every line fell through to the engine's own English and
-- every price was printed with Kanto's yen sign.
--
-- Emerald's clerk has his own script, and it is in the cartridge --
-- RomExtractorGen3:itemMenuActions lifts it, along with the currency glyph
-- and the words on the BUY / SELL / QUIT menu.  His lines carry {VAR1} and
-- friends where the name, the count and the price go, so they are filled
-- rather than reassembled.
--
-- WHAT IS STILL THE ENGINE'S is the LAYOUT: this is the port's list with
-- Hoenn's words in it, not Emerald's mart screen with its own panels and its
-- IN BAG box.  That is the next piece of this, and it is a screen rather than
-- a string.
-- ---------------------------------------------------------------------------
local function martText(game)
  return (game.data.constants or {}).gen3MartText
end

local function fill(text, vars)
  return (text:gsub("{(VAR%d)}", function(key)
    return tostring((vars or {})[key] or "")
  end))
end

-- The clerk's own line, or the engine's when this dataset has no clerk.
local function line(game, key, fallback, vars)
  local said = martText(game)
  local text = said and said[key]
  if type(text) == "string" then return fill(text, vars) end
  return fallback
end

-- A price in the cartridge's own currency.
local function price(game, amount)
  local said = martText(game)
  if said and type(said.money) == "string" then
    return fill(said.money, { VAR1 = tostring(amount) })
  end
  return ("94u%d"):format(amount)
end

local function buy(game, stock)
  local items = {}
  for _, id in ipairs(stock) do
    local def = game.data.items[id]
    if def then
      table.insert(items, {
        value = id,
        label = def.name,
        right = price(game, def.price),
      })
    end
  end
  local greet = txt(game, "_PokemartBuyingGreetingText", "Take your time.")
  local notEnough = line(game, "noMoney",
                         txt(game, "_PokemartNotEnoughMoneyText",
                             Strings("You don't have\nenough money.")))
  local list
  list = ListMenu.new(game, "BUY", items, {
    dialogue = true,
    money = function() return game.save.money end,
    footer = greet,
    onChoose = function(item)
      local def = game.data.items[item.value]
      if game.save.money < def.price then
        list.footer = notEnough
        return
      end
      local affordable = math.min(99, math.floor(game.save.money / math.max(1, def.price)))
      game.stack:push(QuantityBox.new(game, {
        max = affordable,
        unitPrice = def.price,
        onDone = function(qty)
          if not qty then
            list.footer = greet
            return
          end
          local cost = qty * def.price
          -- _PokemartTellBuyPriceText + yes/no confirm
          list.footer = line(game, "buyTotal",
                             Strings("%s?\nThat will be\n%s. OK?", def.name,
                                     price(game, cost)),
                             { VAR1 = def.name, VAR2 = tostring(qty),
                               VAR3 = tostring(cost) })
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              list.footer = greet
              return
            end
            if game.save.money < cost then
              list.footer = notEnough
              return
            end
            if not Bag.add(game.save, item.value, qty, game.data) then
              list.footer = line(game, "bagFull",
                                 txt(game, "_PokemartItemBagFullText",
                                     Strings("You can't carry\nany more items.")))
              return
            end
            require("src.core.Sound").play(game.data, "Purchase")
            game.save.money = game.save.money - cost
            list.footer = line(game, "boughtBag",
                               txt(game, "_PokemartBoughtItemText",
                                   Strings("Here you are!\nThank you!")))
          end))
        end,
      }))
    end,
  })
  game.stack:push(list)
end

local function sell(game)
  -- Sell list is ITEMLISTMENU with wPrintItemPrices cleared
  -- (pokemart.asm .sellMenuLoop): name + quantity only.  Price shows
  -- in the quantity chooser.  Stuffing "xN" into the label next to a
  -- right-aligned ¥ price made long names overlap (issue #116).
  local items = {}
  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items[id]
    table.insert(items, {
      value = id,
      label = def and def.name or id,
      right = "x" .. game.save.inventory[id],
    })
  end
  local greet = txt(game, "_PokemartBuyingGreetingText", "Take your time.")
  local list
  list = ListMenu.new(game, "SELL", items, {
    dialogue = true,
    money = function() return game.save.money end,
    footer = greet,
    onChoose = function(item)
      local def = game.data.items[item.value]
      -- only key items and HMs are unsellable (pokemart.asm IsKeyItem /
      -- IsItemHM); zero-price items like ETHER sell for ¥0.  An unknown id
      -- (nil def) has no price, so treat it as unsellable too rather than
      -- indexing nil below -- guards saves that already picked up a bogus
      -- ITEM_NONE "0" from Blue's House before that pickup was fixed (#11).
      if not def or def.keyItem
         or require("src.inventory.ItemEffects").alias(item.value, def):find("^HM_") then
        list.footer = line(game, "cantBuy",
                           txt(game, "_PokemartUnsellableItemText",
                               Strings("I can't put a\nprice on that.")),
                           { VAR1 = def and def.name or item.value,
                             VAR2 = def and def.name or item.value })
        return
      end
      local unit = math.floor(def.price / 2)
      game.stack:push(QuantityBox.new(game, {
        max = game.save.inventory[item.value] or 1,
        unitPrice = unit,
        onDone = function(qty)
          if not qty then
            list.footer = greet
            return
          end
          -- _PokemartTellSellPriceText + yes/no confirm
          list.footer = line(game, "sellPrice",
                             Strings("I can pay you\n%s for that.",
                                     price(game, unit * qty)),
                             { VAR1 = tostring(unit * qty) })
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              list.footer = greet
              return
            end
            game.save.money = game.save.money + unit * qty
            Bag.remove(game.save, item.value, qty)
            local left = game.save.inventory[item.value]
            if left then
              item.right = "x" .. left
            else
              list:removeCurrent()
            end
            list.footer = line(game, "sold",
                               txt(game, "_PokemartThankYouText", "Thank you!"),
                               { VAR1 = tostring(unit * qty),
                                 VAR2 = def.name or item.value })
          end))
        end,
      }))
    end,
  })
  game.stack:push(list)
end

-- HOENN GETS ITS OWN COUNTER.  Everything above is the Game Boy mart with
-- the cartridge's words in it, which is the right fallback and the wrong
-- SCREEN: Emerald's is a 240x160 GBA counter with the money in the corner and
-- the stock down the right.  When the dataset carries the clerk's script it
-- carries that screen too, and BUY and SELL both open it.
local function gen3Counter(game)
  if not martText(game) then return nil end
  local ok, screen = pcall(require, "src.ui.Gen3ShopMenu")
  if not (ok and type(screen) == "table") then return nil end
  return screen
end

function ShopMenu.new(game, stock, onQuit)
  local counter = gen3Counter(game)
  if counter then
    local Menu = require("src.ui.Menu")
    local menu = Menu.new(game, {
      { label = line(game, "buy", Strings("BUY")), keepOpen = true,
        onSelect = function()
          game.stack:push(counter.new(game, { mode = "buy", stock = stock }))
        end },
      { label = line(game, "sell", Strings("SELL")), keepOpen = true,
        onSelect = function()
          game.stack:push(counter.new(game, { mode = "sell" }))
        end },
      { label = line(game, "quit", Strings("QUIT")), onSelect = onQuit },
    }, { tx = 0, ty = 0, tw = 8, th = 8 })
    menu.onCancel = onQuit
    return menu
  end
  return ShopMenu.classic(game, stock, onQuit)
end

function ShopMenu.classic(game, stock, onQuit)
  -- keepOpen: the mart menu stays underneath its list so closing the
  -- list lands back here; only QUIT (or B) leaves and fires onQuit
  local menu = Menu.new(game, {
    { label = line(game, "buy", Strings("BUY")), keepOpen = true,
      onSelect = function() buy(game, stock) end },
    { label = line(game, "sell", Strings("SELL")), keepOpen = true,
      onSelect = function() sell(game) end },
    { label = line(game, "quit", Strings("QUIT")), onSelect = onQuit },
  }, { tx = 0, ty = 0, tw = 8, th = 8 })
  menu.onCancel = onQuit
  return menu
end

return ShopMenu
