-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE UNDERGROUND'S OWN MENU, which is how you are meant to leave.
--
-- Going down was built in pass 130 and coming back up was a DELIBERATE
-- DEVIATION: the Explorer Kit doubled as the way out, because on the cartridge
-- `CanUseExplorerKit` refuses the kit down here precisely because this menu is
-- what you use, and with neither the menu nor a substitute descending would
-- have been a softlock.  This is the menu, so that deviation can retire.
--
-- SEVEN OPTIONS, IN THE CARTRIDGE'S ORDER, which is `sUndergroundMenuOptions`
-- in pokeplatinum's `src/underground/menus.c`:
--
--   TRAPS  SPHERES  GOODS  TREASURES  <player's name>  GO UP  CLOSE
--
-- The order is not cosmetic.  GO UP is sixth of seven, and a port that dropped
-- the four it cannot serve yet would move it to second and put the one option
-- that matters under a different finger.
--
-- THE LABELS ARE THE CARTRIDGE'S, read out of message bank 634 at indices
-- 121..127 -- the same bank as "{STRVAR_1 3 0 0} has left the underground
-- tunnels." -- rather than typed in English here.  A port that hardcodes
-- "GO UP" is a port that shows English on a Japanese cartridge.
--
-- ...AND THE FIFTH IS NOT A LABEL AT ALL.  Bank 634 index 125 is
-- `{STRVAR_1 1 1 0}`, a string variable, because the row is the PLAYER'S OWN
-- NAME.  pret has the branch in as many words: that one entry goes through
-- `StringList_AddFromString` while the other six go through
-- `StringList_AddFromMessageBank`.  Substituted here; left as the raw variable
-- it would read "{STRVAR_1 1 1 0}" on screen.
--
-- WHAT IS AND IS NOT WIRED.  GO UP and CLOSE work.  The other five have no
-- subsystem behind them -- `Gen4Underground`'s own header says spheres, traps,
-- secret bases and the vendors are not built -- so they REFUSE, by name, with a
-- line saying which. They are not silent no-ops: a menu row that swallows a tap
-- is indistinguishable from a broken one, and this port has shipped that bug
-- before.
--
-- IT TAKES A FINGER AS WELL AS A BUTTON.  The Underground is the one place in
-- Platinum where the FIELD is on the touch screen -- which is why
-- `menus.c` builds this window on `BG_LAYER_MAIN_3` while `top_screen.c` uses
-- the SUB layers for the radar -- so a tap has to work. Rows are rectangles and
-- `_layout` below is PUBLISHED so a check can compute those rectangles for
-- itself instead of asking this file where it thinks they are; asking the
-- subject is how the launcher's grid check passed a consistently wrong layout.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Gen4Text = require("src.import.Gen4Text")
local Gen4Underground = require("src.world.Gen4Underground")

local Gen4UndergroundMenu = {}
Gen4UndergroundMenu.__index = Gen4UndergroundMenu

local W, H = 256, 192

-- The message bank and the seven entries in it, which is the whole of this
-- menu's text.  `player` marks the one that is a string variable rather than a
-- label; `id` is what `select` dispatches on, so a reorder cannot silently
-- rewire the actions.
Gen4UndergroundMenu.BANK = 634
Gen4UndergroundMenu.OPTIONS = {
  { id = "traps",     entry = 121 },
  { id = "spheres",   entry = 122 },
  { id = "goods",     entry = 123 },
  { id = "treasures", entry = 124 },
  { id = "trainer",   entry = 125, player = true },
  { id = "go_up",     entry = 126 },
  { id = "close",     entry = 127 },
}

-- WHAT EACH UNSERVED ROW IS WAITING FOR, named rather than lumped under one
-- "not implemented".  Four different subsystems, and saying which keeps the
-- refusal useful to whoever reads the log.
Gen4UndergroundMenu.UNSERVED = {
  traps     = "the trap inventory is not built",
  spheres   = "the sphere inventory is not built",
  goods     = "the goods inventory is not built",
  treasures = "the treasure inventory is not built",
  trainer   = "the Underground's trainer records are not built",
}

-- THE CARTRIDGE'S OWN GEOMETRY, out of the `Window_Add` call in `menus.c`:
--
--     Window_Add(..., BG_LAYER_MAIN_3, 20, 1, 11, NELEMS(...) * 3, 13, ...)
--
-- x 20, y 1, width 11 tiles, and a height of three tiles PER OPTION -- so the
-- row pitch is three tiles and the panel is exactly 7 * 3 of them.  The cursor
-- sprite sits at x 204, y 20 (`sSpriteTemplates[CURSOR_TEMPLATE]`), and 20 is
-- the first row's centre: panel top 8 plus half a 24px pitch.  Every number
-- here is read, not chosen.
Gen4UndergroundMenu._layout = {
  tile = 8,
  panelTileX = 20, panelTileY = 1, panelTileW = 11,
  rowTiles = 3,
  panelX = 20 * 8, panelY = 1 * 8, panelW = 11 * 8,
  pitch = 3 * 8,
  firstCentreY = 1 * 8 + (3 * 8) / 2,
  cursorX = 204,
  -- `Menu_New(&template, 28, 4, ...)`: the labels start 28px into the window
  -- and 4px down, one every 16px of font + `lineSpacing` 8 -- so x 188 and
  -- row tops 12 + 24 * i
  textX = 20 * 8 + 28,
  textY = 1 * 8 + 4,
  -- sSpriteTemplates[ICON_TEMPLATE]: the option icons at x 174, y 20 + 24 * i
  iconX = 174,
}

-- The rectangle option `i` occupies, derived from `_layout` alone so that the
-- same arithmetic is available to a check without calling into this file.
function Gen4UndergroundMenu.rowRect(i, count)
  local L = Gen4UndergroundMenu._layout
  count = count or #Gen4UndergroundMenu.OPTIONS
  if type(i) ~= "number" or i < 1 or i > count then return nil end
  return L.panelX, L.panelY + (i - 1) * L.pitch, L.panelW, L.pitch
end

-- Which option a local point lands on, or nil.
function Gen4UndergroundMenu.rowAt(x, y, count)
  count = count or #Gen4UndergroundMenu.OPTIONS
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  for i = 1, count do
    local rx, ry, rw, rh = Gen4UndergroundMenu.rowRect(i, count)
    if x >= rx and x < rx + rw and y >= ry and y < ry + rh then return i end
  end
  return nil
end

-- ----------------------------------------------------------------- labels --

local function playerName(game)
  local save = game and game.save
  local name = save and (save.playerName or save.name)
  if type(name) == "string" and name ~= "" then return name end
  return "PLAYER"
end

function Gen4UndergroundMenu:labelFor(option)
  if option.player then return playerName(self.game) end
  local data = self.game and self.game.data
  -- `resolve`, NOT A RAW `data.text` LOOKUP.  A row read straight out of the
  -- table prints whatever control markup the entry carries -- `{WAIT 3}` and
  -- a dangling wait among them -- because nothing has run `gen4Markup` over
  -- it, and this reached a menu row rather than a text box, which is the one
  -- place `show_text` would have done it on the way past.
  local line = Gen4Text.resolve(data, Gen4UndergroundMenu.BANK, option.entry,
                                self.game)
  if type(line) == "string" and line ~= "" then return line end
  -- NO ENGLISH FALLBACK.  A missing bank entry is a broken import, and showing
  -- a hardcoded word would hide it behind something that looks right.
  Logger.warn("gen4 underground menu: bank %d entry %d is missing, so a row "
                .. "has no label", Gen4UndergroundMenu.BANK, option.entry)
  return nil
end

-- ------------------------------------------------------------------- life --

function Gen4UndergroundMenu:uiSize() return W, H end
function Gen4UndergroundMenu:wantsFillScale() return true end
function Gen4UndergroundMenu:wantsEdgeBleed() return false end

function Gen4UndergroundMenu.new(game, opts)
  local self = setmetatable({}, Gen4UndergroundMenu)
  self.game = game
  self.opts = opts or {}
  self.index = 1
  self.rows = {}
  for _, option in ipairs(Gen4UndergroundMenu.OPTIONS) do
    self.rows[#self.rows + 1] = {
      id = option.id, entry = option.entry, player = option.player,
      label = self:labelFor(option),
    }
  end
  self.message = nil
  return self
end

function Gen4UndergroundMenu:close()
  local onCancel = self.opts.onCancel
  self.game.stack:pop()
  if type(onCancel) == "function" then onCancel() end
end

-- ------------------------------------------------------------------ doing --

function Gen4UndergroundMenu:activate(i)
  local row = self.rows[i]
  if not row then return false end
  if row.id == "close" then
    self:close()
    return true
  end
  if row.id == "go_up" then
    local ow = self.game and self.game.overworld
    local ok, why = Gen4Underground.leave(self.game, ow)
    if ok then
      -- the warp is already running; the menu must not sit over the trip
      self.game.stack:pop()
      return true
    end
    -- A refusal here is worth showing: "nothing remembers where you came down"
    -- is a save that cannot climb out, and silence would read as a dead button.
    self.message = tostring(why or "cannot go up from here")
    Logger.warn("gen4 underground menu: go up refused -- %s", self.message)
    return false
  end
  local waiting = Gen4UndergroundMenu.UNSERVED[row.id]
  if waiting then
    self.message = waiting
    Logger.info("gen4 underground menu: %s is not available yet -- %s",
                tostring(row.label or row.id), waiting)
    return false
  end
  return false
end

function Gen4UndergroundMenu:update()
  local input = self.game and self.game.input
  if not input then return end
  local count = #self.rows
  if count == 0 then return self:close() end
  if input:wasPressed("up") then
    self.index = (self.index - 2) % count + 1
    self.message = nil
  elseif input:wasPressed("down") then
    self.index = self.index % count + 1
    self.message = nil
  elseif input:wasPressed("a") then
    self:activate(self.index)
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

-- THE MAIN SCREEN'S OWN POINTER MAPPING, not `SecondScreen.toLocal`. That one
-- answers nil unless the second screen is the one being drawn, which is right
-- for the mining minigame (second-screen only) and wrong here: this menu is on
-- the main screen, so the presentation rect is what converts a press.
local function toLocal(px, py)
  local ok, Renderer = pcall(require, "src.render.Renderer")
  local r = ok and Renderer and Renderer.uiPresentation or nil
  if not r or not r.scaleX or r.scaleX == 0 or r.scaleY == 0 then return nil end
  if px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then
    return nil
  end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

-- A press is OURS whether or not it landed on a row: this panel is modal, and
-- letting a miss fall through would move the player underneath the menu.
function Gen4UndergroundMenu:touchpressed(_, px, py)
  local x, y = toLocal(px, py)
  if not x then return true end
  local i = Gen4UndergroundMenu.rowAt(x, y, #self.rows)
  if not i then return true end
  self.index = i
  self.message = nil
  self:activate(i)
  return true
end

-- ------------------------------------------------------------------- draw --

-- a sprite from `gen4_menu_art` (src/import/Gen4MenuArt.lua) and its record
local artImages = {}
function Gen4UndergroundMenu.art(game, key)
  local index = game and game.data and game.data.gen4_menu_art
  local rec = index and index[key]
  if type(rec) ~= "table" or type(rec.path) ~= "string" then return nil end
  if artImages[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    artImages[rec.path] = ok and img or false
    if artImages[rec.path] then artImages[rec.path]:setFilter("nearest", "nearest") end
  end
  return artImages[rec.path] or nil, rec
end

function Gen4UndergroundMenu:draw()
  local g = love.graphics
  local L = Gen4UndergroundMenu._layout
  local count = #self.rows

  Font.drawBox(L.panelTileX, L.panelTileY, L.panelTileW, count * L.rowTiles)

  for i, row in ipairs(self.rows) do
    local centre = L.firstCentreY + (i - 1) * L.pitch
    local selected = (i == self.index)
    if selected then
      -- the start menu's cursor sprite (menu_gra cursor, underground_menu.NCLR
      -- row 1), at x 204, y 20 + 24 * pos: a 96x32 cell from (-48, -16)
      local cursor, rec = Gen4UndergroundMenu.art(self.game, "ug_cursor")
      if cursor then
        g.setColor(1, 1, 1, 1)
        g.draw(cursor, L.cursorX + (rec.originX or -48), centre + (rec.originY or -16))
      else
        g.setColor(0.98, 0.83, 0.30, 0.55)
        local rx, ry, rw, rh = Gen4UndergroundMenu.rowRect(i, count)
        g.rectangle("fill", rx + 2, ry + 2, rw - 4, rh - 4)
        g.setColor(1, 1, 1, 1)
      end
    end
    -- the option's icon: colour (palette row 1) on the cursor's row, grey
    -- (row 0) elsewhere -- the first frame of animation option * 3
    local icon, irec = Gen4UndergroundMenu.art(self.game,
      ("ug_icon_%d_%s"):format(i - 1, selected and "colour" or "grey"))
    if icon then
      g.setColor(1, 1, 1, 1)
      g.draw(icon, L.iconX + (irec.originX or -16), centre + (irec.originY or -16))
    end
    -- An unserved row is drawn dimmed, so the refusal is visible before the
    -- tap rather than only after it.
    local dim = Gen4UndergroundMenu.UNSERVED[row.id] ~= nil
    if dim then g.setColor(0.60, 0.60, 0.60, 1) end
    Font.draw(row.label or "?", L.textX, L.textY + (i - 1) * L.pitch)
    if dim then g.setColor(1, 1, 1, 1) end
  end

  if self.message then
    Font.drawBox(1, 20, 30, 4)
    Font.draw(self.message, 16, 168)
  end
end

return Gen4UndergroundMenu
