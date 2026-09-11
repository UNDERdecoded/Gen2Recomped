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

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the menu sits in the top-left, each row two
-- tiles apart, and the info panel fills the screen under it.
local BOX = { tx = 0, ty = 0, tw = 15 }
local ROW_STEP = 2
local INFO = { tx = 0, ty = 0, tw = 20, th = 12 }
local INFO_VALUE_X = 112

function Gen3MainMenu:uiSize() return GBA_W, GBA_H end
function Gen3MainMenu:wantsFillScale() return true end

function Gen3MainMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
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
  if item.key == "continue" then
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
    if love.event and love.event.quit then love.event.quit() end
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
  local t = math.floor(tonumber(save.playTime) or 0)
  return {
    { words[1] or "PLAYER", (save.player and save.player.name) or "PLAYER" },
    { words[4] or "BADGES", tostring(badges) },
    { words[2] or "POKéDEX", tostring(owned) },
    { words[3] or "TIME",
      ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60) },
  }
end

function Gen3MainMenu:draw()
  -- the plain field the cartridge clears to, not the title art: the menu is
  -- its own screen and nothing shows through it
  love.graphics.setColor(0.05, 0.11, 0.20, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
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
