-- BLACK AND WHITE'S FIELD MENU, over Platinum's (src/ui/Gen4StartMenu.lua),
-- whose row actions and save flow it keeps. The art is /a/0/7/1's
-- (src/import/Gen5MenuArt.lua); the words are bank 34.
--
-- THE MENU IS THE TOUCH SCREEN: grid paper, and the entries as dark folder
-- tabs two to a row, read left to right -- POKeMON, POKeDEX / BAG, the
-- player's name (the card) / SAVE, OPTIONS (Bulbapedia's capture of the
-- cartridge) -- each an icon and its word; the chosen one is the cyan tab,
-- its icon running its animation. The red (x) at the foot closes it.
-- With the second screen shown it is drawn there; on one screen the tabs are
-- drawn over the world.
--
-- MEASURED, there being no symbols: the tabs' rectangles (x 3-125 / 131-253,
-- y 24-66 / 72-114 / 120-162), the icon and word positions, the (x).

local Gen4StartMenu = require("src.ui.Gen4StartMenu")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local Gen5StartMenu = setmetatable({}, { __index = Gen4StartMenu })
Gen5StartMenu.__index = Gen5StartMenu
Gen5StartMenu.isOpaque = false

local W, H = 256, 192
local floor = math.floor
local BANK = 34
local ORDER = { "pokemon", "pokedex", "bag", "trainerCase", "save", "options" }
local WORD = { pokedex = 1, pokemon = 2, bag = 3, save = 5, options = 6 }
local ICON = { options = 5, bag = 6, pokemon = 8, save = 9, trainerCase = 10, pokedex = 11 }
local FEMALE_BAG = 7
local COLS = { { 3, 125 }, { 131, 253 } }
local ROWS = { { 24, 66 }, { 72, 114 }, { 120, 162 } }
local ICON_DX, LABEL_DX, LABEL_DY = 29, 47, 15
local CLOSE_AT, CLOSE_RECT = { 220, 164 }, { 166, 191, 216, 255 }
local INK = { { 1, 1, 1 }, { 0.30, 0.30, 0.30 } }
local ICON_TICKS = 6

function Gen5StartMenu.new(game, opts)
  local self = Gen4StartMenu.new(game, opts)
  setmetatable(self, Gen5StartMenu)
  self.menuArt = (game.data or {}).gen5_menu_art or {}
  local keep = {}
  for _, row in ipairs(self.rows) do keep[row.id] = true end
  local rows = {}
  for _, id in ipairs(ORDER) do
    if keep[id] then
      local icon = ICON[id]
      if id == "bag" and self:isFemale() then icon = FEMALE_BAG end
      rows[#rows + 1] = { id = id, label = self:word(id), bwIcon = icon }
    end
  end
  -- the cartridge's tabs fill the grid; MODS (the port's, see
  -- Gen4StartMenu.modsRow) is a half-height tab of its own in the strip
  -- under it, left of the (x), and always the last row
  self.gridCount = #rows
  -- LINK (Gen4StartMenu.linkRow) is a half-height tab in the same strip,
  -- left of MODS; with both there the two share the strip's width
  local link = Gen4StartMenu.linkRow(game, self)
  if link then rows[#rows + 1] = link end
  local mods = Gen4StartMenu.modsRow(game)
  if mods then rows[#rows + 1] = mods end
  self.rows = rows
  self.index = 1
  for i, row in ipairs(rows) do if row.id == game.gen4StartMenuCursor then self.index = i end end
  return self
end

function Gen5StartMenu:isFemale()
  local g = ((self.game.save or {}).player or {}).gender
  return g == "girl" or g == "female" or g == 1
end

function Gen5StartMenu:word(id)
  if id == "trainerCase" then
    return tostring((((self.game.save or {}).player or {}).name) or "PLAYER")
  end
  local text = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(BANK, WORD[id] or 0)]
  if type(text) ~= "string" or text == "" then return id:upper() end
  return text
end

-- the MODS tab: the strip under the grid, the grid's left column wide
local MODS_RECT = { 167, 189, 3, 125 }
-- one cartridge tab in buttons_N (and the cyan cursor's height), squeezed to it
local TAB_SRC = { 0, 24, 128, 43 }

-- the strip's tabs when LINK and MODS are both there
local STRIP_RECTS = { { 167, 189, 3, 105 }, { 167, 189, 109, 211 } }

function Gen5StartMenu:rect(i)
  local grid = self.gridCount or #self.rows
  if i > grid and self.rows[i] then
    local extras = #self.rows - grid
    if extras <= 1 then return MODS_RECT end
    return STRIP_RECTS[i - grid]
  end
  local col, row = COLS[(i - 1) % 2 + 1], ROWS[floor((i - 1) / 2) + 1]
  return row and { row[1], row[2], col[1], col[2] }
end

local function inRect(r, p) return r and p.y >= r[1] and p.y <= r[2] and p.x >= r[3] and p.x <= r[4] end

function Gen5StartMenu:se(name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, name) end
end

function Gen5StartMenu:update()
  local count = #self.rows
  if count == 0 then return self:close() end
  self.frame = (self.frame or 0) + 1
  local tap = self.tapAt
  self.tapAt = nil
  if tap then
    if inRect(CLOSE_RECT, tap) then self:se("SEQ_SE_DP_SELECT"); return self:close() end
    for i = 1, count do
      if inRect(self:rect(i), tap) then
        self.index = i
        self.game.gen4StartMenuCursor = self.rows[i].id
        self:se("SEQ_SE_DP_SELECT")
        return self:select()
      end
    end
    return
  end
  local input = self.game.input
  if not input then return end
  local before = self.index
  local i = self.index - 1
  -- the grid is the cartridge's tabs; a MODS tab (rows past gridCount) sits
  -- below it and is reached by DOWN from the grid's last row
  local grid = self.gridCount or count
  if input:wasPressed("up") then
    if i >= grid then
      if grid > 0 then self.index = floor((grid - 1) / 2) * 2 + 1 end
    elseif i >= 2 then self.index = self.index - 2 end
  elseif input:wasPressed("down") then
    if i + 2 < grid then self.index = self.index + 2
    elseif i < grid and grid < count and floor(i / 2) == floor((grid - 1) / 2) then
      self.index = grid + 1
    end
  elseif input:wasPressed("left") then
    if i < grid and i % 2 == 1 then self.index = self.index - 1
    elseif i > grid then self.index = self.index - 1 end
  elseif input:wasPressed("right") then
    if i < grid and i % 2 == 0 and i + 1 < grid then self.index = self.index + 1
    elseif i >= grid and i + 1 < count then self.index = self.index + 1 end
  elseif input:wasPressed("a") then
    self:se("SEQ_SE_DP_SELECT")
    return self:select()
  elseif input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("x") then
    self:se("SEQ_SE_DP_SELECT")
    return self:close()
  end
  if self.index ~= before then
    self:se("SEQ_SE_DP_SELECT")
    self.swellFrom = self.frame
    self.game.gen4StartMenuCursor = self.rows[self.index].id
  end
end

function Gen5StartMenu:onSecondScreen()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function Gen5StartMenu:touchpressed(id, px, py)
  local x, y
  if self:onSecondScreen() and SecondScreen.toLocal then
    x, y = SecondScreen.toLocal(self.game, px, py)
  else
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end

function Gen5StartMenu:bwImg(key)
  local rec = self.menuArt[key]
  if type(rec) ~= "table" then return nil end
  return self:imgAt(rec.path), rec
end

function Gen5StartMenu:bwSprite(key, x, y)
  local img, rec = self:bwImg(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

-- THE MODS TAB, out of the cartridge's own art: one dark tab cut from
-- buttons_6 and the cyan cursor_0, both squeezed to the strip's height, and
-- the word centred on it in the tabs' ink.
function Gen5StartMenu:drawModsTab(row, r, selected)
  local g = love.graphics
  local w, h = r[4] - r[3], r[2] - r[1] + 1
  local tabs = self:bwImg("buttons_6")
  local sy = h / TAB_SRC[4]
  -- a narrower tab when LINK and MODS share the strip
  local sx = (w + 6) / TAB_SRC[3]
  if tabs then
    self.modsTabQuad = self.modsTabQuad or g.newQuad(TAB_SRC[1], TAB_SRC[2],
      TAB_SRC[3], TAB_SRC[4], tabs:getDimensions())
    g.setColor(1, 1, 1, 1)
    g.draw(tabs, self.modsTabQuad, r[3] - 3, r[1], 0, sx, sy)
  else
    g.setColor(0.15, 0.15, 0.15, 1)
    g.rectangle("fill", r[3], r[1], w, h)
  end
  if selected then
    local cur, rec = self:bwImg("cursor_0")
    if cur then
      local cw, ch = cur:getDimensions()
      g.setColor(1, 1, 1, 1)
      g.draw(cur, floor((r[3] + r[4]) / 2) + 1 - cw * sx / 2, r[1] + (h - ch * sy) / 2, 0, sx, sy)
    end
  end
  g.setColor(1, 1, 1, 1)
  local label = row.label or ""
  Font.draw(label, r[3] + floor((w - Font.width(label)) / 2), r[1] + floor((h - 16) / 2) + 1)
end

function Gen5StartMenu:drawPanel(whole)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local count = #self.rows
  if whole then
    local back = self:bwImg("backdrop")
    if back then g.draw(back, 0, 0) end
  end
  -- the grid art counts the cartridge's tabs only; MODS draws its own
  count = self.gridCount or count
  local layout = count >= 6 and 6 or count == 5 and 5 or 4
  local tabs = self:bwImg("buttons_" .. layout)
  if tabs and count >= 4 then g.draw(tabs, 0, 0) end
  Font.pushStyle({ text = INK[1], shadow = INK[2] })
  for i, row in ipairs(self.rows) do
    local r = self:rect(i)
    if r and i > (self.gridCount or count) then
      self:drawModsTab(row, r, i == self.index)
    elseif r then
      if not tabs or count < 4 then
        g.setColor(0.15, 0.15, 0.15, 1)
        g.rectangle("fill", r[3], r[1], r[4] - r[3], r[2] - r[1])
        g.setColor(1, 1, 1, 1)
      end
      local cx, cy = floor((r[3] + r[4]) / 2), floor((r[1] + r[2]) / 2)
      local selected = i == self.index
      if selected then self:bwSprite("cursor_0", cx + 1, cy) end
      -- cells 1-4 are the resting icon bobbing (cell 0 is a displaced pose)
      local frame = selected and (1 + floor((self.frame or 0) / ICON_TICKS) % 4) or 1
      if not self:bwSprite(("icon_%d_%d"):format(row.bwIcon, frame), r[3] + ICON_DX, cy) then
        self:bwSprite(("icon_%d_0"):format(row.bwIcon), r[3] + ICON_DX, cy)
      end
      Font.draw(row.label or "", r[3] + LABEL_DX, r[1] + LABEL_DY)
    end
  end
  Font.popStyle()
  self:bwSprite("close", CLOSE_AT[1], CLOSE_AT[2])
  g.setColor(1, 1, 1, 1)
end

function Gen5StartMenu:draw()
  if self:onSecondScreen() then
    return SecondScreen.draw(self.game, function() self:drawPanel(true) end)
  end
  self:drawPanel(false)
end

return Gen5StartMenu
