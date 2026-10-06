-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's main menu.
--
-- Not a box on the title: a screen of its own, the way the cartridge draws it.
-- Each option is a WINDOW -- x = 3, width 26 tiles, the first at y = 1, the
-- next `height + 2` below it -- and CONTINUE's window is five lines tall
-- because it carries the save summary inside it rather than opening a panel.
-- All of that is `sOptions` and the loop in main_menu.c, carried in
-- Gen4Menus and written into the cache by the `menus` stage.
--
-- THE WORDS ARE THE CARTRIDGE'S.  Bank 550 gives CONTINUE, NEW GAME, PLAYER,
-- TIME, BADGES and POKéDEX, and the menus stage writes them out already
-- resolved, so this file has no English of its own to fall back to and no bank
-- lookup to do.  Where a row has no cartridge string -- OPTION, which Platinum
-- does not have on this menu at all -- the record says `fromCartridge = false`
-- and carries the label this port chose.
--
-- WHY OPTION IS HERE ANYWAY.  On the DS, text speed and the message frame live
-- in the in-game START menu, so a player who has not started a game has nowhere
-- to set them.  Every other title this engine boots offers the row before the
-- first save exists; leaving Platinum without it would make it the only one
-- that could not be configured until after NEW GAME.
--
-- THE DEX ROW IS SKIPPED, NOT BLANKED.  RenderContinueOption `continue`s past
-- it while the Pokedex has not been obtained, which closes the gap rather than
-- leaving an empty line -- so the summary is four rows or three, never four
-- with a hole.

local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4MainMenu = {}
Gen4MainMenu.__index = Gen4MainMenu
Gen4MainMenu.isOpaque = true

local W, H = 256, 192

-- The fallbacks, used only where the cache carries no `menus` record -- a
-- Platinum cache extracted before that stage existed.  They are this file's
-- own words and are deliberately the plainest possible: a wrong-looking menu
-- that says CONTINUE beats a right-looking one with blank rows.
local FALLBACK = {
  layout = { optionX = 3, optionWidth = 26, firstY = 1, gap = 2,
             lineTiles = 2, linePixels = 16, margin = 32 },
  colors = { background = { 0.39, 0.39, 1 }, unfocused = { 0.84, 0.84, 0.84 } },
  rows = {
    { id = "continue", lines = 5, label = "CONTINUE" },
    { id = "newGame", lines = 1, label = "NEW GAME" },
    { id = "options", lines = 1, label = "OPTION" },
  },
  continueRows = {
    { label = "PLAYER", value = "playerName" },
    { label = "TIME", value = "playTime" },
    { label = "BADGES", value = "badgeCount" },
    { label = "POKéDEX", value = "seenCount", needsPokedex = true },
  },
}

function Gen4MainMenu:uiSize() return W, H end
function Gen4MainMenu:wantsFillScale() return true end
function Gen4MainMenu:wantsEdgeBleed() return false end

function Gen4MainMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

-- Is there a save on disk?  The active version's own file, which is what every
-- other screen in this engine asks and what decides whether CONTINUE exists.
local function saveOnDisk()
  local ok, info = pcall(function()
    local name = require("src.core.SaveData").saveFilename(GameVersion.get())
    return love.filesystem and love.filesystem.getInfo
       and love.filesystem.getInfo(name) or nil
  end)
  return ok and info ~= nil
end

local function sameItems(_, items) return items end

function Gen4MainMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4MainMenu)
  self.game = game
  self.onNewGame, self.onContinue, self.onCancel =
    opts.onNewGame, opts.onContinue, opts.onCancel
  self.index = 1

  local rec = (game.data and game.data.gen4_menus) or {}
  self.layout = rec.layout or FALLBACK.layout
  self.colors = rec.colors or FALLBACK.colors
  self.continueRows = rec.continueRows or FALLBACK.continueRows

  local haveSave = saveOnDisk()
  local items = {}
  for _, row in ipairs(rec.rows or FALLBACK.rows) do
    -- CONTINUE is the one row the cartridge itself withholds: with no save
    -- there is nothing for it to summarise, and pressing it would load a file
    -- that is not there.
    if row.id ~= "continue" or haveSave then
      items[#items + 1] = {
        key = row.id,
        label = row.label or Strings(row.id:upper()),
        lines = row.lines or 1,
      }
    end
  end
  -- The launcher's own row, as on every other title: without it Platinum would
  -- be the one game with no way back to the game list.
  items[#items + 1] = { key = "exit", label = Strings("EXIT GAME"), lines = 1 }

  local hooked = Runtime.call("ui.title_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.title_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  self.items = items
  self.save = haveSave and self:loadSummary() or nil
  return self
end

-- The save, read once, for the CONTINUE window's summary.  A failure here is
-- not fatal: the row still exists and still loads; it simply shows no figures.
function Gen4MainMenu:loadSummary()
  local ok, loaded = pcall(require("src.core.SaveData").load)
  return (ok and loaded) or nil
end

function Gen4MainMenu:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

local function beep(self)
  pcall(function()
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end)
end

function Gen4MainMenu:choose()
  local item = self.items[self.index]
  if not item then return end
  if item.onSelect and not item.key then
    self.game.stack:pop()
    return item.onSelect()
  end
  if item.key == "continue" then
    if self.onContinue then self.onContinue() end
  elseif item.key == "newGame" then
    if self.onNewGame then self.onNewGame() end
  elseif item.key == "options" then
    local boot = self.game.data.field and self.game.data.field.boot
    local screens = boot and boot.screens or {}
    Screens.push(self.game, screens.options or "OptionsMenu")
  elseif item.key == "exit" then
    self.game:returnToLauncher()
  elseif item.onSelect then
    item.onSelect()
  end
end

-- FocusNextOption: the focus STOPS at either end of the list (no wrap), and
-- only a move that lands somewhere new makes a sound.
function Gen4MainMenu:update(dt)
  dt = dt or 1 / 60
  self.t = (self.t or 0) + dt
  self:scrollStep(dt)
  local input = self.game.input
  if not input then return end
  local n = #self.items
  if n == 0 then return end
  if input:wasPressed("down") then
    if self.index < n then self.index = self.index + 1; beep(self) end
    self:targetScroll()
  elseif input:wasPressed("up") then
    if self.index > 1 then self.index = self.index - 1; beep(self) end
    self:targetScroll()
  elseif input:wasPressed("a") then
    beep(self)
    self:choose()
  elseif input:wasPressed("b") then
    beep(self)
    self:close()
  end
end

-- ------------------------------------------------------------------- draw --

-- The four figures the CONTINUE window shows, by the key the cache names.
-- Each is derived here rather than stored, so a row the cache adds later can
-- be answered without this table changing shape.
function Gen4MainMenu:value(key)
  local save = self.save
  if not save then return "" end
  if key == "playerName" then
    return tostring((save.player and save.player.name) or "")
  elseif key == "playTime" then
    local seconds = 0
    local ok, n = pcall(require("src.core.SaveData").playSeconds, save)
    if ok and tonumber(n) then seconds = math.floor(n) end
    return ("%d:%02d"):format(math.floor(seconds / 3600),
                              math.floor(seconds / 60) % 60)
  elseif key == "badgeCount" then
    local ok, Badges = pcall(require, "src.inventory.Badges")
    if not ok then return "0" end
    local got, count = pcall(Badges.count, self.game.data, save)
    return tostring((got and tonumber(count)) or 0)
  elseif key == "seenCount" then
    local n = 0
    for _ in pairs((save.pokedex or {}).seen or {}) do n = n + 1 end
    if n == 0 then
      for _ in pairs((save.pokedex or {}).owned or {}) do n = n + 1 end
    end
    return tostring(n)
  end
  return ""
end

function Gen4MainMenu:hasPokedex()
  local dex = self.save and self.save.pokedex
  if not dex then return false end
  if next(dex.seen or {}) ~= nil then return true end
  return next(dex.owned or {}) ~= nil
end

-- ------------------------------------------------------------ the windows --
--
-- THE FOCUSED OPTION IS A DIFFERENT WINDOW, NOT A CURSOR.  RenderOptionsFrames
-- draws the focused option in STANDARD_WINDOW_FIELD's frame (palette 3, whose
-- colour 6 DoColorCycleStep rewrites every frame from
-- sFocusedOptionBorderColors) over white paper, and every other option in
-- STANDARD_WINDOW_SYSTEM's frame over grey paper (UNFOCUSED_OPTION_BG_COLOR in
-- colour 15 of palette 1).  There is no arrow anywhere on the screen; the old
-- one was this port's.  The pictures are Gen4MainMenuArt's (`gen4_main_menu_art`)
-- and the colours its `gen4_main_menu_ink`; a cache without them draws the
-- engine's own frame and keeps the arrow, so focus is still visible.

local function art(self, key)
  local rec = ((self.game.data or {}).gen4_main_menu_art or {})[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil, {} end
  self.images = self.images or {}
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil, type(rec) == "table" and rec or {}
end

local function rgb(c) return { c[1] / 255, c[2] / 255, c[3] / 255 } end

function Gen4MainMenu:ink()
  return (self.game.data or {}).gen4_main_menu_ink
end

-- a 24 x 24 nine-slice around the content rect (tx, ty, tw, th), in pixels
-- already scrolled by `oy`
local function nineSlice(self, img, tx, ty, tw, th, oy)
  local g = love.graphics
  local iw, ih = img:getDimensions()
  self.quads = self.quads or {}
  local function q(i)
    local key = tostring(img) .. i
    if not self.quads[key] then
      self.quads[key] = g.newQuad((i % 3) * 8, math.floor(i / 3) * 8, 8, 8, iw, ih)
    end
    return self.quads[key]
  end
  local x0, y0 = (tx - 1) * 8, (ty - 1) * 8 - oy
  local x1, y1 = (tx + tw) * 8, (ty + th) * 8 - oy
  g.draw(img, q(0), x0, y0); g.draw(img, q(2), x1, y0)
  g.draw(img, q(6), x0, y1); g.draw(img, q(8), x1, y1)
  for i = 0, tw - 1 do
    g.draw(img, q(1), (tx + i) * 8, y0); g.draw(img, q(7), (tx + i) * 8, y1)
  end
  for j = 0, th - 1 do
    g.draw(img, q(3), x0, (ty + j) * 8 - oy); g.draw(img, q(5), x1, (ty + j) * 8 - oy)
  end
end

-- The focused border's colour this frame: one step of the 28-colour cycle per
-- frame (MainMenu_Main calls DoColorCycleStep every frame).
function Gen4MainMenu:borderColour()
  local ink = self:ink()
  local cycle = ink and ink.borderCycle
  if type(cycle) ~= "table" or #cycle == 0 then return nil end
  local step = math.floor((self.t or 0) * 60) % #cycle + 1
  return cycle[step]
end

-- the windows' tops in tiles, `height + 2` apart from y = 1 (RenderOptions)
function Gen4MainMenu:tops()
  local L = self.layout
  local tops, ty = {}, L.firstY
  for i, item in ipairs(self.items) do
    tops[i] = ty
    ty = ty + (item.lines or 1) * L.lineTiles + L.gap
  end
  return tops
end

-- TargetFocusedOptionForScroll, in pixels: scroll up to a window whose top
-- (frame included) is above the view, or down until a window whose top is
-- below the view's bottom has its frame's bottom on the bottom edge.
function Gen4MainMenu:targetScroll()
  local L = self.layout
  local tops = self:tops()
  local item = self.items[self.index]
  if not (item and tops[self.index]) then return end
  local top = (tops[self.index] - 1) * 8
  local height = ((item.lines or 1) * L.lineTiles + 2) * 8
  local target = self.scrollTarget or 0
  if target > top then target = top end
  if target + H <= top then target = top + height - H end
  self.scrollTarget = target
  self.scrollPos = self.scrollPos or 0
end

-- DoScrollStep: a quarter of the distance a frame, at most 12 pixels
function Gen4MainMenu:scrollStep(dt)
  local target = self.scrollTarget or 0
  local pos = self.scrollPos or 0
  if pos == target then return end
  self.scrollAcc = (self.scrollAcc or 0) + dt * 60
  while self.scrollAcc >= 1 and pos ~= target do
    self.scrollAcc = self.scrollAcc - 1
    local speed = (target - pos) / 4
    if speed > 12 then speed = 12 elseif speed < -12 then speed = -12 end
    pos = pos + speed
    if math.abs(target - pos) < 1 / 8 then pos = target end
  end
  if pos == target then self.scrollAcc = 0 end
  self.scrollPos = pos
end

-- `tx, ty, tw` are the window's CONTENT rect, which is what the cartridge's
-- own coordinates are in: RenderContinueOption prints at x = 32 and
-- y = TEXT_LINES(i) INSIDE the window, and the frame is drawn outside it.
-- The words AND the figures are in the player's colours -- TEXT_COLOR(7, 8,
-- 15) for a boy, (3, 4, 15) for a girl.
function Gen4MainMenu:drawContinue(tx, ty, tw, oy)
  local L = self.layout
  local left = tx * 8
  local right = (tx + tw) * 8
  local ink = self:ink()
  local player = self.save and self.save.player or {}
  local female = player.gender == "female" or player.gender == "girl" or player.gender == 1
  local pair = ink and (female and ink.female or ink.male)
  if pair then Font.pushStyle({ text = rgb(pair[1]), shadow = rgb(pair[2]) }) end
  -- Line 0 is the word CONTINUE itself, printed by the caller; the summary
  -- starts on line 1, exactly as the cartridge's loop does.
  local line = 1
  for _, row in ipairs(self.continueRows) do
    if not (row.needsPokedex and not self:hasPokedex()) then
      local value = self:value(row.value)
      local y = ty * 8 + line * L.linePixels - oy
      Font.draw(tostring(row.label or ""), left + L.margin, y)
      -- Right-aligned with the same margin the labels are inset by, which is
      -- what PrintRightAlignedWithMargin does: one number, used on both sides.
      Font.draw(value, right - L.margin - Font.width(value), y)
      line = line + 1
    end
  end
  if pair then Font.popStyle() end
end

function Gen4MainMenu:draw()
  local g = love.graphics
  local ink = self:ink()
  local bg = ink and rgb(ink.background) or self.colors.background or FALLBACK.colors.background
  g.setColor(bg[1], bg[2], bg[3], 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local L = self.layout
  if self.scrollTarget == nil then self:targetScroll(); self.scrollPos = self.scrollTarget end
  local oy = math.floor(self.scrollPos or 0)

  -- THE WINDOW THE PLAYER SEES IS THE FRAME AROUND THE CONTENT.
  -- `Window_DrawStandardFrame` -> `DrawStandardWindowFrame` (render_window.c)
  -- lays the frame at `x - 1 .. x + width` and `y - 1 .. y + height`, one tile
  -- outside the window on every side, and `RenderOptions` advances by
  -- `height + 2` with the comment "Add 2 to account for the window border".
  -- So a one-line option is 2 content tiles and FOUR visible ones, and the
  -- column is 28 tiles wide: x = 3, width = 26, frame from tile 2 to tile 29.
  local unfocused = art(self, "frame_unfocused")
  local focused = art(self, "frame_focused")
  local glow = art(self, "frame_focused_glow")
  local haveArt = unfocused and focused
  local tops = self:tops()
  local cycle = self:borderColour()

  for i, item in ipairs(self.items) do
    local th = (item.lines or 1) * L.lineTiles
    local ty = tops[i]
    local y = ty * 8 - oy
    if y + (th + 1) * 8 > 0 and y - 8 < H then
      local isFocused = i == self.index
      if haveArt then
        local paper = ink and (isFocused and ink.paper or ink.paperUnfocused)
          or (isFocused and { 255, 255, 255 } or { 214, 214, 214 })
        g.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
        g.rectangle("fill", L.optionX * 8, y, L.optionWidth * 8, th * 8)
        g.setColor(1, 1, 1, 1)
        nineSlice(self, isFocused and focused or unfocused, L.optionX, ty, L.optionWidth, th, oy)
        if isFocused and glow and cycle then
          g.setColor(cycle[1] / 255, cycle[2] / 255, cycle[3] / 255, 1)
          nineSlice(self, glow, L.optionX, ty, L.optionWidth, th, oy)
          g.setColor(1, 1, 1, 1)
        end
      else
        Font.drawBox(L.optionX - 1, ty - 1 - oy / 8, L.optionWidth + 2, th + 2)
      end

      -- DRAWN AT WHITE, not at black.  Platinum's font page is PRE-TINTED: the
      -- sheet bakes the letter dark and its shadow light -- TEXT_COLOR(1, 2,
      -- 15), which is exactly what MainMenuUtil_InitWindow asks for.
      if ink and ink.text then Font.pushStyle({ text = rgb(ink.text[1]), shadow = rgb(ink.text[2]) }) end
      Font.draw(item.label, L.optionX * 8, y)
      if ink and ink.text then Font.popStyle() end
      if item.key == "continue" then
        self:drawContinue(L.optionX, ty, L.optionWidth, oy)
      end
      if isFocused and not haveArt then
        Font.drawCode(Theme.cursor, (L.optionX - 1) * 8, y)
      end
    end
  end

  -- DrawScrollArrows: up while any window's top is above the view, down while
  -- any window's top is at or below its bottom edge, at (128, 8) / (128, 184)
  local target = self.scrollTarget or 0
  local up, down = false, false
  for i, item in ipairs(self.items) do
    local top = (tops[i] - 1) * 8
    if target > top then up = true end
    if target + H <= top then down = true end
  end
  local function arrow(key, x, yy)
    local img, rec = art(self, key)
    if img then g.draw(img, x + (rec.originX or -img:getWidth() / 2), yy + (rec.originY or -img:getHeight() / 2)) end
  end
  if up then arrow("scroll_up", W / 2, 8) end
  if down then arrow("scroll_down", W / 2, H - 8) end
end

return Gen4MainMenu
