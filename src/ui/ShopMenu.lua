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

-- THE MONEY SIGN, NOT THREE LETTERS.
--
-- The Game Boy fallback here was the literal bytes <01>"94u", so every mart
-- price on a Game Boy cartridge read "94u300" where it should have read
-- "\194\165300".  Reported from Prism, but Gold, Silver and Crystal print
-- through this same line and were showing it too; only Emerald escaped,
-- because its clerk carries his own `money` string from the cartridge and
-- never reaches this fallback.
--
-- "\194\165" is U+00A5 in UTF-8, which is what the Gen 1 and Gen 2 charmaps
-- spell $F0 as (charmap.asm) -- so Font.encode turns it straight back into
-- the money tile the cartridge draws.  Written as escapes rather than as a
-- literal so no editor or tool can mangle the two bytes again.
local MONEY_GLYPH = "\194\165"
-- Hoenn's, U+20BD, written as escapes for the same reason.
local GEN3_MONEY_GLYPH = "\226\130\189"

-- A price in the cartridge's own currency.
local function price(game, amount)
  local said = martText(game)
  if said and type(said.money) == "string" then
    return fill(said.money, { VAR1 = tostring(amount) })
  end
  -- THREE FONTS, THREE DIFFERENT CHARACTERS, and none of them is a dollar:
  -- U+00A5 on the Game Boy, U+20BD in Hoenn, and a literal ASCII "$" in
  -- Sinnoh, which Platinum's font draws as the Poke-dollar.  The reasoning
  -- and the measurements are in `GameVersion.moneySign`, which is also why
  -- the non-Gen-4 answer is handed to it rather than decided there: this
  -- screen has always printed U+20BD on Gen 3 while four other screens print
  -- U+00A5, and making those four agree is a separate fix.
  local Version = require("src.core.GameVersion")
  local sign = Version.moneySign(
    Version.isGen3() and GEN3_MONEY_GLYPH or MONEY_GLYPH)
  return sign .. tostring(amount)
end

local function buy(game, stock, bargain, onQuit)
  local items = {}
  for _, row in ipairs(stock) do
    local id = bargain and row.item or row
    local def = game.data.items[id]
    if def then
      table.insert(items, {
        value = id,
        label = def.name,
        right = price(game, bargain and row.price or def.price),
        unitPrice = bargain and row.price or nil,
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
    onCancel = onQuit,
    onChoose = function(item)
      local def = game.data.items[item.value]
      local unitPrice = item.unitPrice or def.price
      if bargain and (game.save.bargainShop or {})[item.value] then
        list.footer = Strings("SOLD OUT")
        return
      end
      if game.save.money < unitPrice then
        list.footer = notEnough
        return
      end
      local affordable = bargain and 1 or math.min(99, math.floor(game.save.money / math.max(1, unitPrice)))
      game.stack:push(QuantityBox.new(game, {
        max = affordable,
        unitPrice = unitPrice,
        onDone = function(qty)
          if not qty then
            list.footer = greet
            return
          end
          local cost = qty * unitPrice
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
            if bargain and (game.save.bargainShop or {})[item.value] then
              list.footer = Strings("SOLD OUT")
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
            if bargain then
              game.save.bargainShop = game.save.bargainShop or {}
              game.save.bargainShop[item.value] = true
            end
            game.save.money = game.save.money - cost
            list.footer = line(game, "boughtBag",
                               txt(game, "_PokemartBoughtItemText",
                                   Strings("Here you are!\nThank you!")))
          end))
        end,
      }))
    end,
  })
  if not bargain then game.stack:push(list) end
  return list
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

-- WHERE HOENN PUTS THE BOX, read rather than guessed.
--
-- Reported from play: "also need the gen3 mart menu to show properly as it
-- would in emerald".  The counter behind this menu had been Emerald's for a
-- while; the three-row box in front of it was still at the Game Boy's (0,0)
-- with a Game Boy's width, on a screen that is 240 wide.
--
-- sShopMenuWindowTemplates says (2,1), nine tiles by six -- and those are the
-- window's INTERIOR, which is the one conversion this does: the port's box
-- includes its frame, so it is two tiles wider and two taller and starts one
-- tile up and to the left.  RomExtractorGen3:extractShopMenu reads it.
local function gen3Box(game)
  local c = (game.data.constants or {}).gen3ShopMenu
  local left = c and tonumber(c.left)
  local top = c and tonumber(c.top)
  local width = c and tonumber(c.width)
  local height = c and tonumber(c.height)
  if not (left and top and width and height) then
    return { tx = 0, ty = 0, tw = 8, th = 8 }
  end
  return { tx = math.max(0, left - 1), ty = math.max(0, top - 1),
           tw = width + 2, th = height + 2 }
end

-- FireRed's buy screen lets the shop floor show through its frame, so the
-- stack draws what is under it -- including this BUY / SELL / SEE YA! box,
-- which the cartridge takes down while the list is up.  The box under the
-- screen stops drawing until the screen closes.
function ShopMenu.coverWith(game, screen)
  local under = game.stack:top()
  if under and screen.isOpaque == false then
    local draw = under.draw
    under.draw = function() end
    local quit = screen.onQuit
    screen.onQuit = function(...)
      under.draw = draw
      if quit then return quit(...) end
    end
  end
  game.stack:push(screen)
end

function ShopMenu.new(game, stock, onQuit, opts)
  if opts and opts.bargain then return buy(game, stock, true, onQuit) end
  local counter = gen3Counter(game)
  if counter then
    local fireRed = require("src.core.GameVersion").get() == "firered"
    local Menu = require("src.ui.Menu")
    local menu
    menu = Menu.new(game, {
      { label = line(game, "buy", Strings("BUY")), keepOpen = true,
        onSelect = function()
          if fireRed then
            -- FireRed's extracted counter is translucent and the cartridge
            -- removes the BUY/SELL/QUIT box while its list is open.
            return ShopMenu.coverWith(game,
              counter.new(game, { mode = "buy", stock = stock }))
          end
          -- Emerald's generic counter stays on the stack but hides its menu.
          menu.hidden = true
          game.stack:push(counter.new(game, {
            mode = "buy", stock = stock, under = menu,
          }))
        end },
      { label = line(game, "sell", Strings("SELL")), keepOpen = true,
        onSelect = function()
          if fireRed then
            return ShopMenu.coverWith(game,
              counter.new(game, { mode = "sell" }))
          end
          -- Emerald sells from the bag's own pocket list.
          if counter.openSellBag then return counter.openSellBag(game) end
          game.stack:push(counter.new(game, { mode = "sell" }))
        end },
      { label = line(game, "quit", Strings("QUIT")), onSelect = onQuit },
    }, gen3Box(game))
    -- ...AND ON HOENN'S SCREEN.  Without this the box is a state with no
    -- surface of its own, so it is CENTRED inside the 240x160 the overworld
    -- holds -- which moves a menu the cartridge puts two tiles from the left
    -- edge into the middle of the screen, and is most of what "the gen1 mart
    -- menu" looked like.
    menu.uiSize = function() return require("src.ui.Theme").uiSize() end
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
