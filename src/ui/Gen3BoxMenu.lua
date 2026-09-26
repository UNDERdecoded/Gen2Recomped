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
-- AND THE CHROME, which used to be the part that was not.  The cartridge
-- draws the left PkMn DATA panel and the party panel as BG1 tilemaps out of
-- one 144-tile sheet, and both are ripped now (see extractStoragePanels):
-- 085722A0 is the left panel, 08DD36C8 the party one, and the sheet under
-- them is 08DD2FE8.  What is still this port's own is the two top tabs and
-- the buttons row under the grid.  Everything INSIDE the panels is the
-- cartridge's too: the four lines of the PkMn DATA panel and where each
-- sits, the 64x64 window its front pic stands in, the party's six slots, the
-- twenty-four pixels between them, and the places the cursor lights up.

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
local SIDE = { x = 0, y = 0, tx = 0, ty = 0, tw = 10, th = 20 }
local PANEL = {
  pic = { x = 40, y = 48 },
  name = { x = 6, y = 88 },
  species = { x = 6, y = 103 },
  level = { x = 10, y = 117 },
  item = { x = 6, y = 131 },
  -- the 64x64 hole the panel's art leaves for the FRONT PIC, which is
  -- (40, 48) read as a centre.  The dataset carries the same rectangle off
  -- the rip; this is what a cache imported before it falls back to.
  window = { x = 8, y = 16, width = 64, height = 64 },
}
local PARTY = {
  x = 80, y = 0, w = 96, h = 160,
  -- CreateMonIconSprite's own coordinates (080CB7E8); the cursor sits twelve
  -- pixels above each, exactly as it does over the box grid
  slots = { { 104, 64 }, { 152, 16 }, { 152, 40 }, { 152, 64 },
            { 152, 88 }, { 152, 112 } },
  -- GetCursorCoordsByPos (080CD444) case 1 is the party, and it is a CURSOR
  -- table, not an icon table: pos 0 is (104, 52), pos 1..5 are (152, 24n+4)
  -- and pos 6 -- CANCEL -- is (152, 132).  Every one of those is exactly
  -- twelve above the icon coordinate above, which is the check that the two
  -- tables are the same six places; CANCEL has no icon, so its cursor
  -- coordinate is all there is of it.
  cancel = { 152, 132 },
  -- WHERE THE LIT RECTANGLE GOES, which is what "when hovering over the
  -- cancel button the highlight isnt over the cancel button at all" was.
  -- The highlight was being drawn around the CURSOR coordinate as though it
  -- were the button's centre, which put it twelve pixels high and four wide
  -- of a plate the art draws at (136, 136).  The art's own boxes start FOUR
  -- BELOW the cursor and are thirty-two across: a slot frame is 32x24 and
  -- CANCEL's plate is 32x16, measured off the extracted panel and agreeing
  -- with 080CD4A6's table to the pixel.
  lift = 12, drop = 4, markW = 32, markH = 24, cancelH = 16,
}
-- row 0 is the title: Emerald puts the cursor on the box name when you walk
-- off the top of the grid, and left/right there change box
local TITLE_ROW = 0

-- The rectangle that lights up for party place i -- 1..6 for the slots, one
-- past them for CANCEL -- built from the cursor table above rather than from
-- the icon table, because CANCEL is not an icon.
local function partyMark(i)
  local spot = PARTY.slots[i]
  local cx = spot and spot[1] or PARTY.cancel[1]
  local cy = spot and (spot[2] - PARTY.lift) or PARTY.cancel[2]
  return cx - PARTY.markW / 2, cy + PARTY.drop, PARTY.markW,
         spot and PARTY.markH or PARTY.cancelH
end

function Gen3BoxMenu:uiSize() return GBA_W, GBA_H end
function Gen3BoxMenu:wantsFillScale() return true end

function Gen3BoxMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- WHAT THE CARTRIDGE SAYS ABOUT DEPOSITING, out of the storage system's own
-- string block (gen3PCMenu.storage.text, swept beside "What would you like to
-- do?").  The fallbacks are this port's English for a cache imported before
-- the sweep; none of them is the wording it used to use, which was invented.
local BOX_FALLBACK = {
  deposited = "was deposited.",
  boxFull   = "The BOX is full.",
  lastMon   = "That's your last POKeMON!",
  whichTake = "Which one will you take?",
}

function Gen3BoxMenu.word(game, key)
  local storage = ((game.data.constants or {}).gen3PCMenu or {}).storage
  local said = type(storage) == "table" and type(storage.text) == "table"
               and storage.text[key] or nil
  return type(said) == "string" and said or BOX_FALLBACK[key]
end

function Gen3BoxMenu.new(game, opts)
  local self = setmetatable({ game = game, opts = opts or {}, t = 0 },
                            Gen3BoxMenu)
  Boxes.ensure(game.save)
  self.row, self.col = 1, 1
  -- DEPOSIT OPENS ON THE PARTY, because on the cartridge it IS a party
  -- screen: sInPartyMenu is set from the box option before the first frame,
  -- so BOXOPTION_DEPOSIT slides the party in and puts the cursor in it rather
  -- than on the grid.  The question it asks afterwards -- "Deposit in which
  -- BOX?" -- is the other half of the same fact: the mon is chosen first and
  -- the box second, which is the wrong way round if the grid has the cursor.
  --
  -- Reported from play: "the deposit Pokemon screen should show your party
  -- from the start not the box".
  if self.opts.mode == "deposit" then
    self.partyOpen, self.partyIndex = true, 1
  end
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

-- THE DEPOSIT HALF, and it happens IN THIS SCREEN.
--
-- This used to push the Gen 3 party MENU over the box and take a pick there,
-- on the reasoning that the port already had a party list that looked right.
-- The cartridge does not: storage's party is a panel of this screen that
-- slides in over the grid (PARTY above), the cursor starts in it for the
-- deposit option, and the grid behind it stays visible because it is the
-- destination.  Reported from play: "the deposit Pokemon screen should show
-- your party from the start not the box".
--
-- SELECT still lands here, because SELECT is how the older screen reached
-- deposit and a save in the wild may have that habit; it just opens the panel
-- instead of a second screen.
function Gen3BoxMenu:deposit()
  local game = self.game
  if #(game.save.party or {}) <= 1 then
    game.stack:push(TextBox.new(game, Gen3BoxMenu.word(game, "lastMon")))
    return
  end
  self.onButtons = nil
  self.partyOpen, self.partyIndex = true, 1
end

-- Put the party mon in slot `index` into the box on screen.  The box is the
-- one the grid is showing, which is what the cartridge asks for by name
-- ("Deposit in which BOX?") and what left/right on the title row chooses
-- here -- so stepping out of the panel, changing box and coming back is the
-- same choice in a different order.
function Gen3BoxMenu:depositFromParty(index)
  local game = self.game
  local party = game.save.party or {}
  local mon = party[index]
  if not mon then return end
  if #party <= 1 then
    game.stack:push(TextBox.new(game, Gen3BoxMenu.word(game, "lastMon")))
    return
  end
  if #self:box() >= Boxes.capacity() then
    game.stack:push(TextBox.new(game, Gen3BoxMenu.word(game, "boxFull")))
    return
  end
  table.remove(party, index)
  table.insert(self:box(), mon)
  -- the cartridge's line is the bare "was deposited." with the name in front
  -- of it, the way every storage message is built
  game.stack:push(TextBox.new(game,
    ("%s %s"):format(self:nameOf(mon), Gen3BoxMenu.word(game, "deposited"))))
  local last = #PARTY.slots + 1
  self.partyIndex = math.max(1, math.min(self.partyIndex, math.min(#party, last)))
end

function Gen3BoxMenu:nameOf(mon)
  local def = self.game.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

function Gen3BoxMenu:clampCursor()
  -- Gen 3 storage is a fixed array of slots and imported/cartridge boxes can
  -- have holes.  Lua's `#box` is undefined for that shape (Boxes.lua documents
  -- the same invariant), so a mon dropped into slot 3 of an otherwise empty
  -- box could make `#box` read as 0 and snap the hand back to slot 1.  The next
  -- A then picked up nothing, which made MOVE POKEMON look broken again even
  -- after the held-mon logic itself had been fixed.
  local box = self:box()
  local last = 0
  for i = 1, Boxes.capacity() do
    if box[i] ~= nil then last = i end
  end
  local slot = (self.row - 1) * COLS + self.col
  if last == 0 then
    self.row, self.col = 1, 1
    return
  end
  if slot > last then
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
        local box = self:box()
        require("src.ui.Screens").push(game, "Gen3SummaryMenu", {
          mon = mon,
          party = box,
          partyIndex = slot,
          onMonChange = function(index)
            self.row = math.floor((index - 1) / COLS) + 1
            self.col = (index - 1) % COLS + 1
          end,
        })
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
    -- B HAS THREE MEANINGS HERE, and it used to have one.
    --
    -- Holding a mon, it puts the mon back -- walking out of the screen with
    -- one in hand is how it went missing.  With the party panel up, it slides
    -- the panel out, which is what the panel's own B branch below was written
    -- for and never reached: this test ran first and popped the whole screen,
    -- so that branch was dead code and the panel could only be left through
    -- CANCEL.  With neither, it closes the box.
    if self:returnHeld() then return end
    if self.partyOpen then
      self.partyOpen, self.partyIndex, self.partyReturn = nil, nil, nil
      return
    end
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
      -- ...and what A means here is the mode's, exactly as it is over the
      -- grid: MOVE picks the mon up to carry it, DEPOSIT puts it away.
      --
      -- AN EMPTY PLACE IS A DESTINATION.  Reported from play: "with the move
      -- menu in the pokemon storage system im not able to take a pokemon from
      -- the box and place it into the empty spots in my party".  This read
      -- the mon standing on the place FIRST and did nothing at all when there
      -- was none -- so the empty places, which are the only ones you ever
      -- want to put a mon down on, were the one part of the party A did not
      -- work on.  carryFromParty has always handled both: with an empty hand
      -- it needs a mon to pick up and returns when there is none, and with a
      -- full one it puts the mon down whether or not anybody is standing
      -- there.  So the question is its own, and asking it out here only ever
      -- took the answer away.  DEPOSIT keeps the guard, because depositing
      -- nothing is not an action.
      if self.opts.mode == "deposit" then
        if (self.game.save.party or {})[self.partyIndex] then
          self:depositFromParty(self.partyIndex)
        end
      else
        self:carryFromParty(self.partyIndex)
      end
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
        -- MOVE POKeMON and MOVE ITEMS may summon it (080C839E), and so may
        -- DEPOSIT -- which opens inside it and needs a way back once the
        -- player has stepped out to change box.  WITHDRAW gets "Which one
        -- will you take?" instead, and has no use for the party at all.
        if self.opts.mode == "move" or self.opts.mode == "deposit" then
          self.onButtons = nil
          self.partyOpen, self.partyIndex = true, 1
        end
      else
        -- CLOSE BOX with a mon in hand puts it back first, for the same
        -- reason B does
        self:returnHeld()
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
-- slot, swapping with whatever is already there.  A mon carried from a party
-- slot is put down in the box and one carried from the box is put down in the
-- party, which is the whole point of the party panel being reachable here.
--
-- ------- WHERE THE MON WENT
--
-- Reported from play: "If i select move in the pokebox storage, the pokemon
-- dissapears completely it should grab them in your selection and let you
-- place them in a box or from a box to your party."  Both halves of that were
-- true, and the second one is why the first happened.
--
-- A pickup from the BOX did not take the mon out of the box -- it only noted
-- which slot it came from -- so nothing was ever in your hand to see.  A
-- pickup from the PARTY did take it out, and then putting it down ran
--
--     box[slot], box[held.from] = held.mon, target
--
-- where `held.from` is the BOX slot a box pickup came from, and a party
-- pickup has none: it carries `fromParty`.  So that line is `box[nil] = ...`,
-- which is not a silent no-op in Lua -- it raises "table index is nil", and
-- because Lua assigns a multiple assignment only after evaluating all of it,
-- `box[slot] = held.mon` never happened either.  The mon had already left the
-- party and it never reached the box: gone, with the error swallowed.
--
-- So the hand is now real.  A pickup EMPTIES the place it came from -- which
-- is what makes the grab visible, the grid draws what is in the box -- and
-- every put-down has somewhere for the displaced mon to go: back to the
-- origin the hand remembers, party slot or box slot, whichever it was.
-- Nothing is dropped on the floor between the two, and B while holding puts
-- it back rather than walking out with it.

-- WHERE THE HELD MON CAME FROM, put back.  B presses this, and so does
-- anything that would otherwise leave the screen with a mon in hand.
function Gen3BoxMenu:returnHeld()
  local held = self.held
  if not held then return false end
  self.held = nil
  if held.from then
    self:box()[held.from] = held.mon
  else
    local party = self.game.save.party or {}
    table.insert(party, math.min(held.fromParty or (#party + 1), #party + 1),
                 held.mon)
  end
  return true
end

-- ...and the same question asked the other way: a mon that has been displaced
-- by one being put down goes where the hand came from.
function Gen3BoxMenu:placeDisplaced(held, mon)
  if not mon then return end
  if held.from then
    self:box()[held.from] = mon
    return
  end
  local party = self.game.save.party or {}
  if #party < Party.MAX then
    table.insert(party, math.min(held.fromParty or (#party + 1), #party + 1),
                 mon)
    return
  end
  -- the party filled up behind you, which the cartridge cannot arrange and a
  -- mod can: the displaced mon stays in your hand rather than evaporating
  self.held = { mon = mon, from = nil, fromParty = held.fromParty }
end

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
  -- putting one down into the party.  The mon standing there, if any, takes
  -- the hand's own origin -- so party-to-party is a swap and box-to-party
  -- sends the displaced one into the box slot the hand emptied.
  -- whoever is standing on the place, which may be nobody -- an empty place
  -- is where a box mon is meant to go.  (This used to be written
  -- `(held.from == nil) and nil or party[index]`, which is a Lua trap rather
  -- than a branch: `x and nil or y` is always y, so it read party[index]
  -- either way.  That is what it should read; it is spelled that way now so
  -- the next edit does not "fix" it into meaning what it looked like.)
  local target = party[index]
  if target then
    table.remove(party, index)
  elseif #party >= Party.MAX then
    self.game.stack:push(TextBox.new(self.game,
      Strings("Your party is full!")))
    return
  end
  table.insert(party, math.min(index, #party + 1), held.mon)
  self.held = nil
  self:placeDisplaced(held, target)
end

function Gen3BoxMenu:carry(slot)
  local box = self:box()
  if not slot then return end
  local held = self.held
  if not held then
    local mon = box[slot]
    if not mon then return end
    -- INTO THE HAND, and out of the box: the grid draws what the box holds,
    -- so this is the grab the report asked for
    self.held = { mon = mon, from = slot }
    box[slot] = nil
    return
  end
  self.held = nil
  if slot == held.from then
    -- put back where it was picked up from, which is a cancel
    box[slot] = held.mon
    return
  end
  local target = box[slot]
  if target then
    box[slot] = held.mon
    self:placeDisplaced(held, target)
  else
    -- A MON GOES WHERE YOU PUT IT.  This used to `table.remove` the slot it
    -- came from and append at `#box + 1`, which is wrong twice over: the
    -- remove SHIFTS every later mon down one, so dropping one into an empty
    -- square reordered the whole box behind it, and the append picks a slot by
    -- walking off a length that is meaningless on a box with holes -- an
    -- imported PC keeps its mons at the slots the cartridge put them in, and
    -- `#` on that reads 0, so the mon could land at slot 1 on top of nothing,
    -- or past the end of the box where nothing can reach it again.
    box[slot] = held.mon
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

-- ---------------------------------------------------------------------------
-- FIRERED'S CHROME (RomExtractorGen3:extractFireRedStorage): the scrolling
-- BG3 pattern, BG1's PKMN DATA panel, the PARTY POKeMON and CLOSE BOX tabs
-- along the top, the party panel sliding down over the grid, and the hand.
-- ---------------------------------------------------------------------------
function Gen3BoxMenu:frlgRecord()
  local c = self.game and self.game.data and self.game.data.constants
  local r = c and c.gen3FRLGStorage
  return (type(r) == "table" and r.images and r.images.menu) and r or nil
end

function Gen3BoxMenu:frlgImage(key)
  local r = self:frlgRecord()
  local path = r and r.images[key]
  if not path then return nil end
  self._frlg = self._frlg or {}
  if self._frlg[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self._frlg[path] = ok and img or false
  end
  return self._frlg[path] or nil
end

function Gen3BoxMenu:frlgQuad(img, x, y, w, h)
  self._quads = self._quads or {}
  local key = ("%s:%d:%d:%d:%d"):format(tostring(img), x, y, w, h)
  local q = self._quads[key]
  if not q then
    q = love.graphics.newQuad(x, y, w, h, img:getDimensions())
    self._quads[key] = q
  end
  return q
end

function Gen3BoxMenu:frontPic(mon)
  self._pics = self._pics or {}
  local key = tostring(mon.species) .. (mon.shiny and ":s" or "")
  if self._pics[key] == nil then
    local ok, path = pcall(require("src.pokemon.Sprites").path, self.game.data,
                           mon.species, "front", { kind = "dex", shiny = mon.shiny })
    local img
    if ok and path then
      local okImg, image = pcall(require("src.render.Assets").image, path)
      img = okImg and image or nil
    end
    self._pics[key] = img or false
  end
  return self._pics[key] or nil
end

function Gen3BoxMenu:drawFireRed(rec)
  local g = love.graphics
  local frames = (self.t or 0) * 60
  g.setColor(1, 1, 1, 1)
  -- BG3: half a pixel a frame on both axes
  local scroll = self:frlgImage("scroll")
  if scroll then
    local sw, sh = scroll:getDimensions()
    local ox = math.floor(frames / 2) % sw
    local oy = math.floor(frames / 2) % sh
    for y = -oy, GBA_H, sh do
      for x = -ox, GBA_W, sw do g.draw(scroll, x, y) end
    end
  else
    g.setColor(0.16, 0.20, 0.28, 1)
    g.rectangle("fill", 0, 0, GBA_W, GBA_H)
    g.setColor(1, 1, 1, 1)
  end

  -- the box
  local region = self:region()
  local paper = self:wallpaper()
  if paper then g.draw(paper, region.x, region.y) end
  local band = math.floor(tonumber((self:record() or {}).band) or FALLBACK.band)
  local name = self:boxName()
  local nameY = region.y + math.floor((band - 14) / 2)
  local nameX = region.x + math.floor((region.width - Font.width(name)) / 2)
  local two = Font.beginTwoTone({ 1, 1, 1, 1 }, { 0.38, 0.38, 0.38, 1 })
  Font.draw(name, nameX, nameY)
  if two then Font.endTwoTone() end

  local cell = math.floor(tonumber(self:grid().cell) or FALLBACK.grid.cell)
  local box = self:box()
  for row = 1, ROWS do
    for col = 1, COLS do
      local x, y = self:cellAt(row, col)
      local held = box[(row - 1) * COLS + col]
      if held and not (self.held and self.held.from == (row - 1) * COLS + col) then
        self:drawIcon(held, x + cell / 2, y + cell / 2)
      end
    end
  end

  -- BG1: the PKMN DATA panel
  local menu = self:frlgImage("menu")
  if menu then g.draw(menu, 0, 0) end
  local mon = (self.held and self.held.mon) or self:panelMon()
  local data = self:frlgImage("pkmn_data")
  if data then g.draw(data, self:frlgQuad(data, 0, mon and 0 or 16, 64, 16), 8, 0) end
  if mon then
    local pic = self:frontPic(mon)
    if pic then
      local pw, ph = pic:getDimensions()
      g.draw(pic, PANEL.pic.x - math.floor(pw / 2), PANEL.pic.y - math.floor(ph / 2))
    end
    local ink = rec.colors and rec.colors.text
    local fg = ink and { ink[1][1] / 255, ink[1][2] / 255, ink[1][3] / 255, 1 } or { 0.38, 0.38, 0.38, 1 }
    local sh = ink and { ink[2][1] / 255, ink[2][2] / 255, ink[2][3] / 255, 1 } or { 0.84, 0.84, 0.81, 1 }
    local function text(s, x, y, small)
      local faced = small and Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
      local t2 = Font.beginTwoTone(fg, sh)
      if not t2 then g.setColor(fg) end
      Font.draw(s, x, y)
      if t2 then Font.endTwoTone() end
      if faced then Font.popFace() end
      g.setColor(1, 1, 1, 1)
    end
    -- PrintDisplayMonInfo: window (0,11), lines 14 apart, the item in the small face
    local species = self.game.data.pokemon[mon.species]
    text(self:nameOf(mon), 6, 88)
    text("/" .. ((species and species.name) or tostring(mon.species)), 6, 102)
    local sym = ""
    if mon.gender == "male" then sym = "♂" elseif mon.gender == "female" then sym = "♀" end
    text(sym, 10, 116)
    text("Lv" .. tostring(mon.level or 0), 10 + 16, 116)
    local heldItem = mon.heldItem or mon.item
    local def = heldItem and self.game.data.items and self.game.data.items[heldItem]
    if def then text(def.name or tostring(heldItem), 6, 132, true) end
  end

  -- the two tabs, and the party panel sliding down under PARTY POKeMON
  local party = self.game.save.party or {}
  local sheet = self:frlgImage("party_" .. math.max(1, math.min(6, #party)))
  local target = self.partyOpen and 20 or 0
  self.partySlide = self.partySlide or 0
  if self.partySlide < target then self.partySlide = self.partySlide + 1
  elseif self.partySlide > target then self.partySlide = self.partySlide - 1 end
  local slide = self.partySlide
  if sheet then
    -- rows (20 - slide) .. 21 of the panel, top-aligned
    local rows = math.min(22, slide + 2)
    g.draw(sheet, self:frlgQuad(sheet, 0, (20 - slide) * 8, 96, rows * 8), 80, 0)
  end
  local close = self:frlgImage("close_box")
  if close then
    local flash = self.onButtons and self.buttonIndex == 2 and math.floor(frames / 30) % 2 == 1
    g.draw(close, self:frlgQuad(close, 0, flash and 16 or 0, 72, 16), 168, 0)
  end
  if slide > 0 then
    local dy = (slide - 20) * 8
    for i, spot in ipairs(PARTY.slots) do
      local pm = party[i]
      if pm and not (self.held and self.held.fromParty == i) then
        self:drawIcon(pm, spot[1], spot[2] + dy)
      end
    end
  end

  -- the hand: frame 0 open, frame 1 closed while carrying
  local hand = self:frlgImage("hand")
  if hand then
    local hx, hy
    if self.partyOpen and slide == 20 then
      local last = #PARTY.slots + 1
      if self.partyIndex == last then
        hx, hy = PARTY.cancel[1], PARTY.cancel[2] - 12
      else
        local spot = PARTY.slots[self.partyIndex or 1]
        hx, hy = spot[1], spot[2] - 12
      end
    elseif self.onButtons then
      hx, hy = (self.buttonIndex == 1) and 124 or 204, 4
    elseif self.row == TITLE_ROW then
      hx, hy = region.x + region.width / 2, region.y - 4
    else
      local x, y = self:cellAt(self.row, self.col)
      hx, hy = x + cell / 2, y + cell / 2 - 12
    end
    if hx then
      local bob = (not self.held) and (math.floor(frames / 30) % 2) or 0
      if self.held then self:drawIcon(self.held.mon, hx, hy + 4) end
      g.draw(hand, self:frlgQuad(hand, self.held and 32 or 0, 0, 32, 32),
             math.floor(hx - 16), math.floor(hy - 16 + bob))
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3BoxMenu:draw()
  local frlg = self:frlgRecord()
  if frlg then return self:drawFireRed(frlg) end
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
        -- ...but not while the party panel is up: the cursor is IN the
        -- party then, and the grid's own square kept lighting up beside it
        if row == self.row and col == self.col and not self.partyOpen then
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
  --
  -- Reported from play: "the left pokemon data menu in the box isnt showing
  -- the proper graphics still or text like it does in the rom".  This was
  -- Font.drawBox -- the same white slab the party half used to be -- and it
  -- is the cartridge's picture now, off the tilemap at 085722A0 (see
  -- extractStoragePanels).  The drawBox stays as the fallback for a dataset
  -- imported before the rip, exactly as it does for the party panel.
  love.graphics.setColor(1, 1, 1, 1)
  local data = self:panelArt("data")
  if data then
    love.graphics.draw(data, SIDE.x, SIDE.y)
  else
    Font.drawBox(SIDE.tx, SIDE.ty, SIDE.tw, SIDE.th)
  end
  local mon = (self.held and self.held.mon) or self:panelMon()
  if mon then
    -- AND THE PICTURE IN IT IS THE FRONT PIC, not the icon.  The art leaves
    -- a 64x64 window and CreateSprite at 080CA40E puts the mon at its centre;
    -- a 32x32 icon in a 64x64 hole is what it looked like before.  Emerald
    -- stands the pic on the window's floor, the way the summary page does.
    local pic = data and self:frontPic(mon)
    if pic then
      local win = self:picWindow()
      local w, h = pic:getDimensions()
      love.graphics.draw(pic,
                         win.x + math.floor((win.width - w) / 2),
                         win.y + math.max(0, win.height - h))
    else
      self:drawIcon(mon, PANEL.pic.x, PANEL.pic.y)
    end
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
  -- THE MON IN YOUR HAND, drawn on the cursor wherever it is.  The grid and
  -- the party panel both draw what is actually stored, and a held mon is
  -- stored nowhere -- so without this the grab is invisible and looks exactly
  -- like the mon having been lost, which is what was reported.
  self:drawHeld()
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

-- Where the cursor is standing: a party slot while the panel is up, the
-- CANCEL button when the cursor is past the six, otherwise the grid cell.
function Gen3BoxMenu:cursorPoint()
  if self.partyOpen and self.partyIndex then
    local spot = PARTY.slots[self.partyIndex]
    if spot then return spot[1], spot[2] end
    return PARTY.cancel[1], PARTY.cancel[2]
  end
  if self.onButtons or self.row == TITLE_ROW then return nil, nil end
  local cell = math.floor(tonumber(self:grid().cell) or FALLBACK.grid.cell)
  local x, y = self:cellAt(self.row, self.col)
  return x + cell / 2, y + cell / 2
end

function Gen3BoxMenu:drawHeld()
  local held = self.held
  if not held then return end
  local x, y = self:cursorPoint()
  if not x then return end
  love.graphics.setColor(1, 1, 1, 1)
  -- lifted a few pixels, the way a carried mon sits above the hand
  self:drawIcon(held.mon, x, y - 6)
end

-- THE PARTY PANEL, WHICH IS THE CARTRIDGE'S OWN PICTURE.
--
-- Reported from play: "the party menu in the box is white background instead
-- of looking like the rom".  It was Font.drawBox -- the engine's generic
-- rounded white slab -- because the cartridge's panel is a BG1 tilemap and
-- nothing here read one.  extractStoragePanels does now: the loader at
-- 00CA744 names its tiles, its map and its palette, and that is also the
-- function that calls 00CB7E8, which is where PARTY.slots above came from.
-- So the picture and the six places on it were derived separately, years
-- apart in this file, and agree -- which is how each one checks the other.
--
-- The panel is 96 by 176 and the screen is 160 tall: the bottom two rows are
-- the PARTY POKeMON tab, which belongs to the buttons row rather than to the
-- panel, so the draw takes the top 160 and leaves the tab where it is.
function Gen3BoxMenu:panelRecord(key)
  local panels = (self.game.data.constants or {}).gen3StoragePanels
  local rec = panels and panels[key]
  if type(rec) ~= "table" or type(rec.image) ~= "string" then return nil end
  return rec
end

-- Either panel's picture, loaded once.  `false` is cached for one that the
-- dataset names and the disk does not have, so the warning is printed once
-- rather than every frame.
function Gen3BoxMenu:panelArt(key)
  local rec = self:panelRecord(key)
  if not rec then return nil end
  self._panels = self._panels or {}
  if self._panels[key] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.image)
    self._panels[key] = (ok and img) or false
    if not self._panels[key] then
      Logger.warn("gen3 boxes: %s is named by the dataset and is not on "
                  .. "disk -- import the ROM again", tostring(rec.image))
    end
  end
  return self._panels[key] or nil
end

function Gen3BoxMenu:partyPanel() return self:panelArt("party") end

-- WHERE THE FRONT PIC GOES: the 64x64 hole the PkMn DATA art leaves, off the
-- rip when the dataset carries it and off PANEL.window when it does not.
function Gen3BoxMenu:picWindow()
  local rec = self:panelRecord("data")
  local pic = rec and rec.pic
  if type(pic) == "table" and tonumber(pic.width) and tonumber(pic.height) then
    return pic
  end
  return PANEL.window
end

-- The mon's front pic, cached per species and per palette -- a shiny is a
-- different picture.  Nil whenever the sprite will not load, which is what
-- sends the draw back to the icon.
function Gen3BoxMenu:frontPic(mon)
  if not mon then return nil end
  local key = ("%s:%s"):format(tostring(mon.species), tostring(mon.shiny))
  self._pics = self._pics or {}
  if self._pics[key] == nil then
    local got = false
    local ok, path = pcall(function()
      return (require("src.pokemon.Sprites").path(self.game.data, mon.species,
                                                  "front", { mon = mon }))
    end)
    if ok and path then
      local okImg, img = pcall(love.graphics.newImage, path)
      if okImg then got = img end
    end
    self._pics[key] = got
  end
  return self._pics[key] or nil
end

function Gen3BoxMenu:drawParty()
  love.graphics.setColor(1, 1, 1, 1)
  local panel = self:partyPanel()
  if panel then
    local pw, ph = panel:getDimensions()
    local quad = love.graphics.newQuad(0, 0, math.min(pw, PARTY.w),
                                       math.min(ph, PARTY.h), pw, ph)
    love.graphics.draw(panel, quad, PARTY.x, PARTY.y)
  else
    -- a dataset without the picture keeps the frame this screen has always
    -- drawn, rather than the panel going missing altogether
    Font.drawBox(math.floor(PARTY.x / 8), math.floor(PARTY.y / 8),
                 math.floor(PARTY.w / 8), math.floor(PARTY.h / 8))
  end
  local party = self.game.save.party or {}
  local lit = self.partyIndex
  for i, spot in ipairs(PARTY.slots) do
    local mon = party[i]
    if i == lit then
      love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
      love.graphics.rectangle("fill", partyMark(i))
      love.graphics.setColor(1, 1, 1, 1)
    end
    if mon then self:drawIcon(mon, spot[1], spot[2]) end
  end
  if lit == #PARTY.slots + 1 then
    love.graphics.setColor(0.98, 0.86, 0.36, 0.55)
    love.graphics.rectangle("fill", partyMark(lit))
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- the word CANCEL is drawn INTO the cartridge's panel, so printing it
  -- again on top would double it; only a dataset without the picture needs
  -- this screen to say it
  if not self:partyPanel() then
    Font.draw(Strings("CANCEL"), PARTY.cancel[1] - 18, PARTY.cancel[2] - 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3BoxMenu
