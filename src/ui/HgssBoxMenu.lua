-- HEARTGOLD / SOULSILVER'S PC BOXES, over Platinum's (src/ui/Gen4BoxMenu.lua)
-- for everything the boxes DO -- the cursor, carrying, depositing,
-- withdrawing, the party, releasing, marking, the wallpapers, renaming, the
-- box slide -- and drawn as overlay 14 draws it (src/import/Gen4HgssBoxArt.lua),
-- checked against Bulbapedia's capture of the cartridge.
--
-- THE BOXES ARE ON THE TOUCH SCREEN (overlay 14 makes the main engine the
-- bottom one): the base and the wallpaper (char 16 + n at (0, 8)) under the
-- blue frame; the box name in its header plate between the arrows; the thirty
-- icons at (20 + 24 col, 53 + 24 row); the party panel down the right with
-- its six icons; the action menu as a column of buttons at x 166..250 from y
-- 42, 24 apart (MOVE / SUMMARY / HELD ITEMS / MARKING / RELEASE ...), EXIT
-- under it. THE TOP SCREEN is the preview: the message bar, then the
-- Pokemon's No., species, gender, type, nickname, level, NATURE / ABILITY /
-- ITEM and its four moves, and its picture.
--
-- Words: bank 24 (the box words and the twenty-four wallpaper names, from 35)
-- and bank 25 (the messages, numbered as Platinum's bank 19).
--
-- One screen: the touch screen; SELECT shows the preview.
--
-- MEASURED off the capture, not read: every position; the party panel's slot
-- centres; the buttons are drawn in the panel's colours (their art -- likely
-- among the small screens 85 / 86 -- is not paired yet).

local PC = require("src.ui.Gen4BoxMenu")
local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")
local T = require("src.import.Gen4Text")

local HG = setmetatable({}, { __index = PC })
HG.__index = HG
HG.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local BANK_WORDS, BANK_MESSAGES = 24, 25
local WORDS = { MOVE = 61, SUMMARY = 65, WITHDRAW = 69, STORE = 70, ITEM = 66, MARK = 67, RELEASE = 68,
                CANCEL = 73, CONFIRM = 72, GIVE = 81, TAKE = 62, WALLPAPER = 26, NAME = 27, JUMP = 63,
                ["HEADER CANCEL"] = 73, PARTY = 60, EXIT = 71, NATURE = 87, ABILITY = 88, ITEMLABEL = 89,
                NONE = 92 }
local WALLPAPER_NAME, WALLPAPERS = 35, 24

local ICON_X, ICON_Y, PITCH = 20, 53, 24
local NAME_CENTRE, NAME_Y = 82, 21
local ARROW_L, ARROW_R = { 4, 17 }, { 142, 17 }
local PARTY_AT = { 166, 12 }
local PARTY_SLOTS = { { 188, 36 }, { 230, 36 }, { 188, 68 }, { 230, 68 }, { 188, 100 }, { 230, 100 } }
local MENU_X, MENU_Y, MENU_W, MENU_H, MENU_PITCH = 166, 42, 84, 21, 24
local EXIT_RECT = { 165, 188, 190, 249 }
local HEADER_RECT = { 17, 38, 4, 160 }
-- for src/ui/HgssBoxMove.lua (the party panel as a place the hand goes)
HG.PARTY_SLOTS, HG.ICON_X, HG.ICON_Y, HG.PITCH = PARTY_SLOTS, ICON_X, ICON_Y, PITCH

local INK = {
  dark = { text = { 0.29, 0.29, 0.33 }, shadow = { 0.78, 0.78, 0.74 } },
  light = { text = { 1, 1, 1 }, shadow = { 0.42, 0.42, 0.50 } },
  blue = { text = { 0.12, 0.45, 0.93 }, shadow = { 0.62, 0.80, 0.95 } },
  red = { text = { 0.90, 0.25, 0.25 }, shadow = { 0.98, 0.70, 0.70 } },
}

function HG.new(game, opts)
  local self = PC.new(game, opts)
  setmetatable(self, HG)
  self.hg = (game.data or {}).gen4_hgss_box_art or {}
  return self
end

-- ---------------------------------------------------------------- words --

function HG:label(key)
  local n = WORDS[key]
  local s = n and T.resolve(self.game.data, BANK_WORDS, n, self.game)
  if type(s) ~= "string" or s == "" then return key end
  return (s:gsub("\n", " "))
end

function HG:say(n, fallback, ...)
  T.buffer(self.game, ...)
  local s = T.resolve(self.game.data, BANK_MESSAGES, n, self.game)
  if type(s) ~= "string" or s == "" then s = fallback or "" end
  return (s:gsub("[\v\f]+", "\n"))
end

function HG:wallpaperOf(n)
  local save = self.game.save
  n = n or save.currentBox or 1
  local box = Boxes.ensure(save)[n]
  local id = tonumber(box and box.wallpaper)
  if id then return floor(id) % WALLPAPERS end
  return (n - 1) % 16
end

-- the wallpaper list: HGSS's twenty-four, one menu, then CANCEL
function HG:runAction(action)
  if action == "WALLPAPER" then
    self:closeMenu()
    local rows = {}
    for id = 0, WALLPAPERS - 1 do
      local name = T.resolve(self.game.data, BANK_WORDS, WALLPAPER_NAME + id, self.game) or ("WALLPAPER " .. id)
      rows[#rows + 1] = { label = name, key = function() self:setWallpaper(id) end }
    end
    rows[#rows + 1] = { label = self:label("CANCEL"), key = "CANCEL" }
    return self:openMenu(rows, self:say(10, "Pick the wallpaper."))
  end
  return PC.runAction(self, action)
end

-- no Platinum dials on the other screen: it is the preview
function HG:bottomShown() return false end

function HG:onSecond()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

-- ---------------------------------------------------------------- input --

function HG:update(dt)
  local input = self.game.input
  if input and input:wasPressed("select") and not self:onSecond() and not self.menu then
    self.showTop = not self.showTop
    return
  end
  if input then
    for _, k in ipairs({ "a", "b", "up", "down", "left", "right" }) do
      if input:wasPressed(k) then self.alert = nil; break end
    end
  end
  -- the pad between the box and the party panel (HgssBoxMove)
  if input and self:moveCursor(input) then
    self.t = (self.t or 0) + (dt or 1 / 60)
    for _ = 1, self:frames(dt) do self:step() end
    return
  end
  return PC.update(self, dt)
end

local function inRect(r, x, y) return y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] end

function HG:touchpressed(id, px, py)
  local x, y
  if self:onSecond() then
    -- the boxes are the game screen; the preview is the other one
  end
  local r = require("src.render.Renderer").uiPresentation
  x, y = px, py
  if r then x, y = (px - r.x) / r.scaleX, (py - r.y) / r.scaleY end
  if x < 0 or y < 0 or x >= W or y >= H then return false end
  if self.jump or self:busy() then return true end
  self.alert = nil
  -- MOVE mode: a press on a Pokemon may become a drag (HgssBoxMove); the tap
  -- itself is acted on at release, through here again with `dragTap` set
  if not self.menu and not self.dragTap and self:dragBegin(x, y) then return true end
  if self.menu then
    local first = math.max(1, (self.menuTop or 1))
    for i = 1, math.min(#self.menu - first + 1, 5) do
      local by = MENU_Y + (i - 1) * MENU_PITCH
      if x >= MENU_X and x <= MENU_X + MENU_W and y >= by and y <= by + MENU_H then
        self.action = first + i - 1
        return self:pickMenuRow(self.action) or true
      end
    end
    if inRect(EXIT_RECT, x, y) then self:closeMenu() end
    return true
  end
  if inRect(EXIT_RECT, x, y) then
    if self:returnHeld() then return true end
    self:close()
    return true
  end
  if inRect(HEADER_RECT, x, y) then
    if x < 24 then self:changeBox(-1) elseif x > 140 then self:changeBox(1) else self.row = 0; self:choose() end
    return true
  end
  for i, p in ipairs(PARTY_SLOTS) do
    if math.abs(x - p[1]) <= 18 and math.abs(y - p[2]) <= 15 then
      self.partyOpen = true
      self.partyIndex = i
      self:choose()
      return true
    end
  end
  if x >= ICON_X - 12 and x < ICON_X - 12 + 6 * PITCH and y >= ICON_Y - 12 and y < ICON_Y - 12 + 5 * PITCH then
    self.partyOpen = nil
    self.col = floor((x - (ICON_X - 12)) / PITCH) + 1
    self.row = floor((y - (ICON_Y - 12)) / PITCH) + 1
    self:choose()
  end
  return true
end
-- touchmoved / touchreleased: the drag, in src/ui/HgssBoxMove.lua

-- ----------------------------------------------------------------- draw --

function HG:hgImg(key)
  local rec = self.hg[key]
  if type(rec) ~= "table" then return nil end
  return self:image(rec.path), rec
end

function HG:image(path)
  if type(path) ~= "string" then return nil end
  self.hgImages = self.hgImages or {}
  if self.hgImages[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.hgImages[path] = ok and img or false
    if self.hgImages[path] then self.hgImages[path]:setFilter("nearest", "nearest") end
  end
  return self.hgImages[path] or nil
end

function HG:hgSprite(key, x, y)
  local img, rec = self:hgImg(key)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

local function put(text, x, y, ink)
  if not text or text == "" then return end
  Font.pushStyle(ink or INK.dark)
  Font.draw(tostring(text), floor(x), floor(y))
  Font.popStyle()
end

function HG:drawButton(x, y, w, h, label, lit)
  local g = love.graphics
  g.setColor(0.33, 0.33, 0.33, 1)
  g.rectangle("fill", x, y, w, h, 3, 3)
  if lit then g.setColor(0.86, 0.33, 0.35, 1) else g.setColor(0.99, 0.96, 0.87, 1) end
  g.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 2, 2)
  g.setColor(1, 1, 1, 1)
  local text = tostring(label or "")
  put(text, x + floor((w - Font.width(text)) / 2), y + floor((h - 12) / 2), lit and INK.light or INK.dark)
end

function HG:drawTouch()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local base = self:hgImg("base")
  if base then g.draw(base, 0, 0) else g.setColor(1, 0.96, 0.87, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  local paper = self:wallpaperId()
  local wall = self:hgImg("wall_" .. paper)
  if wall then g.draw(wall, 0, 8) end
  local frame = self:hgImg("frame")
  if frame then g.draw(frame, 0, 0) end
  -- the box name in the wallpaper's own colours
  local ink = (self.hg.ink or {})[paper]
  local nameInk = ink and { text = { ink[1][1] / 255, ink[1][2] / 255, ink[1][3] / 255 },
                            shadow = { ink[2][1] / 255, ink[2][2] / 255, ink[2][3] / 255 } } or INK.dark
  local name = Font.fit(self:boxNameOf(self.game.save.currentBox or 1), 100)
  put(name, NAME_CENTRE - floor(Font.width(name) / 2), NAME_Y, nameInk)
  local onHeader = (self.row == 0 and not self.partyOpen)
  self:hgSprite(onHeader and "hand_1" or "hand_0", ARROW_L[1], ARROW_L[2])
  self:hgSprite(onHeader and "hand_3" or "hand_2", ARROW_R[1], ARROW_R[2])
  local box = Boxes.ensure(self.game.save)[self.game.save.currentBox or 1] or {}
  for slot = 1, 30 do
    local m = box[slot]
    if m then self:drawIcon(m, ICON_X + (slot - 1) % 6 * PITCH, ICON_Y + floor((slot - 1) / 6) * PITCH, self:iconFaded(m) and PC.XLU or 1) end
  end
  -- the right column: the action menu, or the party
  if self.menu then
    local first = math.max(1, math.min(self.action - 4, #self.menu - 4))
    self.menuTop = first
    for i = 0, 4 do
      local row = self.menu[first + i]
      if row then
        local label = row.label
        if row.mark then label = ({ "●", "▲", "■", "♥", "★", "◆" })[row.mark + 1] or "" end
        self:drawButton(MENU_X, MENU_Y + i * MENU_PITCH, MENU_W, MENU_H, label, first + i == self.action)
      end
    end
  else
    local party = self:hgImg("party_plain") or self:hgImg("party")
    if party then g.draw(party, PARTY_AT[1], PARTY_AT[2]) end
    for i, p in ipairs(PARTY_SLOTS) do
      local m = self.game.save.party[i]
      if m then self:drawIcon(m, p[1], p[2], self:iconFaded(m) and PC.XLU or 1) end
    end
  end
  self:drawButton(EXIT_RECT[3], EXIT_RECT[1], EXIT_RECT[4] - EXIT_RECT[3], EXIT_RECT[2] - EXIT_RECT[1], self:label("EXIT"), false)
  -- the hand: on the header, a slot, a party slot; what it carries 4 below
  local hx, hy
  if self.partyOpen then
    local p = PARTY_SLOTS[self.partyIndex]
    if p then hx, hy = p[1], p[2] - 12 else hx, hy = 220, 172 end
  elseif self.row == 0 then hx, hy = NAME_CENTRE, 14
  elseif self.row >= 1 and self.row <= 5 then hx, hy = ICON_X + (self.col - 1) * PITCH, ICON_Y + (self.row - 1) * PITCH - 12
  else hx, hy = 220, 172 end
  local dx, dy = self:dragPoint()
  if dx then hx, hy = dx, dy end
  if self.held then self:drawIcon(self.held.mon, hx, hy + 4) end
  if not self:hgSprite(self.held and "hand_9" or "hand_8", hx, hy) then
    g.setColor(1, 1, 1, 1); g.polygon("fill", hx - 4, hy - 8, hx + 4, hy - 8, hx, hy)
  end
  self:drawAlert(put, INK.dark)
  g.setColor(1, 1, 1, 1)
end

function HG:drawTop()
  local g = love.graphics
  g.setColor(0.24, 0.53, 0.94, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local preview = self:hgImg("preview")
  if preview then g.draw(preview, 0, 0) end
  -- the message bar
  local bar = self:hgImg("message")
  if bar then g.draw(bar, 0, -4) end
  local mode = self.opts and self.opts.mode
  local title = self.message ~= "" and self.message
    or self:say(mode == "deposit" and 50 or mode == "withdraw" and 51 or mode == "items" and 53 or 52, "Move Pokémon")
  put((tostring(title):gsub("\n", " ")), 8, 6, INK.dark)
  local mon = self:previewMon()
  if not mon then return end
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local egg = mon.egg or mon.isEgg
  local num = self:dexNumber(mon)
  put(("No.%03d"):format(tonumber(num) or 0), 10, 42)
  put(egg and "EGG" or ((def and def.name) or tostring(mon.species)):upper(), 62, 42)
  if not egg then
    local gender = require("src.pokemon.DayCare").gender(data, mon)
    if gender == "male" then put("♂", 126, 42, INK.blue) elseif gender == "female" then put("♀", 126, 42, INK.red) end
    local types = def and def.types
    if type(types) == "table" then
      self:drawTypeIcon(types[1], 158, 48)
      if types[2] and types[2] ~= types[1] then self:drawTypeIcon(types[2], 192, 48) end
    end
  end
  put(self:nameOf(mon), 8, 57)
  if not egg then put("Lv." .. tostring(mon.level or 1), 36, 73) end
  put(self:label("NATURE"), 8, 89, INK.light)
  local natures = (data.constants or {}).natureOrder or {}
  local nat = mon.nature or (mon.personality and natures[mon.personality % 25 + 1])
  if nat then put(tostring(nat):sub(1, 1):upper() .. tostring(nat):sub(2):lower(), 8, 105) end
  put(self:label("ABILITY"), 8, 121, INK.light)
  local ability = require("src.pokemon.AbilityOf").pick(mon, def and def.abilities)
  if ability then
    local id = tonumber(ability)
    local name = id and (data.text or {})[("TEXT_B0720_%05d"):format(id)] or tostring(ability)
    put(name, 8, 137)
  end
  put(self:label("ITEMLABEL"), 8, 154, INK.light)
  local held = mon.heldItem or mon.item
  local item = held and data.items and data.items[held]
  put((item and item.name) or self:label("NONE"), 8, 170)
  -- the moves
  for i = 1, 4 do
    local e = (mon.moves or {})[i]
    local id = type(e) == "table" and (e.id or e.move) or e
    local mv = id and (data.moves or {})[id]
    if mv then put(mv.name, 167, 105 + (i - 1) * 16) end
  end
  -- the picture
  local Sprites = require("src.pokemon.Sprites")
  local path = Sprites.path(data, mon.species, "front", { mon = mon, kind = "summary" })
  local img = path and self:image(path)
  if img then
    local w, h = img:getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(img, 138, 100, 0, 1, 1, w / 2, h / 2)
  end
end

function HG:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self:onSecond() then
    self:drawTouch()
    SecondScreen.draw(self.game, function() self:drawTop() end)
  elseif self.showTop then
    self:drawTop()
  else
    self:drawTouch()
  end
  g.setColor(1, 1, 1, 1)
end

require("src.ui.HgssBoxMove").install(HG, PC)

return HG
