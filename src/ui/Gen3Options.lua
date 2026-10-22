-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's OPTION screen.
--
-- Six rows and CANCEL, and every word on it -- the row names and the values
-- each row cycles through -- is read off the cartridge:
--
--   TEXT SPEED    SLOW / MID / FAST
--   BATTLE SCENE  ON / OFF
--   BATTLE STYLE  SHIFT / SET
--   SOUND         MONO / STEREO
--   BUTTON MODE   NORMAL / LR / L=A
--   FRAME         TYPE 1 .. cartridge frame count
--   CANCEL
--
-- The ROWS are not in that order in the ROM -- BUTTON MODE sits after CANCEL
-- in memory -- so the order above is stated by the extractor rather than
-- read, and the suite checks it against the screen. The vocabulary is the
-- part that would otherwise have been invented, and it is the part derived.
--
-- Which of these the engine can actually honour is a separate question and
-- an honest one: TEXT SPEED, BATTLE SCENE, BATTLE STYLE and SOUND map onto
-- options this port already has. BUTTON MODE and FRAME are stored and shown
-- and do nothing yet, and this file says so rather than hiding the rows --
-- a screen missing two of its six lines is a worse lie than two lines that
-- do not bite.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3Options = {}
Gen3Options.__index = Gen3Options
Gen3Options.isOpaque = true
Gen3Options.shaderPresetBypass = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED geometry: header strip, then one row every three tiles with
-- the value column at the right.
local HEADER_TH = 3
local ROW_TOP = 3
local ROW_STEP = 3
local LABEL_X = 16
local VALUE_X = 128
local CURSOR_X = 4
-- how many rows fit under the header: the screen is 20 tiles tall, the header
-- takes three, and a row is three with a tile of border either side
local VISIBLE = 5

function Gen3Options:uiSize() return GBA_W, GBA_H end
function Gen3Options:wantsFillScale() return true end

function Gen3Options:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- How each row reads and writes the save's own options table. Keeping the
-- mapping here rather than in the record means the extractor stays a
-- description of the cartridge and this file owns what the engine does with
-- it.
local BINDINGS = {
  -- the frame delays TextBox actually reads (5/3/1).  These were the words
  -- "slow"/"mid"/"fast": a save's numeric 3 matched none of them, so the row
  -- showed SLOW, and picking a value wrote a string TextBox rejects.
  textSpeed = { field = "textSpeed", choices = { 5, 3, 1 } },
  battleScene = { field = "battleAnim", choices = { true, false } },
  battleStyle = { field = "battleStyle", choices = { "shift", "set" } },
  sound = { field = "stereo", choices = { false, true } },
  -- BUTTON MODE IS NOT INERT ANY MORE.
  --
  -- Reported from play: "in the controls options menu add in support for the
  -- L and R button for gen3 emerald."  This row has been on the screen since
  -- the OPTION screen was read and it could not do anything, because two of
  -- its three settings are about buttons this engine did not have.  It has
  -- them now (src/core/Input.lua), so the row is wired: NORMAL leaves L and R
  -- doing nothing, LR makes them page a list, and L=A makes L a second A.
  buttonMode = { field = "gen3ButtonMode", choices = { 1, 2, 3 } },
  frame = { field = "gen3Frame", inert = true },
}

local function frameTypeCount(game)
  local frames = game and game.data and game.data.font
                 and game.data.font.frames
  local count = math.floor(tonumber(frames and frames.count) or 0)
  if count > 0 then return count end
  -- Old/pre-frame caches do not carry the extracted count.  Keep the
  -- cartridge defaults rather than exposing Emerald's twenty choices on
  -- FireRed, whose option menu has exactly ten (sOptionMenuItemCounts).
  return require("src.core.GameVersion").get() == "firered" and 10 or 20
end

function Gen3Options.new(game, opts)
  local self = setmetatable({}, Gen3Options)
  self.game = game
  self.onCancel = opts and opts.onCancel
  self.index = 1
  self.blink = 0
  self.frameTypes = frameTypeCount(game)

  local record = (game.data.constants or {}).gen3Options
  -- THE WORD ON THE LAST ROW, which nothing had ever set.
  --
  -- Reported from play as a crash: UP at the top of the list wraps to CANCEL,
  -- which is the one row with no record behind it, and the draw fell back to
  -- `self.cancelLabel` -- a field assigned nowhere in this file.  Font.draw
  -- was handed nil and died on `#text`.  DOWN to the bottom of the list did
  -- the same thing; UP is just the fastest way there.
  --
  -- The cartridge supplies the word: extractOptions reads sOptionMenuText and
  -- keeps it as `cancel`, alongside the six row labels.  Falling back to the
  -- engine's own string means a cache built before that keeps working rather
  -- than crashing in a different place.
  self.cancelLabel = (record and record.cancel) or Strings("CANCEL")
  self.rows = {}
  for _, row in ipairs(record and record.rows or {}) do
    if row.label then
      self.rows[#self.rows + 1] = {
        key = row.key, label = row.label,
        values = row.values, value = row.value,
        binding = BINDINGS[row.key],
      }
    end
  end
  self.cartridgeRows = #self.rows

  -- THE ENGINE'S OWN SETTINGS, appended.
  --
  -- Emerald's OPTION screen has six rows and the cartridge's vocabulary for
  -- them, which is what the block above reads.  It does not have volume
  -- sliders, a video mode, key bindings or a mod manager -- and a Gen 3 game
  -- that cannot reach those has lost every setting the other versions have,
  -- for no better reason than that a GBA had no menu for them.  So the
  -- engine's rows follow the cartridge's, from the SAME list OptionsMenu
  -- builds, minus anything the six already cover.
  local covered = {
    textSpeed = true, animations = true, battleStyle = true,
    sound = true, stereo = true,
  }
  local okRows, extra = pcall(function()
    local rows = require("src.ui.OptionsMenu").buildRows(game)
    -- AND THE MODS' OWN ROWS, WHICH THIS SCREEN HAS NEVER SHOWN.
    --
    -- `buildRows` is only half of how the other versions' OPTIONS list is
    -- assembled: OptionsMenu.new takes what it returns and runs it through
    -- the `ui.options.rows` hook, which is the seam every mod adds, removes
    -- and reorders rows through.  This screen called buildRows directly and
    -- stopped there, so on Emerald -- and nowhere else -- every row a mod
    -- adds was missing and every row a mod takes away was still on screen.
    --
    -- With the voxel mod installed that was eight rows absent (WATER,
    -- ANTI-ALIAS, V-GRID, CURVE, 3D-BTL, BACK SPRITES, DAYTIME, VR) and two
    -- dead rows present (TILT and GBC FX, which that mod holds at zero for
    -- as long as it is installed), on the one version the mod is mostly
    -- about.  PERFORMANCE is a vanilla row and did appear; what it had left
    -- to scale on this screen was the FPS ceiling.
    --
    -- Run INSIDE the pcall that was already here, so a mod whose hook
    -- throws leaves the screen with the cartridge's own six rows and a
    -- warning on the console -- the same degradation a failed buildRows has
    -- always had -- rather than a Gen 3 OPTION screen that cannot open.
    local Runtime = require("src.mods.Runtime")
    local hooked = Runtime.call("ui.options.rows",
                                function(_, vanilla) return vanilla end,
                                game, rows)
    if type(hooked) ~= "table" then
      Logger.error("gen3 options: ui.options.rows returned %s; keeping the "
                   .. "vanilla rows", type(hooked))
      return rows
    end
    return hooked
  end)
  if okRows and type(extra) == "table" then
    for _, row in ipairs(extra) do
      if row.label and not covered[row.id] then
        self.rows[#self.rows + 1] = {
          key = row.id, label = row.label, engine = row,
        }
      end
    end
  else
    Logger.warn("gen3 options: the engine's own rows are unavailable (%s)",
                tostring(extra))
  end

  self.scroll = 0
  if #self.rows == 0 then
    Logger.warn("gen3 options: this dataset carries no OPTION vocabulary")
  end
  return self
end

-- The index of the value a row is currently showing.
function Gen3Options:choiceOf(row)
  local options = (self.game.save and self.game.save.options) or {}
  local bind = row.binding
  if not bind then return 1 end
  if row.key == "frame" then
    return math.max(1, math.min(self.frameTypes, options[bind.field] or 1))
  end
  local current = options[bind.field]
  for i, v in ipairs(bind.choices or {}) do
    if v == current then return i end
  end
  return 1
end

function Gen3Options:cycle(row, delta)
  if row and row.engine then
    -- an engine row owns its own step; `activate` rows (MODS, CONTROLS) open
    -- something instead and are handled by A alone
    if row.engine.step then pcall(row.engine.step, self.game, delta) end
    return
  end
  local save = self.game.save
  if not (save and row.binding) then return end
  save.options = save.options or {}
  local bind = row.binding
  if row.key == "frame" then
    local at = self:choiceOf(row) - 1
    save.options[bind.field] = (at + delta) % self.frameTypes + 1
  else
    local choices = bind.choices or {}
    if #choices == 0 then return end
    local at = self:choiceOf(row) - 1
    save.options[bind.field] = choices[(at + delta) % #choices + 1]
  end
  -- let the engine act on the ones it honours
  if not bind.inert and self.game.applyOptions then
    pcall(self.game.applyOptions, self.game, save.options)
  end
end

-- What the value column reads for a row.
function Gen3Options:valueText(row)
  if row.engine then
    local ok, text = pcall(function()
      return row.engine.value and row.engine.value(self.game) or ""
    end)
    return (ok and text) or ""
  end
  if row.key == "frame" then
    local n = self:choiceOf(row)
    return ("%s %d"):format(row.value or "TYPE", n)
  end
  local values = row.values or {}
  return values[self:choiceOf(row)] or (values[1] or "")
end

function Gen3Options:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3Options:animate(dt)
  self.blink = (self.blink + 1) % 60
end

-- Keep the cursor inside the window.  CANCEL is the row after the last one
-- and rides at the bottom of the list rather than in a fixed strip, so the
-- whole thing is one scrollable column.
function Gen3Options:clampScroll()
  local total = #self.rows + 1
  local maxScroll = math.max(0, total - VISIBLE)
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + VISIBLE then
    self.scroll = self.index - VISIBLE
  end
  self.scroll = math.max(0, math.min(self.scroll, maxScroll))
end

function Gen3Options:update(dt)
  self:animate(dt)
  local input = self.game.input
  local n = #self.rows + 1                  -- the rows, then CANCEL
  local row = self.rows[self.index]
  if input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("right") then
    self:cycle(row, 1)
  elseif input:wasPressed("left") then
    self:cycle(row, -1)
  elseif input:wasPressed("a") then
    if self.index > #self.rows then return self:close() end
    if row and row.engine and row.engine.activate then
      return pcall(row.engine.activate, self.game)
    end
    self:cycle(row, 1)
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
  self:clampScroll()
end

-- FIRERED'S OPTION SCREEN (pokefirered src/option_menu.c): a black field,
-- the header window (2,3) and the list window (2,7) each in a frame, rows
-- 13 pixels apart with the value at x 130 in red, the top bar's control
-- hint, and the chosen row left out of the BLDY lighten everything else gets.
local FRLG_VISIBLE = 7

function Gen3Options:drawFireRed()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, GBA_W, GBA_H)
  -- top bar: window 2, palette 15 (sTextWindowPalettes[2]) filled with colour 15
  g.setColor(0, 123 / 255, 197 / 255, 1)
  g.rectangle("fill", 0, 0, GBA_W, 16)
  local function text(s, x, y, ink, shadow)
    local two = Font.beginTwoTone(ink, shadow)
    if not two then g.setColor(ink) end
    Font.draw(s, x, y)
    if two then Font.endTwoTone() end
    g.setColor(1, 1, 1, 1)
  end
  local white, dark = { 1, 1, 1, 1 }, { 99 / 255, 99 / 255, 99 / 255, 1 }
  local gray, light = { 99 / 255, 99 / 255, 99 / 255, 1 }, { 214 / 255, 214 / 255, 206 / 255, 1 }
  local red, pink = { 230 / 255, 8 / 255, 8 / 255, 1 }, { 255 / 255, 189 / 255, 115 / 255, 1 }
  -- "{DPAD}PICK {LR}SWITCH {B}CANCEL", right-aligned to 228
  local hints = { { "+", "PICK" }, { "A", "SWITCH" }, { "B", "CANCEL" } }
  local width = 0
  for _, h in ipairs(hints) do width = width + 12 + Font.width(h[2]) + 6 end
  local x = 228 - width + 6
  for _, h in ipairs(hints) do
    g.setColor(white)
    g.rectangle("line", x + 0.5, 2.5, 10, 9, 3, 3)
    text(h[1], x + 2, 0, white, dark)
    x = x + 12
    text(h[2], x, 0, white, dark)
    x = x + Font.width(h[2]) + 6
  end

  Font.drawBox(1, 2, 28, 4)
  text(Strings("OPTION"), 2 * 8 + 8, 3 * 8 + 1, gray, light)
  Font.drawBox(1, 6, 28, 14)

  local total = #self.rows + 1
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + FRLG_VISIBLE then self.scroll = self.index - FRLG_VISIBLE end
  self.scroll = math.max(0, math.min(self.scroll, math.max(0, total - FRLG_VISIBLE)))
  local ox, oy = 2 * 8, 7 * 8
  for slot = 1, math.min(FRLG_VISIBLE, total) do
    local i = self.scroll + slot
    if i > total then break end
    local row = self.rows[i]
    local y = oy + (slot - 1) * 13 + 2
    local selected = (i == self.index)
    if selected then
      -- The cartridge leaves the selected row out of BLDY, which is subtle
      -- on modern displays. A solid blue strip preserves that behavior while
      -- making the active row unambiguous and keeping both columns readable.
      g.setColor(0, 123 / 255, 197 / 255, 1)
      g.rectangle("fill", ox, y - 2, 208, 14)
    end
    local labelInk, labelShadow = selected and white or gray, selected and dark or light
    local valueInk, valueShadow = selected and white or red, selected and dark or pink
    text((row and row.label) or self.cancelLabel or "", ox + 8, y, labelInk, labelShadow)
    if row then text(self:valueText(row), ox + 130, y, valueInk, valueShadow) end
  end
  -- everything but the chosen row is lightened by BLDY 2 (of 16)
  local sel = self.index - self.scroll
  local top = (sel - 1) * 13 + 58
  g.setColor(1, 1, 1, 2 / 16)
  g.rectangle("fill", 0, 16, GBA_W, top - 16)
  g.rectangle("fill", 0, top + 14, GBA_W, GBA_H - top - 14)
  g.rectangle("fill", 0, top, 16, 14)
  g.rectangle("fill", 224, top, GBA_W - 224, 14)
  if self.scroll + FRLG_VISIBLE < total then
    Font.drawCode(Theme.moreArrow, 27 * 8, 19 * 8)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen3Options:draw()
  if require("src.core.GameVersion").get() == "firered" then return self:drawFireRed() end
  love.graphics.setColor(0.30, 0.44, 0.64, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  Font.drawBox(0, 0, 30, HEADER_TH)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("OPTION"), LABEL_X, 8)

  -- A WINDOW, not the whole list.  Six cartridge rows fit; six plus the
  -- engine's twenty do not, and a box sized to all of them runs off the
  -- bottom of a 160-pixel screen and takes CANCEL with it.
  local total = #self.rows + 1
  local shown = math.min(VISIBLE, total)
  local rowsTh = shown * ROW_STEP + 1
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, ROW_TOP, 30, rowsTh)
  love.graphics.setColor(0, 0, 0, 1)

  for slot = 1, shown do
    local i = self.scroll + slot
    local y = (ROW_TOP + 1 + (slot - 1) * ROW_STEP) * 8
    local row = self.rows[i]
    -- `or ""` is not belt-and-braces for its own sake: this is a draw, and a
    -- nil here takes the whole game down with a blue screen rather than
    -- losing one word off one row
    local label = (row and row.label) or self.cancelLabel or ""
    if i > total then break end
    Font.draw(label, LABEL_X, y)
    if row then Font.draw(self:valueText(row), VALUE_X, y) end
    if i == self.index and self.blink < 40 then
      -- Theme.cursor, not a literal arrow: this cartridge has no arrow
      -- glyph, so a "\u{25B6}" here asks the charmap for a character it
      -- does not have and draws nothing at all
      Font.drawCode(Theme.cursor, CURSOR_X, y)
    end
  end

  -- the more-below marker, on the border row like every other list here
  if self.scroll + shown < total then
    Font.drawCode(Theme.moreArrow, (30 - 2) * 8,
                  (ROW_TOP + rowsTh - 1) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Options
