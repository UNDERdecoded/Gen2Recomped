-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's main menu -- which is a SCREEN, not a box on the title.
--
-- That is the whole reason this file exists.  The port opened a menu on top
-- of the title art, which put a white window across the middle of the POKéMON
-- logo: the logo looked misaligned because it was half-covered, not because
-- it was in the wrong place.  On the cartridge, pressing START leaves the
-- title behind entirely -- CB2_InitMainMenu clears both backgrounds and draws
-- the menu on a plain field, and the logo is never underneath it.
--
-- THE ROWS, and which of them exist:
--
--   CONTINUE     only with a save on disk
--   NEW GAME
--   OPTION
--   EXIT GAME    this port's, not the cartridge's -- a GBA has no way out
--
-- CONTINUE opens the info panel first (PLAYER / BADGES / POKéDEX / TIME), the
-- way DisplayContinueGameInfo does, and only A from there loads the game.
--
-- AND THE SAVE CHECK IS A REAL ONE.  The title screen used to ask SaveData
-- for an `exists` function, which this engine does not have -- the call raised
-- inside a pcall, the pcall answered "no save", and CONTINUE never appeared no
-- matter how many times the game was saved.  It asks the filesystem for the
-- active version's save file now, which is what TitleState has always done.

local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3MainMenu = {}
Gen3MainMenu.__index = Gen3MainMenu
Gen3MainMenu.isOpaque = true

-- Only the height is a constant now: the width is whatever the window asks
-- for (Gen3Wide.uiSize), because a GBA screen is 160 rows whatever it is wide.
local GBA_H = 160

-- RECONSTRUCTED, not derived: the menu sits in the top-left, each row two
-- tiles apart, and the info panel fills the screen under it.
local BOX = { tx = 0, ty = 0, tw = 15 }
local ROW_STEP = 2
local INFO = { tx = 0, ty = 0, tw = 20, th = 12 }
local INFO_VALUE_X = 112

-- THE SAME SURFACE THE TITLE ASKS FOR.
--
-- This menu is pushed over the title and Game:draw takes the size from the
-- TOPMOST state that has one -- so if this asked for the cartridge's 240 the
-- canvas would snap back to it the moment START was pressed, and the screen
-- underneath would be laid out for a width it no longer has.  Asked for
-- directly: "ensure that the main menu and intro animations extend to wide
-- screen and fill the screen without black borders".
local Gen3Wide = require("src.ui.Gen3Wide")

function Gen3MainMenu:uiSize() return Gen3Wide.uiSize() end
function Gen3MainMenu:wantsFillScale() return true end

-- NOT A PANEL, so its edge is not a frame to continue.
--
-- Renderer:bleedEdges paints the letterbox with the surface's outermost row
-- and column so a menu's border appears to run to the window edge.  Here the
-- outermost column is CB2_InitMainMenu's own plain field, which this screen draws itself -- pulling it
-- outward stretches that sideways instead of extending a border.  Reported
-- from play: "fix the stretching of borders on the start menu, main menu,
-- main menu intro and the continue, new game, options, exit menus ... instead
-- make them full screen/fit the screen without stretching".  wantsFillScale
-- above is what makes it fill; this is what stops it smearing.
function Gen3MainMenu:wantsEdgeBleed() return false end

function Gen3MainMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local w = select(1, Gen3Wide.uiSize())
  return { P.trueColorZone(0, 0, math.ceil(w / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- Is there a save on disk?  The active version's own file, which is what
-- SaveData.saveFilename answers and what every other screen in this engine
-- asks.  See the note at the top: the version this replaced called a function
-- that does not exist, so the answer was always no.
local function saveOnDisk()
  local ok, info = pcall(function()
    local name = require("src.core.SaveData").saveFilename(GameVersion.get())
    return love.filesystem and love.filesystem.getInfo
       and love.filesystem.getInfo(name) or nil
  end)
  return ok and info ~= nil
end

local function sameItems(_, items) return items end

function Gen3MainMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3MainMenu)
  self.game = game
  self.onNewGame = opts.onNewGame
  self.onContinue = opts.onContinue
  self.onCancel = opts.onCancel
  self.index = 1
  self.info = nil

  local items = {}
  if saveOnDisk() then
    items[#items + 1] = { key = "continue", label = Strings("CONTINUE") }
  end
  items[#items + 1] = { key = "newGame", label = Strings("NEW GAME") }
  -- OPTION AND EXIT GAME ON EVERY GEN 3 MENU, FIRERED INCLUDED.
  --
  -- FireRed's cartridge menu really is CONTINUE and NEW GAME only -- its
  -- OPTION lives in the START menu and a GBA has no "exit" -- and this was
  -- written to match.  But EXIT GAME is not the cartridge's row, it is the
  -- launcher's: it is how the player puts this game down and picks another,
  -- and leaving it off meant FireRed was the one game with no way out of it
  -- but the window close button.  OPTION comes with it so the two menus a
  -- player moves between do not differ by a row.
  items[#items + 1] = { key = "option", label = Strings("OPTION") }
  items[#items + 1] = { key = "exit", label = Strings("EXIT GAME") }
  local hooked = Runtime.call("ui.title_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.title_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  self.items = items
  return self
end

function Gen3MainMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3MainMenu:choose()
  local item = self.items[self.index]
  if not item then return end
  -- a row a mod added carries its own handler and is not one of the four
  if item.onSelect and not item.key then
    self.game.stack:pop()
    return item.onSelect()
  end
  if item.key == "continue" and GameVersion.isFRLG() then
    -- the stats are already on the window; A loads straight away
    if self.onContinue then self.onContinue() end
  elseif item.key == "continue" then
    local ok, loaded = pcall(require("src.core.SaveData").load)
    if ok and loaded then
      self.info = loaded
    elseif self.onContinue then
      self.onContinue()
    end
  elseif item.key == "newGame" then
    if self.onNewGame then self.onNewGame() end
  elseif item.key == "option" then
    local boot = self.game.data.field and self.game.data.field.boot
    local screens = boot and boot.screens or {}
    Screens.push(self.game, screens.options or "OptionsMenu")
  elseif item.key == "exit" then
    -- back to the game list, not out of the process -- see
    -- Game:returnToLauncher
    self.game:returnToLauncher()
  elseif item.onSelect then
    item.onSelect()
  end
end

-- Reported from play: "the ... main menu intro music/sounds arent playing".
-- The rows moved and chose in silence.  Every other Emerald menu in this port
-- plays SE_SELECT on a press -- the START menu, the bag -- and this one, which
-- is the first menu anybody sees, played nothing at all.
local function menuBeep(self)
  pcall(function()
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end)
end

function Gen3MainMenu:update(dt)
  local input = self.game.input
  if self.info then
    -- the continue panel: A loads, B goes back to the rows
    if input:wasPressed("a") then
      menuBeep(self)
      self.info = nil
      if self.onContinue then self.onContinue() end
    elseif input:wasPressed("b") then
      menuBeep(self)
      self.info = nil
    end
    return
  end
  local n = #self.items
  if n == 0 then return end
  if input:wasPressed("down") then
    self.index = self.index % n + 1
    menuBeep(self)
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
    menuBeep(self)
  elseif input:wasPressed("a") then menuBeep(self) self:choose()
  elseif input:wasPressed("b") then menuBeep(self) self:close()
  end
end

-- PLAYER / BADGES / POKéDEX / TIME, in the words the cartridge's save panel
-- uses -- the same run the START menu's save flow reads.
function Gen3MainMenu:infoRows(save)
  local game = self.game
  local words = ((game.data.constants or {}).gen3Screens or {}).saveInfo
  words = words and words.items or { Strings("PLAYER"), Strings("POKéDEX"),
                                     Strings("TIME"), Strings("BADGES") }
  local badges = 0
  local okBadges, Badges = pcall(require, "src.inventory.Badges")
  if okBadges then
    local ok, count = pcall(Badges.count, game.data, save)
    badges = (ok and tonumber(count)) or 0
  end
  local owned = 0
  for _ in pairs((save.pokedex or {}).owned or {}) do owned = owned + 1 end
  local t = math.floor(require("src.core.SaveData").playSeconds(save))
  return {
    { words[1] or "PLAYER", (save.player and save.player.name) or "PLAYER" },
    { words[4] or "BADGES", tostring(badges) },
    { words[2] or "POKéDEX", tostring(owned) },
    { words[3] or "TIME",
      ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60) },
  }
end

-- ---------------------------------------------------------------------------
-- FIRERED'S MAIN MENU (pokefirered src/main_menu.c)
--
-- Wide white windows 24 tiles across at tile column 3 on a light-blue field:
-- CONTINUE is ten rows tall and prints PLAYER / POKeDEX / TIME / BADGES in the
-- player's gender colour, every other row is two.  There is no cursor -- the
-- chosen window is the one left undimmed (WIN0 over it, BLDY 7 darken
-- outside).  OPTION and EXIT GAME are this port's rows, laid out the same way.
-- ---------------------------------------------------------------------------
local FRLG_BG = { 139 / 255, 148 / 255, 1 }
local FRLG_INK, FRLG_SHADOW = { 98 / 255, 98 / 255, 98 / 255 }, { 213 / 255, 213 / 255, 205 / 255 }
local FRLG_BOY, FRLG_GIRL = { 33 / 255, 132 / 255, 1 }, { 1, 24 / 255, 173 / 255 }

-- WHAT FITS ON A 160-PIXEL SCREEN.
--
-- Twenty tile rows, and every window draws a border row above and below
-- itself -- so the stack runs from `top - 1` down to
-- `top + total + (n - 1) * gap`, and that last row has to be 19 or less.
--
-- The cartridge's own look is a two-row gap and sixteen pixels between the
-- CONTINUE panel's four lines, and it has room for that because its menu is
-- three windows.  A launcher build shows FOUR -- EXIT GAME is ours, not the
-- cartridge's -- and four at those sizes wants twenty-one rows.  The old
-- fixed layout simply ran off the bottom: the last window's lower border
-- landed on row 20 and was never drawn.
--
-- So the spacing is chosen rather than fixed, widest first, closing the gap
-- before tightening the panel.  Three windows keep the cartridge's exact
-- layout; four sit one row closer with two pixels less leading.
local FRLG_LINE_STEPS = { 16, 14, 12 }
local FRLG_GAPS = { 2, 1 }
local FRLG_LAST_ROW = 19

-- The CONTINUE panel is its label plus four lines at `step`, and the lines
-- start 18px down: 26 + 3 * step pixels of content, in whole tiles.
local function frlgPanelRows(step)
  return math.ceil((26 + 3 * step) / 8)
end

function Gen3MainMenu:frlgWindows()
  local n = #self.items
  local function rowsFor(step)
    local total = 0
    for _, item in ipairs(self.items) do
      total = total + (item.key == "continue" and frlgPanelRows(step) or 2)
    end
    return total
  end
  local step, gap = FRLG_LINE_STEPS[1], FRLG_GAPS[1]
  local fitted = false
  for _, s in ipairs(FRLG_LINE_STEPS) do
    for _, g in ipairs(FRLG_GAPS) do
      if not fitted and 1 + rowsFor(s) + (n - 1) * g <= FRLG_LAST_ROW then
        step, gap, fitted = s, g, true
      end
    end
  end
  -- Nothing fitted only if a mod has added rows past what the screen holds;
  -- the tightest layout is still the best answer, and the rows past the
  -- bottom are that mod's problem rather than a silently broken menu.
  local wins, top = { step = step }, 1
  for i, item in ipairs(self.items) do
    local h = item.key == "continue" and frlgPanelRows(step) or 2
    wins[i] = { tx = 3, ty = top, tw = 24, th = h }
    top = top + h + gap
  end
  return wins
end

local function frlgText(text, x, y, ink)
  local two = Font.beginTwoTone(ink, FRLG_SHADOW)
  if not two then love.graphics.setColor(ink[1], ink[2], ink[3], 1) end
  Font.draw(text, x, y)
  if two then Font.endTwoTone() end
end

function Gen3MainMenu:drawFireRed()
  local g = love.graphics
  local width = select(1, self:uiSize())
  g.setColor(FRLG_BG[1], FRLG_BG[2], FRLG_BG[3], 1)
  g.rectangle("fill", 0, 0, width, GBA_H)
  g.setColor(1, 1, 1, 1)
  if self.frlgSave == nil then
    local ok, loaded = pcall(require("src.core.SaveData").load)
    self.frlgSave = ok and loaded or false
  end
  local save = self.frlgSave
  local wins = self:frlgWindows()
  for i, item in ipairs(self.items) do
    local w = wins[i]
    Font.drawBox(w.tx - 1, w.ty - 1, w.tw + 2, w.th + 2)
    local x, y = w.tx * 8, w.ty * 8
    frlgText(item.label, x + 2, y + 2, FRLG_INK)
    if item.key == "continue" and save then
      local rows = self:infoRows(save)
      local ink = (save.player and save.player.gender == "girl") and FRLG_GIRL or FRLG_BOY
      -- the cartridge's order: PLAYER, POKeDEX (once you have one), TIME, BADGES
      local order = { rows[1], rows[3], rows[4], rows[2] }
      local line = 0
      -- ...at whatever leading the window was sized for (frlgWindows)
      local step = wins.step or 16
      for _, row in ipairs(order) do
        if row then
          frlgText(row[1], x + 2, y + 18 + line * step, ink)
          frlgText(row[2], x + 62, y + 18 + line * step, ink)
          line = line + 1
        end
      end
    end
  end
  -- dim everything but the chosen window
  local sel = wins[self.index]
  if sel then
    local top = (sel.ty - 1) * 8 + 2
    local bottom = (sel.ty + sel.th + 1) * 8 - 2
    g.setColor(0, 0, 0, 7 / 16)
    g.rectangle("fill", 0, 0, width, top)
    g.rectangle("fill", 0, bottom, width, GBA_H - bottom)
    g.rectangle("fill", 0, top, 18, bottom - top)
    g.rectangle("fill", 222, top, width - 222, bottom - top)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3MainMenu:draw()
  if GameVersion.isFRLG() then return self:drawFireRed() end
  -- the plain field the cartridge clears to, not the title art: the menu is
  -- its own screen and nothing shows through it
  -- the plain field runs the whole width of whatever surface this is on, so a
  -- wide window is filled by the field rather than framed in black
  love.graphics.setColor(0.05, 0.11, 0.20, 1)
  love.graphics.rectangle("fill", 0, 0, select(1, Gen3Wide.uiSize()), GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  local glyphH = Font.glyphHeight()
  local inset = math.max(0, math.floor((ROW_STEP * 8 - glyphH) / 2))

  if self.info then
    Font.drawBox(INFO.tx, INFO.ty, INFO.tw, INFO.th)
    love.graphics.setColor(0, 0, 0, 1)
    local y = (INFO.ty + 1) * 8 + inset
    for _, row in ipairs(self:infoRows(self.info)) do
      Font.draw(row[1], (INFO.tx + 1) * 8, y)
      Font.draw(row[2], INFO_VALUE_X, y)
      y = y + ROW_STEP * 8
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- TOP-ANCHORED, unlike every Game Boy menu in this engine.  A pokered box
  -- hangs its choices off the BOTTOM interior row and lets the slack fall
  -- under the top edge; Emerald's main menu starts at the top and the box is
  -- cut to fit, which is what "the rows should start at the top of the box"
  -- means and what this does.
  local th = #self.items * ROW_STEP + 2
  Font.drawBox(BOX.tx, BOX.ty, BOX.tw, th)
  love.graphics.setColor(0, 0, 0, 1)
  for i, item in ipairs(self.items) do
    local y = (BOX.ty + 1 + (i - 1) * ROW_STEP) * 8 + inset
    Font.draw(item.label, (BOX.tx + 2) * 8, y)
    if i == self.index then
      Font.drawCode(Theme.cursor, (BOX.tx + 1) * 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3MainMenu
