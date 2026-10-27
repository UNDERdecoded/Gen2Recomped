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
-- THE COUNTER IS AN OVERLAY, NOT A SCREEN.
--
-- Reported from play, with a shot of both: "the pink is supposed to be blank
-- and allowing the map to show through".  The violet ground IS the field's
-- colour 0 -- the background's transparency -- and the extractor was baking
-- it opaque while this state claimed the whole surface, so the mart painted a
-- solid purple sheet over Hoenn instead of standing in front of it.
Gen3ShopMenu.isOpaque = false

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the three panels, matched to the bag's.
-- WHERE THE CARTRIDGE PUTS THE PANELS, measured off its OWN field rather
-- than off a screenshot.
--
-- The counter's background is one 240x160 picture (see the extractor's
-- shopMenuField) and it already has holes in it: a cream list panel on the
-- right, a white box across the bottom left, and a 24x24 socket for the
-- selected item's icon.  Walking that picture a tile at a time gives their
-- rectangles exactly -- list (14,1) 15x18, description (0,13) 14x6, icon
-- (1,9) 3x3 -- and they are NOT where this screen had been drawing its own
-- boxes: the list was three tiles too far left and five rows too short, and
-- the description ran the full width of the screen, under the list panel.
--
-- The money and the "IN BAG" count sit over plain ground in the picture,
-- because on the cartridge those two are windows opened at runtime; those
-- keep the port's drawn frame, which is what a window is.
local FIELD_LIST = { tx = 14, ty = 1,  tw = 15, th = 18 }
local FIELD_DESC = { tx = 0,  ty = 13, tw = 14, th = 6 }
local FIELD_ICON = { x = 12, y = 74, size = 24 }

-- ...AND THE RUNTIME WINDOWS ARE sShopBuyMenuWindowTemplates, verbatim.
--
-- Those are INTERIORS -- the cartridge draws its frame in the tiles around
-- them -- and Font.drawBox takes the outer rectangle, so `framed` is the one
-- conversion between the two.  The list and the description are holes in the
-- field picture and keep the rectangles measured off it, which agree.
local WIN_MONEY   = { tx = 1,  ty = 1,  tw = 10, th = 2 }
local WIN_IN_BAG  = { tx = 1,  ty = 11, tw = 12, th = 2 }
local WIN_PRICE   = { tx = 18, ty = 11, tw = 10, th = 2 }
local WIN_MESSAGE = { tx = 2,  ty = 15, tw = 27, th = 4 }
local function framed(w)
  return { tx = w.tx - 1, ty = w.ty - 1, tw = w.tw + 2, th = w.th + 2 }
end

-- sShopBuyMenuListTemplate: the cursor at the window's own left edge, the
-- name eight pixels in, the price right-aligned 120 pixels across, and the
-- first row one pixel down.
local LIST_CURSOR_X = 0
local LIST_ITEM_X = 8
local LIST_PRICE_RIGHT = 120
local LIST_UP_TEXT_Y = 1

local MONEY_BOX = framed(WIN_MONEY)
local LIST_BOX  = { tx = 11, ty = 0, tw = 19, th = 13 }
local DESC_BOX  = { tx = 0, ty = 13, tw = 30, th = 7 }
local ROW_PITCH = 16
local VISIBLE_ROWS = 6

-- HOW MANY ROWS FIT, which the cartridge's own panel decides.
--
-- The drawn box held six; the field's list panel is eighteen tiles tall and
-- holds eight at the cartridge's sixteen-pixel pitch.  Scrolling has to agree
-- with drawing or the cursor walks off the bottom of a panel that still has
-- room, so both ask this.
function Gen3ShopMenu.rows(game)
  local path = ((game and game.data and game.data.constants or {})
                .gen3ShopMenu or {}).image
  if type(path) ~= "string" then return VISIBLE_ROWS end
  return math.floor((FIELD_LIST.th - 1) * 8 / ROW_PITCH)
end
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

local function buyRecord(game)
  local r = (game.data.constants or {}).gen3BuyMenu
  return type(r) == "table" and type(r.windows) == "table" and r or nil
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
  local fit = Gen3ShopMenu.rows(self.game)
  self.top = math.max(1, math.min(self.top or 1, #rows - fit + 1))
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
  -- the counter box this list was opened from, hidden while it is up
  self.under = opts.under
  self.index, self.top = 1, 1
  self.say = nil
  -- FireRed's screen shows the shop floor through its frame
  if buyRecord(game) and self.kind == "item" then self.isOpaque = false end
  self:rebuild()
  return self
end

-- THE COUNTER: BUY, SELL, QUIT -- and the loop back to it.
--
-- Reported from play, with screenshots: "the pokemarts sell menu isnt showing
-- the gen3 bag and the buy menu isnt looking like the gen3 buy menu".  Both
-- had the same cause, and it was not in this file: `pokemart` pushed the
-- screen id "ShopMenu", and Screens.GEN3_ALIASES has no entry for that name --
-- so every counter in Hoenn fell straight through to src/ui/ShopMenu.lua,
-- pokered's Game Boy list, which is what those screenshots are.  This screen
-- had been built for exactly that complaint and only the decoration counters
-- were ever reaching it.
--
-- The three-row menu lives here rather than at the call site because it is
-- part of the counter: `pokemart` (mode 0) builds it at 0x00DFA8E and the two
-- decoration modes branch straight past it at 0x00DFA8C, which is why
-- Gen3Commands.g3_decoration_mart opens the list directly and this does not.
--
-- The words are the cartridge's -- gen3MartText carries BUY, SELL and QUIT --
-- and so is the LOOP: closing either list comes back here rather than
-- leaving the counter, which is the "Is there anything else I can help you
-- with?" the clerk says, and only QUIT (or B) hands the script back.
-- WHERE THE THREE-ROW BOX GOES, read rather than guessed.
--
-- sShopMenuWindowTemplates says (2,1), nine tiles by six, and those are the
-- window's INTERIOR -- the port's box includes its frame, so it is two tiles
-- wider and taller and starts one tile up and left.  extractShopMenu reads
-- it; a dataset without it keeps the Game Boy's corner.
--
-- The uiSize override matters as much as the coordinates: a menu with no
-- surface of its own is CENTRED inside the 240x160 the overworld holds, which
-- takes a box the cartridge puts two tiles from the left edge and drops it in
-- the middle of the screen.
function Gen3ShopMenu.counterBox(game)
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

-- THE COUNTER: BUY, SELL, QUIT.
--
-- Reported from play, with screenshots: "the pokemarts sell menu isnt showing
-- the gen3 bag and the buy menu isnt looking like the gen3 buy menu".  The
-- `pokemart` command pushed the screen id "ShopMenu", which has no entry in
-- Screens.GEN3_ALIASES, so it resolved to src/ui/ShopMenu.lua -- pokered's.
-- That file did hand Hoenn over to this screen, but only after its own
-- detour; naming this one directly is what makes the route legible.
--
-- The three rows live here rather than at the call site because they are part
-- of the counter: `pokemart` (mode 0) builds them at 0x00DFA8E and the two
-- decoration modes branch straight past it at 0x00DFA8C, which is why
-- Gen3Commands.g3_decoration_mart opens the list directly and this does not.
--
-- `keepOpen` is the cartridge's shape: the box stays UNDER the list it opens,
-- so closing the list lands back on it -- "Is there anything else I can help
-- you with?" -- and only QUIT (or B) hands the script back.
function Gen3ShopMenu.counter(game, opts)
  opts = opts or {}
  local Menu = require("src.ui.Menu")
  local stock = opts.stock or {}
  local onQuit = opts.onQuit
  -- ...AND THE THREE-ROW BOX GOES AWAY WHILE THE LIST IS UP.  The counter is
  -- an overlay now, so anything left under it shows through its own
  -- transparent ground -- and on the cartridge the buy screen is a screen,
  -- with no BUY/SELL/QUIT box behind it.  `hidden` keeps the state on the
  -- stack, which is what makes closing the list land back on it.
  local menu
  menu = Menu.new(game, {
    { label = line(game, "buy", Strings("BUY")), keepOpen = true,
      onSelect = function()
        menu.hidden = true
        game.stack:push(Gen3ShopMenu.new(game, { mode = "buy", stock = stock,
                                                 under = menu }))
      end },
    { label = line(game, "sell", Strings("SELL")), keepOpen = true,
      onSelect = function() Gen3ShopMenu.openSellBag(game) end },
    { label = line(game, "quit", Strings("QUIT")), onSelect = onQuit },
  }, Gen3ShopMenu.counterBox(game))
  menu.uiSize = function() return require("src.ui.Theme").uiSize() end
  menu.onCancel = onQuit
  game.stack:push(menu)
  return menu
end

function Gen3ShopMenu:selected() return self.rows[self.index] end

-- "x{VAR1}", which is the cartridge's own multiplier string -- the same one
-- the bag's quantity window uses, swept out of the mart text block beside the
-- money glyph.  Two decimal places, because the window is sized for them.
function Gen3ShopMenu:quantityGlyph(n)
  local text = mart(self.game).quantity
  if type(text) == "string" then
    return fill(text, { VAR1 = ("%02d"):format(n) })
  end
  return ("x%02d"):format(n)
end

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
  if self.under then self.under.hidden = nil end
  if self.game.stack then self.game.stack:pop() end
  if self.onQuit then self.onQuit() end
end

function Gen3ShopMenu:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.index = (self.index - 1 + delta) % n + 1
  if self.index < self.top then self.top = self.index end
  local fit = Gen3ShopMenu.rows(self.game)
  if self.index > self.top + fit - 1 then
    self.top = self.index - fit + 1
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
      require("src.pokemon.Gen3GameStats").increment(game.save, 38) -- GAME_STAT_SHOPPED
      require("src.core.Sound").play(game.data, "Purchase")
      self.say = self:repeatLine()
                 or line(game, "boughtBag", Strings("Here you are!\nThank you!"))
    end,
  }))
end

-- THE "HOW MANY" DIALOGUE IS PART OF THIS SCREEN, not a box pushed over it.
--
-- Reported from play, with a shot of the cartridge: "it should pop up asking
-- how many youd like to buy like in the second image".  Three windows open
-- together on the cartridge and close together -- Task_BuyHowManyDialogueInit
-- draws WIN_QUANTITY_IN_BAG and WIN_QUANTITY_PRICE, and the clerk's question
-- goes in WIN_MESSAGE -- and the port was pushing the Game Boy's quantity box
-- over the counter instead, which is why IN BAG stood there the whole time
-- and the question only arrived after the number had been picked.
--
-- So the state lives here: `self.asking` is the dialogue, and while it is up
-- this screen owns the pad.
function Gen3ShopMenu:askQuantity(row, opts)
  self.asking = {
    row = row,
    qty = 1,
    max = math.max(1, math.floor(opts.max or 99)),
    unit = math.max(0, opts.unit or 0),
    message = opts.message,
    onDone = opts.onDone,
  }
  self.say = nil
end

function Gen3ShopMenu:askQuantityInput(step, confirm, cancel)
  local ask = self.asking
  if not ask then return false end
  if cancel then
    self.asking = nil
    return true
  end
  if confirm then
    self.asking = nil
    if ask.onDone then ask.onDone(ask.qty) end
    return true
  end
  if step and step ~= 0 then
    local n = ask.qty + step
    if n < 1 then n = ask.max elseif n > ask.max then n = 1 end
    ask.qty = n
  end
  return true
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
  local TextBox = require("src.render.TextBox")
  self:askQuantity(row, {
    max = math.max(1, most),
    unit = unit,
    message = line(game, "buyHowMany",
                   Strings("%s? Certainly.\nHow many would you like?",
                           row.label),
                   { VAR1 = row.label }),
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
      require("src.pokemon.Gen3GameStats").increment(game.save, 38) -- GAME_STAT_SHOPPED
          require("src.core.Sound").play(game.data, "Purchase")
          self.say = line(game, "boughtBag",
                          Strings("Here you are!\nThank you!"))
        end,
      }))
    end,
  })
end

-- SELLING ONE ITEM, wherever the pick came from.
--
-- Reported from play: "the sell menu should have badges like the bag".  It
-- should -- and the reason it did not have them is that selling was a list of
-- its own here rather than THE BAG.  On the cartridge SELL is
-- CB2_GoToSellMenu, which opens the same bag screen the START menu does with
-- its shop flag set: the five pockets, L and R between them, the bag sprite
-- and the pocket dots down its side.  So the flow moved into the bag and this
-- became the part that is the same either way -- ask how many, name a price,
-- take the yes.
--
-- `host` is whoever is showing the words: `say` writes a line the screen keeps
-- until the cursor moves, `refresh` rebuilds the list under it.
function Gen3ShopMenu.sellItem(game, id, host)
  local def = game.data.items and game.data.items[id]
  local label = (def and def.name) or id
  local function say(text) if host and host.say then host.say(text) end end
  if unsellable(game, id, def) then
    say(line(game, "cantBuy", Strings("I can't put a\nprice on that."),
             { VAR1 = label, VAR2 = label }))
    return
  end
  local unit = math.max(0, sellPriceOf(def))
  local held = (game.save.inventory or {})[id] or 1
  local TextBox = require("src.render.TextBox")
  local ask = (host and host.ask) or function(opts)
    -- no host dialogue of its own: the Game Boy box, which is what the bag
    -- and any other caller still get
    local QuantityBox = require("src.ui.QuantityBox")
    game.stack:push(QuantityBox.new(game, {
      max = opts.max, unitPrice = opts.unit, onDone = opts.onDone,
    }))
  end
  ask({
    max = math.max(1, held),
    unit = unit,
    message = line(game, "sellHowMany",
                   Strings("How many would you like to sell?"),
                   { VAR1 = label }),
    onDone = function(qty)
      if not qty then return end
      local paid = unit * qty
      -- WHICH {VARn} CARRIES THE PRICE IS NOT THE SAME NUMBER ON BOTH
      -- CARTRIDGES.  Emerald's line is "I can pay ¥{STR_VAR_1}." -- FireRed's
      -- is "I can pay ¥{STR_VAR_3}." (strings.c, both games).  This message
      -- has exactly one placeholder, so it costs nothing to fill every slot
      -- with the same value rather than pick the wrong one and print a
      -- blank amount, which is what a hard-coded VAR1 did against FireRed.
      local ask = line(game, "sellPrice",
                       Strings("I can pay you\n%s for that.",
                               price(game, paid)),
                       { VAR1 = tostring(paid), VAR2 = tostring(paid),
                         VAR3 = tostring(paid) })
      game.stack:push(TextBox.new(game, ask, nil, {
        choice = function(yes)
          if not yes then return end
          game.save.money = (tonumber(game.save.money) or 0) + paid
          Bag.remove(game.save, id, qty)
          if host and host.refresh then host.refresh() end
          -- Emerald: "Turned over the {VAR2}\nand received ¥{VAR1}." --
          -- FireRed: "Turned over the {VAR1}...\nworth ¥{VAR3}."  The two
          -- meanings (amount, item) sit in DIFFERENT slots per game -- VAR1
          -- is the amount on one cartridge and the item on the other -- so
          -- unlike sellPrice above this cannot be answered with one value
          -- in every slot; it has to know which cartridge it is.
          local soldVars
          if require("src.core.GameVersion").isFRLG() then
            soldVars = { VAR1 = label, VAR3 = tostring(paid) }
          else
            soldVars = { VAR1 = tostring(paid), VAR2 = label }
          end
          say(line(game, "sold", Strings("Thank you!"), soldVars))
        end,
      }))
    end,
  })
end

function Gen3ShopMenu:sell(row)
  return Gen3ShopMenu.sellItem(self.game, row.id, {
    say = function(text) self.say = text end,
    refresh = function() self:rebuild() end,
    ask = function(opts) self:askQuantity(row, opts) end,
  })
end

-- The bag, opened to sell out of: every pocket, and the pick sells rather
-- than opening the USE/TOSS question.
function Gen3ShopMenu.openSellBag(game)
  local ok, Gen3BagMenu = pcall(require, "src.ui.Gen3BagMenu")
  if not (ok and Gen3BagMenu) then
    return game.stack:push(Gen3ShopMenu.new(game, { mode = "sell" }))
  end
  return game.stack:push(Gen3BagMenu.new(game, { sell = true }))
end

function Gen3ShopMenu:update()
  local input = self.game.input
  if not input then return end
  -- while the "how many" windows are open the pad belongs to them, and UP
  -- counts up the way the cartridge's own selector does
  if self.asking then
    if input:wasPressed("up") then return self:askQuantityInput(1) end
    if input:wasPressed("down") then return self:askQuantityInput(-1) end
    if input:wasPressed("right") then
      local ask = self.asking
      ask.qty = math.min(ask.max, ask.qty + 10)
      return true
    end
    if input:wasPressed("left") then
      local ask = self.asking
      ask.qty = math.max(1, ask.qty - 10)
      return true
    end
    if input:wasPressed("a") then return self:askQuantityInput(0, true) end
    if input:wasPressed("b") then return self:askQuantityInput(0, false, true) end
    return
  end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

function Gen3ShopMenu:keypressed(key)
  if self.asking then
    if key == "up" then return self:askQuantityInput(1) end
    if key == "down" then return self:askQuantityInput(-1) end
    if key == "right" then
      local ask = self.asking
      ask.qty = math.min(ask.max, ask.qty + 10)
      return true
    end
    if key == "left" then
      local ask = self.asking
      ask.qty = math.max(1, ask.qty - 10)
      return true
    end
    if key == "a" then return self:askQuantityInput(0, true) end
    if key == "b" then return self:askQuantityInput(0, false, true) end
    return
  end
  if key == "down" then return self:moveCursor(1) end
  if key == "up" then return self:moveCursor(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

-- ---------------------------------------------------------------------------
-- DRAWING IT
-- ---------------------------------------------------------------------------
local function drawRows(self, box, rows, field)
  box = box or LIST_BOX
  -- ON THE FIELD the list window is the cartridge's, so the offsets are its
  -- own ListMenuTemplate's -- cursor at the window's left edge, the name
  -- eight pixels in, the price right-aligned 120 across.  On the port's drawn
  -- box they stay where they were, because that box is a tile wider a side.
  local left = field and box.tx * 8 or ((box.tx + 1) * 8)
  local x = left + (field and LIST_ITEM_X or CURSOR_INSET + 8)
  local cursorX = left + (field and LIST_CURSOR_X or CURSOR_INSET)
  local right = left + (field and LIST_PRICE_RIGHT or (box.tw - 2) * 8)
  local top = (box.ty + 1) * 8 + (field and LIST_UP_TEXT_Y or 0)
  for i = 0, (rows or VISIBLE_ROWS) - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = top + i * ROW_PITCH
    Font.draw(row.label, x, y)
    if row.right then
      Font.draw(row.right, right - Font.width(row.right), y)
    end
    if self.top + i == self.index then
      Font.drawCode(Theme.cursor, cursorX, y)
    end
  end
end

-- FIRERED'S BUY SCREEN, when the import lifted it (constants.gen3BuyMenu):
-- the cartridge's own frame over the world, and every piece of text in the
-- window sShopBuyMenuWindowTemplatesNormal gives it.  The frame's empty left
-- column is BuyMenuDrawMapView's shop floor, which here is the live world
-- drawn underneath (the screen is not opaque while this record exists).

function Gen3ShopMenu:drawFrlg(r)
  local W = r.windows
  local ok, frame = pcall(require("src.render.Assets").image, r.image)
  love.graphics.setColor(1, 1, 1, 1)
  if ok and frame then love.graphics.draw(frame, 0, 0) end

  -- money: a standard window with the amount right-aligned in it
  local mw = W.money
  Font.drawBox(math.floor(mw.x / 8) - 1, math.floor(mw.y / 8) - 1,
               math.floor(mw.width / 8) + 2, math.floor(mw.height / 8) + 2)
  local label = self:moneyLabel()
  if label then Font.draw(label, mw.x, mw.y) end
  local amount = price(self.game, tonumber(self.game.save.money) or 0)
  Font.draw(amount, mw.x + mw.width - Font.width(amount), mw.y + 12)

  -- the list: name at item_X, price in the small face at 0x69, cursor at 1
  local L = r.list or {}
  local lw = W.list
  local pitch = tonumber(L.rowHeight) or ROW_PITCH
  local rows = tonumber(L.rows) or VISIBLE_ROWS
  for i = 0, rows - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = lw.y + (tonumber(L.upTextY) or 2) + i * pitch
    Font.draw(row.label, lw.x + (tonumber(L.itemX) or 9), y)
    if row.unit and not row.close then
      local faced = Font.pushFace("small")
      local text = price(self.game, row.unit)
      Font.draw(text, lw.x + (tonumber(L.priceX) or 105), y)
      if faced then Font.popFace() end
    end
    if self.top + i == self.index then
      Font.drawCode(Theme.cursor, lw.x + (tonumber(L.cursorX) or 1), y)
    end
  end

  local row = self:selected()
  local ask = self.asking
  if ask then
    local function windowBox(w)
      Font.drawBox(math.floor(w.x / 8) - 1, math.floor(w.y / 8) - 1,
                   math.floor(w.width / 8) + 2,
                   math.floor(w.height / 8) + 2)
    end
    local ib = W.inBag
    windowBox(ib)
    local have = (self.game.save.inventory or {})[ask.row.id] or 0
    Font.draw(line(self.game, "inBag", Strings("IN BAG: %d", have),
                   { VAR1 = tostring(have) }), ib.x, ib.y)

    local qw = W.quantity
    windowBox(qw)
    local faced = Font.pushFace("small")
    Font.draw(self:quantityGlyph(ask.qty), qw.x + 2, qw.y + 10)
    local total = price(self.game, ask.unit * ask.qty)
    Font.draw(total, qw.x + qw.width - Font.width(total), qw.y + 10)
    if faced then Font.popFace() end

    local msg = W.message
    windowBox(msg)
    local my = msg.y
    for chunk in (tostring(ask.message or "") .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(chunk, msg.x, my)
      my = my + 14
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- description (or the clerk's line) and the item's picture
  local dw, D = W.description, r.description or {}
  local text = self.say or (row and (row.close and line(self.game,
                 "quitShopping", "Quit shopping.") or row.description)) or ""
  local y = dw.y + (tonumber(D.y) or 3)
  for chunk in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(chunk, dw.x + (tonumber(D.x) or 0), y)
    y = y + (tonumber(D.lineHeight) or 14)
  end
  local icons = (self.game.data.constants or {}).gen3ItemIcons
  local def = row and row.id and self.game.data.items and self.game.data.items[row.id]
  local index = row and row.close and (icons and icons.listEnd)
                or (def and tonumber(def.index))
  if icons and icons.image and index then
    local okI, img = pcall(require("src.render.Assets").image, icons.image)
    if okI and img then
      local size, cols = icons.size or 24, icons.cols or 1
      local iw, ih = img:getDimensions()
      local quad = love.graphics.newQuad((index % cols) * size,
                                         math.floor(index / cols) * size,
                                         size, size, iw, ih)
      local at = r.itemIcon or { x = 8, y = 124 }
      love.graphics.draw(img, quad, at.x, at.y)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

-- The counter's own background, when this cache carries it.
function Gen3ShopMenu:field()
  local path = ((self.game.data.constants or {}).gen3ShopMenu or {}).image
  if type(path) ~= "string" then return nil end
  local ok, Assets = pcall(require, "src.render.Assets")
  if not ok then return nil end
  local okImg, img = pcall(Assets.image, path)
  return okImg and img or nil
end

function Gen3ShopMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  local frlg = buyRecord(self.game)
  if frlg and self.kind == "item" then return self:drawFrlg(frlg) end

  -- THE CARTRIDGE'S FIELD, when it is in the cache.
  --
  -- Asked for directly: "ensure the rom art is extracted and its loading the
  -- emerald menus properly".  With the picture there, the list panel, the
  -- description box and the item's socket are already drawn in it, so the
  -- port's own frames would double every border -- the same rule the bag
  -- follows.  Only the two runtime windows are drawn on top.
  local field = self:field()
  local listBox = field and FIELD_LIST or LIST_BOX
  local descBox = field and FIELD_DESC or DESC_BOX
  local listRows = Gen3ShopMenu.rows(self.game)
  if field then
    love.graphics.draw(field, 0, 0)
  end

  -- THE MONEY.  The word over it is the cartridge's own -- the trainer card
  -- already had to find it, and there is no second "MONEY" in Hoenn.
  -- ONE LINE, not two: sShopBuyMenuWindowTemplates gives WIN_MONEY a two-tile
  -- interior, which is a single row of text with the word at its left edge and
  -- the number against its right
  Font.drawBox(MONEY_BOX.tx, MONEY_BOX.ty, MONEY_BOX.tw, MONEY_BOX.th)
  local moneyY = WIN_MONEY.ty * 8
  local label = self:moneyLabel()
  if label then Font.draw(label, WIN_MONEY.tx * 8, moneyY) end
  local amount = price(self.game, tonumber(self.game.save.money) or 0)
  Font.draw(amount, (WIN_MONEY.tx + WIN_MONEY.tw) * 8 - Font.width(amount),
            moneyY)

  if not field then
    Font.drawBox(listBox.tx, listBox.ty, listBox.tw, listBox.th)
  end
  drawRows(self, listBox, listRows, field and true or false)

  if not field then
    Font.drawBox(descBox.tx, descBox.ty, descBox.tw, descBox.th)
  end
  local row = self:selected()
  -- WHAT THE PANEL SAYS.  The clerk's last line while there is one, and the
  -- item's own description otherwise, which is what the cartridge shows while
  -- the cursor is just moving.  While the quantity windows are open the
  -- question takes the bottom of the screen instead, in WIN_MESSAGE.
  if not self.asking then
    local text = self.say or (row and not row.close and row.description) or ""
    local y = (descBox.ty + 1) * 8
    for chunk in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(chunk, (descBox.tx + 1) * 8, y)
      y = y + 14
    end
  end

  -- ...AND THE ITEM'S OWN PICTURE, in the socket the field already draws.
  -- The atlas is the bag's -- one icon per item, keyed on the cartridge's own
  -- index -- so this is the same lookup that screen makes.
  -- THE PICTURE WAS NEVER DRAWN, and the reason is one `and`.
  --
  -- Reported from play: "in the pokemart buy menu missing the images of the
  -- items".  `local okImg, icon = okA and pcall(Assets.image, ...)` reads as
  -- two results and is not: `and` is an expression, so it is adjusted to ONE
  -- value -- okImg took pcall's true and `icon` was always nil, so this block
  -- loaded the atlas every frame and drew nothing out of it.
  if field and row and not row.close and row.id and not row.decoration then
    local rec = (self.game.data.constants or {}).gen3ItemIcons
    local def = self.game.data.items and self.game.data.items[row.id]
    local index = rec and type(rec.image) == "string" and def
                  and tonumber(def.index)
    local okA, Assets = pcall(require, "src.render.Assets")
    if index and okA then
      local okImg, icon = pcall(Assets.image, rec.image)
      if okImg and icon then
        local size = math.max(1, math.floor(tonumber(rec.size) or 24))
        local cols = math.max(1, math.floor(tonumber(rec.cols) or 1))
        local count = math.floor(tonumber(rec.count) or 0)
        if index < 0 or index >= count then
          index = math.floor(tonumber(rec.blank) or 0)
        end
        local iw, ih = icon:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon,
          love.graphics.newQuad((index % cols) * size,
                                math.floor(index / cols) * size,
                                size, size, iw, ih),
          FIELD_ICON.x, FIELD_ICON.y)
      end
    end
  end

  -- THE THREE WINDOWS OF THE "HOW MANY" DIALOGUE, which open together and
  -- close together the way Task_BuyHowManyDialogueInit opens them: how many
  -- you already hold, over the item's own socket; the running total, across
  -- the list; and the clerk's question along the bottom.
  --
  -- IN BAG used to stand there the whole time, in a box of its own under the
  -- money -- reported as "the in bag is supposed to only appear when an item
  -- is clicked and cover the image of the item".  It is WIN_QUANTITY_IN_BAG,
  -- and where the cartridge puts it is exactly over the icon.
  local ask = self.asking
  if ask then
    local bagBox = framed(WIN_IN_BAG)
    Font.drawBox(bagBox.tx, bagBox.ty, bagBox.tw, bagBox.th)
    local have
    if ask.row.decoration then
      have = require("src.world.Gen3Decorations")
             .count(self.game.save, ask.row.id)
    else
      have = (self.game.save.inventory or {})[ask.row.id] or 0
    end
    local inBag = line(self.game, "inBag", Strings("IN BAG: %d", have),
                       { VAR1 = tostring(have) })
    Font.draw(inBag, WIN_IN_BAG.tx * 8, WIN_IN_BAG.ty * 8)

    local priceBox = framed(WIN_PRICE)
    Font.drawBox(priceBox.tx, priceBox.ty, priceBox.tw, priceBox.th)
    local count = self:quantityGlyph(ask.qty)
    local total = price(self.game, ask.unit * ask.qty)
    Font.draw(count, WIN_PRICE.tx * 8, WIN_PRICE.ty * 8)
    Font.draw(total, (WIN_PRICE.tx + WIN_PRICE.tw) * 8 - Font.width(total),
              WIN_PRICE.ty * 8)

    local msgBox = framed(WIN_MESSAGE)
    Font.drawBox(msgBox.tx, msgBox.ty, msgBox.tw, msgBox.th)
    local y2 = WIN_MESSAGE.ty * 8
    for chunk in (tostring(ask.message or "") .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(chunk, WIN_MESSAGE.tx * 8, y2)
      y2 = y2 + 14
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ShopMenu
