-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's BAG.
--
-- Not the Gen 2 pack with different words.  That screen is a Game Boy list in
-- a 160x144 letterbox with four pockets called ITEMS / BALLS / KEY ITEMS /
-- TM-HM; this one is a 240x160 GBA screen with FIVE, in the cartridge's own
-- order, its own words, and a description panel under the list that the Game
-- Boy bag does not have.
--
-- WHERE THE POCKETS COME FROM, and why it matters that they are read.
--
-- Nothing on the cartridge declares the bag's contents either -- but the five
-- pocket names sit CONSECUTIVELY in the text region in tab order, so that run
-- is the layout, exactly as the START menu's labels were.
--
--   ITEMS   POKé BALLS   TMs & HMs   BERRIES   KEY ITEMS
--
-- And there is a trap in it: the SAME five words appear a second time, in a
-- DIFFERENT order, as the PC's deposit list (ITEMS, KEY ITEMS, POKé BALLS,
-- TMs & HMs, BERRIES).  Nothing but the order tells the two runs apart, so
-- the discovery pass locates both and records them separately; this screen
-- reads the BAG's.  Written from memory it would have had KEY ITEMS third.
--
-- THE BAG ITSELF is the cartridge's too, now.  It never passes a background
-- loader -- it is a compressed SPRITE sheet -- so every graphics pass here
-- was structurally blind to it, and the screen had a rectangle of empty green
-- where the biggest object on it belongs.  The discovery pass finds it as a
-- same-tag PAIR of sheets (the boy's bag and the girl's), six 64x64 frames
-- each, with the sprite palette carrying that tag right behind them.
--
-- WHICH FRAME goes with which pocket is a reconstruction: the six are the bag
-- tilted toward each tab, and pairing them in order is the reading that makes
-- the tilt follow the cursor.  What is NOT reconstructed is the art or which
-- of the two bags a save carries -- that is the player's own answer to
-- Birch's question.
--
-- THE GEOMETRY IS DERIVED NOW TOO, and it was the last thing here that was
-- not.  sDefaultBagWindows is six { bg, tileX, tileY, w, h, palette,
-- baseBlock } rows terminated by a $FF, and the ten unterminated rows behind
-- it are the context menu's; the list's own offsets -- where the item name
-- starts, where the cursor goes, where the count is right-aligned -- come off
-- its ListMenuTemplate.  All of it was already in the cache under
-- gen3BagScreen and this screen read NONE of it: three boxes placed by hand
-- on a flat green fill, with the cartridge's own 240x160 field sitting
-- unused beside them.
--
-- The item's picture is derived as well: gItemIconTable is 378 pairs of an
-- LZ77 24x24 sheet and an LZ77 palette, composed into one atlas whose slot is
-- the item's own cartridge index.

local Assets = require("src.render.Assets")
local UiQuad = require("src.render.UiQuad")
local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

-- Gen3Wide is asked for on every frame and from uiSize/sgbPalettes on
-- whatever cadence the renderer queries them; resolved once instead.
local Gen3WideMod
local function gen3Wide()
  Gen3WideMod = Gen3WideMod or require("src.ui.Gen3Wide")
  return Gen3WideMod
end

local Gen3BagMenu = {}
Gen3BagMenu.__index = Gen3BagMenu
-- Every other full-screen menu in this port (ShopMenu, Gen3ShopMenu,
-- Gen3Options, ...) declares this; the bag never did.  Opening the TM CASE
-- or the BERRY POUCH pushes a SECOND Gen3BagMenu on top of the first, and
-- with neither one opaque the stack draws from the bottom up (Game.
-- drawBaseInStack / StateStack:visibleBase) -- the parent screen's bag
-- sprite, tilted toward whatever pocket it was on, painted first and then
-- only PARTLY covered by the child's own background.  Reported from play as
-- a grey silhouette showing through the TM CASE screen.
Gen3BagMenu.isOpaque = true

-- THE BAG IS THE WHOLE SCREEN, and saying so is a bug fix.
--
-- Reported from play, with a screenshot: a column of somebody else's letters
-- down the left-hand edge of the bag.  It was the OVERWORLD, still drawing
-- underneath.  Every other full-screen page in Hoenn -- the dex, the region
-- map, the mart, the summary, the trainer card -- sets this, and the stack
-- draws only from the highest opaque state up (StateStack:visibleBase); the
-- bag never did, so whatever was beneath it kept painting.  It did not show
-- while the surface was the cartridge's own 240 columns, because the bag's
-- own field covered all of them.  It shows now that the field can be wider
-- than the picture.
Gen3BagMenu.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- the field's own edge columns, keyed on its size
local edgeW, edgeH, edgeLeft, edgeRight
local function edgeQuads(fw, fh)
  if edgeW ~= fw or edgeH ~= fh then
    edgeLeft = love.graphics.newQuad(0, 0, 1, fh, fw, fh)
    edgeRight = love.graphics.newQuad(GBA_W - 1, 0, 1, fh, fw, fh)
    edgeW, edgeH = fw, fh
  end
  return edgeLeft, edgeRight
end


-- THE CARTRIDGE'S, when the import has been run; the reconstruction below
-- only when it has not.
--
-- constants.gen3BagScreen carries the composed 240x160 background in both
-- palettes, all six sDefaultBagWindows rectangles, the list's own
-- ListMenuTemplate offsets, the bag sprite's centre, the item icon's cell and
-- the five pocket dots.  Every one of those was written by the importer and
-- read by NOBODY: this screen drew three boxes it placed itself on a flat
-- green fill, which is why it kept looking close but not right.
local FALLBACK = {
  windows = {
    pocketName  = { x = 0,  y = 0,   width = 88,  height = 24 },
    list        = { x = 88, y = 0,   width = 152, height = 104 },
    description = { x = 0,  y = 104, width = 240, height = 56 },
  },
  list = { itemX = 8, cursorX = 0, upTextY = 1, rowHeight = 16, rows = 6,
           quantityRight = 119 },
  description = { x = 3, y = 1 },
  bag = { x = 36, y = 34, size = 64 },
  itemIcon = { x = 8, y = 72, size = 24 },
  pocketDots = { x = 40, y = 24, step = 8, count = 5,
                 selected = { dx = 2, dy = 3, width = 4, height = 4,
                              colour = { male = { 255, 0, 0 },
                                         female = { 106, 180, 213 } } } },
}
local ROW_PITCH = 16
local CURSOR_INSET = 4

-- The pockets, in the cartridge's tab order, paired with the engine's own
-- pocket keys.  The ORDER is the cartridge's; this table only says which of
-- the engine's item classes each of its words covers.
local POCKET_KEYS = { "ITEM", "BALL", "TM_HM", "BERRY", "KEY_ITEM" }

-- ...AND IT ASKS FOR THE WIDE SURFACE, like the title and the main menu, so
-- the margins belong to this screen rather than to whatever is behind it.
function Gen3BagMenu:uiSize()
  return gen3Wide().uiSize()
end
function Gen3BagMenu:wantsFillScale() return true end

function Gen3BagMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local w = select(1, gen3Wide().uiSize())
  return { P.trueColorZone(0, 0, math.ceil(w / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function screenText(game, key)
  local record = ((game.data.constants or {}).gen3Screens or {})[key]
  return record and record.items or nil
end

-- Which pocket an item belongs in, by the fields the port already carries.
-- The item record's own `pocket` wins where the cartridge shipped one.
local function pocketOf(def, id)
  if def and def.pocket then
    local p = def.pocket
    if p == "POKE_BALLS" then return "BALL" end
    if p == "TM_HM" or p == "TMHM" then return "TM_HM" end
    if p == "BERRIES" then return "BERRY" end
    if p == "KEY_ITEMS" then return "KEY_ITEM" end
    return p
  end
  if def and def.berry then return "BERRY" end
  if def and def.machine then return "TM_HM" end
  if def and def.ball then return "BALL" end
  if def and def.keyItem then return "KEY_ITEM" end
  if type(id) == "string" then
    if id:find("^TM_") or id:find("^HM_") then return "TM_HM" end
    if id:find("BERRY") then return "BERRY" end
  end
  return "ITEM"
end

function Gen3BagMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3BagMenu)
  self.game = game
  self.onCancel = opts.onCancel
  -- opened mid-battle: the pick USES the item there and then, against the
  -- fight, rather than opening the field item flow (see choose())
  self.battle = opts.battle
  self.itemPc = opts.itemPc and true or false
  self.pocket = 1
  self.index = 1
  self.top = 1

  local names = screenText(game, "bagPockets")
  if not names then
    Logger.warn("gen3 bag: this dataset carries no pocket names -- falling "
                .. "back to the engine's own")
    names = { Strings("ITEMS"), "POKé BALLS", "TMs & HMs", Strings("BERRIES"),
              Strings("KEY ITEMS") }
  end
  self.pockets = {}
  local screenRec = (game.data.constants or {}).gen3BagScreen
  self.frlg = type(screenRec) == "table" and screenRec.layout == "frlg"
  if self.frlg then
    -- FIRERED'S BAG HAS THREE POCKETS (sPocketNames): the TMs and berries
    -- live in the TM CASE and BERRY POUCH, which open lists of their own
    local frNames = (names and #names == 3) and names
      or { "ITEMS", "KEY ITEMS", "POKé BALLS" }
    for i, key in ipairs({ "ITEM", "KEY_ITEM", "BALL" }) do
      self.pockets[i] = { key = key, name = frNames[i] }
    end
    if opts.pocket == "TM_HM" then
      self.pockets[#self.pockets + 1] = { key = "TM_HM", name = "TM CASE" }
    elseif opts.pocket == "BERRY" then
      self.pockets[#self.pockets + 1] = { key = "BERRY", name = "BERRY POUCH" }
    end
  else
    for i, key in ipairs(POCKET_KEYS) do
      self.pockets[i] = { key = key, name = names[i] or key }
    end
  end
  -- HANDING ONE BACK INSTEAD OF USING IT.
  --
  -- `special Bag_ChooseBerry` is the berry tree asking which berry you want
  -- to plant: it opens the bag AT ONE POCKET, takes a pick, and hands the
  -- item back to the script, which then removes it and plants it.  There is
  -- no USE/TOSS question and no pocket switching -- the cartridge opens the
  -- BERRIES pocket and only that one.
  --
  -- The same shape serves anything else that asks the bag a question rather
  -- than telling it to do something.
  self.pick = opts.pick and true or false
  self.onPick = opts.onPick
  -- SELLING IS THIS SCREEN.  Reported from play: "the sell menu should have
  -- badges like the bag".  It should -- CB2_GoToSellMenu opens the bag with
  -- its shop flag set, so the pockets, the dots and the bag sprite are all
  -- here already and the pick sells instead of asking USE or TOSS.
  self.sell = opts.sell and true or false
  -- THE PC'S TWO USES OF THIS SCREEN.
  --
  -- Reported from play: "the item deposit and withdrawal doesn't seem to work
  -- like it would in emerald and is falling back to gen1 menu".  It was: the
  -- Hoenn PC handed all three item flows to the Game Boy screen in
  -- src/ui/PlayerPC.lua, so ITEM STORAGE opened a pokered list menu inside
  -- Emerald's PC.
  --
  -- Emerald splits them, and WHERE THE CARTRIDGE KEEPS ITS WORDS says how:
  -- "Deposit how many {VAR1}(s)?", "Deposited {VAR2} {VAR1}(s)." and
  -- "Important items can't be stored in the PC!" are BAG strings, sat among
  -- the bag's own toss lines, while "Withdraw how many {VAR1}(s)?",
  -- "Withdrew {VAR2} {VAR1}(s).", "There are no items." and "There is no more
  -- room in the BAG." sit in the PC's own block beside ITEM STORAGE's four
  -- row descriptions.  So DEPOSIT is this bag, listing the bag, taking a pick;
  -- WITHDRAW and TOSS are a screen listing the PC.
  --
  -- `store` is "deposit" (the bag, depositing what you pick), "withdraw" or
  -- "toss" (the same screen over save.pcItems).  The second pair is `pcList`.
  self.store = opts.store
  self.pcList = (self.store == "withdraw" or self.store == "toss")
  if self.pcList then self.lockPocket = true end
  -- FireRed's DEPOSIT ITEM opens the real bag at the ITEMS pocket, but its
  -- ITEMMENULOCATION_ITEMPC mode disables pocket switching.  The striped bag
  -- and the bag sprite are still the real bag; only the title/window semantics
  -- and the input mode change (item_menu.c GoToBagMenu / SwitchBagPocket).
  if self.frlg and self.itemPc then
    self.pocket = 1
    self.lockPocket = true
  end
  if opts.pocket then
    for i, row in ipairs(self.pockets) do
      if row.key == opts.pocket then self.pocket = i break end
    end
    self.lockPocket = true
  end
  self.actions = screenText(game, "bagActions")
  -- ...AND THE ONE THE CATCHING TUTORIAL OPENS, WHICH NOBODY DRIVES.
  --
  -- Reported from play: "the bag he opens in the tutorial is the gen1 bag".
  -- It was -- the demo pushed the engine's generic ListMenu -- and this is
  -- the screen Emerald opens instead.  It is the SAME bag: what the tutorial
  -- changes is only that the list is scripted rather than the save's, and
  -- that no button is ever read.  DisplayListMenuID's tutorial arm does
  -- exactly that, and so does this: `rows` replaces the pocket's contents,
  -- `script` gets a frame, and `noInput` says the pad is not consulted.
  self.scriptRows = opts.rows
  self.script = opts.script
  self.noInput = opts.noInput and true or false
  self:rebuild()
  return self
end

-- The list for the current pocket, in ACQUISITION order (Bag.order), which is
-- what wBagItems holds and what the cartridge shows -- not alphabetical.
-- The extracted screen, or the reconstruction when the cache predates it.
function Gen3BagMenu:screen()
  local r = (self.game.data.constants or {}).gen3BagScreen
  if type(r) ~= "table" or type(r.windows) ~= "table" then return FALLBACK end
  return r
end

-- One window's rectangle, in pixels.  sDefaultBagWindows counts in TILES and
-- the importer multiplies out, so everything here is already pixels.
function Gen3BagMenu:box(key)
  local r = self:screen()
  if self.frlg and key == "quantity" then
    -- sWindowTemplates[0], opened by InitQuantityToTossOrDeposit.
    return { x = 192, y = 120, width = 40, height = 32 }
  end
  return (r.windows and r.windows[key]) or FALLBACK.windows[key]
end

function Gen3BagMenu:subBox(key)
  if self.frlg and key == "quantityPrompt" then
    -- ShowBagWindow(6, 2) -> sWindowTemplates[8].
    return { x = 48, y = 120, width = 128, height = 32 }
  end
  return nil
end

function Gen3BagMenu:drawContentFrame(b, frameIndex)
  if not b then return end
  local tx, ty = math.floor(b.x / 8) - 1, math.floor(b.y / 8) - 1
  local tw, th = math.floor(b.width / 8) + 2, math.floor(b.height / 8) + 2
  if frameIndex == "standard" and Font.drawStandardBox then
    Font.drawStandardBox(tx, ty, tw, th)
  else
    Font.drawBox(tx, ty, tw, th, tonumber(frameIndex) or 1)
  end
end

function Gen3BagMenu:listRows()
  local r = self:screen()
  local n = math.floor(tonumber(r.list and r.list.rows) or FALLBACK.list.rows)
  return math.max(1, n)
end

function Gen3BagMenu:rebuild()
  local game = self.game
  -- a scripted list is the whole pocket: no CLOSE BAG row either, because
  -- the tutorial cannot be backed out of
  if self.scriptRows then
    self.rows = self.scriptRows
    self.index = math.min(math.max(1, self.index), #self.rows)
    self.top = 1
    return
  end
  -- THE PC'S OWN LIST: one list, no pockets, and the store is save.pcItems.
  -- Sorted, because a PC box has no acquisition order to preserve the way
  -- wBagItems does -- pcItems is a map, and a map has no order at all.
  if self.pcList then
    local pc = game.save.pcItems or {}
    local ids = {}
    for id in pairs(pc) do ids[#ids + 1] = id end
    table.sort(ids)
    local rows = {}
    for _, id in ipairs(ids) do
      local def = game.data.items and game.data.items[id]
      rows[#rows + 1] = {
        id = id,
        label = (def and def.name) or id,
        qty = pc[id],
        description = def and (def.description or def.desc),
      }
    end
    -- the cartridge ends the list with CANCEL, and CANCEL is one of the four
    -- words already read off sItemStorageActions
    rows[#rows + 1] = { close = true,
                        label = Gen3BagMenu.pcWord(game, "cancel") }
    self.rows = rows
    self.index = math.min(math.max(1, self.index), #rows)
    self.top = math.max(1, math.min(self.top, math.max(1, #rows - self:listRows() + 1)))
    return
  end
  local want = self.pockets[self.pocket].key
  local rows = {}
  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items and game.data.items[id]
    if pocketOf(def, id) == want then
      rows[#rows + 1] = {
        id = id,
        label = (def and def.name) or id,
        -- WHERE THE COUNTS LIVE.  `save.items` is not a field any save
        -- has -- the bag is `save.inventory`, which is what Bag.order walks
        -- and what Bag.add and Bag.remove write -- so every quantity read
        -- here came back nil and Emerald's bag showed no "x3" against
        -- anything at all.
        qty = (game.save.inventory or {})[id],
        important = def and (tonumber(def.importance) or 0) ~= 0
          or want == "KEY_ITEM" or nil,
        description = def and (def.description or def.desc),
      }
    end
  end
  -- The LIST row is CANCEL on FireRed.  "Close the BAG." belongs to the
  -- description window underneath it (Bag_BuildListMenuTemplate versus
  -- PrintItemDescriptionOnMessageWindow); using the description as the row
  -- label is what produced the screenshot's incorrect CLOSE BAG entry.
  rows[#rows + 1] = {
    close = true,
    label = self.frlg and Strings("CANCEL") or Strings("CLOSE BAG"),
  }
  self.rows = rows
  self.index = math.min(self.index, #rows)
  self.top = math.max(1, math.min(self.top, #rows - self:listRows() + 1))
end

function Gen3BagMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3BagMenu:selected() return self.rows[self.index] end

function Gen3BagMenu:movePocket(delta)
  if self.lockPocket then return end
  self.pocket = (self.pocket - 1 + delta) % #self.pockets + 1
  self.index, self.top = 1, 1
  self:rebuild()
end

function Gen3BagMenu:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.message = nil
  self.index = (self.index - 1 + delta) % n + 1
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
end

-- ------------------------------------------------------------- the PC's words
--
-- Two blocks, because the cartridge keeps them in two places: the PC's own
-- (gen3PCMenu.text, swept beside ITEM STORAGE's row descriptions) and the
-- bag's (gen3ItemText, swept beside the bag's action labels).  Each falls
-- back to this port's English only when the cache predates the sweep.
local PC_FALLBACK = {
  withdrawPrompt = Strings.source("Withdraw how many\n{VAR1}(s)?"),
  withdrew       = Strings.source("Withdrew {VAR2}\n{VAR1}(s)."),
  noItems        = "There are no items.",
  bagFull        = Strings.source("There is no more\nroom in the BAG."),
  cancel         = "CANCEL",
  title          = "ITEM STORAGE",
}
local BAG_FALLBACK = {
  depositPrompt = Strings.source("Deposit how many\n{VAR1}(s)?"),
  deposited     = Strings.source("Deposited {VAR2}\n{VAR1}(s)."),
  noRoomStore   = Strings.source("There's no room to\nstore items."),
  cantStore     = Strings.source("Important items\ncan't be stored in\nthe PC!"),
  tossImportant = Strings.source("That's much too\nimportant to toss\nout!"),
  tossHowMany   = Strings.source("Toss out how many\n{VAR1}(s)?"),
  tossedMany    = Strings.source("Threw away {VAR2}\n{VAR1}(s)."),
  tossConfirm   = Strings.source("Is it okay to\nthrow away {VAR2}\n{VAR1}(s)?"),
}

function Gen3BagMenu.pcWord(game, key)
  local pc = (game.data.constants or {}).gen3PCMenu or {}
  if key == "cancel" then
    local rows = pc.itemStorage
    local word = type(rows) == "table" and rows[#rows] or nil
    return type(word) == "string" and word or PC_FALLBACK.cancel
  end
  if key == "title" then
    local rows = pc.main
    local word = type(rows) == "table" and rows[1] or nil
    return type(word) == "string" and word or PC_FALLBACK.title
  end
  local said = type(pc.text) == "table" and pc.text[key] or nil
  return type(said) == "string" and said or Strings(PC_FALLBACK[key] or "")
end

local function bagWord(game, key)
  local said = ((game.data.constants or {}).gen3ItemText or {})[key]
  return type(said) == "string" and said or Strings(BAG_FALLBACK[key] or "")
end

-- {VAR1} is the item, {VAR2} the count -- which is how the cartridge writes
-- both PC lines and both bag ones.
local function fillLine(text, name, qty)
  return (tostring(text or "")
    :gsub("{STR_VAR1}", "{VAR1}"):gsub("{STR_VAR2}", "{VAR2}")
    :gsub("{VAR2}", tostring(qty or 1)):gsub("{VAR1}", name))
end

-- IS THIS ONE OF THE ITEMS THE PC REFUSES?
--
-- ItemId_GetImportance, which the importer already reads off gItems and
-- files as `importance` (and mirrors as `keyItem`).  It is one byte and it is
-- the whole rule: an item with importance set cannot be deposited and cannot
-- be tossed, which is what stops the BIKE, the ROD, the DEVON GOODS and every
-- badge-shaped errand item from being posted into a box and lost.
--
-- Reported from play: "also allows for the depositing of key items I don't
-- think that was allowed in the game".  It was not, and nothing here asked.
function Gen3BagMenu.isImportant(game, id)
  local def = game.data.items and game.data.items[id]
  if not def then return false end
  local importance = tonumber(def.importance)
  if importance then return importance ~= 0 end
  -- a cache imported before gItems carried the byte: keyItem is the same
  -- answer under an older name, and an HM is important on every cartridge
  return def.keyItem == true or (type(id) == "string" and id:find("^HM_") ~= nil)
end

-- How many stacks the PC can hold, and whether this one would be a new stack.
function Gen3BagMenu:pcFull(id)
  local pc = self.game.save.pcItems or {}
  if pc[id] then return false end
  local cap = math.floor(tonumber((self.game.data.field or {}).pcItemCap) or 50)
  local stacks = 0
  for _ in pairs(pc) do stacks = stacks + 1 end
  return stacks >= cap
end

-- A LINE THE SCREEN IS SAYING, in the description panel, until the cursor
-- moves off it.  The cartridge prints these into the same window the item
-- description uses, and doing it that way here means a prompt cannot outlive
-- the thing that asked it -- a pushed TextBox under a pushed quantity window
-- would still be sitting there after the quantity was cancelled.
function Gen3BagMenu:say(text)
  self.message = text
end

-- ...and one it stops for, which is a real box the player dismisses.  Used
-- for the answers ("Withdrew 5 POTIONs."), which the cartridge waits on.
function Gen3BagMenu:tell(text)
  -- FireRed's deposit flow never leaves the bag for its answer.  ShowBagWindow
  -- overlays sWindowTemplates[9] on the lower-right description area and waits
  -- for A/B there.  Keep that message owned by this state so the bag, item
  -- icon and list remain visible behind it instead of flashing back to field.
  if self.frlg and self.itemPc then
    self.resultMessage = tostring(text or "")
    return
  end
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, text))
end

-- Ask how many, then act.  An important item never reaches here (the callers
-- refuse it first).  FireRed's ITEMPC deposit has its own lower-screen prompt
-- geometry; the generic quantity state remains for the shared non-ITEMPC paths.
function Gen3BagMenu:askQuantity(id, held, prompt, done)
  local game = self.game
  local def = game.data.items and game.data.items[id]
  local name = (def and def.name) or id
  if self.frlg and self.itemPc and self.store == "deposit" then
    game.stack:push(require("src.ui.Gen3ItemPcQuantity").new(game, self, {
      max = math.max(1, math.floor(held or 1)),
      itemName = name,
      verb = "DEPOSIT",
      onDone = function(qty)
        if qty and qty > 0 then done(qty, name) end
      end,
    }))
    return
  end
  local QuantityBox = require("src.ui.QuantityBox")
  self:say(fillLine(prompt, name, held))
  game.stack:push(QuantityBox.new(game, {
    max = math.max(1, math.floor(held or 1)),
    onDone = function(qty)
      self.message = nil
      if not qty or qty <= 0 then return end
      done(qty, name)
    end,
  }))
end

-- DEPOSIT: the bag's list, the bag's words, the PC's store.
function Gen3BagMenu:depositItem(id)
  local game = self.game
  if Gen3BagMenu.isImportant(game, id) then
    Sound.play(game.data, "Press_AB")
    return self:tell(bagWord(game, "cantStore"))
  end
  if self:pcFull(id) then
    return self:tell(bagWord(game, "noRoomStore"))
  end
  local held = (game.save.inventory or {})[id] or 1
  local function deposit(qty, name)
    Bag.remove(game.save, id, qty)
    game.save.pcItems = game.save.pcItems or {}
    game.save.pcItems[id] = (game.save.pcItems[id] or 0) + qty
    self:rebuild()
    Sound.play(game.data, "Withdraw_Deposit")
    self:tell(fillLine(bagWord(game, "deposited"), name, qty))
  end
  -- item_menu.c Task_ChooseHowManyToDeposit skips the quantity UI when there
  -- is exactly one.  That is the common early-game POTION case in the user's
  -- comparison and it also avoids a one-item selector the cartridge never
  -- shows.
  local def = game.data.items and game.data.items[id]
  local name = (def and def.name) or id
  if held <= 1 then return deposit(1, name) end
  self:askQuantity(id, held, bagWord(game, "depositPrompt"), deposit)
end

-- WITHDRAW: the PC's list, the PC's words, the bag as the destination.
function Gen3BagMenu:withdrawItem(id)
  local game = self.game
  local pc = game.save.pcItems or {}
  local held = pc[id] or 1
  self:askQuantity(id, held, Gen3BagMenu.pcWord(game, "withdrawPrompt"),
    function(qty, name)
      if not Bag.add(game.save, id, qty, game.data) then
        return self:tell(Gen3BagMenu.pcWord(game, "bagFull"))
      end
      pc[id] = pc[id] - qty
      if pc[id] <= 0 then pc[id] = nil end
      self:rebuild()
      Sound.play(game.data, "Withdraw_Deposit")
      self:tell(fillLine(Gen3BagMenu.pcWord(game, "withdrew"), name, qty))
    end)
end

-- TOSS, out of the PC rather than the bag: the same three lines the bag's own
-- toss uses, because they are the same three strings on the cartridge.
function Gen3BagMenu:tossStored(id)
  local game = self.game
  if Gen3BagMenu.isImportant(game, id) then
    Sound.play(game.data, "Press_AB")
    return self:tell(bagWord(game, "tossImportant"))
  end
  local pc = game.save.pcItems or {}
  local held = pc[id] or 1
  self:askQuantity(id, held, bagWord(game, "tossHowMany"), function(qty, name)
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game,
      fillLine(bagWord(game, "tossConfirm"), name, qty), nil, {
        choice = function(yes)
          if not yes then return end
          pc[id] = (pc[id] or 0) - qty
          if pc[id] <= 0 then pc[id] = nil end
          self:rebuild()
          self:tell(fillLine(bagWord(game, "tossedMany"), name, qty))
        end,
      }))
  end)
end

function Gen3BagMenu:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end
  -- The PC's three rows act on the pick instead of asking what to do with
  -- it: on the cartridge the question was asked before the list opened.
  if self.store == "deposit" then return self:depositItem(row.id) end
  if self.store == "withdraw" then return self:withdrawItem(row.id) end
  if self.store == "toss" then return self:tossStored(row.id) end
  -- ...and a bag opened AT A COUNTER sells what is picked and stays open, the
  -- way the cartridge's shop flag makes it
  if self.sell then
    return require("src.ui.Gen3ShopMenu").sellItem(self.game, row.id, {
      say = function(text) self:say(text) end,
      refresh = function() self:rebuild() end,
    })
  end
  -- a bag opened to ANSWER A QUESTION hands the answer back and closes; it
  -- does not offer to use or toss what was picked
  if self.pick then
    self.game.stack:pop()
    if self.onPick then self.onPick(row.id) end
    return
  end
  -- IN BATTLE there is no USE/TOSS question -- the cartridge does not offer
  -- to throw a POTION away mid-fight -- so the pick goes straight through
  -- the engine's own item flow, which is where balls, medicine and the
  -- turn it costs already live.  This screen is the cartridge's list and its
  -- words, not a second implementation of what an item does.
  if self.battle then
    local ok, err = pcall(function()
      require("src.ui.BagMenu").useItem(self.game, self.battle, row.id, self)
    end)
    if not ok then
      Logger.warn("gen3 bag: %s could not be used in battle: %s",
                  tostring(row.id), tostring(err))
    end
    return
  end
  -- OUT HERE the cartridge asks first.  What it offers depends on the
  -- pocket, and the five lists are the cartridge's own -- see
  -- src/ui/Gen3ItemMenu.lua and RomExtractorGen3:itemMenuActions.
  --
  -- This used to push a screen called `ItemUseMenu` inside a pcall.  No such
  -- screen exists anywhere in this port, so the pcall failed every time and
  -- logged "no item flow yet" -- which made EVERY out-of-battle item use in
  -- Hoenn do nothing at all, TMs and HMs included, with the machine data and
  -- the teaching code both already present and working.
  -- TM CASE and BERRY POUCH are their OWN screens on FireRed (tm_case.c,
  -- berry_pouch.c) -- not the bag reopened at a locked pocket, which is
  -- what this pushed until Gen3TMCase.lua/Gen3BerryPouch.lua existed.
  if self.frlg and row.id == "TM_CASE" then
    self.game.stack:push(require("src.ui.Gen3TMCase").new(self.game, {
      onCancel = function() self:rebuild() end,
    }))
    return
  end
  if self.frlg and row.id == "BERRY_POUCH" then
    self.game.stack:push(require("src.ui.Gen3BerryPouch").new(self.game, {
      onCancel = function() self:rebuild() end,
    }))
    return
  end
  local entries = self:actionsFor(row.id)
  if not entries then
    -- no cartridge list: use it, which is what the choice would have led to
    return self:act("use", row.id)
  end
  local Gen3ItemMenu = require("src.ui.Gen3ItemMenu")
  self.game.stack:push(Gen3ItemMenu.new(self.game, {
    entries = entries.entries,
    columns = entries.columns,
    onPick = function(kind) self:act(kind, row.id) end,
  }))
end

-- The pocket's own action list, as the cartridge lists it, or nil for a
-- dataset imported before that stage existed.  Asked from two places -- the
-- screen that draws it, and the SELECT button, which wants to know whether
-- REGISTER is one of the rows -- so the POCKET RULE lives here once.  It is
-- not BagMenu's: this one folds Emerald's own pocket names onto the engine's
-- (KEY_ITEMS -> KEY_ITEM), and the action lists are keyed by the folded name.
function Gen3BagMenu.actionList(game, id)
  local menu = (game and game.data and game.data.constants or {}).gen3ItemMenu
  if type(menu) ~= "table" then return nil end
  local def = game.data.items and game.data.items[id]
  local list = menu.pockets and menu.pockets[pocketOf(def, id)]
  if not list then return nil end
  return list, menu
end

-- ...and the one question the overworld asks of it: may this item sit on
-- SELECT?  Emerald asks the POCKET rather than the item -- the whole KEY
-- ITEMS pocket offers REGISTER and nothing else does -- which is why no Hoenn
-- item carries a per-item flag for it to be read off.
function Gen3BagMenu.canRegister(game, id)
  local list, menu = Gen3BagMenu.actionList(game, id)
  for _, action in ipairs(list or {}) do
    if (menu.kinds or {})[action] == "register" then return true end
  end
  return false
end

function Gen3BagMenu:actionsFor(id)
  local list, menu = Gen3BagMenu.actionList(self.game, id)
  if not list then return nil end
  -- ...AND REGISTER TURNS INTO DESELECT ON THE ITEM ALREADY ON THE BUTTON.
  --
  -- The cartridge keeps ONE key-item list and overwrites that cell when the
  -- item under the cursor is the registered one (SetMenuActions); it is not a
  -- second list, which is why the import records the pair rather than a sixth
  -- pocket.  Without the swap the row still says REGISTER after you have
  -- registered something, and pressing it un-registers -- so the menu was
  -- telling you the opposite of what the button would do.
  local swap = (menu.deselect and menu.register
                and id == (self.game.save or {}).registeredItem)
               and menu.register or nil
  local entries = {}
  for i, action in ipairs(list) do
    if swap and action == swap then action = menu.deselect end
    entries[i] = { label = menu.labels[action] or "",
                   kind = menu.kinds[action] or "other" }
  end
  return { entries = entries, columns = menu.columns or 2 }
end

-- A line the cartridge says, with the flow's own placeholders filled in.
local function cartridgeLine(game, key)
  local text = ((game.data.constants or {}).gen3ItemText or {})[key]
  return type(text) == "string" and text or nil
end

-- WHAT EACH ANSWER DOES.  Nothing here re-implements what an item MEANS:
-- USE and GIVE go through the engine's own item flow, which is where balls,
-- medicine, machines and the party picker already live.
function Gen3BagMenu:act(kind, id)
  local game = self.game
  local BagMenu = require("src.ui.BagMenu")
  if kind == "use" then
    local ok, err = pcall(BagMenu.useItem, game, nil, id, self)
    if not ok then
      Logger.warn("gen3 bag: %s could not be used: %s", tostring(id),
                  tostring(err))
    end
    return
  end
  if kind == "give" then
    local ok, err = pcall(BagMenu.giveItem, game, id,
                          function() self:rebuild() end)
    if not ok then
      Logger.warn("gen3 bag: %s could not be given: %s", tostring(id),
                  tostring(err))
    end
    return
  end
  if kind == "register" then
    -- ItemMenu_Register says nothing: the badge on the row and the DESELECT
    -- row next time are the whole acknowledgement, so the list has to be
    -- rebuilt or the screen genuinely does not change.
    game.save.registeredItem = (game.save.registeredItem ~= id) and id or nil
    Sound.play(game.data, "Press_AB")
    self:rebuild()
    Logger.info("gen3 bag: SELECT is now %s",
                tostring(game.save.registeredItem or "empty"))
    return
  end
  if kind == "toss" then
    return self:toss(id)
  end
  if kind == "checkTag" then
    -- the BERRY TAG screen is not built yet; the cartridge's own list still
    -- offers it, because hiding an action the cartridge shows would move
    -- everything under it
    Logger.info("gen3 bag: no BERRY TAG screen yet for %s", tostring(id))
    return
  end
  -- "cancel", "blank" and anything the cartridge has that this port has no
  -- use for: back to the list
end

-- TOSS: how many, then the cartridge's own question, then its own answer.
function Gen3BagMenu:toss(id)
  local game = self.game
  local def = game.data.items and game.data.items[id]
  local name = (def and def.name) or id
  local QuantityBox = require("src.ui.QuantityBox")
  local TextBox = require("src.render.TextBox")
  local held = (game.save.inventory or {})[id] or 1
  local function fill(text)
    return (text:gsub("{VAR1}", name):gsub("{VAR2}", name)
                :gsub("{STR_VAR1}", name):gsub("{STR_VAR2}", name))
  end
  game.stack:push(QuantityBox.new(game, {
    max = held,
    onDone = function(qty)
      if not qty or qty <= 0 then return end
      local ask = cartridgeLine(game, "tossPrompt")
                  or Strings("Throw away this\n%s?", name)
      -- `choice` is the CALLBACK, not a flag: TextBox calls it with the
      -- answer, so a boolean here is a crash waiting for a yes.
      game.stack:push(TextBox.new(game, fill(ask), nil, {
        choice = function(yes)
          if not yes then return end
          Bag.remove(game.save, id, qty)
          self:rebuild()
          local said = cartridgeLine(game, "tossed")
                       or Strings("Threw away\n%s.", name)
          game.stack:push(TextBox.new(game, fill(said)))
        end,
      }))
    end,
  }))
end

function Gen3BagMenu:update(dt)
  -- the cursor blinks, so the screen counts frames (see drawRows)
  self.tick = (self.tick or 0) + 1
  if self.script then self.script(self) end
  if self.noInput then return end
  local input = self.game.input
  if self.resultMessage then
    if input:wasPressed("a") or input:wasPressed("b") then
      Sound.play(self.game.data, "Press_AB")
      self.resultMessage = nil
    end
    return
  end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("right") then self:movePocket(1)
  elseif input:wasPressed("left") then self:movePocket(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

-- THE LIST'S OWN GEOMETRY, off the cartridge's ListMenuTemplate: the item's
-- The badge itself, loaded once and drawn wherever the registered row is.
-- Which of the two the player wears is the same question the background asks.
function Gen3BagMenu:drawRegisteredBadge(win, rowY)
  local rec = (self:screen() or {}).registered
  if type(rec) ~= "table" then return end
  local player = (self.game.save or {}).player or {}
  local path = (player.gender == "girl" and rec.female)
               or rec.male or rec.female
  if type(path) ~= "string" then return end
  if self._badge == nil or self._badgePath ~= path then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self._badge, self._badgePath = (ok and img) or false, path
  end
  if not self._badge then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self._badge,
                     win.x + (tonumber(rec.x) or 96),
                     rowY + (tonumber(rec.dy) or -1))
end

-- x inside the window, the cursor's, the first row's y and the pitch.  The
-- quantity is right-aligned to `quantityRight` pixels in, which is where the
-- cartridge puts it -- not to the window's far edge, which is what this drew
-- and why the counts sat under the frame.
local function drawRows(self, inset)
  local r = self:screen()
  local L = r.list or FALLBACK.list
  local win = self:box("list")
  local pitch = math.max(8, math.floor(tonumber(L.rowHeight) or ROW_PITCH))
  local itemX = win.x + (tonumber(L.itemX) or 8)
  local cursorX = win.x + (tonumber(L.cursorX) or 0)
  local qtyRight = win.x + (tonumber(L.quantityRight) or (win.width - 8))
  local top = win.y + (tonumber(L.upTextY) or 1)
  local first = self.top
  for i = 0, self:listRows() - 1 do
    local row = self.rows[first + i]
    if not row then break end
    local y = top + i * pitch + inset
    Font.draw(row.label, itemX, y)
    -- The registered-item badge is the cartridge's feedback for SELECT.
    if row.id and row.id == (self.game.save or {}).registeredItem then
      self:drawRegisteredBadge(win, top + i * pitch)
    end
    if L.quantityX and row.qty and not row.close and not row.important then
      -- FireRed: "x" then the count right-aligned in three digit cells, in
      -- the small face, at a fixed x (BagListMenuItemPrintFunc) -- shown
      -- even for a single item; key items print none
      local faced = Font.pushFace("small")
      local n = tostring(row.qty)
      local cell = Font.width("0")
      Font.draw("x", win.x + L.quantityX, y)
      Font.draw(n, win.x + L.quantityX + Font.width("x") + cell * (3 - #n), y)
      if faced then Font.popFace() end
    elseif row.qty and row.qty > 1 then
      local qty = Strings("x%d", row.qty)
      Font.draw(qty, qtyRight - Font.width(qty), y)
    end
    if first + i == self.index then
      if self.frlg then
        -- FRLG uses the ListMenu triangle cursor at the list template cursor x.
        -- The flashing full-row outline belongs to the other Gen 3 bag path.
        Font.drawCode(Theme.cursor, cursorX, y)
      else
        local mark = (r.pocketDots or {}).selected
        local player = (self.game.save or {}).player or {}
        local rgb = (mark and mark.colour
                     and ((player.gender == "girl" and mark.colour.female)
                          or mark.colour.male or mark.colour.female))
                    or { 255, 0, 0 }
        if math.floor((self.tick or 0) / 30) % 2 == 0 then
          local boxY = top + i * pitch
          love.graphics.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
          love.graphics.rectangle("fill", cursorX, boxY, win.width - (cursorX - win.x), 1)
          love.graphics.rectangle("fill", cursorX, boxY + pitch - 1,
                                  win.width - (cursorX - win.x), 1)
          love.graphics.rectangle("fill", cursorX, boxY, 1, pitch)
          love.graphics.rectangle("fill", win.x + win.width - 1, boxY, 1, pitch)
          love.graphics.setColor(0, 0, 0, 1)
        end
      end
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
end

-- The bag picture for this save, and the frame for the pocket in front.
local warned = false
local function warnOnce(fmt, ...)
  if warned then return end
  warned = true
  Logger.warn("gen3 bag: " .. fmt, ...)
end

function Gen3BagMenu:bagFrame()
  local record = (self.game.data.constants or {}).gen3Bag
  if type(record) ~= "table" then
    -- says WHICH half is missing, because "no bag" has two very different
    -- causes: a cache imported before the sprite was found, and a picture
    -- that failed to load out of one that has it
    warnOnce("this cache carries no gen3Bag record -- re-import to get the "
             .. "bag picture")
    return nil
  end
  local player = (self.game.save or {}).player or {}
  local which = (player.gender == "girl" and record.female) or record.male
                or record.female
  if not which then
    warnOnce("the gen3Bag record names no picture")
    return nil
  end
  local ok, image = pcall(Assets.image, which)
  if not ok or not image then
    warnOnce("%s could not be loaded (%s)", tostring(which), tostring(image))
    return nil
  end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local fw = math.floor(tonumber(record.frameWidth) or 64)
  local fh = math.floor(tonumber(record.frameHeight) or 64)
  local index = math.min(frames, self.pocket) - 1
  local iw, ih = image:getDimensions()
  return image, UiQuad.get(self,"pocket",image,index * fw,0,fw,fh,iw,ih), fw, fh
end

-- The screen's own background, in the palette this save's player carries.
function Gen3BagMenu:background()
  local r = self:screen()
  local images = r.images
  if type(images) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local path
  if self.itemPc then
    path = (player.gender == "girl" and images.itemPcFemale)
           or images.itemPcMale or images.itemPcFemale
  end
  path = path or (player.gender == "girl" and images.female) or images.male
              or images.female
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

-- The 24x24 picture for one item, off the atlas the importer composes from
-- gItemIconTable.  The slot IS the item's cartridge index, so there is no
-- table to walk: icon n sits at (n % cols, n / cols).
function Gen3BagMenu:itemIcon(id, forcedIndex)
  local rec = (self.game.data.constants or {}).gen3ItemIcons
  if type(rec) ~= "table" or type(rec.image) ~= "string" then return nil end
  local def = id and self.game.data.items and self.game.data.items[id]
  local index = forcedIndex ~= nil and tonumber(forcedIndex)
                or (def and tonumber(def.index))
  if not index then return nil end
  local count = math.floor(tonumber(rec.count) or 0)
  if index < 0 or index >= count then index = math.floor(tonumber(rec.blank) or 0) end
  local ok, img = pcall(Assets.image, rec.image)
  if not ok or not img then return nil end
  local size = math.max(1, math.floor(tonumber(rec.size) or 24))
  local cols = math.max(1, math.floor(tonumber(rec.cols) or 1))
  local iw, ih = img:getDimensions()
  return img, UiQuad.get(self,"item",img,(index % cols) * size,
                                    math.floor(index / cols) * size,
                                    size, size, iw, ih), size
end

function Gen3BagMenu:draw()
  local inset = self.frlg and 0 or math.max(0, math.floor((ROW_PITCH - Font.glyphHeight()) / 2))
  local r = self:screen()

  -- THE PICTURE IS 240 COLUMNS AND THE SURFACE MAY BE WIDER.
  --
  -- Same shape as the intro's: every rectangle, window and cursor below is
  -- measured against the cartridge's own screen, so rather than rewrite them
  -- the whole page is SHIFTED into the middle and the slack either side is
  -- filled from the field's own edge columns.  Stretching a one-pixel column
  -- sideways can only ever repeat a colour that is already the whole column,
  -- so the margin is the background continuing rather than anything invented
  -- -- the left edge is the striped field, the right is the list panel's own
  -- border.
  local Gen3Wide = gen3Wide()
  local surfaceW = select(1, Gen3Wide.uiSize())
  local margin = Gen3Wide.inset(surfaceW)
  if margin > 0 then
    local field = not self.pcList and self:background() or nil
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, surfaceW, GBA_H)
    if field then
      local fw, fh = field:getDimensions()
      love.graphics.setColor(1, 1, 1, 1)
      -- the two one-pixel edge columns, cut once: built inline they were two
      -- Quad objects on every frame the bag is open
      local left, right = edgeQuads(fw, fh)
      love.graphics.draw(field, left, 0, 0, 0, margin, 1)
      love.graphics.draw(field, right, margin + GBA_W, 0, 0, margin + 1, 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.push()
  love.graphics.translate(margin, 0)

  -- THE BACKGROUND, and only the drawn boxes when there isn't one.  The
  -- cartridge's field carries the three panels, the pocket tabs and the hole
  -- the item icon sits in, all in one 240x160 picture; drawing boxes on top
  -- of it would double every border.
  -- ...AND NOT THE BAG'S FIELD WHEN THIS IS THE PC.  The cartridge's item
  -- storage is its own screen with its own background, and this port has not
  -- read that one -- so the honest thing is the port's own drawn windows
  -- rather than the BAG's picture, whose printed pocket tabs would sit over
  -- a list that has no pockets and label it wrongly.  Everything with meaning
  -- in it -- the list, the counts, the icon, the description, the words -- is
  -- still the cartridge's.
  local field = not self.pcList and self:background() or nil
  if field then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(field, 0, 0)
  else
    love.graphics.setColor(0.20, 0.42, 0.36, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
    for _, key in ipairs({ "pocketName", "list", "description" }) do
      local b = self:box(key)
      Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
                   math.floor(b.width / 8), math.floor(b.height / 8))
    end
  end

  -- the bag itself, tilted toward the pocket in front.
  --
  -- TRIED, AND REVERTED: skipping this for the TM CASE / BERRY POUCH sub-
  -- views (opened with a locked pocket) on the grounds that neither has a
  -- bag drawn on the real cartridge -- they are their own screens
  -- (tm_case.c / berry_pouch.c), not the bag's.  It uncovered a worse
  -- problem instead of fixing one: the extracted FRLG background
  -- (bag_male.png/bag_female.png) carries a flat grey drop-shadow tile
  -- where the bag SPRITE normally sits on top of it, and with the sprite
  -- gone that shadow shows as an unexplained grey blob.  Drawing the bag
  -- anyway at least reads as "a bag", which is closer to right than a
  -- silhouette with nothing on it.  The real fix is TM CASE and BERRY
  -- POUCH getting their own extracted backgrounds instead of borrowing the
  -- bag's; out of scope for this pass.
  local image, quad = nil, nil
  if not self.pcList then image, quad = self:bagFrame() end
  if image and quad then
    local B = r.bag or FALLBACK.bag
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad, B.x or FALLBACK.bag.x, B.y or FALLBACK.bag.y)
  end

  -- WHICH POCKET YOU ARE IN, as the cartridge shows it: five cells of one
  -- tile in a row above the bag, the one in front filled.  This screen had
  -- no indicator at all -- the pocket name was the only clue -- so pressing
  -- left and right past an empty pocket looked like nothing had happened.
  --
  -- THE CARTRIDGE SWAPS A TILE, and the importer finds which one: the five
  -- cells share one tile, and exactly one tile the tilemap never places
  -- differs from it by a solid block -- a 4x4 at (2,3) whose colour index is
  -- RED in the boy's palette and blue in the girl's.  So the marker drawn
  -- here is the cartridge's own block, in the cartridge's own colour, over
  -- the cell the background already drew.
  --
  -- Reported from play: "the red dots for the selected page at the top arent
  -- showing properly".  They were not showing at all: this used to draw a
  -- one-pixel underline of its own invention below the cell, because nothing
  -- had gone looking for the tile the cartridge swaps in.
  local dots = not self.pcList
               and (r.pocketDots
                    or (r.layout ~= "frlg" and FALLBACK.pocketDots))
               or nil
  local mark = dots and dots.selected
  if dots and mark and (tonumber(dots.count) or 0) > 0 then
    local step = math.max(1, math.floor(tonumber(dots.step) or 8))
    local i = math.min(math.floor(dots.count), self.pocket) - 1
    local player = (self.game.save or {}).player or {}
    local rgb = (mark.colour
                 and ((player.gender == "girl" and mark.colour.female)
                      or mark.colour.male or mark.colour.female))
                or { 255, 0, 0 }
    love.graphics.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
    love.graphics.rectangle("fill",
                            dots.x + i * step + (tonumber(mark.dx) or 2),
                            dots.y + (tonumber(mark.dy) or 3),
                            tonumber(mark.width) or 4,
                            tonumber(mark.height) or 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ...AND THE ITEM'S OWN PICTURE, at the place the record names.
  --
  -- `itemIcon` is where the ICON goes, not where its box does -- the box is
  -- 32x28 at (4,70) and the 24x24 picture sits at (8,72) inside it.  Adding
  -- half the difference on top of that, as if the record were the box, moved
  -- it four right and two down and put its right-hand column on the border.
  local row = self:selected()
  if row and (row.id or (row.close and self.frlg)) then
    -- CreateItemMenuIcon(ITEMS_COUNT) is FireRed's RETURN/CANCEL arrow.  It is
    -- slot 375 in gItemIconTable (include/constants/items.h), immediately after
    -- the last real item; the import already bakes that slot into this atlas.
    local icon, iquad = self:itemIcon(row.id, row.close and self.frlg and 375 or nil)
    if icon and iquad then
      local cell = r.itemIcon or FALLBACK.itemIcon
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(icon, iquad, cell.x, cell.y)
    end
  end

  -- THE POCKET NAME, CENTRED IN ITS OWN WINDOW.
  --
  -- Reported from play: "theres also a line going through the bags pocket
  -- name in the top".  There was -- the pill's own bottom border.  The window
  -- is sixteen pixels tall and the name was drawn four pixels down from its
  -- top plus the row inset, which put a twelve-pixel glyph's last row past
  -- the pill and straight through the border underneath it.  Centring the
  -- glyph in the window's own height is what the cartridge does and it clears
  -- the border by a pixel.
  love.graphics.setColor(0, 0, 0, 1)
  local pocketBox = self:box("pocketName")
  local name = self.pcList and Gen3BagMenu.pcWord(self.game, "title")
               or (self.itemPc and self.frlg and "DEPOSIT ITEM")
               or self.pockets[self.pocket].name
  if self.itemPc and self.frlg then
    -- sDefaultBagWindowsDeposit[2] is content (1,1) 8x2.  Its standard frame
    -- sits one tile outside, so the complete fixed Type-1 box is 10x4 at 0,0.
    -- The normal pocket-name window is 9 tiles wide and palette 15; deposit is
    -- deliberately the narrower 8-tile palette-12 window seen in retail.
    pocketBox = { x = 8, y = 8, width = 64, height = 16 }
    if Font.drawStandardBox then Font.drawStandardBox(0, 0, 10, 4)
    else Font.drawBox(0, 0, 10, 4, 1) end
  end
  local small = self.itemPc and self.frlg and Font.hasFace and Font.hasFace("small")
  local faced = small and Font.pushFace("small")
  local uiStyles = self.game.data.font and self.game.data.font.uiTextStyles or {}
  local titleStyle = self.frlg and (self.itemPc and uiStyles.dark or uiStyles.white)
  if titleStyle then Font.pushStyle(titleStyle) end
  Font.draw(name, pocketBox.x + math.max(0, math.floor((pocketBox.width - Font.width(name)) / 2)),
            pocketBox.y + math.max(0, math.floor((pocketBox.height - Font.glyphHeight()) / 2)))
  if titleStyle then Font.popStyle() end
  if faced then Font.popFace() end
  if self.frlg and uiStyles.dark then Font.pushStyle(uiStyles.dark) end
  drawRows(self, inset)
  if self.frlg and uiStyles.dark then Font.popStyle() end

  -- the description panel, which is the half of this screen the Game Boy bag
  -- does not have at all
  local desc = self:box("description")
  local D = r.description or FALLBACK.description
  local text
  if self.message then
    text = self.message
  elseif self.pcList and #self.rows <= 1 then
    text = Gen3BagMenu.pcWord(self.game, "noItems")
  elseif self.pcList and row and row.close then
    -- The PC's CANCEL describes ending the PC list, not closing the bag.
    local describe = ((self.game.data.constants or {}).gen3PCMenu or {}).describe
    text = (type(describe) == "table" and describe[#describe]) or ""
  else
    text = row and (row.close and (self.frlg and Strings("CLOSE BAG")
                                   or Strings("Close the BAG."))
                    or row.description) or ""
  end
  -- FireRed prints three lines at the face's own fourteen-pixel pitch from
  -- y 3 (PrintItemDescriptionOnMessageWindow); the record says so.
  local pitch = tonumber(D.lineHeight) or ROW_PITCH
  local y = desc.y + (tonumber(D.y) or 1)
        + (D.lineHeight and r.layout == "frlg" and 0 or inset)
  local descStyle = self.frlg and uiStyles.white
  if descStyle then Font.pushStyle(descStyle) end
  for line in tostring(text or ""):gmatch("[^\n]+") do
    Font.draw(line, desc.x + (tonumber(D.x) or 3), y)
    y = y + pitch
  end
  if descStyle then Font.popStyle() end
  if self.resultMessage then
    -- sWindowTemplates[9] content: (6,15), 23x4.  DrawStdFrameWithCustomTile...
    -- adds one tile around it, producing the retail 200x48 panel from x40.
    if Font.drawStandardBox then Font.drawStandardBox(5, 14, 25, 6)
    else Font.drawBox(5, 14, 25, 6, 1) end
    love.graphics.setColor(0, 0, 0, 1)
    local my = 122
    if self.frlg and uiStyles.dark then Font.pushStyle(uiStyles.dark) end
    for line in (self.resultMessage .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 48, my)
      my = my + 14
    end
    if self.frlg and uiStyles.dark then Font.popStyle() end
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3BagMenu
