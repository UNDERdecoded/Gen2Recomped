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
local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3BagMenu = {}
Gen3BagMenu.__index = Gen3BagMenu

local GBA_W, GBA_H = 240, 160

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

function Gen3BagMenu:uiSize() return GBA_W, GBA_H end
function Gen3BagMenu:wantsFillScale() return true end

function Gen3BagMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
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
  for i, key in ipairs(POCKET_KEYS) do
    self.pockets[i] = { key = key, name = names[i] or key }
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
  return (r.windows and r.windows[key]) or FALLBACK.windows[key]
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
        description = def and (def.description or def.desc),
      }
    end
  end
  -- CLOSE BAG is a row, not a button: B and this land in the same place, and
  -- the cartridge lists it at the end of every pocket.
  rows[#rows + 1] = { close = true, label = Strings("CLOSE BAG") }
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
  self.index = (self.index - 1 + delta) % n + 1
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
end

function Gen3BagMenu:choose()
  local row = self:selected()
  if not row or row.close then return self:close() end
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
-- dataset imported before that stage existed.
function Gen3BagMenu:actionsFor(id)
  local menu = (self.game.data.constants or {}).gen3ItemMenu
  if type(menu) ~= "table" then return nil end
  local def = self.game.data.items and self.game.data.items[id]
  local list = menu.pockets and menu.pockets[pocketOf(def, id)]
  if not list then return nil end
  local entries = {}
  for i, action in ipairs(list) do
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
    -- ItemMenu_Register says nothing; the list redraws with the item marked
    game.save.registeredItem = (game.save.registeredItem ~= id) and id or nil
    Sound.play(game.data, "Press_AB")
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
  if self.script then self.script(self) end
  if self.noInput then return end
  local input = self.game.input
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("right") then self:movePocket(1)
  elseif input:wasPressed("left") then self:movePocket(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close()
  end
end

-- THE LIST'S OWN GEOMETRY, off the cartridge's ListMenuTemplate: the item's
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
    if row.qty and row.qty > 1 then
      local qty = Strings("x%d", row.qty)
      Font.draw(qty, qtyRight - Font.width(qty), y)
    end
    if first + i == self.index then
      Font.drawCode(Theme.cursor, cursorX, y)
    end
  end
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
  return image, love.graphics.newQuad(index * fw, 0, fw, fh, iw, ih), fw, fh
end

-- The screen's own background, in the palette this save's player carries.
function Gen3BagMenu:background()
  local r = self:screen()
  local images = r.images
  if type(images) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local path = (player.gender == "girl" and images.female) or images.male
               or images.female
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(Assets.image, path)
  return ok and img or nil
end

-- The 24x24 picture for one item, off the atlas the importer composes from
-- gItemIconTable.  The slot IS the item's cartridge index, so there is no
-- table to walk: icon n sits at (n % cols, n / cols).
function Gen3BagMenu:itemIcon(id)
  local rec = (self.game.data.constants or {}).gen3ItemIcons
  if type(rec) ~= "table" or type(rec.image) ~= "string" then return nil end
  local def = id and self.game.data.items and self.game.data.items[id]
  local index = def and tonumber(def.index)
  if not index then return nil end
  local count = math.floor(tonumber(rec.count) or 0)
  if index < 0 or index >= count then index = math.floor(tonumber(rec.blank) or 0) end
  local ok, img = pcall(Assets.image, rec.image)
  if not ok or not img then return nil end
  local size = math.max(1, math.floor(tonumber(rec.size) or 24))
  local cols = math.max(1, math.floor(tonumber(rec.cols) or 1))
  local iw, ih = img:getDimensions()
  return img, love.graphics.newQuad((index % cols) * size,
                                    math.floor(index / cols) * size,
                                    size, size, iw, ih), size
end

function Gen3BagMenu:draw()
  local inset = math.max(0, math.floor((ROW_PITCH - Font.glyphHeight()) / 2))
  local r = self:screen()

  -- THE BACKGROUND, and only the drawn boxes when there isn't one.  The
  -- cartridge's field carries the three panels, the pocket tabs and the hole
  -- the item icon sits in, all in one 240x160 picture; drawing boxes on top
  -- of it would double every border.
  local field = self:background()
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

  -- the bag itself, tilted toward the pocket in front
  local image, quad = self:bagFrame()
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
  local dots = r.pocketDots or FALLBACK.pocketDots
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
  if row and row.id then
    local icon, iquad = self:itemIcon(row.id)
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
  local name = self.pockets[self.pocket].name
  local nameY = pocketBox.y
                + math.max(0, math.floor((pocketBox.height - Font.glyphHeight()) / 2))
  Font.draw(name, pocketBox.x + math.max(0, math.floor((pocketBox.width - Font.width(name)) / 2)),
            nameY)
  drawRows(self, inset)

  -- the description panel, which is the half of this screen the Game Boy bag
  -- does not have at all
  local desc = self:box("description")
  local D = r.description or FALLBACK.description
  local text = row and (row.close and Strings("Close the BAG.")
                        or row.description) or ""
  local y = desc.y + (tonumber(D.y) or 1) + inset
  for line in tostring(text or ""):gmatch("[^\n]+") do
    Font.draw(line, desc.x + (tonumber(D.x) or 3), y)
    y = y + ROW_PITCH
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3BagMenu
