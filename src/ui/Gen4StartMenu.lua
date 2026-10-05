-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's START MENU, and the second half of the original brief:
--
--   "instead of showing the start menu on the bottom screen have a start menu
--    on the main screen like the other games have the choice to switch between
--    the two styles."
--
-- BOTH STYLES, and the switch is a row on the OPTIONS screen rather than a boot
-- flag, so it can be changed mid-game:
--
--   MAIN    the menu is on the main screen, which is where Red through Emerald
--           put theirs.  Default, because it makes Platinum continuous with the
--           rest of this launcher's library and muscle memory carries over.
--   BOTTOM  the authentic arrangement.  It goes through `SecondScreen`, so on
--           the inset mode it appears in the corner panel and is clickable
--           there, and on swap it takes the window.
--
-- WHAT IS THE CARTRIDGE'S:
--
--   * THE ROWS AND THEIR ORDER, from `StartMenu_MakeOptionList` rather than
--     from the enum -- the two differ.  The list is built RETIRE, CHAT,
--     POKEDEX, POKEMON, BAG, TRAINER CASE, SAVE, OPTIONS, EXIT, each added only
--     if its hide flag is clear, so an ordinary field menu is the last seven.
--   * THE WORDS, bank 367.  TRAINER CASE's entry is a TEMPLATE and not a word
--     -- `{STRVAR_1 3, 0, 0}`, filled with the player's name -- so printing it
--     raw would put a control code on the menu.
--   * THE ICONS.  `animIdx = option * ICON_ANIM_COUNT` is the mapping, and a
--     FEMALE player's BAG is group 9, which is why the sheet has ten cells for
--     nine options.
--   * THE GEOMETRY: the panel at tile (20, 1), eleven tiles wide and three per
--     row; the icons centred at x = 174 and the cursor at x = 204, both at
--     y = 20 + 24 * i.
--
-- WHAT IS NOT: which rows are AVAILABLE.  Platinum hides a row behind a save
-- flag this port's Gen 4 save does not carry yet, so the Pokedex and party rows
-- are gated on the same conditions the engine's own start menu uses -- the dex
-- being handed over, and the party not being empty -- rather than on a flag
-- that would always read false and hide them forever.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local Gen4StartMenu = {}
Gen4StartMenu.__index = Gen4StartMenu

local W, H = 256, 192

-- Used when the cache carries no `startMenu` record: the same seven rows in the
-- same order, so a pre-`menus` cache gets a working menu with the engine's
-- words rather than an empty panel.
local FALLBACK_ROWS = {
  { id = "pokedex", label = "POKéDEX" },
  { id = "pokemon", label = "POKéMON" },
  { id = "bag", label = "BAG" },
  { id = "trainerCase", label = "", playerName = true },
  { id = "save", label = "SAVE" },
  { id = "options", label = "OPTIONS" },
  { id = "exit", label = "EXIT" },
}

local FALLBACK_LAYOUT = {
  panelX = 160, panelY = 8, panelW = 88, rowTiles = 3,
  pitch = 24, iconX = 174, cursorX = 204, firstY = 20,
}

function Gen4StartMenu:uiSize() return W, H end
function Gen4StartMenu:wantsFillScale() return true end
function Gen4StartMenu:wantsEdgeBleed() return false end

-- NOT opaque: the start menu sits over the world on every other version in this
-- launcher and it does here too, in both styles -- on `bottom` the world is
-- what the main screen is still showing.
Gen4StartMenu.isOpaque = false

function Gen4StartMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4StartMenu)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}

  local menus = (game.data or {}).gen4_menus or {}
  local record = menus.startMenu or {}
  self.layout = record.layout or FALLBACK_LAYOUT
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}

  local source = record.rows
  if not source or #source == 0 then
    Logger.warn("gen4 start menu: this cache carries no start-menu record -- "
                .. "falling back to the engine's own words")
    source = FALLBACK_ROWS
  end

  self.rows = {}
  -- DURING A SAFARI GAME the cartridge swaps its hide flags for
  -- `StartMenu_GetSafariHiddenOptions` -- SAVE and CHAT only -- so RETIRE,
  -- which the record marks hidden for the ordinary field, appears, and SAVE
  -- goes.
  self.safari = (game.save or {}).safari ~= nil
  for _, row in ipairs(source) do
    local hidden = row.hidden
    if self.safari then
      hidden = (row.id == "save" or row.id == "chat")
    end
    if not hidden and self:available(row.id) then
      self.rows[#self.rows + 1] = {
        id = row.id,
        label = self:labelFor(row),
        icon = self:iconFor(row),
      }
    end
  end
  self.index = 1
  return self
end

-- ------------------------------------------------------------------ rows --

-- Whether a row belongs on the menu at all.  See the header: Platinum's own
-- hide flags are not in this port's Gen 4 save, so these are the engine's
-- conditions, which answer the same questions.
function Gen4StartMenu:available(id)
  if id == "pokedex" then
    local ok, Flags = pcall(require, "src.script.Flags")
    if ok and Flags.hasPokedex then return Flags.hasPokedex(self.game.save) end
    return true
  end
  if id == "pokemon" then
    return #((self.game.save or {}).party or {}) > 0
  end
  return true
end

function Gen4StartMenu:labelFor(row)
  if row.playerName then
    local player = ((self.game.save or {}).player or {})
    return tostring(player.name or Strings("PLAYER"))
  end
  local label = row.label
  if type(label) ~= "string" or label == "" then return row.id:upper() end
  -- A leftover control code would print as braces; the only template on this
  -- menu is handled above, so anything still carrying one is a row this port
  -- does not know how to fill and its own name is the honest stand-in.
  if label:find("{") then return row.id:upper() end
  return label
end

-- THE FEMALE BAG IS A DIFFERENT ICON, which is one line in the cartridge and
-- would be a silently wrong picture here.
function Gen4StartMenu:iconFor(row)
  local index = row.icon
  if index == nil then return nil end
  if row.femaleIcon then
    local gender = ((self.game.save or {}).player or {}).gender
    if gender == "girl" or gender == "female" then index = row.femaleIcon end
  end
  return index
end

-- ---------------------------------------------------------------- pictures --

function Gen4StartMenu:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4StartMenu:icon(index)
  if index == nil then return nil end
  return self:img(("menu/icons_%02d"):format(index))
end

-- ------------------------------------------------------------------ input --

function Gen4StartMenu:style()
  local options = (self.game.save or {}).options or {}
  return (options.gen4StartMenuStyle == "bottom") and "bottom" or "main"
end

function Gen4StartMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4StartMenu:reopen()
  return function() Screens.push(self.game, "StartMenu") end
end

function Gen4StartMenu:select()
  local row = self.rows[self.index]
  if not row then return end
  local reopen = self:reopen()
  local id = row.id
  if id == "exit" then return self:close() end
  self.game.stack:pop()
  if id == "retire" then
    -- `StartMenu_SelectRetire`: SCRIPT_ID(SAFARI_GAME, 21) -- "Would you like
    -- to retire from the Safari Game?" and, on yes, back to the gate
    local ow = self.game.overworld
    local rows = require("src.world.Gen4TileScripts").compile(self.game.data, "safari_game", 21)
    if ow and rows then ow:queueScript(rows, { mapId = ow.map and ow.map.id }) end
    if self.onCancel then self.onCancel() end
    return
  end
  if id == "pokedex" then
    Screens.push(self.game, "PokedexMenu", { onCancel = reopen })
  elseif id == "pokemon" then
    Screens.push(self.game, "PartyMenu", { onCancel = reopen })
  elseif id == "bag" then
    Screens.push(self.game, "BagMenu", { onCancel = reopen })
  elseif id == "trainerCase" then
    Screens.push(self.game, "TrainerCard", { onCancel = reopen })
  elseif id == "options" then
    Screens.push(self.game, "OptionsMenu", { onCancel = reopen })
  elseif id == "save" then
    self:engineAction(Strings("SAVE"), reopen)
  else
    Logger.warn("gen4 start menu: '%s' has no screen yet", tostring(id))
    if self.onCancel then self.onCancel() end
  end
end

-- SAVE IS THE ENGINE'S, deliberately and not by omission.  It is the one row
-- with a consequence -- the panel, the confirmation, the "now saving" beat, the
-- write and the failure message -- and all of that already exists, correct, in
-- `StartMenu`.  Re-implementing it here would give this port two save flows
-- that can disagree, and the one that disagrees would be the one nobody tests.
--
-- So the row is fetched FROM the engine's own menu by its label and its action
-- is run.  If the engine's menu has no such row on this cartridge, that is said
-- rather than silently doing nothing on a keypress.
function Gen4StartMenu:engineAction(label, reopen)
  local ok, menu = pcall(require("src.ui.StartMenu").new, self.game)
  local item
  if ok and type(menu) == "table" then
    for _, candidate in ipairs(menu.items or {}) do
      if candidate.label == label then item = candidate break end
    end
  end
  if item and item.onSelect then
    -- The engine's rows re-open the ENGINE's start menu on cancel; this one
    -- has to come back here instead, which is what `reopen` is.
    local okRun, err = pcall(item.onSelect)
    if okRun then return end
    Logger.warn("gen4 start menu: the engine's '%s' row raised (%s)",
                tostring(label), tostring(err))
  else
    Logger.warn("gen4 start menu: the engine's start menu has no '%s' row on "
                .. "this cartridge", tostring(label))
  end
  if reopen then reopen() end
end

function Gen4StartMenu:update()
  local input = self.game.input
  if not input then return end
  local count = #self.rows
  if count == 0 then return self:close() end
  if input:wasPressed("up") then
    self.index = (self.index - 2) % count + 1
  elseif input:wasPressed("down") then
    self.index = self.index % count + 1
  elseif input:wasPressed("a") then
    self:select()
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

function Gen4StartMenu:drawPanel()
  local g = love.graphics
  local L = self.layout
  local rows = #self.rows
  local h = rows * L.pitch + 8

  Font.drawBox(math.floor(L.panelX / 8), math.floor(L.panelY / 8),
               math.floor(L.panelW / 8), rows * L.rowTiles)

  for i, row in ipairs(self.rows) do
    local y = L.firstY + (i - 1) * L.pitch
    local selected = (i == self.index)

    -- The cursor first: on hardware it is a sprite behind the row, and drawing
    -- it after the label would cover the label.
    if selected then
      local cursor = self:img("menu/cursor")
      if cursor then
        local cw, ch = cursor:getDimensions()
        g.setColor(1, 1, 1, 1)
        g.draw(cursor, L.cursorX - cw / 2, y - ch / 2)
      else
        g.setColor(0.98, 0.83, 0.30, 0.55)
        g.rectangle("fill", L.panelX + 4, y - 10, L.panelW - 8, 20)
        g.setColor(1, 1, 1, 1)
      end
    end

    local icon = self:icon(row.icon)
    if icon then
      local iw, ih = icon:getDimensions()
      -- Grey when it is not the row you are on, colour when it is: the
      -- cartridge swaps the sprite's palette (PALETTE_GRAYSCALE /
      -- PALETTE_COLORED) rather than its picture, and one composed picture is
      -- all this port has, so the difference is carried in the tint.
      if selected then g.setColor(1, 1, 1, 1) else g.setColor(0.62, 0.64, 0.68, 1) end
      g.draw(icon, L.iconX - iw / 2, y - ih / 2)
      g.setColor(1, 1, 1, 1)
    end

    local label = row.label or ""
    local width = Font.width(label)
    -- Right-aligned into the panel, clear of the icon column: the icons are
    -- centred at 174 and the panel ends at panelX + panelW, so the words sit in
    -- what is left rather than on top of the pictures.
    local right = L.panelX + L.panelW - 6
    local x = right - width
    local floor = L.iconX + 14
    if x < floor then x = floor end
    Font.draw(label, x, y - 6)
  end
  g.setColor(1, 1, 1, 1)
end

-- THE BALL COUNT (`StartMenu_PrintBallCount`): a 12x4-tile window at tile
-- (1, 1) while a Safari Game runs -- "SAFARI BALLS" over "Stock: NN".
function Gen4StartMenu:drawBallCount()
  local st = (self.game.save or {}).safari
  if not st then return end
  local text = (self.game.data or {}).text or {}
  Font.drawBox(1, 1, 12, 4)
  local title = text.TEXT_B0367_00009 or "SAFARI BALLS"
  local stock = (text.TEXT_B0367_00011 or "Stock: {N}")
    :gsub("{[^}]*}", ("%d"):format(st.balls or 0), 1)
  Font.draw(title, 16, 16)
  Font.draw(stock, 16, 32)
end

function Gen4StartMenu:draw()
  if self:style() == "bottom" and SecondScreen.mode(self.game) ~= "off" then
    -- The authentic arrangement, through the second-screen surface -- so on
    -- `inset` the menu is in the corner panel and on `swap` it takes the
    -- window, and this file does not have to know which.
    SecondScreen.drawFrame(self.game)
    return SecondScreen.draw(self.game, function() self:drawPanel() end)
  end
  self:drawPanel()
  self:drawBallCount()
end

return Gen4StartMenu
