-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's BAG (src/applications/bag/{main,sprites,windows}.c).
--
-- EIGHT POCKETS, not five: ITEMS, MEDICINE, POKé BALLS, TMs & HMs, BERRIES,
-- MAIL, BATTLE ITEMS and KEY ITEMS, every word bank 395's, in the order an
-- item record's own `fieldPocket` numbers them.  Which pocket an item is in is
-- that field (see `Gen4Items.checkPockets`).
--
-- WHAT IS ON THE TOP SCREEN, back to front -- a DS layer's priority counts
-- DOWN towards the front, and a sprite draws over a BG of its own priority:
--
--   MAIN_3 (3)  `bag/item_list_border` -- the white panel behind the list
--   MAIN_2 (2)  the item list window, tile (14, 0), 17 x 18 tiles, NINE rows
--               of sixteen pixels; and the pocket name, centred on x = 50
--   MAIN_1 (1)  `bag/bag_ui_main`, which clips the list to its frame -- row 0
--               and row 8 of the list are half hidden behind it, which is why
--               the cartridge pads the list with an empty entry at each end
--   OBJ   (1)  the bag (48, 50), the item highlight (177, 24 + 16 * (pos - 1)),
--               the item's icon (22, 172)
--   MAIN_0 (0)  the pocket icons (window at tile (0, 11), blit at y 3) and the
--               description (tile (0, 18), printed at x 40)
--   OBJ   (0)  the pocket highlight (iconsX + spacing * i + 6, 97) and the two
--               pocket arrows (2, 96) / (98, 96)
--
-- AND THE BOTTOM SCREEN: the Poke Ball dial (pokeball_inside, affine, under
-- pokeball_borders), one 40x40 button per accessible pocket around it at
-- `sPocketButtonSpritesPositions_<n>Pockets`, and the dial's own button.
--
-- THE LIST IS THE CARTRIDGE'S ListMenu, not a scrolling window of ours: an
-- empty HEADER entry first, the items, CLOSE BAG, an empty header last; the
-- cursor starts on row 1, moves freely until row 5 and then the list scrolls
-- under it (`UpdateOffsetsForScroll`), and it does not wrap.  Each pocket
-- keeps its own cursor, as `BagApplicationPocket.cursorPos/cursorScroll` do.
--
-- A ROW (`ItemListMenuPrintCB` and windows.c):
--   * the name at x 0 -- or at 35 in the TM and Berry pockets, which print
--     "No." and a two-digit number from font_special_chars first (an HM
--     prints the HM tag from item_entry_icons and its number at x 16)
--   * "x" at ITEM_COUNT_START_POS (109; 115 in the TM pocket) and the count
--     right-aligned to ITEM_COUNT_NUMBER_START_POS (134); HMs have none
--   * a registered Key Item carries the SELECT tag at x 96
--
-- ART: `gen4_graphics` carries the BG pictures (bag/bag_ui_main,
-- bag/item_list_border, bag/pocket_selector_icons); `gen4_bag_art`
-- (Gen4BagArt) the sprites in their resolved palettes, the window blits and
-- the touch screen.  Each is optional, and a missing one leaves its element
-- out rather than drawing a likeness.
--
-- WHAT AN ITEM DOES IS NOT REIMPLEMENTED HERE: using, giving and tossing live
-- in `BagMenu.useItem`, which Emerald's bag calls too.

local Bag = require("src.inventory.Bag")
local Font = require("src.render.Font")
local Gen4Palettes = require("src.render.Gen4Palettes")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4BagMenu = {}
Gen4BagMenu.__index = Gen4BagMenu
Gen4BagMenu.isOpaque = true

local W, H = 256, 192

-- BagUI_CreateWindows: ITEM_LIST at tile (14, 0), 17 x TEXT_LINES_TILES(9).
local LIST = { x = 14 * 8, y = 0, w = 17 * 8, h = 18 * 8 }
local LINE = 16
local VISIBLE = 9                       -- BAG_UI_NUM_VISIBLE_ITEMS
-- ITEM_COUNT_NUMBER_START_POS and ITEM_COUNT_START_POS (windows.c): the count
-- ends 2 pixels short of the window, the "x" sits three digits and seven
-- pixels before that -- one digit further right in the TM pocket.
local COUNT_RIGHT = 17 * 8 - 2
local COUNT_X = COUNT_RIGHT - 3 * 6 - 7
local NUMBERED_TEXT_X = 35              -- textXOffset for TMs and Berries
local REGISTERED_X = 96

-- ITEM_DESCRIPTION at tile (0, 18), printed at x 40, sixteen-pixel lines.
local DESCRIPTION = { x = 40, y = 18 * 8 }

-- The pocket strip: POCKET_INDICATOR at tile (0, 11), the 10x10 corner of
-- each 16-pixel cell blitted at y 3, the unfocused icon at pocketType * 32 and
-- the focused one sixteen further along.  POCKET_NAMES at tile (0, 13),
-- printed at y 2, centred on screen x 50 (`PrintPocketNameCentered`).
local ICON_BLIT = 10
local ICON_CELL = 16
local ICON_STRIDE = 32
local INDICATOR_Y = 88
local ICON_INSET = 3
local NAME_CENTER_X = 50
local NAME_Y = 104 + 2

-- sBagUISpriteTemplates
local BAG_AT = { 48, 50 }
local ITEM_AT = { 22, 172 }
local HIGHLIGHT_AT = { 177, 24 }
local POCKET_HIGHLIGHT_Y = 97
local ARROW_LEFT_AT = { 2, 96 }
local ARROW_RIGHT_AT = { 98, 96 }

-- The touch screen (main.c): button tile positions by accessible-pocket count,
-- and the dial button at tile (13, 7).
local BUTTONS = {
  [8] = { { 1, 4 }, { 2, 10 }, { 5, 15 }, { 10, 18 }, { 17, 18 }, { 22, 15 }, { 25, 10 }, { 26, 4 } },
  [7] = { { 2, 10 }, { 5, 15 }, { 10, 18 }, { 17, 18 }, { 22, 15 }, { 25, 10 }, { 26, 4 } },
  [4] = { { 1, 4 }, { 5, 15 }, { 22, 15 }, { 26, 4 } },
  [1] = { { 17, 18 } },
}
local DIAL_BUTTON_AT = { 13 * 8, 7 * 8 }
-- sPocketButtonTouchRectangles_<n>Pockets: { top, bottom, left, right },
-- inclusive -- the same 40 x 40 squares the buttons are drawn in
local BUTTON_RECTS = {
  [8] = { { 32, 71, 8, 47 }, { 80, 119, 16, 55 }, { 120, 159, 40, 79 }, { 144, 183, 80, 119 },
          { 144, 183, 136, 175 }, { 120, 159, 176, 215 }, { 80, 119, 200, 239 }, { 32, 71, 208, 247 } },
  [7] = { { 80, 119, 16, 55 }, { 120, 159, 40, 79 }, { 144, 183, 80, 119 }, { 144, 183, 136, 175 },
          { 120, 159, 176, 215 }, { 80, 119, 200, 239 }, { 32, 71, 208, 247 } },
  [4] = { { 32, 71, 8, 47 }, { 120, 159, 40, 79 }, { 120, 159, 176, 215 }, { 32, 71, 208, 247 } },
  [1] = { { 144, 183, 136, 175 } },
}
Gen4BagMenu.BUTTONS, Gen4BagMenu.BUTTON_RECTS = BUTTONS, BUTTON_RECTS
-- THE DIAL (main.c): DIAL_CENTER (128, 80), the button a 48-pixel square on
-- it (sDialBtnTouchRect), a turn STARTED in the ring between radius 26 and 64
-- (sDialTouchedTouchBox) and KEPT while the stylus stays between 16 and 80
-- (sDialHeldTouchBox).  One list step per 2 * 80 * 3.14 / 36 = 13 pixels of
-- arc (18 steps a turn for menus and counts), and the picture turns 36
-- degrees per list step, 18 per menu step, on the pad as well (RotateDial).
local DIAL = { x = 128, y = 80, radius = 80, button = 24, startIn = 26, startOut = 64,
               holdIn = 16, holdOut = 80 }
Gen4BagMenu.DIAL = DIAL
-- StepPocketSwitchPressedButtonAnim: the pressed face and the shockwave on
-- frame 3, done on frame 7; StepDialButtonPressedAnim: pressed 3 frames,
-- half 2; the shockwave is 3 + 2 frames (button_shockwave_anim)
local POCKET_PRESS_AT, POCKET_PRESS_DONE = 3, 7
local SHOCKWAVE_FRAMES = { 3, 2 }

-- bank 7 (the bag's own, Bag_Text_*): the action words and the messages
local TEXT_BANK = 7
local T = {
  use = 0, trash = 1, register = 2, give = 3, checkTag = 4, confirm = 5, walk = 6,
  cancel = 8, check = 16, deselect = 18, isSelected = 42, moveWhere = 45,
  throwHowMany = 52, threwAway = 53, throwOk = 54, yes = 82, no = 83,
  throwCount = 84, pp = 86, power = 87, accuracy = 88, category = 89,
  notApplicable = 24, closeBag = 41, plant = 95, open = 96, type = 98,
}
Gen4BagMenu.TEXT = T
local ACTION_FALLBACK = {
  use = "USE", trash = "TRASH", register = "REGISTER", give = "GIVE", checkTag = "CHECK TAG",
  confirm = "CONFIRM", walk = "WALK", cancel = "CANCEL", check = "CHECK", deselect = "DESELECT",
  plant = "PLANT", open = "OPEN",
}
-- the item ids MakeItemActionsMenu tests by number
local ITEM_BICYCLE, ITEM_POFFIN_CASE = 450, 449
local POCKET_MAIL = 5

-- Pocket types (enum Pocket).
local POCKET_TMHMS, POCKET_BERRIES, POCKET_KEY_ITEMS = 3, 4, 7
local FIRST_BERRY = 149                 -- ITEM_CHERI_BERRY; Item_BerryNumber

-- font_special_chars: digits are tiles 0..9, "No." tiles 13..14.
local SPECIAL_DIGIT_W = 8
local SPECIAL_NUMBER_AT = 13 * 8

-- THE CARTRIDGE'S TEXT COLOURS.  Every bag text window is BG palette 3 of
-- bag_ui_main.NCLR, and the printers ask for three pairs out of it:
-- TEXT_COLOR(1, 2, 0) the list and pocket name, (15, 14, 0) the description,
-- (8, 9, 0) an item being moved.  Read from the cache (`gen4_graphics`
-- palettes); these are the fallback for a cache that predates that.
local INK = {
  list = { { 16 / 255, 25 / 255, 33 / 255 },
           { 173 / 255, 189 / 255, 189 / 255 } },
  description = { { 1, 1, 1 }, { 0, 0, 0 } },
  moving = { { 165 / 255, 181 / 255, 206 / 255 },
             { 107 / 255, 140 / 255, 181 / 255 } },
}
local INK_SLOT = 3
local INK_ENTRIES = {
  list = { 1, 2 }, description = { 15, 14 }, moving = { 8, 9 },
}

function Gen4BagMenu:ink(which)
  local pair = (self.inkPairs and self.inkPairs[which]) or INK[which]
  Font.pushStyle({ text = pair[1], shadow = pair[2] })
end

function Gen4BagMenu:uiSize() return W, H end
function Gen4BagMenu:wantsFillScale() return true end
function Gen4BagMenu:wantsEdgeBleed() return false end

function Gen4BagMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4BagMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4BagMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.onPick = opts.onPick
  self.pick = opts.pick and true or false
  self.battle = opts.battle
  self.cache = {}
  local data = game.data or {}
  self.art = (data.gen4_graphics or {}).screens or {}
  self.bagArt = data.gen4_bag_art or {}
  if not next(self.bagArt) then
    Logger.warn("gen4 bag: this cache carries no gen4_bag_art -- the bag, the "
                .. "highlights and the touch screen need tools/gen4_art_extract bag")
  end

  local pairs_ = {}
  for which, at in pairs(INK_ENTRIES) do
    pairs_[which] = Gen4Palettes.text(game.data, "bag/bag_ui_main",
                                      INK_SLOT, at[1], at[2])
  end
  if pairs_.list and pairs_.description and pairs_.moving then
    self.inkPairs = pairs_
  end

  local record = (data.gen4_menus or {}).bag or {}
  self.pockets = record.pockets
  if not self.pockets or #self.pockets == 0 then
    Logger.warn("gen4 bag: this cache carries no pocket names -- "
                .. "falling back to the engine's own")
    self.pockets = { Strings("ITEMS"), Strings("MEDICINE"), "POKé BALLS",
                     "TMs & HMs", Strings("BERRIES"), Strings("MAIL"),
                     Strings("BATTLE ITEMS"), Strings("KEY ITEMS") }
  end

  -- A bag opened AT ONE POCKET has that one pocket accessible, exactly as the
  -- cartridge's berry-planting and Poffin bags do: one icon, one button, no
  -- arrows.  AN EXACT NAME BEATS A CONTAINING ONE, because "ITEMS" is inside
  -- "BATTLE ITEMS" and "KEY ITEMS" too.
  self.pocket = 1
  if opts.pocket then
    local wanted = tostring(opts.pocket):upper()
    local exact, loose
    for i, name in ipairs(self.pockets) do
      local upper = tostring(name):upper()
      if upper == wanted then
        exact = exact or i
      elseif upper:find(wanted, 1, true) then
        loose = loose or i
      end
    end
    self.pocket = exact or loose or 1
    self.lockPocket = true
  end

  -- each pocket's own ListMenu position: { listPos, cursorPos }, 0-based
  self.cursors = {}
  self.listPos, self.cursorPos = 0, 1
  self.index, self.top = 2, 1
  self:rebuild()
  return self
end

function Gen4BagMenu:female()
  local player = (self.game.save or {}).player or {}
  local g = player.gender
  return g == "girl" or g == "female" or g == 1
end

local function loadImage(self, path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- a `gen4_graphics` screen picture
function Gen4BagMenu:img(key)
  local rec = self.art[key]
  return loadImage(self, (type(rec) == "table" and rec.path) or rec)
end

-- a `gen4_bag_art` picture and its record (for the sprite origin)
function Gen4BagMenu:sprite(key)
  local rec = self.bagArt[key]
  if type(rec) ~= "table" then return nil end
  return loadImage(self, rec.path), rec
end

-- draws a `gen4_bag_art` sprite anchored where its template puts it
function Gen4BagMenu:drawSprite(key, x, y)
  local img, rec = self:sprite(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

-- The pockets this bag shows, as indices into `self.pockets`.
function Gen4BagMenu:shownPockets()
  if self.lockPocket then return { self.pocket } end
  local out = {}
  for i = 1, #self.pockets do out[i] = i end
  return out
end

-- The pocket's entries, as `LoadCurrentPocketItemNames` builds them.
function Gen4BagMenu:rebuild()
  local game = self.game
  local want = self.pocket - 1
  local rows = { { header = true } }
  local registered = (game.save or {}).registeredItem
  for _, id in ipairs(Bag.order(game.save) or {}) do
    local def = game.data.items and game.data.items[id]
    local pocket = def and def.fieldPocket or 0
    if pocket == want then
      local numeric = def and tonumber(def.id) or tonumber(id)
      local row = {
        id = id,
        label = (def and def.name) or tostring(id),
        qty = (game.save.inventory or {})[id],
        iconId = numeric,
        description = def and def.description,
        important = def and def.preventToss or nil,
        registered = registered ~= nil and registered == id or nil,
      }
      -- THE TM POCKET LISTS THE MOVE, not "TM01": `LoadTMHMMoveName`.
      local machine = def and def.machine
      if machine and machine.move then
        local move = (game.data.moves or {})[machine.move]
        row.label = (type(move) == "table" and move.name) or row.label
        local n = tonumber(tostring(def.name or ""):match("(%d+)$"))
        row.number, row.hm = n, machine.kind == "HM"
      elseif pocket == POCKET_BERRIES and numeric then
        row.number = numeric - FIRST_BERRY + 1
      end
      rows[#rows + 1] = row
    end
  end
  rows[#rows + 1] = { close = true, label = Strings("CLOSE BAG") }
  rows[#rows + 1] = { header = true }
  self.rows = rows

  -- LimitItemListScroll: a list that shrank keeps its cursor on a real entry
  local count = #rows
  local entries = count - 1
  local shown = (entries > VISIBLE - 1) and (VISIBLE - 2) or (entries - 1)
  if self.listPos ~= 0 and self.listPos + shown > entries - 1 then
    self.listPos = math.max(0, entries - 1 - shown)
  end
  if self.listPos + self.cursorPos >= entries - 1 then
    self.cursorPos = entries - 1 - self.listPos
  end
  if self.cursorPos < 1 and self.listPos == 0 then self.cursorPos = 1 end
  self:syncIndex()
end

function Gen4BagMenu:syncIndex()
  self.index = self.listPos + self.cursorPos + 1
  self.top = self.listPos + 1
end

function Gen4BagMenu:listRows() return math.min(VISIBLE, #self.rows) end

local function isHeader(rows, i) local r = rows[i] return r == nil or r.header end

-- ONE STEP of the cartridge's ListMenu (`UpdateOffsetsForScroll`, repeated
-- while it lands on a header, as `UpdateSelectedRow` does).  Returns whether
-- anything moved.
function Gen4BagMenu:moveCursor(down)
  down = (down == true) or (type(down) == "number" and down > 0)
  local rows, max = self.rows, self:listRows()
  local function step()
    local c, l = self.cursorPos, self.listPos
    if not down then
      local newPos = (max == 1) and 0 or (max - (math.floor(max / 2) + max % 2) - 1)
      if l == 0 then
        while c > 0 do
          c = c - 1
          if not isHeader(rows, l + c + 1) then self.cursorPos = c; return 1 end
        end
        return 0
      end
      while c > newPos do
        c = c - 1
        if not isHeader(rows, l + c + 1) then self.cursorPos = c; return 1 end
      end
      self.listPos, self.cursorPos = l - 1, newPos
      return 2
    else
      local newPos = (max == 1) and 0 or (math.floor(max / 2) + max % 2)
      if l == #rows - max then
        while c < max - 1 do
          c = c + 1
          if not isHeader(rows, l + c + 1) then self.cursorPos = c; return 1 end
        end
        return 0
      end
      while c < newPos do
        c = c + 1
        if not isHeader(rows, l + c + 1) then self.cursorPos = c; return 1 end
      end
      self.listPos, self.cursorPos = l + 1, newPos
      return 2
    end
  end
  local moved = 0
  repeat
    local r = step()
    if r > moved then moved = r end
  until r ~= 2 or not isHeader(rows, self.listPos + self.cursorPos + 1)
  self:syncIndex()
  return moved ~= 0
end

-- Walks the cursor to `self.index` when something set it directly.
function Gen4BagMenu:clampScroll()
  local want = math.max(2, math.min(self.index or 2, #self.rows - 1))
  local guard = 0
  while self.listPos + self.cursorPos + 1 ~= want and guard < 1000 do
    guard = guard + 1
    if not self:moveCursor(want > self.listPos + self.cursorPos + 1) then break end
  end
  self:syncIndex()
end

function Gen4BagMenu:selected() return self.rows[self.index] end

function Gen4BagMenu:close()
  if self.closed then return end
  self.closed = true
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4BagMenu:movePocket(delta)
  if self.lockPocket then return end
  self.cursors[self.pocket] = { self.listPos, self.cursorPos }
  self.pocket = (self.pocket - 1 + delta) % #self.pockets + 1
  local saved = self.cursors[self.pocket] or { 0, 1 }
  self.listPos, self.cursorPos = saved[1], saved[2]
  self:rebuild()
end

-- A on an item.  A bag opened to answer a question (`pick`) hands the item
-- straight back, and the battle's bag uses it; the field bag opens the
-- cartridge's action menu (MakeItemActionsMenu) instead.
function Gen4BagMenu:choose()
  if self.closed then return end
  local row = self:selected()
  if not row or row.close then return self:close() end
  if row.header then return end

  -- A bag opened to ANSWER A QUESTION hands the answer back and closes.
  if self.pick then
    self.game.stack:pop()
    if self.onPick then self.onPick(row.id) end
    return
  end

  if self.battle then return self:useSelected(row.id) end
  self:openActions(row)
end

-- USE (and WALK / CHECK / OPEN / PLANT, which are ItemActionFunc_Use too):
-- what an item does is BagMenu.useItem's, shared with Emerald's bag
function Gen4BagMenu:useSelected(id)
  local shim = {
    items = {}, index = 1,
    close = function() self:close() end,
    refresh = function() self:rebuild() end,
  }
  local ok, err = pcall(function()
    require("src.ui.BagMenu").useItem(self.game, self.battle, id, shim)
  end)
  if not ok then
    Logger.warn("gen4 bag: %s could not be used: %s", tostring(id), tostring(err))
  end
  if not self.closed then self:rebuild() end
end

-- a bag-bank line, its {STRVAR}s filled from `...` (slot 0 first)
function Gen4BagMenu:text(index, fallback, ...)
  local Gen4Text = require("src.import.Gen4Text")
  if select("#", ...) > 0 then Gen4Text.buffer(self.game, ...) end
  local s = Gen4Text.resolve(self.game.data, TEXT_BANK, index, self.game)
  if type(s) ~= "string" or s == "" then return fallback or "" end
  return (s:gsub("[\v\f]", "\n"))
end

-- ----------------------------------------------------- the action menu --

function Gen4BagMenu:pocketType() return self.pocket - 1 end

-- MakeItemActionsMenu, BAG_MODE_NORMAL: CHECK TAG first for a berry; USE (or
-- WALK on the bike, CHECK for mail, OPEN for the Poffin Case, PLANT at an
-- empty patch) when the item has a field function; GIVE and -- outside the
-- TM pocket -- TRASH unless it is too important to part with; REGISTER or
-- DESELECT for a registrable item; CANCEL last.
function Gen4BagMenu:itemActions(id)
  local def = (self.game.data.items or {})[id] or {}
  local numeric = tonumber(def.id) or tonumber(id)
  local pocket = self:pocketType()
  local out = {}
  if pocket == POCKET_BERRIES then out[#out + 1] = "checkTag" end
  if (tonumber(def.fieldUseFunc) or 0) ~= 0 then
    local save = self.game.save or {}
    if numeric == ITEM_BICYCLE and save.onBike then out[#out + 1] = "walk"
    elseif pocket == POCKET_MAIL then out[#out + 1] = "check"
    elseif numeric == ITEM_POFFIN_CASE then out[#out + 1] = "open"
    elseif pocket == POCKET_BERRIES and self.berryPatchEmpty then out[#out + 1] = "plant"
    else out[#out + 1] = "use" end
  end
  if not def.preventToss then
    out[#out + 1] = "give"
    if pocket ~= POCKET_TMHMS then out[#out + 1] = "trash" end
  end
  if def.canRegister or def.registerable then
    local registered = (self.game.save or {}).registeredItem
    out[#out + 1] = (registered ~= nil and registered == id) and "deselect" or "register"
  end
  out[#out + 1] = "cancel"
  return out
end

function Gen4BagMenu:actionLabel(action)
  return self:text(T[action], ACTION_FALLBACK[action] or action)
end

function Gen4BagMenu:openActions(row)
  self.menu = { kind = "actions", rows = self:itemActions(row.id), index = 1, id = row.id,
                name = row.label, qty = row.qty }
end

-- BagUI_ShowItemActionsMenu: a standard window at tile (24, 23 - 2n), 7 wide
-- (23 and 8 in the Berry pocket), its rows 16 apart; Menu_New's text at x 8
-- and the cursor at 0.  It loops round only with four or more rows.
function Gen4BagMenu:actionWindow(n)
  local berries = self:pocketType() == POCKET_BERRIES
  return { tx = berries and 23 or 24, ty = 23 - 2 * n, tw = berries and 8 or 7, th = 2 * n }
end

function Gen4BagMenu:menuStep(delta, byDial)
  local m = self.menu
  local n = #m.rows
  local i = m.index + delta
  if n >= 4 or m.kind == "yesno" then
    -- the action menu loops at four rows; the YES/NO one never does
    if m.kind == "yesno" then i = math.max(1, math.min(n, i)) else i = (i - 1) % n + 1 end
  else
    i = math.max(1, math.min(n, i))
  end
  if i == m.index then return false end
  m.index = i
  -- the pad turns the dial with the cursor; the dial already turned itself
  if not byDial then self:rotateDial(delta < 0 and 18 or -18) end
  return true
end

function Gen4BagMenu:runAction(action)
  local m = self.menu
  self.menu = nil
  local id = m and m.id
  if not id or action == "cancel" then return end
  if action == "give" then
    local ok, err = pcall(function()
      require("src.ui.BagMenu").giveItem(self.game, id, function() if not self.closed then self:rebuild() end end)
    end)
    if not ok then Logger.warn("gen4 bag: give %s: %s", tostring(id), tostring(err)) end
  elseif action == "trash" then
    self:startTrash(m)
  elseif action == "register" then
    self.game.save.registeredItem = id
    self:rebuild()
  elseif action == "deselect" then
    self.game.save.registeredItem = nil
    self:rebuild()
  elseif action == "checkTag" then
    -- BAG_EXIT_CODE_CHECK_BERRY_TAG leaves for the berry's tag, which this
    -- port does not have: its words are the description, shown in the box
    local def = (self.game.data.items or {})[id] or {}
    self:say(def.description or "")
  else
    self:useSelected(id)
  end
end

-- ------------------------------------------------------------ TRASH --

-- ItemActionFunc_Trash: one of an item goes straight to the question;
-- more asks how many first (Throw away how many / x001)
function Gen4BagMenu:startTrash(m)
  local qty = math.max(1, math.floor(tonumber(m.qty) or 1))
  self.trash = { id = m.id, name = m.name, n = 1, max = qty }
  if qty == 1 then self:confirmTrash() else self.trash.stage = "count" end
end

function Gen4BagMenu:trashName()
  local tr = self.trash
  return tostring(tr.name or "")
end

function Gen4BagMenu:confirmTrash()
  local tr = self.trash
  tr.stage = "confirm"
  self.menu = { kind = "yesno", rows = { "yes", "no" }, index = 1 }
end

-- sub_0208C15C: up / down one (wrapping), left / right ten (clamped)
function Gen4BagMenu:trashCount(input)
  local tr = self.trash
  local before = tr.n
  if input:wasPressed("up") then tr.n = tr.n + 1; if tr.n > tr.max then tr.n = 1 end
  elseif input:wasPressed("down") then tr.n = tr.n - 1; if tr.n <= 0 then tr.n = tr.max end
  elseif input:wasPressed("left") then tr.n = math.max(1, tr.n - 10)
  elseif input:wasPressed("right") then tr.n = math.min(tr.max, tr.n + 10) end
  if tr.n ~= before then self:rotateDial(tr.n > before and 18 or -18) end
end

function Gen4BagMenu:resolveTrash(yes)
  local tr = self.trash
  self.menu = nil
  if not yes then self.trash = nil; return end
  local id, n = tr.id, tr.n
  Bag.remove(self.game.save, id, n)
  self.trash = nil
  self:rebuild()
  self:say(self:text(T.threwAway, Strings("Threw away %s.", tr.name), tr.name, tostring(n)))
end

-- a line in the wide message box (2, 19), dismissed by A, B or a tap
function Gen4BagMenu:say(text)
  self.message = tostring(text or "")
end

-- --------------------------------------------------------- moving items --

-- CanMoveSelectedEntry: not CLOSE BAG, only the normal bag, and never in the
-- TM or Berry pocket (they are kept in number order)
function Gen4BagMenu:canMove()
  local row = self:selected()
  if not row or row.close or row.header then return false end
  if self.pick or self.battle then return false end
  local p = self:pocketType()
  return p ~= POCKET_BERRIES and p ~= POCKET_TMHMS
end

function Gen4BagMenu:startMoving()
  local row = self:selected()
  self.moving = { pos = self.index, id = row.id, name = row.label, iconId = row.iconId }
end

-- MoveItemToCurrentPosition + StopMovingItem: Item_MoveInPocket takes the
-- moved item out and puts it in front of the row the bar is over (nothing
-- moves when that is where it already was), and the cursor follows it
function Gen4BagMenu:placeMoving(cancel)
  local mv = self.moving
  self.moving = nil
  if not mv then return end
  local from, to = mv.pos - 1, self.index - 1   -- 1-based item numbers
  if not cancel and not (from == to or from == to - 1) then
    local ids = {}
    for i = 2, #self.rows - 2 do ids[#ids + 1] = self.rows[i].id end
    local src, dst = from - 1, to - 1           -- 0-based slots
    local item = ids[src + 1]
    if dst > src then
      dst = dst - 1
      for i = src, dst - 1 do ids[i + 1] = ids[i + 2] end
    else
      for i = src, dst + 1, -1 do ids[i + 1] = ids[i] end
    end
    ids[dst + 1] = item
    -- the pocket's slots in the bag's one order list, refilled in turn
    local order = Bag.order(self.game.save)
    local inPocket = {}
    for _, id in ipairs(ids) do inPocket[id] = true end
    local k = 0
    for i, id in ipairs(order) do
      if inPocket[id] then k = k + 1; order[i] = ids[k] end
    end
  end
  if mv.pos < self.index then self.cursorPos = self.cursorPos - 1 end
  self:rebuild()
end

-- ---------------------------------------------------------- the dial --

function Gen4BagMenu:rotateDial(degrees)
  self.dialRotation = ((self.dialRotation or 0) + degrees) % 360
end

-- C division and remainder (toward zero)
local function cdiv(a, b) local q = a / b; return q < 0 and math.ceil(q) or math.floor(q) end
local function cmod(a, b) return a - cdiv(a, b) * b end

-- ApproximateArcLength (math_util.c): the step from one touch to the next,
-- projected on the tangent at the first, signed by the turn's direction
local function arcLength(x0, y0, x1, y1)
  local cross = x0 * y1 - y0 * x1
  local len = math.sqrt(y0 * y0 + x0 * x0)
  if len == 0 then return 0 end
  local dot = (y0 * (x1 - x0) + x0 * (y1 - y0)) / len
  local r = math.abs(math.floor(dot))
  return cross <= 0 and -r or r
end
Gen4BagMenu.arcLength = arcLength

-- CalcDialScroll, once a frame: the picture turns with the stylus and every
-- `circumference / stepAngle` pixels of arc queues one step
function Gen4BagMenu:stepDial(stepAngle)
  local d = self.dial
  if not d then return false end
  local p = self.pointer
  local function within(r1, r2)
    if not (p and p.x) then return false end
    local dx, dy = p.x - DIAL.x, p.y - DIAL.y
    local dd = dx * dx + dy * dy
    return dd >= r1 * r1 and dd < r2 * r2
  end
  if not within(DIAL.holdIn, DIAL.holdOut) then
    self.dial = nil
    return true
  end
  local arc = arcLength(DIAL.x - d.prevX, DIAL.y - d.prevY, DIAL.x - p.x, DIAL.y - p.y)
  local circumference = math.floor(2 * DIAL.radius * 3.14)
  local angle = cdiv(arc * 2 * 0xFFFF, circumference)
  self:rotateDial(math.floor(cdiv(angle * 256, 182) / 256))
  local step = cdiv(circumference, stepAngle)
  if arc > 0 then
    if d.queued < 0 then d.queued, d.rem = cdiv(arc, step), cmod(arc, step)
    else d.queued, d.rem = d.queued + cdiv(d.rem + arc, step), cmod(d.rem + arc, step) end
  elseif arc < 0 then
    if d.queued > 0 then d.queued, d.rem = cdiv(arc, step), cmod(arc, step)
    else d.queued, d.rem = d.queued + cdiv(d.rem + arc, step), cmod(d.rem + arc, step) end
  end
  d.prevX, d.prevY = p.x, p.y
  return true
end

-- one queued step a frame, as CheckItemListDialScroll_* / CheckDialScroll_Menu
-- / CheckDialItemAmountChange take them; `step(up)` answers whether it moved
function Gen4BagMenu:drainDial(step)
  local d = self.dial
  if not d or d.queued == 0 then return false end
  local up = d.queued > 0
  if step(up) then d.queued = d.queued + (up and -1 or 1) else d.queued = 0 end
  return true
end

-- ------------------------------------------------- the touch buttons --

function Gen4BagMenu:bottomShown()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  local mode = SS.mode(self.game)
  return (mode == "display" or mode == "inset") and not SS.stowed(self.game), SS
end

function Gen4BagMenu:bottomPoint(px, py)
  local shown, SS = self:bottomShown()
  if not shown then return nil end
  return SS.toLocal(self.game, px, py)
end

local function inRect(r, x, y) return y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] end

-- CheckPlayerPressedPocketButton: none at all in a one-pocket bag
function Gen4BagMenu:pocketButtonAt(x, y)
  local shown = self:shownPockets()
  local rects = #shown ~= 1 and BUTTON_RECTS[#shown]
  if not rects then return nil end
  for i, r in ipairs(rects) do if inRect(r, x, y) then return i end end
  return nil
end

function Gen4BagMenu:dialButtonAt(x, y)
  local b = DIAL.button
  return x >= DIAL.x - b and x <= DIAL.x + b - 1 and y >= DIAL.y - b and y <= DIAL.y + b - 1
end

function Gen4BagMenu:shockwave(x, y) self.shock = { x = x, y = y, t = 0 } end

-- BagUI_DrawBtnShockwave on the dial, the button pressed (StepDialButton-
-- PressedAnim), and the press itself, which every list and menu takes as A
function Gen4BagMenu:pressDial()
  self.dialPress = { t = 0 }
  self:shockwave(DIAL.x, DIAL.y)
end

-- CheckPocketChange_Touch: the pocket changes, and the button it was runs
-- StepPocketSwitchPressedButtonAnim; once it is done and the stylus is off
-- it, it stays lit
function Gen4BagMenu:pressPocket(i)
  local shown = self:shownPockets()
  local p = shown[i]
  if not p then return end
  self.pocketLit = nil
  self.pocketPress = { i = i, t = 0 }
  if p ~= self.pocket then
    self.cursors[self.pocket] = { self.listPos, self.cursorPos }
    self.pocket = p
    local saved = self.cursors[self.pocket] or { 0, 1 }
    self.listPos, self.cursorPos = saved[1], saved[2]
    self:rebuild()
  end
end

function Gen4BagMenu:stepTouchAnims()
  local pp = self.pocketPress
  if pp then
    pp.t = pp.t + 1
    if pp.t == POCKET_PRESS_AT then
      local at = (BUTTONS[#self:shownPockets()] or {})[pp.i]
      if at then self:shockwave(at[1] * 8 + 20, at[2] * 8 + 20) end
    end
    local held = self.pointer and self.pointer.x and self:pocketButtonAt(self.pointer.x, self.pointer.y)
    if pp.t >= POCKET_PRESS_DONE and held ~= pp.i then
      self.pocketLit = pp.i
      self.pocketPress = nil
    end
  end
  local dp = self.dialPress
  if dp then
    dp.t = dp.t + 1
    if dp.t > 6 then self.dialPress = nil end
  end
  local sw = self.shock
  if sw then
    sw.t = sw.t + 1
    if sw.t >= SHOCKWAVE_FRAMES[1] + SHOCKWAVE_FRAMES[2] then self.shock = nil end
  end
end

function Gen4BagMenu:pocketButtonFace(i)
  local pp = self.pocketPress
  if pp and pp.i == i and pp.t >= POCKET_PRESS_AT then return 2 end
  if self.pocketLit == i then return 1 end
  return 0
end

function Gen4BagMenu:dialButtonFace()
  local dp = self.dialPress
  if not dp then return 0 end
  if dp.t <= 3 then return 2 end
  return 1
end

function Gen4BagMenu:touchpressed(id, px, py)
  local x, y = self:bottomPoint(px, py)
  if not x then
    -- a panel tap is never a top-screen one; anything else is the d-pad's
    return self.game.secondScreenInjecting and true or false
  end
  self.pointer = { id = id, x = x, y = y }
  self.touchPressed = true
  if self.message then return true end
  -- the dial's button first: it is A
  if self:dialButtonAt(x, y) then
    self:pressDial()
    self.dialA = true
    return true
  end
  -- a turn of the dial starts in its ring
  local dx, dy = x - DIAL.x, y - DIAL.y
  local dd = dx * dx + dy * dy
  if dd >= DIAL.startIn * DIAL.startIn and dd < DIAL.startOut * DIAL.startOut then
    self.dial = { prevX = x, prevY = y, queued = 0, rem = 0 }
    return true
  end
  -- the pocket buttons only while the list itself is up
  if not (self.menu or self.trash or self.moving) then
    local i = self:pocketButtonAt(x, y)
    if i then self:pressPocket(i) end
  end
  return true
end

function Gen4BagMenu:touchmoved(id, px, py)
  if not (self.pointer and self.pointer.id == id) then return false end
  self.pointer.x, self.pointer.y = self:bottomPoint(px, py)
  return true
end

function Gen4BagMenu:touchreleased(id)
  if not (self.pointer and self.pointer.id == id) then return false end
  self.pointer = nil
  return true
end

-- ------------------------------------------------------------- update --

function Gen4BagMenu:update()
  self:stepTouchAnims()
  local input = self.game.input
  local tapped, dialA = self.touchPressed, self.dialA
  self.touchPressed, self.dialA = nil, nil
  if not input then return end
  local a = input:wasPressed("a") or dialA

  -- a message in the wide box: A, B or a tap puts it away
  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") or tapped then self.message = nil end
    return
  end

  -- the YES / NO of a trash, and the action menu
  if self.menu then
    local stepAngle = 18
    if self:stepDial(stepAngle) then
      self:drainDial(function(up) return self:menuStep(up and -1 or 1, true) end)
      return
    end
    local m = self.menu
    if input:wasPressed("up") then self:menuStep(-1)
    elseif input:wasPressed("down") then self:menuStep(1)
    elseif a then
      if m.kind == "yesno" then self:resolveTrash(m.index == 1)
      else self:runAction(m.rows[m.index]) end
    elseif input:wasPressed("b") then
      if m.kind == "yesno" then self:resolveTrash(false) else self.menu = nil end
    end
    return
  end

  -- how many to throw away
  if self.trash and self.trash.stage == "count" then
    if self:stepDial(18) then
      self:drainDial(function(up)
        local tr = self.trash
        if up then tr.n = tr.n + 1; if tr.n > tr.max then tr.n = 1 end
        else tr.n = tr.n - 1; if tr.n <= 0 then tr.n = tr.max end end
        return true
      end)
      return
    end
    if a then self:confirmTrash()
    elseif input:wasPressed("b") then self.trash = nil
    else self:trashCount(input) end
    return
  end

  -- an item on the move: the bar follows the cursor; A, SELECT or the dial
  -- put it down, B puts it back (A on CLOSE BAG moves it to the end)
  if self.moving then
    if self:stepDial(36) then
      self:drainDial(function(up) return self:moveCursor(not up) end)
      return
    end
    if input:wasPressed("up") then
      if self:moveCursor(false) then self:rotateDial(36) end
    elseif input:wasPressed("down") then
      if self:moveCursor(true) then self:rotateDial(-36) end
    elseif a or input:wasPressed("select") then self:placeMoving(false)
    elseif input:wasPressed("b") then self:placeMoving(true) end
    return
  end

  if self:stepDial(36) then
    self:drainDial(function(up) return self:moveCursor(not up) end)
    return
  end
  if input:wasPressed("select") and self:canMove() then
    self:startMoving()
  elseif input:wasPressed("up") then
    if self:moveCursor(false) then self:rotateDial(36) end
  elseif input:wasPressed("down") then
    if self:moveCursor(true) then self:rotateDial(-36) end
  elseif input:wasPressed("left") then
    self.pocketLit = nil
    self:movePocket(-1)
  elseif input:wasPressed("right") then
    self.pocketLit = nil
    self:movePocket(1)
  elseif a then
    self:choose()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

-- `CalcPocketSelectorIconsPos`: the strip re-spreads over the same ninety
-- pixels whatever the pocket count --
--     iconsX = 6 + (90 - 10 * n) / (n + 1),  spacing = 10 + iconsX - 6
function Gen4BagMenu:iconRow()
  local n = #self:shownPockets()
  local x = 6 + math.floor((90 - ICON_BLIT * n) / (n + 1))
  return x, ICON_BLIT + x - 6
end

function Gen4BagMenu:drawPocketIcons()
  local g = love.graphics
  local sheet = self:img("bag/pocket_selector_icons")
  local shown = self:shownPockets()
  local x0, pitch = self:iconRow()
  if sheet then
    local sw, sh = sheet:getDimensions()
    if sh ~= ICON_CELL or sw < ICON_STRIDE * #self.pockets then
      if not self.warnedIcons then
        self.warnedIcons = true
        Logger.warn("gen4 bag: pocket_selector_icons is %dx%d, not %dx%d -- the bag archive needs re-importing", sw, sh,
                    ICON_STRIDE * #self.pockets, ICON_CELL)
      end
    else
      g.setColor(1, 1, 1, 1)
      for i, p in ipairs(shown) do
        local sx = (p - 1) * ICON_STRIDE + (p == self.pocket and ICON_CELL or 0)
        local quad = g.newQuad(sx, 0, ICON_BLIT, ICON_BLIT, sw, sh)
        g.draw(sheet, quad, x0 + pitch * (i - 1), INDICATOR_Y + ICON_INSET)
      end
    end
  end
  return shown, x0, pitch
end

-- "No." and a zero-padded two-digit number, or an HM's tag and number, from
-- the bag's own special-character sheet.
function Gen4BagMenu:drawNumber(row, x, y)
  local sheet = self:sprite("special_chars")
  if not (sheet and row.number) then return end
  local g = love.graphics
  local sw, sh = sheet:getDimensions()
  local digits = ("%02d"):format(row.number % 100)
  local dx = x
  if row.hm then
    local tags = self:sprite("entry_icons")
    if tags then
      local tw, th = tags:getDimensions()
      g.draw(tags, g.newQuad(40, 0, 24, 16, tw, th), x, y)
    end
    dx = x + 16
    -- PADDING_MODE_SPACES: an HM number under ten has a blank first digit
    if row.number < 10 then digits = " " .. tostring(row.number) end
  else
    g.draw(sheet, g.newQuad(SPECIAL_NUMBER_AT, 0, 16, 8, sw, sh), x, y + 5)
    dx = x + 16
  end
  for k = 1, #digits do
    local d = tonumber(digits:sub(k, k))
    if d then
      g.draw(sheet, g.newQuad(d * SPECIAL_DIGIT_W, 0, SPECIAL_DIGIT_W, 8, sw, sh),
             dx + (k - 1) * SPECIAL_DIGIT_W, y + 5)
    end
  end
end

function Gen4BagMenu:drawList()
  local g = love.graphics
  local pocketType = self.pocket - 1
  local numbered = pocketType == POCKET_TMHMS or pocketType == POCKET_BERRIES
  local movedId = self.moving and self.moving.id
  for slot = 0, self:listRows() - 1 do
    local row = self.rows[self.listPos + slot + 1]
    local y = LIST.y + slot * LINE
    -- ItemListMenuPrintCB: the row being moved prints in TEXT_COLOR(8, 9, 0)
    self:ink((movedId ~= nil and row and row.id == movedId) and "moving" or "list")
    if row and not row.header then
      if row.close then
        Font.draw(row.label, LIST.x, y)
      else
        g.setColor(1, 1, 1, 1)
        if numbered then self:drawNumber(row, LIST.x, y) end
        Font.draw(row.label, LIST.x + (numbered and NUMBERED_TEXT_X or 0), y)
        if row.qty and not row.hm then
          local x = LIST.x + COUNT_X + (pocketType == POCKET_TMHMS and 6 or 0)
          Font.draw("x", x, y)
          local n = tostring(math.min(999, math.floor(row.qty)))
          Font.draw(n, LIST.x + COUNT_RIGHT - Font.width(n), y)
        end
        if pocketType == POCKET_KEY_ITEMS and row.registered then
          local tags = self:sprite("entry_icons")
          if tags then
            local tw, th = tags:getDimensions()
            g.setColor(1, 1, 1, 1)
            g.draw(tags, g.newQuad(0, 0, 40, 16, tw, th), LIST.x + REGISTERED_X, y)
          end
        end
      end
    end
    Font.popStyle()
  end
end

function Gen4BagMenu:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  -- MAIN_3 and MAIN_2
  local panel = self:img("bag/item_list_border")
  if panel then g.draw(panel, 0, 0) end
  local name = tostring(self.pockets[self.pocket] or "")
  self:ink("list")
  Font.draw(name, math.floor(NAME_CENTER_X - Font.width(name) / 2), NAME_Y)
  Font.popStyle()
  self:drawList()

  -- MAIN_1
  local back = self:img("bag/bag_ui_main")
  if back then
    g.setColor(1, 1, 1, 1)
    g.draw(back, 0, 0)
  elseif not panel then
    Font.drawBox(0, 0, 32, 24)
  end

  -- The TM pocket's action menu hides the item box (ToggleHideItemSprite):
  -- sHiddenItemSpriteBoxTiles puts tile 0x26 down column 0 and 0x02 in the
  -- rest of the 5 x 5 at (0, 18) -- tiles that sit at (5, 18) and (5, 19)
  local tmMenu = self.menu and self.menu.kind == "actions" and self:pocketType() == POCKET_TMHMS
  if back and tmMenu then
    local bw, bh = back:getDimensions()
    local edge, blank = g.newQuad(40, 144, 8, 8, bw, bh), g.newQuad(40, 152, 8, 8, bw, bh)
    for ty = 18, 22 do
      g.draw(back, edge, 0, ty * 8)
      for tx = 1, 4 do g.draw(back, blank, tx * 8, ty * 8) end
    end
  end

  -- BagUI_SetHighlightSpritesPalette: 1 (red) while choosing, 2 (grey) while
  -- the action menu, a count or a message has the bag
  local busy = self.menu or self.trash or self.message
  local hl = busy and 1 or 0

  -- OBJ at priority 1: the bag, the item highlight (or, moving, the bar),
  -- the item's icon
  local gender = self:female() and "female" or "male"
  if not self:drawSprite(("bag_%s_%d"):format(gender, self.pocket - 1), BAG_AT[1], BAG_AT[2]) then
    local bag = self:img(("bag/bag_sprite_%s_%02d"):format(gender, self.pocket - 1))
    if bag then g.draw(bag, BAG_AT[1] - bag:getWidth() / 2, BAG_AT[2] - bag:getHeight() / 2) end
  end
  if self.moving then
    -- BAG_SPRITE_MOVING_ITEM_POS_BAR: eight above the row, between it and the
    -- one before -- where the item will go
    self:drawSprite("moving_bar", HIGHLIGHT_AT[1], 16 + LINE * (self.cursorPos - 1))
  else
    local hy = HIGHLIGHT_AT[2] + LINE * (self.cursorPos - 1)
    if not (self:drawSprite("item_highlight_" .. hl, HIGHLIGHT_AT[1], hy)
            or self:drawSprite("item_highlight_0", HIGHLIGHT_AT[1], hy)) then
      Font.drawCode(Theme.cursor, LIST.x - 8, LIST.y + self.cursorPos * LINE)
    end
  end
  -- ItemListMenuCursorCB does nothing while an item is moving: its own icon
  -- and words stay up
  local row = self:selected()
  local iconId = self.moving and self.moving.iconId or (row and row.iconId)
  if tmMenu then
    -- hidden with its box
  elseif row and row.close and not self.moving then
    self:drawSprite("item_return", ITEM_AT[1], ITEM_AT[2])
  elseif iconId then
    local icon = self:img(("items/icon_%03d"):format(iconId))
    if icon then
      g.setColor(1, 1, 1, 1)
      g.draw(icon, ITEM_AT[1] - icon:getWidth() / 2, ITEM_AT[2] - icon:getHeight() / 2)
    end
  end

  -- MAIN_0: the pocket strip and the description
  local shown, x0, pitch = self:drawPocketIcons()
  if tmMenu then
    self:drawTMStats(self.menu.id)
  elseif not busy then
    local text
    if self.moving then
      text = self:text(T.moveWhere, Strings("Move the %s where?", self.moving.name), self.moving.name)
    else
      text = (row and row.close) and Strings("Close Bag") or (row and row.description) or ""
    end
    local y = DESCRIPTION.y
    self:ink("description")
    for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
      if y > H - 8 then break end
      Font.draw(line, DESCRIPTION.x, y)
      y = y + LINE
    end
    Font.popStyle()
  end

  -- OBJ at priority 0: the pocket highlight and the arrows (hidden while an
  -- item moves -- SwitchSpritesForSorting)
  for i, p in ipairs(shown) do
    if p == self.pocket then
      if not self:drawSprite("pocket_highlight_" .. hl, x0 + pitch * (i - 1) + 6, POCKET_HIGHLIGHT_Y) then
        self:drawSprite("pocket_highlight_0", x0 + pitch * (i - 1) + 6, POCKET_HIGHLIGHT_Y)
      end
    end
  end
  if #shown > 1 and not self.moving then
    self:drawSprite("arrow_left", ARROW_LEFT_AT[1], ARROW_LEFT_AT[2])
    self:drawSprite("arrow_right", ARROW_RIGHT_AT[1], ARROW_RIGHT_AT[2])
  end

  self:drawWindows()
  self:drawSubscreen()
  g.setColor(1, 1, 1, 1)
end

-- the standard window frame around a window's tile rectangle
local function frame(win)
  Font.drawBox(win.tx - 1, win.ty - 1, win.tw + 2, win.th + 2)
end

-- the message box frame (Window_DrawMessageBoxWithScrollCursor) around a
-- window, and its lines in FONT_MESSAGE, sixteen apart
local function messageBox(tx, ty, tw, th, text)
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then
    Font.drawDialogueBox(tx - 1, ty - 1, tw + 2, th + 2)
  else
    Font.drawBox(tx - 1, ty - 1, tw + 2, th + 2)
  end
  local y = ty * 8
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    if y < (ty + th) * 8 then Font.draw(Font.fit and Font.fit(line, tw * 8) or line, tx * 8, y) end
    y = y + LINE
  end
end

-- BAG_UI_WINDOW_MSG_BOX (6, 19) 14 x 4, narrow 13 in the Berry pocket, and
-- BAG_UI_WINDOW_MSG_BOX_WIDE (2, 19) 27 x 4
local MSG_BOX, MSG_BOX_WIDE = { tx = 6, ty = 19, tw = 14, th = 4 }, { tx = 2, ty = 19, tw = 27, th = 4 }
-- BAG_UI_WINDOW_THROW_AWAY_COUNT (24, 19) 7 x 4, and sYesNoMenuTemplate (23, 13) 7 x 4
local TRASH_COUNT, YES_NO = { tx = 24, ty = 19, tw = 7, th = 4 }, { tx = 23, ty = 13, tw = 7, th = 4 }
Gen4BagMenu.WINDOWS = { msg = MSG_BOX, wide = MSG_BOX_WIDE, trashCount = TRASH_COUNT, yesNo = YES_NO }

-- a Menu: rows sixteen apart, the words at x 8 (Menu_New's xOffset) and the
-- coloured arrow at 0
function Gen4BagMenu:drawMenuRows(win, labels, index)
  self:ink("list")
  for i, label in ipairs(labels) do
    local y = win.ty * 8 + (i - 1) * LINE
    Font.draw(label, win.tx * 8 + 8, y)
    if i == index then Font.drawCode(Theme.cursor, win.tx * 8, y) end
  end
  Font.popStyle()
end

function Gen4BagMenu:drawWindows()
  local m, tr = self.menu, self.trash
  if m and m.kind == "actions" then
    if self:pocketType() ~= POCKET_TMHMS then
      local box = self:pocketType() == POCKET_BERRIES and { tx = 6, ty = 19, tw = 13, th = 4 } or MSG_BOX
      messageBox(box.tx, box.ty, box.tw, box.th,
        self:text(T.isSelected, Strings("%s is\nselected.", m.name), m.name))
    end
    local win = self:actionWindow(#m.rows)
    frame(win)
    local labels = {}
    for i, a in ipairs(m.rows) do labels[i] = self:actionLabel(a) end
    self:drawMenuRows(win, labels, m.index)
  end
  if tr and tr.stage == "count" then
    messageBox(MSG_BOX.tx, MSG_BOX.ty, MSG_BOX.tw, MSG_BOX.th,
      self:text(T.throwHowMany, Strings("Throw away how many\n%s(s)?", tr.name), tr.name))
    frame(TRASH_COUNT)
    self:ink("list")
    Font.draw(self:text(T.throwCount, ("x%03d"):format(tr.n), ("%03d"):format(tr.n)),
              TRASH_COUNT.tx * 8 + 16, TRASH_COUNT.ty * 8 + 8)
    Font.popStyle()
    -- BAG_SPRITE_ITEM_COUNT_ARROW_UP / DOWN: the shop's scroll arrows
    local shop = self.game.data.gen4_shop_art or {}
    for _, a in ipairs({ { "scroll_up", 220, 156 }, { "scroll_down", 220, 180 } }) do
      local rec = shop[a[1]]
      local img = type(rec) == "table" and loadImage(self, rec.path)
      if img then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, a[2] + (rec.originX or 0), a[3] + (rec.originY or 0))
      end
    end
  elseif tr and tr.stage == "confirm" then
    messageBox(MSG_BOX_WIDE.tx, MSG_BOX_WIDE.ty, MSG_BOX_WIDE.tw, MSG_BOX_WIDE.th,
      self:text(T.throwOk, Strings("Is it OK to throw away\n%d %s?", tr.n, tr.name), tr.name, tostring(tr.n)))
  end
  if m and m.kind == "yesno" then
    frame(YES_NO)
    self:drawMenuRows(YES_NO, { self:text(T.yes, "Yes"), self:text(T.no, "No") }, m.index)
  end
  if self.message then
    messageBox(MSG_BOX_WIDE.tx, MSG_BOX_WIDE.ty, MSG_BOX_WIDE.tw, MSG_BOX_WIDE.th, self.message)
  end
end

-- BagUI_PrintTMHMMoveStats in the description window (0, 18), and the move's
-- type and category icons at (64, 152) and (168, 152) -- the summary's own
-- type sheet, which is the same pl_batt_obj art in the same palette rows
function Gen4BagMenu:drawTMStats(id)
  local def = (self.game.data.items or {})[id] or {}
  local machine = def.machine
  local move = machine and machine.move and (self.game.data.moves or {})[machine.move]
  if type(move) ~= "table" then return end
  local y0 = DESCRIPTION.y
  self:ink("description")
  Font.draw(self:text(T.type, "TYPE"), 0, y0)
  Font.draw(self:text(T.pp, "PP"), 0, y0 + 16)
  Font.draw(self:text(T.category, "CATEGORY"), 96, y0)
  Font.draw(self:text(T.power, "POWER"), 96, y0 + 16)
  Font.draw(self:text(T.accuracy, "ACCURACY"), 96, y0 + 32)
  -- MoveTable_CalcMaxPP(move, 0), two digits padded with spaces
  local pp = tostring(math.floor(tonumber(move.pp) or 0))
  Font.draw(pp, 48 + (2 - #pp) * 6, y0 + 16)
  local na = self:text(T.notApplicable, "---")
  local power, accuracy = tonumber(move.power) or 0, tonumber(move.accuracy) or 0
  Font.draw(power <= 1 and na or tostring(power), 160, y0 + 16)
  Font.draw(accuracy == 0 and na or tostring(accuracy), 160, y0 + 32)
  Font.popStyle()
  local art = self.game.data.gen4_summary_art or {}
  local function icon(key, x, y)
    local rec = art[key]
    local img = type(rec) == "table" and loadImage(self, rec.path)
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
    end
  end
  local typeName = tostring(move.type or ""):lower()
  local alias = { electr = "electric", fight = "fighting", psychc = "psychic" }
  icon("type_" .. (alias[typeName] or typeName), 64, 152)
  icon("category_" .. tostring(move.class or move.category or ""):lower(), 168, 152)
end

-- The touch screen: the dial (turned by RotateDial / the stylus) under its
-- border, the pocket buttons and the dial's button in their faces, and the
-- shockwave a press leaves (`DrawTouchScreenButtons`, BagUI_DrawBtnShockwave)
function Gen4BagMenu:drawSubscreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return end
  local mode = SS.mode(self.game)
  if not ((mode == "display" or mode == "inset") and not SS.stowed(self.game)) then return end
  local borders = self:sprite("sub_borders")
  if not borders then return end
  local shown = self:shownPockets()
  SS.draw(self.game, function()
    local g = love.graphics
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
    local dial = self:sprite("sub_dial")
    if dial then
      -- SUB_3 is affine about DIAL_CENTER; a positive rotation turns it
      -- clockwise on the screen
      g.draw(dial, DIAL.x, DIAL.y, math.rad(self.dialRotation or 0), 1, 1, DIAL.x, DIAL.y)
    end
    g.draw(borders, 0, 0)
    -- a one-pocket bag draws no pocket buttons at all (`numPockets != 1`)
    local at = #shown ~= 1 and BUTTONS[#shown]
    if at then
      for i, p in ipairs(shown) do
        local tile = at[i]
        if tile then
          local face = self:pocketButtonFace(i)
          if not self:drawSprite(("pocket_button_%d_%d"):format(p - 1, face), tile[1] * 8, tile[2] * 8) then
            self:drawSprite(("pocket_button_%d_0"):format(p - 1), tile[1] * 8, tile[2] * 8)
          end
        end
      end
    end
    if not self:drawSprite("dial_button_" .. self:dialButtonFace(), DIAL_BUTTON_AT[1], DIAL_BUTTON_AT[2]) then
      self:drawSprite("dial_button_0", DIAL_BUTTON_AT[1], DIAL_BUTTON_AT[2])
    end
    local sw = self.shock
    if sw then
      local f = sw.t < SHOCKWAVE_FRAMES[1] and 0 or 1
      self:drawSprite("shockwave_" .. f, sw.x, sw.y)
    end
  end)
end

return Gen4BagMenu
