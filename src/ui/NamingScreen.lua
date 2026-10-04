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

-- naming_screen.c's sIconFunctions: the plate to the left of the question
-- ("YOUR NAME?" / "NICKNAME?" / "RIVAL's NAME?") carries a small icon of
-- whoever is being named -- the player's own overworld sprite
-- (NamingScreen_CreatePlayerIcon), the dedicated rival sheet
-- (NamingScreen_CreateRivalIcon), or, when naming a caught Pokémon, that
-- species' bouncing party icon (NamingScreen_CreateMonIcon). Reported from play: "in keyboard typing
-- there's only a green patch.... above that there should be player sprite
-- and if pokemon name is typing then the pokemon sprite" -- this port drew
-- the plate's background tiles but never the OAM sprite the cartridge lays
-- over them, so the patch sat empty.
local iconImgCache = {}
local function loadIconImage(path)
  if not path then return nil end
  if iconImgCache[path] == nil then
    local Assets = require("src.render.Assets")
    local ok, img = pcall(Assets.image, path)
    iconImgCache[path] = ok and img or false
  end
  return iconImgCache[path] or nil
end

-- The player's own overworld walk sprite, standing south (frame 0 is always
-- STAND.down -- see SpriteRenderer.STAND): matches
-- GetPlayerAvatarGraphicsIdByStateIdAndGender(..., PLAYER_AVATAR_STATE_NORMAL)
-- picking the current gender's sheet, ANIM_STD_GO_SOUTH's first frame.
local function playerIconFrame(game)
  local data = game and game.data
  if not data then return nil end
  local okReq, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  local okReq2, Sprites = pcall(require, "src.pokemon.Sprites")
  if not (okReq and okReq2) then return nil end
  local sprites = data.sprites or {}
  local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
  local ok, form = pcall(Sprites.playerForm, data)
  if ok and form and form.walk and sprites[form.walk] then walkId = form.walk end
  local def = walkId and sprites[walkId]
  local img = def and loadIconImage(def.image)
  if not img then return nil end
  local tw = math.floor(tonumber(def.frameWidth) or 16)
  local th = math.floor(tonumber(def.frameHeight) or 16)
  if tw < 8 or th < 8 then tw, th = 16, 16 end
  return img, tw, th
end

-- A Pokémon's bouncing party-icon sprite, resolved exactly the way
-- Gen3PartyMenu:iconFor does (the registry first, then the species row's own
-- field, through the same pokemon.icon mod seam).
local ICON_PERIOD = 0.32
local function monIconFrame(game, species, t)
  local data = game and game.data
  if not (data and species) then return nil end
  local icons = data.icons
  local def = data.pokemon and data.pokemon[species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[species])
                or (def and def.icon)
  local path, frameH
  if type(entry) == "table" then
    path, frameH = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then
    path = entry
  end
  local okHook, hooked = pcall(function()
    return require("src.pokemon.Sprites").iconPath(data, nil, path, {})
  end)
  if okHook and type(hooked) == "string" then path = hooked end
  local img = loadIconImage(path)
  if not img then return nil end
  frameH = frameH or tonumber(icons and icons.frameHeight) or 32
  local iw, ih = img:getDimensions()
  frameH = math.min(frameH, ih)
  local frames = math.max(1, math.floor(ih / frameH))
  local frame = frames > 1
    and (math.floor((t % (ICON_PERIOD * frames)) / ICON_PERIOD) % frames)
    or 0
  return img, iw, frameH, frame
end

local function rivalIconFrame(game, t)
  local data = game and game.data
  local naming = data and data.constants and data.constants.gen3FRLGNaming
  local rec = naming and naming.rivalIcon
  if not (rec and rec.image) then return nil end
  local img = loadIconImage(rec.image)
  if not img then return nil end
  local fw = math.floor(tonumber(rec.frameWidth) or 16)
  local fh = math.floor(tonumber(rec.frameHeight) or 32)
  local anim = rec.animation or { 0, 3, 0, 4 }
  local seconds = (tonumber(rec.frameTicks) or 10) / 60
  local step = math.floor((t % (seconds * #anim)) / seconds) + 1
  return img, fw, fh, anim[step] or 0
end

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
  -- who the plate's icon is of: "player" (own overworld sprite), "rival"
  -- (FireRed's private animated Blue sheet), or "mon" (nickname screens, the
  -- species' party icon) -- see the icon helpers above
  self.kind = opts.kind
  self.species = opts.species or (opts.mon and opts.mon.species)
  self.mon = opts.mon
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

-- GBA names have a separate three-button column. Crossing either edge of
-- a key row reaches that column; vertical movement wraps within its column.
function NamingScreen:moveGen3Cursor(dir)
  local grid = self:grid()
  local keys, buttons = #self.pages[self.page].cells, 3
  local first = keys + 1
  local inButtons = self.row >= first
  if dir == "up" or dir == "down" then
    local delta = dir == "up" and -1 or 1
    if inButtons then self.row = first + (self.row - first + delta) % buttons
    else self.row = (self.row - 1 + delta) % keys + 1 end
  elseif inButtons then
    local keyRows = { 1, 1, 4 }
    self.row = keyRows[self.row - first + 1]
    self.col = dir == "left" and #grid[self.row] or 1
  else
    local width = #grid[self.row]
    local nextCol = self.col + (dir == "left" and -1 or 1)
    if nextCol < 1 or nextCol > width then
      local buttonRows = { 0, 1, 1, 2 }
      self.row, self.col = first + buttonRows[self.row], 1
    else self.col = nextCol end
  end
end

function NamingScreen:update(dt)
  self.blink = (self.blink or 0) + 1
  local GRID = self:grid()
  local caseRow, edRow, edCol, backRow = findMeta(GRID, self.switchLabels)
  local input = self.game.input
  if input:wasPressed("start") then
    if self.pages then self:jumpToEnd() else self:confirm() end
    return
  end
  if input:wasPressed("select") then -- SELECT also walks the pages
    self:flipPage()
    return
  end
  if input:wasPressed("up") then
    if self.pages then return self:moveGen3Cursor("up") end
    -- wrapping up from the top row lands on the case-switch cell
    self.row = self.row > 1 and self.row - 1 or caseRow
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("down") then
    if self.pages then return self:moveGen3Cursor("down") end
    self.row = self.row < #GRID and self.row + 1 or 1
    self.col = math.min(self.col, #GRID[self.row])
  elseif input:wasPressed("left") then
    if self.pages then return self:moveGen3Cursor("left") end
    -- no horizontal movement on the case-switch row
    if self.row ~= caseRow then
      self.col = self.col > 1 and self.col - 1 or #GRID[self.row]
    end
  elseif input:wasPressed("right") then
    if self.pages then return self:moveGen3Cursor("right") end
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

-- FIRERED'S, out of RomExtractorGen3:extractFireRedNaming: BG3 the striped
-- field with the name plate, BG1 the page's coloured frame with the keys on
-- its fill, the three sprite plates in the column at x 204, the bracket
-- cursor at sPageColumnXPos + 38, the underscores and the input arrow.
function NamingScreen:frlgImage(key)
  local constants = self.game.data.constants or {}
  local r = constants.gen3EmeraldNaming or constants.gen3FRLGNaming
  local path = r and r.images and r.images[key]
  if not path then return nil end
  self._img = self._img or {}
  if self._img[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self._img[path] = ok and img or false
  end
  return self._img[path] or nil
end

local FRLG_LABEL = { upper = "label_upper", lower = "label_lower", symbols = "label_others" }

function NamingScreen:drawFireRed(rec)
  local g = love.graphics
  local m = self:metrics()
  local function rgb(t, f) t = t or f return { t[1] / 255, t[2] / 255, t[3] / 255, 1 } end
  local function text(s, x, y, ink, shadow, small)
    local faced = small and Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
    local two = Font.beginTwoTone(ink, shadow)
    if not two then g.setColor(ink) end
    Font.draw(s, x, y)
    if two then Font.endTwoTone() end
    if faced then Font.popFace() end
    g.setColor(1, 1, 1, 1)
  end
  local cc = rec.colors or {}
  g.setColor(1, 1, 1, 1)
  local bg = self:frlgImage("bg")
  if bg then g.draw(bg, 0, 0) end

  -- the banner: window (0,0) 30x2, "{DPAD}MOVE {A}OK {B}BACK" right-aligned
  g.setColor(0, 123 / 255, 197 / 255, 1)
  g.rectangle("fill", 0, 0, 240, 16)
  local white, darkGray = { 1, 1, 1, 1 }, { 98 / 255, 98 / 255, 98 / 255, 1 }
  local hints = { { "+", Strings("MOVE") }, { "A", Strings("OK") }, { "B", Strings("BACK") } }
  local faced = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
  local width = 0
  for _, h in ipairs(hints) do width = width + 12 + Font.width(h[2]) + 4 end
  if faced then Font.popFace() end
  local hx = 240 - 4 - width + 4
  if (self.game.data.constants or {}).gen3EmeraldNaming then hx = 2 end
  for _, h in ipairs(hints) do
    g.setColor(white)
    g.rectangle("line", hx + 0.5, 2.5, 10, 9, 3, 3)
    text(h[1], hx + 2, 0, white, darkGray, true)
    text(h[2], hx + 12, 0, white, darkGray, true)
    local f2 = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
    hx = hx + 12 + Font.width(h[2]) + 4
    if f2 then Font.popFace() end
  end

  -- the question and the typed name, on the plate BG3 already draws
  local entryInk = cc.entry and rgb(cc.entry[2]) or darkGray
  local entryShadow = cc.entry and rgb(cc.entry[3]) or { 0.84, 0.84, 0.81, 1 }
  local title = self.title
  if (self.game.data.constants or {}).gen3EmeraldNaming and self.kind == "mon" then
    title = ((self.game.data.pokemon[self.species] or {}).name or "") .. Strings("'s nickname?")
  end
  text(title, 72, 33, entryInk, entryShadow)
  local base = math.floor((240 - self.maxLen * 8) / 2) + 6
  local underscore, arrow = self:frlgImage("underscore"), self:frlgImage("arrow")
  for i = 1, self.maxLen do
    local x = base + (i - 1) * 8
    local glyph = self.glyphs[i]
    if glyph then text(Strings(glyph), x, 48 + 1, entryInk, entryShadow) end
    if underscore then g.draw(underscore, x + 3 - 4, 60 - 4) end
  end
  local at = math.min(#self.glyphs + 1, self.maxLen)
  if arrow and math.floor((self.blink or 0) / 30) % 2 == 0 then
    g.draw(arrow, base + (at - 1) * 8 - 4, 56 - 4)
  end

  -- the page: BG1's frame, the window's fill, the keys
  local page = self.pages[self.page] or self.pages[1]
  local frame = self:frlgImage("kb_" .. page.name)
  if frame then g.draw(frame, 0, 0) end
  local fill = cc.fill and cc.fill[page.name]
  if fill then
    g.setColor(rgb(fill))
    g.rectangle("fill", 24, 80, 152, 64)
    g.setColor(1, 1, 1, 1)
  end
  local keyInk = cc.key and rgb(cc.key[1]) or white
  local keyShadow = cc.key and rgb(cc.key[2]) or darkGray
  local cols = (self.layout.columns or {})[page.name] or {}
  for r = 1, m.keyRows do
    for c, cell in ipairs(m.rows[r]) do
      -- centred under the cursor, whose centre is sPageColumnXPos + 38
      local s = Strings(cell)
      local cx = 38 + (cols[c] or (c - 1) * 12)
      text(s, cx - math.floor(Font.width(s) / 2), 80 + (r - 1) * 16 + 1, keyInk, keyShadow)
    end
  end

  -- the column of plates: the page swap (labelled with where it goes), BACK, OK
  local nextPage = self.pages[self.page % #self.pages + 1]
  local plates = {
    { self:frlgImage("frame"), 184, 72 },
    { self:frlgImage("back"), 184, 104 },
    { self:frlgImage("ok"), 184, 128 },
  }
  for i, p in ipairs(plates) do
    if p[1] then
      g.draw(p[1], p[2], p[3])
      if m.buttonAt and self.row == m.buttonAt + i - 1 then
        -- the chosen plate brightens (the cartridge's palette flash)
        g.setBlendMode("add")
        g.setColor(1, 1, 1, 0.18 + 0.12 * math.abs(math.sin((self.blink or 0) / 10)))
        g.draw(p[1], p[2], p[3])
        g.setBlendMode("alpha")
        g.setColor(1, 1, 1, 1)
      end
    end
  end
  -- the plate (a 32x16 OBJ at 204,83) and its label (24x8 at 204,84)
  local which = (FRLG_LABEL[nextPage.name] or "label_others"):gsub("^label_", "")
  local plate = self:frlgImage("swap_" .. which)
  if plate then g.draw(plate, 204 - 16, 83 - 8) end
  local label = self:frlgImage("label_" .. which)
  if label then g.draw(label, 204 - 12, 84 - 4) end

  -- the cursor, on a key
  local cursor = self:frlgImage("cursor")
  if cursor and self.row <= m.keyRows then
    g.draw(cursor, 30 + (cols[self.col] or 0), 80 + (self.row - 1) * 16)
  end
  g.setColor(1, 1, 1, 1)
end

-- Drawn last, over the plate's own tiles, at naming_screen.c's exact CreateSprite
-- centres: player/rival at (56,37), Pokémon at (56,40). CreateSprite positions
-- are sprite centres, so convert them to LÖVE's top-left draw coordinates here.
function NamingScreen:drawIcon()
  if not self.kind then return end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if self.kind == "player" then
    local img, tw, th = playerIconFrame(self.game)
    if img then
      local iw, ih = img:getDimensions()
      local quad = love.graphics.newQuad(0, 0, tw, th, iw, ih)
      g.draw(img, quad, 56 - math.floor(tw / 2), 37 - math.floor(th / 2))
    end
  elseif self.kind == "mon" then
    local t = love.timer and love.timer.getTime() or 0
    local img, iw, frameH, frame = monIconFrame(self.game, self.species, t)
    if img then
      local quad = love.graphics.newQuad(0, frame * frameH, iw, frameH,
                                         iw, img:getHeight())
      g.draw(img, quad, 56 - math.floor(iw / 2), 40 - math.floor(frameH / 2))
    end
  elseif self.kind == "rival" then
    local t = love.timer and love.timer.getTime() or 0
    local img, fw, fh, frame = rivalIconFrame(self.game, t)
    if img then
      local iw, ih = img:getDimensions()
      local quad = love.graphics.newQuad(0, frame * fh, fw, fh, iw, ih)
      g.draw(img, quad, 56 - math.floor(fw / 2), 37 - math.floor(fh / 2))
    end
  end
  g.setColor(1, 1, 1, 1)
end

function NamingScreen:draw()
  local constants = self.game.data.constants or {}
  local frlg = self.layout and (constants.gen3EmeraldNaming or constants.gen3FRLGNaming)
  if frlg and frlg.images and frlg.images.bg then
    local faced = Font.hasFace and Font.hasFace("normal") and Font.pushFace("normal")
    self:drawFireRed(frlg)
    self:drawIcon()
    if faced then Font.popFace() end
    return
  end
  if self.layout then
    self:drawGen3()
    self:drawIcon()
    return
  end
  return self:drawClassic()
end

return NamingScreen
