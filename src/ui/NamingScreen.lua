-- The naming screen, whichever cartridge is loaded.
--
-- GEN 1'S KEYBOARD WAS ON SCREEN IN HOENN.  Five rows of nine, "×():;[]", a
-- PK cell and an MN cell, a single case toggle -- the Game Boy's keyboard,
-- drawn over Emerald.  Emerald's is a different shape: FOUR rows of EIGHT,
-- three pages rather than two cases, digits and typographic quotes where the
-- Game Boy has its symbol row, and a button that walks the pages rather than
-- flipping a case.  It is the first thing a new game asks anybody to type
-- into, so it is also the first thing that looks wrong.
--
-- Neither layout is written here.  Gen 1's is the alphabet table below;
-- Emerald's is `constants.gen3Keyboard`, which the extractor finds in the ROM
-- by its shape (twelve rows of eight containing a-z, then A-Z, then the
-- digits) and which carries its own page buttons.  A dataset that has one
-- gets it; a dataset that does not keeps the Game Boy's, which is right for
-- the cartridges that have it.
--
-- Gen 1 letter-grid naming screen (engine/menus/naming_screen.asm).
-- Full gen-1 glyph grid (data/text/alphabets.asm): five 9-cell rows
-- ending in ED, plus a case-switch row.  A picks a letter, B deletes,
-- SELECT flips case, START or the ED cell confirms.  If opts.presets is
-- given, a "NEW NAME" + presets menu is shown first
-- (engine/menus/main_menu.asm name lists).
-- Pops itself from the stack, then calls opts.onDone(name).
--
-- ui.naming.grid may replace either page; keep an "ED" cell and a
-- single-cell case-switch row so confirm / case-flip keep working.

local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")

local NamingScreen = {}
NamingScreen.__index = NamingScreen
NamingScreen.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function NamingScreen:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

-- both letter pages (wAlphabetCase, data/text/alphabets.asm): row 6 is
-- the case-switch cell, labelled with the page it flips to
local GRID_UPPER = {
  { "A", "B", "C", "D", "E", "F", "G", "H", "I" },
  { "J", "K", "L", "M", "N", "O", "P", "Q", "R" },
  { "S", "T", "U", "V", "W", "X", "Y", "Z", " " },
  { "×", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
  { "-", "?", "!", "♂", "♀", "/", ".", ",", "ED" },
  { "lower case" },
}
local GRID_LOWER = {
  { "a", "b", "c", "d", "e", "f", "g", "h", "i" },
  { "j", "k", "l", "m", "n", "o", "p", "q", "r" },
  { "s", "t", "u", "v", "w", "x", "y", "z", " " },
  { "×", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
  { "-", "?", "!", "♂", "♀", "/", ".", ",", "ED" },
  { "UPPER CASE" },
}

-- locate the ED confirm cell and the case-switch row on a (possibly
-- modded) grid; falls back to vanilla coordinates
-- `switchLabels` is the set of single-cell labels that mean "change page"
-- rather than "type this".  Gen 1 has two of them and they are spelled out
-- below; Emerald's come off the cartridge and are whatever it calls its three
-- pages, so they cannot be listed here.
local function findMeta(grid, switchLabels)
  local caseRow, edRow, edCol, backRow = #grid, 5, 9, nil
  for r, row in ipairs(grid) do
    if #row == 1 and ((switchLabels and switchLabels[row[1]])
                      or row[1] == "lower case" or row[1] == "UPPER CASE"
                      or row[1] == "lower" or row[1] == "UPPER") then
      caseRow = r
    end
    -- Emerald's third button, which Gen 1 has no equivalent of: BACK rubs
    -- out the last character, and it is a cell the cursor can land on rather
    -- than only the B button.
    if #row == 1 and row[1] == NamingScreen.GEN3_DELETE then backRow = r end
    for c, cell in ipairs(row) do
      if cell == "ED" or cell == NamingScreen.GEN3_CONFIRM then
        edRow, edCol = r, c
      end
    end
  end
  return caseRow, edRow, edCol, backRow
end

local function sameGrid(grid) return grid end

-- ---------------------------------------------------------------------------
-- EMERALD'S KEYBOARD, off the cartridge.
--
-- The record is three pages of four eight-character rows.  Each row becomes a
-- row of single-glyph cells -- glyph, not byte: the symbols page carries ♂, ♀
-- and the typographic quotes, and cutting those by byte would put half a
-- character in the name.  Font.split is the same splitter the text engine
-- uses, so a cell is exactly what one press types.
--
-- The two rows added underneath are this port's, and they are what the
-- cartridge draws as buttons beside the grid rather than under it: the page
-- switch, labelled with the page it moves to, and the confirm cell.  The
-- existing machinery already understands a single-cell switch row and an "ED"
-- cell, so Emerald's keyboard is a different GRID here rather than a second
-- screen.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- WHERE EMERALD DRAWS ITS NAMING SCREEN.
--
-- The port had the right keys in the wrong place: eight columns on an even
-- pitch, black on a bare white rectangle, with the buttons stacked under the
-- last row.  None of that is what the cartridge shows.
--
-- The RECTANGLES and the KEY COLUMNS are read off the ROM and arrive on
-- `constants.gen3Keyboard.layout` -- the window templates that place the
-- keyboard and the name plate, and sPageColumnXPos, which is why "abcdef ."
-- is three letters, a gap, three more and a space, and then the full stop on
-- its own at the right.  An even pitch cannot express that.
--
-- What is left lives in naming_screen.c's CODE rather than its data, so it is
-- quoted from pret rather than derived:
--
--   * a keyboard row is 16 pixels below the last and is printed one pixel
--     into its window (PrintKeyboardKeys: `i * 16 + 1`);
--   * the cursor is a 16x16 sprite at `sPageColumnXPos[page][col] + 38`,
--     `row * 16 + 88` -- which, against a window that starts at x=24, puts it
--     six pixels left of the key it is sitting on;
--   * the three buttons share a column about x=204 -- the page swap at y=83,
--     BACK at 116, OK at 140 -- each a 32x16 sprite drawn about its centre;
--   * the typed name is printed at y=1 inside the text-entry window and the
--     underscores beneath it are sprites at y=60.
--
-- The WORDS "BACK" and "OK" are this port's. The cartridge's two buttons are
-- baked art, not text, so unlike the three page labels there is no string in
-- the ROM to read -- and a button drawn as a word is a smaller lie than a
-- button that is not there.
-- ---------------------------------------------------------------------------
NamingScreen.GEN3_CONFIRM = "OK"
NamingScreen.GEN3_DELETE = "BACK"

local G3 = {
  rowStep = 16, rowInset = 1,
  cursorDx = -6, cursorDy = -1, cursorW = 16, cursorH = 16,
  buttonCx = 204, buttonW = 32, buttonH = 16,
  buttonCy = { 83, 116, 140 },
  entryInset = 1, underscoreY = 60, underscoreW = 6, underscorePitch = 8,
}

-- THE PLATE UNDER ONE BUTTON'S WORD.  Emerald's are 32-pixel sprites with
-- their word baked in; these are drawn, and a drawn word is only as wide as
-- the font makes it -- "OTHERS" does not fit 32 pixels in every dataset -- so
-- the plate grows to hold it and is kept on the screen rather than clipped.
local function gen3ButtonRect(label, cy)
  local textW = Font.width(Strings(label))
  -- the cartridge's plate: 32 pixels about x=204, so its left edge is 188 --
  -- clear of the keyboard window, which ends at 184.  The left edge is what
  -- is kept; a word too wide for 32 pixels grows the plate to the RIGHT, as
  -- far as the screen's own edge and no further.
  local x = G3.buttonCx - math.floor(G3.buttonW / 2)
  local w = math.max(G3.buttonW, math.min(textW + 6, 238 - x))
  return x, cy - math.floor(G3.buttonH / 2), w, G3.buttonH, textW
end

local function gen3Pages(game)
  local record = game and game.data and (game.data.constants or {}).gen3Keyboard
  if type(record) ~= "table" or type(record.pages) ~= "table" then return nil end
  local layout = type(record.layout) == "table" and record.layout or nil

  local byName = {}
  for _, page in ipairs(record.pages) do
    if type(page) == "table" and page.name then byName[page.name] = page end
  end

  local order = record.cycle
  if type(order) ~= "table" or #order == 0 then
    order = {}
    for _, page in ipairs(record.pages) do order[#order + 1] = page.name end
  end

  local pages = {}
  for _, name in ipairs(order) do
    local page = byName[name]
    if page and type(page.rows) == "table" and page.rows[1] then
      -- THE ROWS ARE KEYS, and the import stage writes them that way now.
      --
      -- Cutting the decoded row up again with the font's own splitter is
      -- what a WORD needs, and a keyboard row is not one: "MNOPQRS" came
      -- back with M and N joined, because "MN" is a ligature in the Game Boy
      -- charmap (the <PK><MN> of POKeMON).  Two letters shared one key and
      -- the row was a key short.  A cache from before the stage wrote cells
      -- still gets the old reading rather than nothing.
      local cells = {}
      if type(page.cells) == "table" and page.cells[1] then
        for _, row in ipairs(page.cells) do
          local out = {}
          for _, cell in ipairs(row) do out[#out + 1] = tostring(cell) end
          if #out > 0 then cells[#cells + 1] = out end
        end
      else
        for _, line in ipairs(page.rows) do
          local row = {}
          for _, span in ipairs(Font.split(tostring(line))) do
            row[#row + 1] = tostring(line):sub(span.from, span.to)
          end
          if #row > 0 then cells[#cells + 1] = row end
        end
      end
      -- A PAGE IS AS WIDE AS ITS OWN COLUMN LIST.  The block stores every
      -- page eight bytes wide and pads the short ones with spaces, but the
      -- symbols page only has SIX keys -- sPageColumnCounts says so, and the
      -- cartridge draws six.  Trimming here is what stops two blank keys
      -- appearing on the right of the digits.
      local wide = layout and layout.columns and layout.columns[name]
      if wide and #wide > 0 then
        for _, row in ipairs(cells) do
          for i = #row, #wide + 1, -1 do row[i] = nil end
        end
      end
      if #cells > 0 then
        pages[#pages + 1] = { name = name, label = page.label or name,
                              cells = cells }
      end
    end
  end
  if #pages < 2 then return nil end
  return pages, layout
end

function NamingScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, NamingScreen)
  self.game = game
  self.title = opts.title or Strings("YOUR NAME?")
  self.presets = opts.presets
  self.maxLen = opts.maxLen or 7
  self.default = opts.default
  self.onDone = opts.onDone
  self.glyphs = {} -- typed glyphs; multi-byte cells (<PK>, ♂, ×) count as 1
  self.row, self.col = 1, 1
  self.lower = false
  -- Emerald's, when the dataset carries it.  nil leaves every line below on
  -- the Game Boy's keyboard, which is what Red and Crystal want.
  self.pages, self.layout = gen3Pages(game)
  if self.pages then
    self.page = 1
    local opens = (game.data.constants or {}).gen3Keyboard.opensOn
    for i, page in ipairs(self.pages) do
      if page.name == opens then self.page = i end
    end
    self.switchLabels = {}
    for _, page in ipairs(self.pages) do self.switchLabels[page.label] = true end
  end
  return self
end

-- The surface the screen is laid out on.  Asked of the Theme rather than
-- fixed, because every other state does -- a screen that answers 160x144 on a
-- dataset whose text box needs 240x160 makes the whole display step down a
-- scale the moment it opens.
function NamingScreen:uiSize()
  -- EMERALD'S KEYBOARD IS A 240x160 SCREEN.  Drawn on the Game Boy's 160x144
  -- letterbox the eight columns ran to the very edge and the two buttons
  -- underneath fell off the bottom.  Every other Gen 3 screen in the port
  -- asks for its own surface for the same reason.
  if self.pages then return 240, 160 end
  return Theme.uiSize()
end

function NamingScreen:wantsFillScale() return self.pages ~= nil end

function NamingScreen:sgbPalettes()
  if not self.pages then return nil end
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 29, 19) }
end

function NamingScreen:enter()
  if self.presets and #self.presets > 0 then
    local Menu = require("src.ui.Menu")
    local items = { { label = Strings("NEW NAME") } }
    for _, preset in ipairs(self.presets) do
      table.insert(items, {
        label = preset,
        onSelect = function()
          -- the menu already popped itself; pop the naming screen too
          self.game.stack:pop()
          if self.onDone then self.onDone(preset) end
        end,
      })
    end
    self.game.stack:push(Menu.new(self.game, items, {
      tx = 4, ty = 0, tw = 12, th = #items * 2 + 2, cancelable = false,
    }))
  end
end

-- Two cases and three pages are the same verb: move to the next layout.  The
-- cursor is clamped afterwards because Emerald's pages are not all the same
-- width once the symbols page's trailing blanks are counted.
function NamingScreen:flipPage()
  if self.pages then
    self.page = self.page % #self.pages + 1
  else
    self.lower = not self.lower
  end
  local GRID = self:grid()
  self.row = math.min(self.row, #GRID)
  self.col = math.min(self.col, #GRID[self.row])
end

function NamingScreen:confirm()
  local name = table.concat(self.glyphs)
  if name == "" then
    name = (self.presets and self.presets[1]) or self.default or "A"
  end
  Sound.play(self.game.data, "Press_AB")
  self.game.stack:pop()
  if self.onDone then self.onDone(name) end
end

function NamingScreen:meta()
  return findMeta(self:grid(), self.switchLabels)
end

function NamingScreen:grid()
  local base
  if self.pages then
    local page = self.pages[self.page] or self.pages[1]
    base = {}
    for _, row in ipairs(page.cells) do base[#base + 1] = row end
    -- the button says where it takes you, exactly as the cartridge's does,
    -- and the two under it are Emerald's other two: rub out, and done
    local nextPage = self.pages[self.page % #self.pages + 1]
    base[#base + 1] = { nextPage.label }
    base[#base + 1] = { NamingScreen.GEN3_DELETE }
    base[#base + 1] = { NamingScreen.GEN3_CONFIRM }
  else
    base = self.lower and GRID_LOWER or GRID_UPPER
  end
  if not Runtime.wantsHook("ui.naming.grid") then return base end
  local hooked = Runtime.call("ui.naming.grid", sameGrid, base, {
    lower = self.lower and true or false,
    title = self.title,
    maxLen = self.maxLen,
    game = self.game,
  })
  if type(hooked) ~= "table" or #hooked == 0 then return base end
  return hooked
end

-- Gen 1 jumps the cursor to ED once the name is full.
function NamingScreen:jumpToEnd()
  local _, edRow, edCol = self:meta()
  self.row, self.col = edRow, edCol
end

function NamingScreen:update(dt)
  local GRID = self:grid()
  local caseRow, edRow, edCol, backRow = findMeta(GRID, self.switchLabels)
  local input = self.game.input
  if input:wasPressed("start") then
    self:confirm()
    return
  end
  if input:wasPressed("select") then -- SELECT also walks the pages
    self:flipPage()
    return
  end
  if input:wasPressed("up") then
    -- wrapping up from the top row lands on the case-switch cell
    self.row = self.row > 1 and self.row - 1 or caseRow
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("down") then
    self.row = self.row < #GRID and self.row + 1 or 1
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("left") then
    -- no horizontal movement on the case-switch row
    if self.row ~= caseRow then
      self.col = self.col > 1 and self.col - 1 or #GRID[self.row]
    end
  elseif input:wasPressed("right") then
    if self.row ~= caseRow then
      self.col = self.col < #GRID[self.row] and self.col + 1 or 1
    end
  elseif input:wasPressed("b") then
    table.remove(self.glyphs)
  elseif input:wasPressed("a") then
    if self.row == edRow and self.col == edCol then
      self:confirm()
      return
    end
    if self.row == caseRow then
      self:flipPage()
      return
    end
    if backRow and self.row == backRow then
      -- BACK is what the B button does, on a key
      table.remove(self.glyphs)
      return
    end
    if #self.glyphs < self.maxLen then
      Sound.play(self.game.data, "Press_AB")
      table.insert(self.glyphs, GRID[self.row][self.col])
      if #self.glyphs >= self.maxLen then self:jumpToEnd() end
    end
  end
end

-- WHERE THE KEYS GO.
--
-- RECONSTRUCTED, and the numbers are the part to correct against a
-- screenshot: the cartridge draws its keyboard as a window with the page
-- button and the confirm cell BESIDE the grid rather than under it, and this
-- port's machinery understands them as two more rows.  What is derived is the
-- grid's SHAPE -- eight columns and four rows -- which is the block's own.
--
-- The pitch is measured off the widest key rather than assumed, so a
-- proportional font cannot run one key into the next.
function NamingScreen:metrics()
  local rows = self:grid()

  -- THE CARTRIDGE'S OWN GEOMETRY, when the dataset carries it: the keyboard
  -- window's tile rectangle, the key columns inside it, and the button column
  -- beside it.  Nothing here is measured off the font, because none of it is
  -- the font's to decide -- Emerald puts a key at sPageColumnXPos[page][col]
  -- whatever it is about to draw there.
  if self.layout and self.layout.keyboard and self.layout.columns then
    local kb = self.layout.keyboard
    local page = self.pages and (self.pages[self.page] or self.pages[1])
    local cols = self.layout.columns[page and page.name] or {}
    local keyRowCount = page and #page.cells or #rows
    return {
      left = kb.left * 8, top = kb.top * 8,
      rows = rows, keyRows = keyRowCount,
      cols = cols, rowStep = G3.rowStep, rowInset = G3.rowInset,
      lineH = G3.rowStep,
      pitch = (cols[2] or 12) - (cols[1] or 0),
      buttonAt = keyRowCount + 1,
      buttonX = G3.buttonCx - math.floor(G3.buttonW / 2),
      buttonCy = G3.buttonCy,
      layout = self.layout,
    }
  end

  local widest = 8
  for _, row in ipairs(rows) do
    for _, cell in ipairs(row) do
      local w = Font.width(Strings(cell))
      if w > widest then widest = w end
    end
  end
  local sw = self:uiSize()
  local left = 16

  -- the page switch and the confirm cell are single-cell rows past the
  -- keyboard's own; they get a column of their own on the right, and the
  -- grid gets what is left
  local keyRowCount = #rows
  if self.pages then
    local page = self.pages[self.page] or self.pages[1]
    keyRowCount = #page.cells
  end
  local buttonW = 0
  for r = keyRowCount + 1, #rows do
    for _, cell in ipairs(rows[r]) do
      local w = Font.width(Strings(cell))
      if w > buttonW then buttonW = w end
    end
  end
  if buttonW > 0 then buttonW = buttonW + 12 end

  local columns = 0
  for r = 1, keyRowCount do
    if #rows[r] > columns then columns = #rows[r] end
  end
  local pitch = widest + 8
  -- ...and the whole thing has to fit the screen it is drawn on, buttons
  -- included: sized off the grid alone, "lower" ran off the right edge
  local room = sw - 8 - left - buttonW
  if columns > 0 and columns * pitch > room then
    pitch = math.max(12, math.floor(room / columns))
  end
  local top = self.pages and 46 or 48
  local lineH = math.max(16, Font.glyphHeight() + 3)
  -- WHICH ROWS ARE KEYS AND WHICH ARE BUTTONS.  The page switch and the
  -- confirm cell are two more rows to everything that MOVES the cursor --
  -- which is what makes one keyboard out of three pages and a done key --
  -- but the cartridge draws them BESIDE the grid, not under it.  So they are
  -- rows for the navigation and a column for the eye.
  local buttonAt = (buttonW > 0) and (keyRowCount + 1) or nil
  return { left = left, top = top, pitch = pitch, lineH = lineH, rows = rows,
           keyRows = keyRowCount, buttonAt = buttonAt,
           buttonX = left + columns * pitch + 8 }
end

-- Where row `r`, column `c` is drawn, in surface pixels.
function NamingScreen:cellAt(m, r, c)
  if m.buttonAt and r >= m.buttonAt then
    if m.buttonCy then
      local cy = m.buttonCy[r - m.buttonAt + 1] or m.buttonCy[#m.buttonCy]
      -- the buttons are sprites drawn about their centre, and the word is
      -- centred on the plate
      local label = (m.rows[r] or {})[1] or ""
      local bx, by, w, _, textW = gen3ButtonRect(label, cy)
      return bx + math.floor((w - textW) / 2), by + 1
    end
    return m.buttonX, m.top + (r - m.buttonAt) * m.lineH
  end
  if m.cols then
    local x = m.cols[c] or ((c - 1) * (m.pitch or 12))
    return m.left + x, m.top + (r - 1) * m.rowStep + m.rowInset
  end
  return m.left + (c - 1) * m.pitch, m.top + (r - 1) * m.lineH
end

-- The screen the Game Boy cartridges get: a white page, a row of dashes and
-- the arrow cursor, which is what Red and Crystal draw.
function NamingScreen:drawClassic()
  local sw, sh = self:uiSize()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, sw, sh)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.title, 8, 8)
  local m = self:metrics()
  -- typed name with dashes for the empty slots, on the font's own pitch
  local slot = math.max(8, Font.width("W") + 2)
  for i = 1, self.maxLen do
    Font.draw(self.glyphs[i] or "-", m.left + 40 + (i - 1) * slot, 26)
  end
  for r, row in ipairs(m.rows) do
    for c, cell in ipairs(row) do
      local x, y = self:cellAt(m, r, c)
      Font.draw(Strings(cell), x, y)
    end
  end
  local cx, cy = self:cellAt(m, self.row, self.col)
  Font.drawCode(Theme.cursor, cx - 8, cy)
  love.graphics.setColor(1, 1, 1, 1)
end

-- WHERE THE TYPED NAME SITS.  The text-entry window is seventeen tiles wide
-- and the name is centred in it, eight pixels a slot, which is the pitch the
-- underscore sprites are laid out on.
function NamingScreen:entryBaseX()
  local entry = self.layout and self.layout.entry
  if not entry then return 0 end
  local left, width = entry.left * 8, entry.width * 8
  return left + math.floor((width - self.maxLen * G3.underscorePitch) / 2)
end

-- One of Emerald's three buttons: a plate with a word on it. The cartridge
-- draws them as sprites and this draws them as boxes, so the SHAPE is this
-- port's; the column and the three heights are the cartridge's.
local function gen3Button(cy, label, selected)
  local x, y, w, h, textW = gen3ButtonRect(label, cy)
  if selected then
    love.graphics.setColor(0.98, 0.86, 0.36, 1)
  else
    love.graphics.setColor(0.93, 0.93, 0.90, 1)
  end
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setColor(0.36, 0.36, 0.40, 1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3, 3)
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(Strings(label), x + math.floor((w - textW) / 2), y + 1)
end

-- Emerald's, at the coordinates read off the cartridge.
function NamingScreen:drawGen3()
  local sw, sh = self:uiSize()
  local m = self:metrics()

  -- the field behind everything: Emerald's naming screen is a blue wash that
  -- lightens towards the bottom, not the Game Boy's white page
  local bands = 16
  for i = 0, bands - 1 do
    local t = i / (bands - 1)
    love.graphics.setColor(0.13 + 0.17 * t, 0.25 + 0.19 * t, 0.44 + 0.20 * t, 1)
    love.graphics.rectangle("fill", 0, math.floor(i * sh / bands), sw,
                            math.ceil(sh / bands) + 1)
  end

  -- THE NAME PLATE.  Two windows of two rows each, touching: the upper one
  -- asks and the lower one holds what has been typed.  They are drawn as one
  -- box, with the frame the cartridge's own art gives it.
  local box, entry = self.layout.entryBox, self.layout.entry
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(box.left - 1, box.top - 1, box.width + 2,
               (entry.top + entry.height) - box.top + 2)
  Font.draw(self.title, box.left * 8, box.top * 8 + G3.entryInset)

  local baseX = self:entryBaseX()
  local textY = entry.top * 8 + G3.entryInset
  for i = 1, self.maxLen do
    local x = baseX + (i - 1) * G3.underscorePitch
    local glyph = self.glyphs[i]
    if glyph then Font.draw(Strings(glyph), x, textY) end
    -- the underscore is drawn for every slot, filled or not, exactly as the
    -- cartridge's sprites are
    love.graphics.setColor(0.36, 0.36, 0.40, 1)
    love.graphics.rectangle("fill", x + 1, G3.underscoreY, G3.underscoreW, 1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- THE KEYBOARD, in the window the ROM places it in
  local kb = self.layout.keyboard
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(kb.left - 1, kb.top - 1, kb.width + 2, kb.height + 2)

  -- the cursor first, so it sits behind its key rather than over it
  local cx, cy = self:cellAt(m, self.row, self.col)
  if self.row <= m.keyRows then
    love.graphics.setColor(0.98, 0.86, 0.36, 1)
    love.graphics.rectangle("fill", cx + G3.cursorDx, cy + G3.cursorDy,
                            G3.cursorW, G3.cursorH, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
  end

  for r = 1, m.keyRows do
    for c, cell in ipairs(m.rows[r]) do
      local x, y = self:cellAt(m, r, c)
      Font.draw(Strings(cell), x, y)
    end
  end

  -- ...and the three buttons beside it
  for r = m.buttonAt, #m.rows do
    local i = r - m.buttonAt + 1
    local cyB = m.buttonCy[i] or m.buttonCy[#m.buttonCy]
    gen3Button(cyB, m.rows[r][1], self.row == r)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function NamingScreen:draw()
  if self.layout then return self:drawGen3() end
  return self:drawClassic()
end

return NamingScreen
