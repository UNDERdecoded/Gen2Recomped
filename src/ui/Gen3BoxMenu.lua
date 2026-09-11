-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's PC boxes.
--
-- Reported from play: "the emerald pokemon box system doesnt seem to be
-- imlemented with the emerald screens etc".  It was not -- Hoenn opened Bill's
-- PC, which is a stack of TEXT MENUS: pick WITHDRAW, then pick a row from a
-- list of names.  Emerald's is a GRID.  Thirty slots to a box laid out six by
-- five, every one of them showing the Pokemon's own icon, and the box you are
-- in is changed from the title above the grid rather than from a menu item.
--
-- The SHAPE is not this port's invention and it is not decoration either: the
-- storage the save actually has is fourteen boxes of thirty, and the save
-- layout derives both numbers from the cartridge (see Boxes.load).  A list of
-- twenty names cannot show a box of thirty at all, which is the part that
-- stopped being cosmetic.
--
-- WHAT COMES OFF THE CARTRIDGE: the box count and capacity, every icon, every
-- name -- and, since "Box backgrounds are still missing" was reported from
-- play, the WALLPAPER behind the grid and the rectangle it goes in.  The
-- import reads all thirty-two of them (see extractBoxWallpapers) together with
-- the loader's own placement: the picture is 160x144 at x 80, y 16, its top
-- three rows of tiles are the plate the box name is written on, and the slots
-- are twenty-four pixels apart from the cursor's own table.
--
-- WHAT IS STILL RECONSTRUCTED: the CHROME.  The cartridge draws the left
-- panel, the party panel and the two top tabs as BG1 tilemaps out of one
-- 144-tile sheet, and that art is not extracted yet -- so the frames here
-- are this port's own.  Everything INSIDE them is the cartridge's: the four
-- lines of the PkMn DATA panel and where each sits, the party's six slots,
-- and the twenty-four pixels between them.

local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Menu = require("src.ui.Menu")
local Party = require("src.pokemon.Party")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Theme = require("src.ui.Theme")

local Gen3BoxMenu = {}
Gen3BoxMenu.__index = Gen3BoxMenu
Gen3BoxMenu.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- Six across and five down is the cartridge's, and so is everything in
-- FALLBACK below -- it is what the import's own record says, repeated here so
-- the screen still lands in the right place on a dataset that predates the
-- wallpaper rip.  The record wins wherever it exists.
local COLS, ROWS = 6, 5
local FALLBACK = {
  region = { x = 80, y = 16, width = 160, height = 144 },
  grid = { x = 88, y = 32, cell = 24, cols = COLS, rows = ROWS },
  band = 24,
  newGameMask = 3,
}
-- THE LEFT EIGHTY PIXELS ARE NOT THE PARTY.
--
-- Reported from play: "in the pc storage box i dont see my pokemon party in
-- the left sidebar", and this file's own header used to agree -- it said the
-- cartridge draws the party there.  It does not.
--
-- The left 80x160 is a permanent "PkMn DATA" panel about the mon UNDER THE
-- CURSOR, and its four lines come out of PrintDisplayMonInfo (080CA4FC),
-- which prints into a window the template at 08572714 places at (0, 88),
-- 72x56:
--
--     6, 88    the nickname
--     6, 103   "/" and the species name
--     10, 117  the gender symbol, then "Lv" and the level
--     6, 131   the held item's name, blank when it holds nothing
--
-- with the mon's FRONT PIC above it at (40, 48) -- CreateSprite's own
-- coordinates at 080CA40E, which is where this already drew an icon.
--
-- THE PARTY is a twelve-by-twenty-two tilemap that slides DOWN OVER THE BOX
-- GRID at x 80, and only in MOVE POKeMON, MOVE ITEMS and DEPOSIT.  Its
-- slots are not a column: slot 1 sits alone on the left at (104, 64) and
-- slots 2..6 run down the right at x 152, twenty-four pixels apart -- the
-- same twenty-four the box grid uses, which is a good check that both
-- tables are being read right.
local SIDE = { tx = 0, ty = 0, tw = 10, th = 20 }
local PANEL = {
  pic = { x = 40, y = 48 },
  name = { x = 6, y = 88 },
  species = { x = 6, y = 103 },
  level = { x = 10, y = 117 },
  item = { x = 6, y = 131 },
}
local PARTY = {
  x = 80, y = 0, w = 96, h = 160,
  -- CreateMonIconSprite's own coordinates (080CB7E8); the cursor sits twelve
  -- pixels above each, exactly as it does over the box grid
  slots = { { 104, 64 }, { 152, 16 }, { 152, 40 }, { 152, 64 },
            { 152, 88 }, { 152, 112 } },
  cancel = { 152, 132 },
}
-- row 0 is the title: Emerald puts the cursor on the box name when you walk
-- off the top of the grid, and left/right there change box
local TITLE_ROW = 0

function Gen3BoxMenu:uiSize() return GBA_W, GBA_H end
function Gen3BoxMenu:wantsFillScale() return true end

function Gen3BoxMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3BoxMenu.new(game, opts)
  local self = setmetatable({ game = game, opts = opts or {}, t = 0 },
                            Gen3BoxMenu)
  Boxes.ensure(game.save)
  self.row, self.col = 1, 1
  return self
end

function Gen3BoxMenu:box() return Boxes.active(self.game.save) end

-- Which mon is under the cursor, and the slot it sits in.  A box is a dense
-- list -- the engine's storage has no holes -- so the slot IS the index.
function Gen3BoxMenu:selected()
  if self.row == TITLE_ROW then return nil, nil end
  local slot = (self.row - 1) * COLS + self.col
  return self:box()[slot], slot
end

function Gen3BoxMenu:boxName()
  local save = self.game.save
  local n = save.currentBox or 1
  local named = save.boxNames and save.boxNames[n]
  if type(named) == "string" and #named > 0 then return named end
  return ("BOX %d"):format(n)
end

function Gen3BoxMenu:changeBox(delta)
  local count = Boxes.count()
  local save = self.game.save
  save.currentBox = ((save.currentBox or 1) - 1 + delta) % count + 1
  Sound.play(self.game.data, "Press_AB")
end

-- ---------------------------------------------------------------------------
-- what a slot can do
-- ---------------------------------------------------------------------------

function Gen3BoxMenu:withdraw(slot)
  local game = self.game
  local box = self:box()
  local mon = box[slot]
  if not mon then return end
  if #game.save.party >= Party.MAX then
    game.stack:push(TextBox.new(game,
      Strings("Your party is full!")))
    return
  end
  table.remove(box, slot)
  Party.add(game.save.party, mon)
  self:clampCursor()
  game.stack:push(TextBox.new(game,
    ("%s was taken out."):format(self:nameOf(mon))))
end

function Gen3BoxMenu:release(slot)
  local box = self:box()
  local mon = box[slot]
  if not mon then return end
  local name = self:nameOf(mon)
  table.remove(box, slot)
  self:clampCursor()
  self.game.stack:push(TextBox.new(self.game,
    ("%s was released."):format(name)))
end

-- The deposit half.  Emerald pulls the party up over the grid; this port has
-- a party screen that already looks right and already answers a pick, so the
-- flow borrows it rather than drawing a second party list here.
function Gen3BoxMenu:deposit()
  local game = self.game
  if #game.save.party <= 1 then
    game.stack:push(TextBox.new(game,
      Strings("You can't deposit your last POKéMON!")))
    return
  end
  -- `pickOnly` + `onSwitch` is how EVERY picker in this port is asked for --
  -- an item's target, a script's `choosemon`, the battle's forced switch --
  -- and it is what Screens' alias table says the Gen 3 party menu serves.  A
  -- callback under any other name is a push that alias declines, and the
  -- player gets the Game Boy party list in Hoenn.
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon)
      if not mon then return end
      if #self:box() >= Boxes.capacity() then
        game.stack:push(TextBox.new(game, Strings("This BOX is full!")))
        return
      end
      local party = game.save.party
      for i = 1, #party do
        if party[i] == mon then
          table.remove(party, i)
          break
        end
      end
      table.insert(self:box(), mon)
      game.stack:push(TextBox.new(game,
        ("%s was stored."):format(self:nameOf(mon))))
    end,
  })
end

function Gen3BoxMenu:nameOf(mon)
  local def = self.game.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

function Gen3BoxMenu:clampCursor()
  local used = #self:box()
  local slot = (self.row - 1) * COLS + self.col
  if used == 0 then
    self.row, self.col = 1, 1
    return
  end
  if slot > used then
    local last = used
    self.row = math.floor((last - 1) / COLS) + 1
    self.col = (last - 1) % COLS + 1
  end
end

function Gen3BoxMenu:openSlotMenu(slot)
  local game = self.game
  local mon = self:box()[slot]
  if not mon then return end
  game.stack:push(Menu.new(game, {
    { label = Strings("WITHDRAW"),
      onSelect = function() self:withdraw(slot) end },
    { label = Strings("SUMMARY"), keepOpen = true,
      onSelect = function()
        require("src.ui.Screens").push(game, "SummaryMenu", mon)
      end },
    { label = Strings("RELEASE"),
      onSelect = function() self:release(slot) end },
    { label = Strings("CANCEL") },
  }, { tx = 18, ty = 8, tw = 11, th = 10, noSound = true }))
end

-- ---------------------------------------------------------------------------

function Gen3BoxMenu:update(dt)
  self.t = (self.t or 0) + (dt or 0)
  local input = self.game.input
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    self.game.stack:pop()
    if self.opts.onCancel then self.opts.onCancel() end
    return
  end
  if input:wasPressed("select") then
    self:deposit()
    return
  end
  -- ---- the party panel, while it is up ----------------------------------
  --
  -- Emerald reaches it by cursor NAVIGATION rather than by a dedicated key:
  -- down off the bottom of the grid lands on the buttons row, and A on
  -- PARTY POKeMON slides the party in.  So there is no new binding here
  -- either.  Inside it: DOWN cycles the seven places, LEFT jumps to slot 1
  -- and RIGHT comes back to the one you left (080CF654 / 080CF67C), and B
  -- or CANCEL slides it out again.
  if self.partyOpen then
    local last = #PARTY.slots + 1        -- ...plus CANCEL
    if input:wasPressed("down") then
      self.partyIndex = self.partyIndex < last and self.partyIndex + 1 or 1
    elseif input:wasPressed("up") then
      self.partyIndex = self.partyIndex > 1 and self.partyIndex - 1 or last
    elseif input:wasPressed("left") then
      if self.partyIndex ~= 1 then
        self.partyReturn = self.partyIndex
        self.partyIndex = 1
      end
    elseif input:wasPressed("right") then
      if self.partyIndex == 1 then
        self.partyIndex = self.partyReturn or 2
      end
    elseif input:wasPressed("b")
        or (input:wasPressed("a") and self.partyIndex == last) then
      Sound.play(self.game.data, "Press_AB")
      self.partyOpen, self.partyIndex, self.partyReturn = nil, nil, nil
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      local mon = (self.game.save.party or {})[self.partyIndex]
      if mon then self:carryFromParty(self.partyIndex) end
    end
    return
  end

  -- ---- and the buttons row under the grid --------------------------------
  --
  -- PARTY POKeMON and CLOSE BOX, which is where the cartridge puts them: a
  -- row you reach by walking DOWN off the bottom of the grid, and the only
  -- way in to the party.
  if self.onButtons then
    if input:wasPressed("left") or input:wasPressed("right") then
      self.buttonIndex = self.buttonIndex == 1 and 2 or 1
    elseif input:wasPressed("up") then
      self.onButtons, self.row = nil, ROWS
    elseif input:wasPressed("down") then
      self.onButtons, self.row = nil, TITLE_ROW
    elseif input:wasPressed("a") then
      Sound.play(self.game.data, "Press_AB")
      if self.buttonIndex == 1 then
        -- MOVE POKeMON and MOVE ITEMS are the only modes that may summon it
        -- (080C839E); WITHDRAW gets "Which one will you take?" instead
        if self.opts.mode == "move" then
          self.onButtons = nil
          self.partyOpen, self.partyIndex = true, 1
        end
      else
        self.game.stack:pop()
        if self.opts.onCancel then self.opts.onCancel() end
      end
    end
    return
  end

  if input:wasPressed("up") then
    self.row = self.row > TITLE_ROW and self.row - 1 or ROWS
  elseif input:wasPressed("down") then
    if self.row == ROWS then
      -- off the bottom of the grid is the buttons row, not a wrap
      self.onButtons, self.buttonIndex = true, 1
    else
      self.row = self.row < ROWS and self.row + 1 or TITLE_ROW
    end
  elseif input:wasPressed("left") then
    if self.row == TITLE_ROW then
      self:changeBox(-1)
    else
      self.col = self.col > 1 and self.col - 1 or COLS
    end
  elseif input:wasPressed("right") then
    if self.row == TITLE_ROW then
      self:changeBox(1)
    else
      self.col = self.col < COLS and self.col + 1 or 1
    end
  elseif input:wasPressed("a") then
    if self.row == TITLE_ROW then
      self:changeBox(1)
      return
    end
    local _, slot = self:selected()
    -- WHAT A IS FOR depends on what the storage menu was asked for.  Emerald
    -- asks WITHDRAW / DEPOSIT / MOVE before it opens the grid at all
    -- (Gen3StorageMenu), and the grid then does one thing rather than
    -- offering the lot on every slot.
    local mode = self.opts.mode
    if mode == "deposit" then
      Sound.play(self.game.data, "Press_AB")
      self:deposit()
      return
    end
    if mode == "move" then
      Sound.play(self.game.data, "Press_AB")
      self:carry(slot)
      return
    end
    if slot and self:box()[slot] then
      Sound.play(self.game.data, "Press_AB")
      if mode == "withdraw" then
        self:withdraw(slot)
      else
        self:openSlotMenu(slot)
      end
    end
  end
end

-- MOVE POKEMON: pick one up, put it down somewhere else.
--
-- The cartridge lets you carry a Pokemon around the grid and drop it in any
-- slot, swapping with whatever is already there.  A box in this engine is a
-- DENSE list -- storage has no holes -- so "an empty slot" means the end of
-- the list, and dropping there appends rather than leaving a gap.
-- PICKING ONE UP OUT OF THE PARTY, which is the whole point of the party
-- panel being reachable in MOVE POKeMON: a mon carried from a party slot is
-- put down in the box, and one carried from the box is put down in the
-- party.  The party is a dense list -- Party.remove closes the gap -- so a
-- pickup leaves a hole only until it is put down again.
function Gen3BoxMenu:carryFromParty(index)
  local party = self.game.save.party or {}
  local held = self.held
  if not held then
    local mon = party[index]
    if not mon then return end
    -- the last one on its feet may not leave: the same rule the deposit
    -- half already keeps
    if #party <= 1 then
      self.game.stack:push(TextBox.new(self.game,
        Strings("There's just one\nPOKéMON with you!")))
      return
    end
    self.held = { mon = mon, fromParty = index }
    table.remove(party, index)
    return
  end
  -- putting one down into the party
  if #party >= Party.MAX then
    self.game.stack:push(TextBox.new(self.game,
      Strings("Your party is full!")))
    return
  end
  table.insert(party, math.min(index, #party + 1), held.mon)
  if held.from then self:box()[held.from] = nil end
  self.held = nil
end

function Gen3BoxMenu:carry(slot)
  local box = self:box()
  if not slot then return end
  local held = self.held
  if not held then
    local mon = box[slot]
    if not mon then return end
    self.held = { mon = mon, from = slot }
    return
  end
  self.held = nil
  if slot == held.from then return end
  local target = box[slot]
  if target then
    box[slot], box[held.from] = held.mon, target
  else
    -- A MON GOES WHERE YOU PUT IT.  This used to `table.remove` the slot it
    -- came from and append at `#box + 1`, which is wrong twice over: the
    -- remove SHIFTS every later mon down one, so dropping one into an empty
    -- square reordered the whole box behind it, and the append picks a slot by
    -- walking off a length that is meaningless on a box with holes -- an
    -- imported PC keeps its mons at the slots the cartridge put them in, and
    -- `#` on that reads 0, so the mon could land at slot 1 on top of nothing,
    -- or past the end of the box where nothing can reach it again.
    box[slot], box[held.from] = held.mon, nil
  end
  self:clampCursor()
end

-- The icon load is Gen3PartyMenu's, called as a plain function: it reads
-- nothing off its receiver but `game`, and one cache for every screen that
-- draws an icon is better than two that disagree.
function Gen3BoxMenu:iconFor(mon)
  local ok, img, frameH = pcall(require("src.ui.Gen3PartyMenu").iconFor,
                                { game = self.game }, mon)
  if not ok then return nil end
  return img, frameH
end

local ICON_PERIOD = 0.32

function Gen3BoxMenu:drawIcon(mon, cx, cy)
  local img, frameH = self:iconFor(mon)
  if not img then return end
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH or ih, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local frame = frames > 1
    and (math.floor(((self.t or 0) % (ICON_PERIOD * frames)) / ICON_PERIOD)
         % frames) or 0
  self.quads = self.quads or {}
  local key = ("%d:%d:%d"):format(iw, frameH, frame)
  local quad = self.quads[key]
  if not quad then
    quad = love.graphics.newQuad(0, frame * frameH, iw, frameH, iw, ih)
    self.quads[key] = quad
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, math.floor(cx - iw / 2),
                     math.floor(cy - frameH / 2))
end

-- ---------------------------------------------------------------------------
-- the wallpaper
-- ---------------------------------------------------------------------------

function Gen3BoxMenu:record()
  return (self.game and self.game.data and self.game.data.constants
          or {}).gen3BoxWallpapers
end

function Gen3BoxMenu:region()
  local rec = self:record()
  return (rec and rec.region) or FALLBACK.region
end

function Gen3BoxMenu:grid()
  local rec = self:record()
  return (rec and rec.grid) or FALLBACK.grid
end

-- WHICH PICTURE THIS BOX WEARS.  An imported save carries the byte the
-- cartridge stored -- one per box, and the PC's WALLPAPER item is what changes
-- it -- so that is read first.  A save that has never seen a Gen 3 PC gets the
-- cartridge's own new-game answer instead: box i starts on wallpaper i & 3.
function Gen3BoxMenu:wallpaperId()
  local rec = self:record()
  local box = self:box()
  local id = tonumber(box and box.wallpaper)
  if id then return math.floor(id) end
  local mask = math.floor(tonumber(rec and rec.newGameMask)
                          or FALLBACK.newGameMask)
  return ((self.game.save.currentBox or 1) - 1) % (mask + 1)
end

local warnedNoPaper = false

function Gen3BoxMenu:wallpaper()
  local rec = self:record()
  if not rec then
    -- SAY WHY, ONCE.  The wallpapers are cartridge art: they arrive with an
    -- IMPORT, not with a code change, so a cache built before the rip has no
    -- pictures to draw and the box keeps its flat rectangle.  Reported twice
    -- as "the box backgrounds are still missing", which is what a silent
    -- fallback earns.
    if not warnedNoPaper then
      warnedNoPaper = true
      Logger.warn("gen3 boxes: this dataset has no wallpapers -- it was "
                  .. "imported before they were ripped, so the box keeps its "
                  .. "plain background until the ROM is imported again")
    end
    return nil
  end
  local id = self:wallpaperId()
  local path
  if id == tonumber(rec.friendId) then
    -- id 16 means "one of Walda's sixteen", and WHICH one is Walda's own
    -- saved pattern.  Nothing in this port fills that in yet, so the first of
    -- her set stands in rather than the box losing its picture.
    path = rec.friends and rec.friends[1]
  else
    path = rec.images and rec.images[id + 1]
  end
  if type(path) ~= "string" then return nil end
  self._paper = self._paper or {}
  local held = self._paper[path]
  if held == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    held = (ok and img) or false
    self._paper[path] = held
    if not held and not warnedNoPaper then
      -- the record is here and the picture is not, which is the same story
      -- one import older: the data was written, the art was not
      warnedNoPaper = true
      Logger.warn("gen3 boxes: %s is named by the dataset and is not on "
                  .. "disk -- import the ROM again", tostring(path))
    end
  end
  return held or nil
end

function Gen3BoxMenu:cellAt(row, col)
  local grid = self:grid()
  local cell = math.floor(tonumber(grid.cell) or FALLBACK.grid.cell)
  return grid.x + (col - 1) * cell, grid.y + (row - 1) * cell
end

function Gen3BoxMenu:draw()
  love.graphics.setColor(0.16, 0.20, 0.28, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  -- ---- the box's own picture -------------------------------------------
  --
  -- 160x144 at x 80, y 16: not the screen, the BOX AREA of it, which is what
  -- the cartridge's own copy says (extractBoxWallpapers).  Everything below
  -- is drawn on top of it in the rectangle it leaves.
  local region = self:region()
  local paper = self:wallpaper()
  if paper then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(paper, region.x, region.y)
  else
    love.graphics.setColor(0.30, 0.44, 0.64, 1)
    love.graphics.rectangle("fill", region.x, region.y,
                            region.width, region.height)
  end

  -- ---- the name, on the plate the wallpaper's top rows draw -------------
  local rec = self:record()
  local band = math.floor(tonumber(rec and rec.band) or FALLBACK.band)
  local name = self:boxName()
  local nameY = region.y + math.floor((band - 8) / 2)
  local nameX = region.x + math.floor((region.width - Font.width(name)) / 2)
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(name, nameX, nameY)
  if self.row == TITLE_ROW then
    Font.drawCode(Theme.cursor, nameX - 12, nameY)
  end
  Font.draw("<", region.x + 4, nameY)
  Font.draw(">", region.x + region.width - 12, nameY)

  -- ---- the grid ---------------------------------------------------------
  local cell = math.floor(tonumber(self:grid().cell) or FALLBACK.grid.cell)
  local box = self:box()
  for row = 1, ROWS do
    for col = 1, COLS do
      local x, y = self:cellAt(row, col)
      local slot = (row - 1) * COLS + col
      if slot <= Boxes.capacity() then
        if row == self.row and col == self.col then
          love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
          love.graphics.rectangle("fill", x, y, cell, cell, 3, 3)
          love.graphics.setColor(1, 1, 1, 1)
        end
        local held = box[slot]
        if held then
          self:drawIcon(held, x + cell / 2, y + cell / 2)
        end
      end
    end
  end

  -- ---- the PkMn DATA panel, about whatever the cursor is on -------------
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(SIDE.tx, SIDE.ty, SIDE.tw, SIDE.th)
  local mon = (self.held and self.held.mon) or self:panelMon()
  if mon then
    self:drawIcon(mon, PANEL.pic.x, PANEL.pic.y)
    Font.draw(self:nameOf(mon), PANEL.name.x, PANEL.name.y)
    -- "/SPECIES" -- the slash is part of the line on the cartridge, not a
    -- separator this port invented
    local species = self.game.data.pokemon[mon.species]
    Font.draw("/" .. ((species and species.name) or tostring(mon.species)),
              PANEL.species.x, PANEL.species.y)
    -- the gender symbol, then Lv and the number.  Genderless mons -- and
    -- NIDORAN, which the cartridge forces into that arm at 080CEF14 because
    -- its species already carries the symbol -- get a blank instead.
    local sym = ""
    if mon.gender == "male" then sym = "♂ "
    elseif mon.gender == "female" then sym = "♀ " end
    Font.draw(sym .. "Lv" .. tostring(mon.level or 0),
              PANEL.level.x, PANEL.level.y)
    -- the held item's NAME, which is a line of its own here rather than an
    -- icon; blank when it is not holding anything
    local held = mon.heldItem or mon.item
    local def = held and self.game.data.items and self.game.data.items[held]
    Font.draw(def and (def.name or tostring(held)) or "",
              PANEL.item.x, PANEL.item.y)
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- ---- the two buttons under the grid ------------------------------------
  --
  -- PARTY POKeMON at x 80 and CLOSE BOX at x 168, both sixteen tall along
  -- the top on the cartridge (SetPos 1,10,0 and 2,21,0).  Drawn under the
  -- grid here, where this layout has the room, until the tab art is ripped.
  do
    local labels = { Strings("PARTY"), Strings("CLOSE BOX") }
    for i, text in ipairs(labels) do
      local bx = (i == 1) and 88 or 168
      if self.onButtons and self.buttonIndex == i then
        love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
        love.graphics.rectangle("fill", bx - 4, 146, Font.width(text) + 8, 14,
                                3, 3)
        love.graphics.setColor(1, 1, 1, 1)
      end
      Font.draw(text, bx, 149)
    end
  end

  -- ---- ...and the party, when it is up ----------------------------------
  if self.partyOpen then self:drawParty() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- WHICH MON THE PANEL IS ABOUT: whatever the cursor is on, in the box or in
-- the party.
function Gen3BoxMenu:panelMon()
  if self.partyOpen and self.partyIndex then
    return (self.game.save.party or {})[self.partyIndex]
  end
  return (self:selected())
end

-- THE PARTY PANEL.
--
-- Six slots and a CANCEL, at CreateMonIconSprite's own coordinates.  The
-- frame is this port's -- the cartridge's is a BG1 tilemap that is not
-- extracted yet -- but every position inside it is the cartridge's.
function Gen3BoxMenu:drawParty()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(math.floor(PARTY.x / 8), math.floor(PARTY.y / 8),
               math.floor(PARTY.w / 8), math.floor(PARTY.h / 8))
  local party = self.game.save.party or {}
  for i, spot in ipairs(PARTY.slots) do
    local mon = party[i]
    if i == self.partyIndex then
      love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
      love.graphics.rectangle("fill", spot[1] - 16, spot[2] - 16, 32, 32, 3, 3)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if mon then self:drawIcon(mon, spot[1], spot[2]) end
  end
  if self.partyIndex == #PARTY.slots + 1 then
    love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
    love.graphics.rectangle("fill", PARTY.cancel[1] - 20, PARTY.cancel[2] - 8,
                            40, 16, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
  end
  Font.draw(Strings("CANCEL"), PARTY.cancel[1] - 18, PARTY.cancel[2] - 4)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3BoxMenu
