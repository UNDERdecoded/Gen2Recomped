-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's KEYBOARD, which was falling back to the Game Boy's.
--
-- Reported from play: "the keyboard where you type your name or your pokemons
-- nickname is also not correct for gen4 platinum its falling back to gen1".
-- It was: nothing in GEN4_ALIASES named `NamingScreen`, so every prompt --
-- the player's name, the rival's, a nickname, a box -- opened Kanto's.
--
-- THE GRID IS THE CARTRIDGE'S, read out of applications/naming_screen.c
-- rather than eyeballed: SIX ROWS OF THIRTEEN, where row 0 is the HOME ROW of
-- buttons and rows 1 to 5 are the characters.  `NamingScreen_LoadKeyboardLayout`
-- builds exactly that -- `sHomeRowLayouts[page]` into row 0 and
-- `sCharCodes[page][0..4]` into the rest -- and the three English pages are
-- UPPER, lower and OTHERS.
--
-- THE HOME ROW REPEATS ITS BUTTONS ACROSS CELLS, and that is not padding: it
-- is how a button two or three cells wide is navigated with a d-pad.  UPPER
-- takes cells 1-2, lower 3-4, OTHERS 5-6, the space/skip key 7-8, BACK 9-11
-- and OK 12-13.  Kept as the cartridge writes it, so the cursor moves through
-- them the way it does on hardware.
--
-- THE PICTURES ARE THE CARTRIDGE'S NOW, and so is the geometry.  Reported from
-- play after the first version of this screen: it "still needs a lot of work
-- before it matches the platinum rom".  It did, and the reason was that
-- `/data/namein.narc` had never been opened -- so the layout was Platinum's and
-- everything a player looks at was a guess.  `Gen4Naming` reads it now, and
-- with it the screen stops guessing:
--
--   * THE BACKDROP AND THE PANEL are composed pictures, one panel per page.
--   * THE PANEL SITS WHERE THE APP PARKS IT.  Its layer rests at background
--     offset (-11, -80), and an offset scrolls the VIEW, so the picture is at
--     screen (11, 80).
--   * THE CHARACTER GRID IS THIRTEEN BY FIVE, not thirteen by six, in cells
--     SIXTEEN BY NINETEEN, not sixteen square.  `Window_Add(..., 2, 1, 26, 12,
--     ...)` is the rectangle and `NamingScreen_InitializeCharsGraphics` is the
--     pitch: five `PrintChars` calls at `i * 19 + 4`.  The home row is not in
--     that window at all -- it is sprites, above the panel.
--   * THE KEYBOARD IS A CHECKERBOARD, painted by code in two palette indices
--     per page rather than stored in the tilemap, which is why opening the
--     archive alone would still have left a frame with nothing in it.
--
--   * THE HOME ROW, THE CURSOR AND THE ENTRY ARE THE SPRITE BANK (members
--     1/10/12/14, Gen4Naming.images, cache `gen4_naming_art`): the overlay
--     frame with its SELECT / B BUTTON / START hints, the UPPER / lower /
--     Others tabs (the page's bright), BACK and OK with their pressed frames
--     -- every label baked into the art -- the glowing cursor, the
--     underscores, the header icon and a Pokemon's gender mark. Children of
--     the overlay at x 22, so they wiggle with it when a page lands.
--   * THE HOME ROW HAS NO SPACE KEY: columns 7-8 are NMS_CONTROL_SKIP and the
--     cursor never stops there.
--
-- The prompt is the BOTTOM screen's message box; with no second screen it
-- sits in the top strip beside the icon.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Gen4Naming = require("src.import.Gen4Naming")

local Gen4NamingScreen = {}
Gen4NamingScreen.__index = Gen4NamingScreen
Gen4NamingScreen.isOpaque = true

local W, H = 256, 192

Gen4NamingScreen.ROWS = 6
Gen4NamingScreen.COLS = 13

-- The home row, cell for cell.  A repeated name is one button spanning those
-- cells; the drawing merges them and the cursor does not.
local HOME = {
  "upper", "upper", "lower", "lower", "others", "others",
  "skip", "skip", "back", "back", "back", "ok", "ok",
}

-- The three English pages, five rows of thirteen each.  `sCharCodesUpper0..4`
-- and their lower and OTHERS counterparts, with the cartridge's CHAR_SPACE
-- written as an empty cell -- a blank key is a real key on this keyboard and
-- pressing it types nothing, which is what the cartridge does with it.
local PAGES = {
  {
    id = "upper", label = "UPPER",
    rows = {
      { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "", ",", "." },
      { "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "", "'", "-" },
      { "U", "V", "W", "X", "Y", "Z", "", "", "", "", "", "♂", "♀" },
      { "", "", "", "", "", "", "", "", "", "", "", "", "" },
      { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "", "" },
    },
  },
  {
    id = "lower", label = "lower",
    rows = {
      { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "", ",", "." },
      { "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "", "'", "-" },
      { "u", "v", "w", "x", "y", "z", "", "", "", "", "", "♂", "♀" },
      { "", "", "", "", "", "", "", "", "", "", "", "", "" },
      { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "", "" },
    },
  },
  {
    id = "others", label = "OTHERS",
    rows = {
      { ",", ".", ":", ";", "!", "?", "", "", "", "♂", "♀", "", "" },
      { "\"", "\"", "'", "'", "(", ")", "", "", "", "", "", "", "" },
      { "…", "·", "~", "@", "#", "%", "+", "-", "*", "/", "=", "", "" },
      { "◎", "○", "□", "△", "◇", "♠", "♥", "♦", "♣", "★", "♪", "", "" },
      { "☀", "☁", "☂", "☃", "☺", "☻", "☹", "☻", "Ｚ", "↑", "↓", "", "" },
    },
  },
}

-- WHERE EVERYTHING SITS, and every number is the cartridge's.
--
-- The previous version of this file put the grid at (24, 64) on sixteen-square
-- cells and said so in a comment about multiples of eight.  The multiples of
-- eight were a real fix -- `Font.drawBox` takes TILES and `Font.draw` takes
-- PIXELS, and a layout that is not a whole number of tiles puts every box a
-- fraction of a tile from the text inside it, which is what "text is outside of
-- boxes" was.  But it was a fix to a layout that was invented.  This one is
-- read, and it is not all multiples of eight, because the cartridge's is not:
-- the rows are NINETEEN pixels.  The boxes are gone with the guess, so nothing
-- rounds any more.
local PANEL_X, PANEL_Y = 11, 80
local GRID_X, GRID_Y = PANEL_X + 2 * 8, PANEL_Y + 1 * 8   -- 27, 88
local CELL_W, CELL_H = 16, 19
local CHAR_ROWS = 5
local GLYPH_INSET = 4

-- The home row, at the y its sprites use and on the keyboard's own column
-- pitch from the x its first sprite uses.  See Gen4Naming for why those two
-- numbers are the whole arrangement.
local HOME_X, HOME_Y, HOME_H = 4, 0x44, 16

-- THE PROMPT AND THE TYPED NAME ARE ON THE OTHER SCREEN on hardware: the
-- keyboard is the top screen and `LoadMessageBoxGraphics` puts the message box
-- on BG_LAYER_SUB_0.  With one screen they go above the keyboard, in the space
-- the panel does not use, and those two positions are this port's and are the
-- only positions on this screen that are.
local TITLE_Y = 8
local ENTRY_Y = 32

-- The checkerboard, when the cache has no colours for it.  Deliberately drab:
-- a stand-in that looks like a choice is a stand-in nobody replaces.
local FALLBACK_BG = { 0.24, 0.27, 0.36 }
local FALLBACK_ALT = { 0.19, 0.22, 0.30 }

function Gen4NamingScreen:uiSize() return W, H end
function Gen4NamingScreen:wantsFillScale() return true end
function Gen4NamingScreen:wantsEdgeBleed() return false end

function Gen4NamingScreen:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4NamingScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4NamingScreen)
  self.game = game
  -- The same options the Game Boy screen takes, because the alias has to serve
  -- every existing call site unchanged.
  self.title = opts.title or Strings("YOUR NAME?")
  self.maxLen = opts.maxLen or 7
  self.onDone = opts.onDone
  self.presets = opts.presets
  self.choice = self.presets and #self.presets > 0 and 1 or nil
  self.kind = opts.kind
  self.female = opts.female
  self.mon = opts.mon
  self.species = opts.species or (opts.mon and opts.mon.species)

  self.glyphs = {}
  for ch in tostring(opts.default or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #self.glyphs < self.maxLen then self.glyphs[#self.glyphs + 1] = ch end
  end

  self.page = 1
  -- 1 is the home row; 2..6 are the characters. The cursor starts hidden on
  -- the first key, (0, 1) in the app's terms (ns.c 2584-2587).
  self.row, self.col = 2, 1

  self.art = (game.data or {}).gen4_naming or nil
  self.sprites = (game.data or {}).gen4_naming_art or nil
  self.ink = (game.data or {}).gen4_naming_ink or nil
  self.glow, self.ticks, self.cursorTick = 180, 0, 0
  self.cache = {}
  if not self.art then
    Logger.warn("gen4 naming screen: this cache carries no `gen4_naming` "
                .. "record -- the keyboard is drawn in the engine's own frame")
  end
  return self
end

-- One of the cache's pictures.  The record is `{ path, width, height, ... }`.
function Gen4NamingScreen:img(entry)
  local path = (type(entry) == "table" and entry.path) or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- The two colours this page's checkerboard is painted in.  `bgColour` and
-- `altColour` are INDICES into the window's palette row and `colours` is that
-- row, so a cache with the pictures but no palette still gets a keyboard --
-- in the fallback colours, which is visibly a fallback.
function Gen4NamingScreen:checkerColours()
  local art = self.art or {}
  local list = art.colours
  local function colour(indices, fallback)
    local index = indices and indices[self.page]
    local rgb = index and list and list[index + 1]
    if type(rgb) == "table" and rgb[1] then return rgb end
    return fallback
  end
  return colour(art.bgColour, FALLBACK_BG), colour(art.altColour, FALLBACK_ALT)
end

-- What is in a cell, as { kind = "button"|"char", value = ... }.
function Gen4NamingScreen:cell(row, col)
  if row == 1 then
    local id = HOME[col]
    return id and { kind = "button", value = id } or nil
  end
  local page = PAGES[self.page]
  local line = page and page.rows[row - 1]
  local ch = line and line[col]
  if ch == nil then return nil end
  return { kind = "char", value = ch }
end

function Gen4NamingScreen:close(name)
  self.game.stack:pop()
  if self.onDone then self.onDone(name) end
end

function Gen4NamingScreen:typed()
  return table.concat(self.glyphs)
end

-- -------------------------------------------------------------- the cursor --

-- Where the cursor sprite stands (NamingScreen_UpdateCursorSpritePosition,
-- ns.c 2591-2627): on a key at (26 + 16 col, 91 + 19 row); on the home row at
-- sHomeRowCursorXCoords, y 68, the bracket for a tab or the wide one for
-- BACK / OK.
local HOME_BUTTON = { upper = 1, lower = 2, others = 3, back = 6, ok = 7 }
function Gen4NamingScreen:cursorPlace()
  if self.row == 1 then
    local id = HOME[self.col]
    local n = HOME_BUTTON[id] or 1
    return Gen4Naming.HOME_CURSOR_X[n], 68, (id == "back" or id == "ok") and "cursor_wide" or "cursor_tab"
  end
  return 26 + 16 * (self.col - 1), 91 + 19 * (self.row - 2), nil
end

-- every reposition starts the glow at 180 degrees (ns.c 2627)
function Gen4NamingScreen:placed()
  self.glow = 180
  self.cursorTick = 0
end

function Gen4NamingScreen:press(cell)
  if not cell then return end
  if cell.kind == "char" then
    -- A BLANK KEY IS A REAL KEY and types nothing, which is what the
    -- cartridge's CHAR_SPACE cells do in the middle of a page.
    if cell.value ~= "" and #self.glyphs < self.maxLen then
      self.glyphs[#self.glyphs + 1] = cell.value
      -- the cursor's pop (seq 60): a dot swelling and shrinking, 2 ticks a
      -- frame; then, if the name is full, the cursor goes to OK
      self.pop = { tick = 0, x = select(1, self:cursorPlace()), y = select(2, self:cursorPlace()) }
    end
    return
  end
  local id = cell.value
  if id == "upper" then self:turnTo(1)
  elseif id == "lower" then self:turnTo(2)
  elseif id == "others" then self:turnTo(3)
  elseif id == "back" then
    -- BACK animates only when something was deleted (ns.c 2934-2970)
    if #self.glyphs > 0 then
      self.glyphs[#self.glyphs] = nil
      self.pressed = { id = "back", tick = 0 }
    end
  elseif id == "ok" then
    self.pressed = { id = "ok", tick = 0 }
    self:close(self:typed())
  end
end

-- A page change (ns.c 2213-2265): the new panel slides in from the left, 24
-- pixels a 30 Hz frame, the old one drops away 10 a frame, and when the new
-- one lands the overlay and its buttons wiggle.
function Gen4NamingScreen:turnTo(page)
  if page == self.page then return end
  self.slide = { from = self.page, frame = 0 }
  self.page = page
end

-- THE MOVE (NamingScreen_MoveCursor, ns.c 2489-2526): the grid wraps; a step
-- passes over SKIP cells and, on the home row, over the rest of the button it
-- started on, so a wide button is left in one press.
function Gen4NamingScreen:move(dx, dy)
  local rows, cols = Gen4NamingScreen.ROWS, Gen4NamingScreen.COLS
  local startId = self.row == 1 and HOME[self.col] or nil
  local row, col = self.row, self.col
  if dx ~= 0 then self.lastDx = dx end
  for _ = 1, rows * cols do
    row = (row - 1 + dy) % rows + 1
    col = (col - 1 + dx) % cols + 1
    local id = row == 1 and HOME[col] or nil
    local same = dx ~= 0 and row == 1 and id == startId
    if id ~= "skip" and not same then break end
  end
  self.row, self.col = row, col
  self:placed()
end

-- 60 Hz ticks and the 30 Hz frames the app's logic runs on
function Gen4NamingScreen:tickTimers(dt)
  self.clock = (self.clock or 0) + (dt or 1 / 60) * 60
  while self.clock >= 1 do
    self.clock = self.clock - 1
    self.ticks = (self.ticks or 0) + 1
    self.cursorTick = (self.cursorTick or 0) + 1
    if self.pop then
      self.pop.tick = self.pop.tick + 1
      if self.pop.tick >= 18 then
        self.pop = nil
        if #self.glyphs >= self.maxLen then self.row, self.col = 1, 12; self:placed() end
      end
    end
    if self.pressed then
      self.pressed.tick = self.pressed.tick + 1
      if self.pressed.tick >= 8 then self.pressed = nil end
    end
    if self.ticks % 2 == 0 then
      -- the glow: +20 degrees a frame, back to 0 past 360 (ns.c 2629-2641)
      self.glow = (self.glow or 180) + 20
      if self.glow > 360 then self.glow = 0 end
      if self.slide then
        self.slide.frame = self.slide.frame + 1
        if 238 - 24 * self.slide.frame <= -1 then
          self.slide = nil
          self.wiggle = 0
        end
      elseif self.wiggle then
        self.wiggle = self.wiggle + 1
        if self.wiggle >= 7 then self.wiggle = nil end
      end
    end
  end
end

function Gen4NamingScreen:update(dt)
  self:tickTimers(dt)
  local input = self.game.input
  if not input then return end
  if self.choice then
    local count = #self.presets + 1
    if input:wasPressed("up") then self.choice = (self.choice - 2) % count + 1 end
    if input:wasPressed("down") then self.choice = self.choice % count + 1 end
    if input:wasPressed("a") or input:wasPressed("start") then
      if self.choice == 1 then self.choice = nil
      else self:close(self.presets[self.choice - 1]) end
    end
    return
  end
  -- THE CURSOR STARTS HIDDEN, and the first d-pad or A press only shows it
  -- (ns.c 2584-2587, 2854-2857)
  if not self.cursorShown then
    for _, k in ipairs({ "left", "right", "up", "down", "a" }) do
      if input:wasPressed(k) then self.cursorShown = true; self:placed(); return end
    end
  end
  if input:wasPressed("left") then self:move(-1, 0) end
  if input:wasPressed("right") then self:move(1, 0) end
  if input:wasPressed("up") then self:move(0, -1) end
  if input:wasPressed("down") then self:move(0, 1) end
  if input:wasPressed("a") then self:press(self:cell(self.row, self.col)) end
  if input:wasPressed("b") then self:press({ kind = "button", value = "back" }) end
  if input:wasPressed("select") then self:turnTo(self.page % 3 + 1) end
  -- START goes to OK (12, 0) rather than confirming
  if input:wasPressed("start") then
    self.cursorShown = true
    self.row, self.col = 1, 12
    self:placed()
  end
end

-- THE TOUCH RECTANGLES (ns.c 3243-3315): the tabs at (25|57|89, 60) 32x23,
-- BACK (157, 60) 33x23, OK (197, 60) 33x23, the keys 17x20 from (28, 88)
local TOUCH_HOME = { { 25, "upper", 32 }, { 57, "lower", 32 }, { 89, "others", 32 }, { 157, "back", 33 }, { 197, "ok", 33 } }
local HOME_COL = { upper = 1, lower = 3, others = 5, back = 9, ok = 12 }
function Gen4NamingScreen:touchpressed(_, px, py)
  local r = require("src.render.Renderer").uiPresentation
  if not r or px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return false end
  local x, y = (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
  if self.choice then
    local index = math.floor((y - 48) / 22) + 1
    if x >= 24 and x < 232 and index >= 1 and index <= #self.presets + 1 then
      if index == 1 then self.choice = nil else self:close(self.presets[index - 1]) end
    end
    return true
  end
  if y >= 60 and y <= 83 then
    for _, b in ipairs(TOUCH_HOME) do
      if x >= b[1] and x <= b[1] + b[3] then
        self.row, self.col = 1, HOME_COL[b[2]]
        self:placed()
        self:press({ kind = "button", value = b[2] })
        return true
      end
    end
  end
  for row = 0, CHAR_ROWS - 1 do
    for col = 0, Gen4NamingScreen.COLS - 1 do
      local kx, ky = 28 + 16 * col, 88 + 19 * row
      if x >= kx and x <= kx + 16 and y >= ky and y <= ky + 19 then
        self.row, self.col = row + 2, col + 1
        self:placed()
        self:press(self:cell(self.row, self.col))
        return true
      end
    end
  end
  return true
end

-- ------------------------------------------------------------------- draw --

-- A BOX IN PIXELS, for the screen's fallbacks (a cache without the sprites)
local function frame(x, y, w, h)
  local g = love.graphics
  g.setColor(0.08, 0.10, 0.16, 0.72)
  g.rectangle("fill", x, y, w, h)
  g.setColor(0.86, 0.88, 0.94, 1)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  g.setColor(1, 1, 1, 1)
end

-- one of the cartridge's naming sprites at its sprite position
function Gen4NamingScreen:sprite(key, x, y)
  local rec = self.sprites and self.sprites[key]
  local img = rec and self:img(rec)
  if not img then return false end
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

-- the overlay's wiggle, +4 +4 -3 -3 +2 +2 0 (ns.c 2147-2178)
local WIGGLE = { 4, 4, -3, -3, 2, 2, 0 }
function Gen4NamingScreen:wiggleX()
  return self.wiggle and WIGGLE[self.wiggle + 1] or 0
end

-- THE HOME ROW: the tabs (the page's bright, the others dim), BACK and OK
-- (pressed for 8 ticks), every label baked into its sprite; children of the
-- overlay, so they wiggle with it
function Gen4NamingScreen:drawHomeRow()
  local dx = self:wiggleX()
  local names = { "upper", "lower", "others" }
  for i, id in ipairs(names) do
    self:sprite(("tab_%s_%s"):format(id, self.page == i and "on" or "off"), Gen4Naming.TAB_X[i] + dx, 68)
  end
  local p = self.pressed
  self:sprite((p and p.id == "back") and "back_pressed" or "back", Gen4Naming.BACK_X + dx, 68)
  self:sprite((p and p.id == "ok") and "ok_pressed" or "ok", Gen4Naming.OK_X + dx, 68)
end

-- the engine's own home row, for a cache without the sprites
local LABEL = { upper = "A-Z", lower = "a-z", others = "SYM", back = "BACK", ok = "OK" }
function Gen4NamingScreen:drawHomeRowFallback()
  local col = 1
  while col <= Gen4NamingScreen.COLS do
    local id = HOME[col]
    local span = 0
    while HOME[col + span] == id do span = span + 1 end
    if id ~= "skip" then
      local x = HOME_X + (col - 1) * CELL_W
      local w = span * CELL_W
      frame(x, HOME_Y, w, HOME_H)
      if self.row == 1 and HOME[self.col] == id or id == PAGES[self.page].id then
        love.graphics.setColor(0.98, 0.83, 0.30, 0.6)
        love.graphics.rectangle("fill", x + 1, HOME_Y + 1, w - 2, HOME_H - 2)
        love.graphics.setColor(1, 1, 1, 1)
      end
      local label = LABEL[id] or ""
      Font.draw(label, x + math.floor((w - Font.width(label)) / 2), HOME_Y + 2)
    end
    col = col + span
  end
end

-- THE CHECKERBOARD, exactly as `NamingScreen_InitializeCharsGraphics` paints
-- it: the whole window in one colour, then 16x19 rectangles of the other over
-- the ODD columns of rows 0, 2 and 4 and the EVEN columns of rows 1 and 3.
function Gen4NamingScreen:drawChecker(page, ox, oy)
  local g = love.graphics
  local saved = self.page
  self.page = page
  local base, alt = self:checkerColours()
  self.page = saved
  local cols = Gen4NamingScreen.COLS
  local gx, gy = GRID_X + (ox or 0), GRID_Y + (oy or 0)
  g.setColor(base[1], base[2], base[3], 1)
  g.rectangle("fill", gx, gy, cols * CELL_W, CHAR_ROWS * CELL_H)
  g.setColor(alt[1], alt[2], alt[3], 1)
  for row = 0, CHAR_ROWS - 1 do
    for col = (row % 2 == 0) and 1 or 0, cols - 1, 2 do
      g.rectangle("fill", gx + col * CELL_W, gy + row * CELL_H, CELL_W, CELL_H)
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- one keyboard page -- its panel, checkerboard and characters -- moved by
-- (ox, oy) from where the app parks it
function Gen4NamingScreen:drawPage(page, ox, oy)
  local g = love.graphics
  local art = self.art or {}
  local panel = self:img((art.panels or {})[page])
  if panel then
    g.setColor(1, 1, 1, 1)
    g.draw(panel, PANEL_X + ox, PANEL_Y + oy)
  end
  self:drawChecker(page, ox, oy)
  local rows = PAGES[page] and PAGES[page].rows or {}
  for r = 1, CHAR_ROWS do
    local y = GRID_Y + oy + (r - 1) * CELL_H
    for col = 1, Gen4NamingScreen.COLS do
      local ch = rows[r] and rows[r][col]
      if ch and ch ~= "" then
        local x = GRID_X + ox + (col - 1) * CELL_W
        Font.draw(ch, x + math.floor((CELL_W - Font.width(ch)) / 2), y + GLYPH_INSET)
      end
    end
  end
end

-- THE CURSOR: a white mask in the glow's colour -- (29, sin(angle) x 10 + 15,
-- 0) of 31 -- cycling cells 32, 37, 38, 37 eight ticks each on a key, the
-- bracket on the home row; and the pop after a character is typed
function Gen4NamingScreen:drawCursor()
  local g = love.graphics
  local G = math.floor(math.sin(math.rad(self.glow or 180)) * 10) + 15
  if G < 0 then G = 0 end
  g.setColor(29 / 31, G / 31, 0, 1)
  if self.pop then
    local k = math.floor(self.pop.tick / 2)
    local seq = { 0, 1, 2, 3, 4, 3, 2, 1, 0 }
    g.setColor(29 / 31, G / 31, 0, 0.5)
    self:sprite("cursor_pop_" .. (seq[math.min(9, k + 1)]), self.pop.x, self.pop.y)
  elseif self.cursorShown then
    local x, y, key = self:cursorPlace()
    if not key then
      local cycle = { 0, 1, 2, 1 }
      key = "cursor_key_" .. cycle[math.floor((self.cursorTick or 0) / 8) % 4 + 1]
    else
      x = x + self:wiggleX()
    end
    self:sprite(key, x, y)
  end
  g.setColor(1, 1, 1, 1)
end

-- THE NAME AS TYPED (ns.c 2364-2424): the window at tile (10, 3), twelve
-- pixels a character in TEXT_COLOR(14, 15, 1); an underscore under each place
-- at (80 + 12 i, 39), the next one bobbing 0 / +1 / +2 / +1 for 6 / 3 / 3 / 4
-- ticks; the header icon at (24, 8); a Pokemon's gender at (80 + 13 max, 27)
function Gen4NamingScreen:drawEntry()
  local ink = self.ink or {}
  local function c(rgb, fb) rgb = rgb or fb return { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 } end
  Font.pushStyle({ text = c(ink.ink, { 16, 25, 33 }), shadow = c(ink.shadow, { 173, 189, 189 }) })
  for i, ch in ipairs(self.glyphs) do
    local x = 80 + 12 * (i - 1)
    Font.draw(ch, x + math.floor((12 - Font.width(ch)) / 2), 24)
  end
  Font.popStyle()
  local bob = { 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1 }
  for i = 1, self.maxLen do
    local dy = (i == #self.glyphs + 1) and bob[(self.ticks or 0) % 16 + 1] or 0
    self:sprite("underscore", 80 + 12 * (i - 1), 39 + dy)
  end
  -- the header icon
  local t = self.ticks or 0
  local walk = { 0, 1, 2, 1 }
  local kind = self.kind
  if kind == "mon" or kind == "pokemon" then
    self:drawMonIcon(t)
  elseif kind == "box" then
    self:sprite("icon_box_" .. (math.floor(t / 6) % 4), 24, 8)
  elseif kind == "tablet" then
    self:sprite("icon_shaymin", 24, 8)
  elseif kind == "rival" then
    self:sprite("icon_rival_" .. walk[math.floor(t / 12) % 4 + 1], 24, 8)
  elseif kind == "player" or kind == nil then
    local female = self.female
    if female == nil then
      local p = self.game.save and self.game.save.player
      female = p and (p.gender == 1 or p.gender == "girl" or p.gender == "female")
    end
    self:sprite((female and "icon_female_" or "icon_male_") .. walk[math.floor(t / 12) % 4 + 1], 24, 8)
  end
  -- a Pokemon's gender mark
  if self.mon then
    local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
    local gender = ok and Pokemon.genderOf(self.game.data, self.mon)
    if gender == "male" or gender == "female" then
      self:sprite("gender_" .. gender, 80 + self.maxLen * 13, 27)
    end
  end
end

-- the Pokemon's own icon where cell 52 stands, hopping 6 px up for 3 ticks
-- in every 23 (seq 50)
function Gen4NamingScreen:drawMonIcon(t)
  local data = self.game.data or {}
  local species = self.species or (self.mon and self.mon.species)
  local icons = data.icons
  local def = data.pokemon and data.pokemon[species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[species]) or (def and def.icon)
  local path = type(entry) == "table" and entry.image or entry
  local img = type(path) == "string" and self:img(path)
  if not img then return end
  local frameH = (type(entry) == "table" and tonumber(entry.frameHeight)) or 32
  local iw, ih = img:getDimensions()
  local quad = love.graphics.newQuad(0, 0, iw, math.min(frameH, ih), iw, ih)
  local hop = (t % 23) >= 20 and -6 or 0
  local ref = self.sprites and self.sprites.icon_male_0
  local ox, oy = ref and ref.originX or -16, ref and ref.originY or -16
  love.graphics.draw(img, quad, 24 + ox, 8 + oy + hop)
end

function Gen4NamingScreen:drawPrompt()
  -- THE PROMPT IS THE BOTTOM SCREEN'S: a message box at tile (2, 19), 27 x 4
  -- (ns.c 2396-2409). With no second screen showing it goes in the top
  -- strip beside the icon, the only place this screen leaves for it.
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function()
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      love.graphics.setColor(1, 1, 1, 1)
      if Font.hasDialogueFrame and Font.hasDialogueFrame() then Font.drawDialogueBox(1, 18, 29, 6)
      else Font.drawBox(1, 18, 29, 6) end
      Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
      Font.draw(self.title, 16, 152)
      Font.popStyle()
    end)
    return
  end
  Font.draw(self.title, 56, 4)
end

function Gen4NamingScreen:draw()
  local g = love.graphics
  local art = self.art or {}
  if self.choice then
    g.setColor(0.13, 0.16, 0.27, 1)
    g.rectangle("fill", 0, 0, W, H)
    frame(16, 16, 224, 160)
    g.setColor(1, 1, 1, 1)
    Font.draw(self.title, 24, 24)
    for i = 1, #self.presets + 1 do
      local label = i == 1 and Strings("NEW NAME") or self.presets[i - 1]
      local y = 48 + (i - 1) * 22
      if self.choice == i then
        g.setColor(0.38, 0.42, 0.55, 1)
        g.rectangle("fill", 24, y - 2, 208, 20)
        g.setColor(1, 1, 1, 1)
      end
      Font.draw(label, 32, y)
    end
    return
  end

  -- BG2, the backdrop (priority 3)
  local background = self:img(art.background)
  if background then
    g.setColor(1, 1, 1, 1)
    g.draw(background, 0, 0)
  else
    g.setColor(0.13, 0.16, 0.27, 1)
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end

  local hasSprites = self.sprites and self.sprites.overlay
  -- the page dropping away (priority 2), then the overlay sprite (priority 2,
  -- in front of a background of its own priority), then the page in front
  if self.slide then
    local f = self.slide.frame
    self:drawPage(self.slide.from, 0, math.min(116, 10 * f))
    if hasSprites then self:sprite("overlay", Gen4Naming.PARENT_X, 56) end
    self:drawPage(self.page, -(238 - 24 * f) - 11, 0)
  else
    if hasSprites then self:sprite("overlay", Gen4Naming.PARENT_X + self:wiggleX(), 56) end
    self:drawPage(self.page, 0, 0)
  end

  if hasSprites then
    self:drawHomeRow()
    self:drawEntry()
    self:drawCursor()
  else
    local shown = {}
    for i = 1, self.maxLen do shown[i] = self.glyphs[i] or "_" end
    frame(8, ENTRY_Y - 5, W - 16, 22)
    Font.draw(table.concat(shown, " "), 16, ENTRY_Y)
    self:drawHomeRowFallback()
    if self.row > 1 then
      local x, y = self:cursorPlace()
      g.setColor(0.98, 0.83, 0.30, 0.6)
      g.rectangle("fill", x + 1, y - 2, CELL_W - 2, CELL_H - 2)
      g.setColor(1, 1, 1, 1)
    end
  end
  self:drawPrompt()
  g.setColor(1, 1, 1, 1)
end

return Gen4NamingScreen
