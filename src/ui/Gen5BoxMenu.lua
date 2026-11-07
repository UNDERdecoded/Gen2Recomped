-- BLACK AND WHITE'S PC BOXES, over HGSS's (src/ui/HgssBoxMenu.lua, itself over
-- Platinum's) for everything the boxes do; drawn with /a/1/1/6's art
-- (src/import/Gen5BoxArt.lua) as Bulbapedia's capture of the cartridge shows:
--
-- THE TOUCH SCREEN: the box -- the wallpaper at (0, 8) under the frame, the
-- name in its header between << and >>, thirty icons at (22 + 24 col,
-- 50 + 24 row) -- the dotted ground to the right holding the party panel when
-- it is open, the action menu as a column of buttons there, and the foot:
-- PARTY PKMN, the red (x) and the blue back.
-- THE TOP SCREEN: the cyan title bar (the mode: MOVE POKeMON ...), No. and
-- species with its type, nickname, gender and level, NATURE / ABILITY / ITEM,
-- MOVES LEARNED, the markings, the picture.
--
-- Words: bank 9 (BW's box words, wallpapers from 41) and 10 (the messages).
--
-- MEASURED off the capture: every position; the buttons are drawn in the
-- frame's colours (their art is not paired yet).

local HG = require("src.ui.HgssBoxMenu")
local PC = require("src.ui.Gen4BoxMenu")
local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local BW = setmetatable({}, { __index = HG })
BW.__index = BW
BW.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local WORDS = { MOVE = 81, SUMMARY = 74, WITHDRAW = 78, STORE = 79, ITEM = 75, MARK = 76, RELEASE = 77,
                CANCEL = 80, CONFIRM = 84, GIVE = 93, TAKE = 92, WALLPAPER = 32, NAME = 33, JUMP = 31,
                ["HEADER CANCEL"] = 34, PARTY = 69, NATURE = 100, ABILITY = 101, ITEMLABEL = 102,
                NONE = 105, NO = 108, LV = 107, MOVES = 109, YES = 110 }
-- Platinum's message numbers (bank 19) -> BW's bank 10
local MESSAGE = { [13] = 12, [31] = 28, [14] = 13 }
local WALLPAPER_NAME = 41

local ICON_X, ICON_Y, PITCH = 22, 50, 24
local NAME_CENTRE, NAME_Y = 84, 22
local ARROW_L, ARROW_R = { 16, 29 }, { 158, 29 }
local PARTY_AT = { 166, 22 }
local PARTY_SLOTS = { { 190, 44 }, { 230, 44 }, { 190, 80 }, { 230, 80 }, { 190, 116 }, { 230, 116 } }
local MENU_X, MENU_Y, MENU_W, MENU_H, MENU_PITCH = 168, 24, 82, 21, 24
local PARTY_BUTTON = { 172, 191, 2, 92 }
local CLOSE_RECT, BACK_RECT = { 168, 191, 196, 222 }, { 168, 191, 226, 255 }
local HEADER_RECT = { 19, 38, 6, 162 }

local INK = {
  dark = { text = { 0.20, 0.20, 0.22 }, shadow = { 0.72, 0.72, 0.74 } },
  light = { text = { 1, 1, 1 }, shadow = { 0.35, 0.35, 0.40 } },
  blue = { text = { 0.12, 0.45, 0.93 }, shadow = { 0.62, 0.80, 0.95 } },
  red = { text = { 0.90, 0.25, 0.25 }, shadow = { 0.98, 0.70, 0.70 } },
}

local function put(text, x, y, ink)
  if not text or text == "" then return end
  Font.pushStyle(ink or INK.dark)
  Font.draw(tostring(text), floor(x), floor(y))
  Font.popStyle()
end

function BW.new(game, opts)
  local self = HG.new(game, opts)
  setmetatable(self, BW)
  self.hg = (game.data or {}).gen5_box_art or {}
  return self
end

function BW:text(bank, n)
  local s = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(bank, n or -1)]
  return type(s) == "string" and s ~= "" and s or nil
end

function BW:label(key)
  local s = self:text(9, WORDS[key])
  return s and (s:gsub("{[^}]*}", "")) or key
end

function BW:say(n, fallback, ...)
  local args = { ... }
  local s = self:text(10, MESSAGE[n] or n) or fallback or ""
  return (s:gsub("{VAR1}", tostring(args[1] or "")):gsub("{[^}]*}", ""))
end

function BW:runAction(action)
  if action == "WALLPAPER" then
    self:closeMenu()
    local rows = {}
    -- THE PAGES (READ, overlay 170 0x021E8A74, lists at 0x021EF928..9F8, bank 9
    -- words): the categories SCENERY 1-3 / MISC. (#35-38), and SPECIAL (#57)
    -- only once bit 1 of the clear byte is set (script op 0x0E4; arm9
    -- 0x02007A80; save.gen5ClearBits); four papers a page, #41-56 the
    -- sixteen plain ones; SPECIAL's page RESHIRAM, ZEKROM, MONOCHROME, TEAM
    -- PLASMA (#58-61), its NEXT (#68) to MUNNA, ZOROARK, SUBWAY, MUSICAL
    -- (#62-65) only once bit 2 is set. So papers 16-19 wait on bit 1, 20-23
    -- on bit 2, and paper 16 + k is word 58 + k (#57 is the category's name)
    local bits = tonumber(self.game and self.game.save and self.game.save.gen5ClearBits) or 0
    for id = 0, 23 do
      local need = (id >= 20 and 2) or (id >= 16 and 1) or nil
      if not need or math.floor(bits / need) % 2 == 1 then
        local word = id < 16 and (WALLPAPER_NAME + id) or (WALLPAPER_NAME + 1 + id)
        rows[#rows + 1] = { label = self:text(9, word) or ("WALLPAPER " .. id), key = function() self:setWallpaper(id) end }
      end
    end
    rows[#rows + 1] = { label = self:label("CANCEL"), key = "CANCEL" }
    return self:openMenu(rows, self:say(10, "Pick the wallpaper."))
  end
  return PC.runAction(self, action)
end

-- ---------------------------------------------------------------- input --

local function inRect(r, x, y) return y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] end

function BW:touchpressed(id, px, py)
  local r = require("src.render.Renderer").uiPresentation
  local x, y = px, py
  if r then x, y = (px - r.x) / r.scaleX, (py - r.y) / r.scaleY end
  if x < 0 or y < 0 or x >= W or y >= H then return false end
  if self.jump or self:busy() then return true end
  if self.menu then
    local first = self.menuTop or 1
    for i = 1, math.min(#self.menu - first + 1, 6) do
      local by = MENU_Y + (i - 1) * MENU_PITCH
      if x >= MENU_X and x <= MENU_X + MENU_W and y >= by and y <= by + MENU_H then
        self.action = first + i - 1
        return self:pickMenuRow(self.action) or true
      end
    end
    if inRect(BACK_RECT, x, y) or inRect(CLOSE_RECT, x, y) then self:closeMenu() end
    return true
  end
  if inRect(BACK_RECT, x, y) or inRect(CLOSE_RECT, x, y) then
    if self:returnHeld() then return true end
    if self.partyOpen then self.partyOpen = nil; return true end
    self:close()
    return true
  end
  if inRect(PARTY_BUTTON, x, y) then self.partyOpen = not self.partyOpen; self.partyIndex = 1; return true end
  if inRect(HEADER_RECT, x, y) then
    if x < 28 then self:changeBox(-1) elseif x > 140 then self:changeBox(1) else self.row = 0; self:choose() end
    return true
  end
  if self.partyOpen then
    for i, p in ipairs(PARTY_SLOTS) do
      if math.abs(x - p[1]) <= 18 and math.abs(y - p[2]) <= 16 then self.partyIndex = i; self:choose(); return true end
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

-- ----------------------------------------------------------------- draw --

function BW:drawButton(x, y, w, h, label, lit)
  local g = love.graphics
  g.setColor(0.15, 0.15, 0.16, 1)
  g.rectangle("fill", x, y, w, h, 3, 3)
  if lit then g.setColor(0.30, 0.82, 0.90, 1) else g.setColor(0.86, 0.86, 0.87, 1) end
  g.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 2, 2)
  g.setColor(1, 1, 1, 1)
  local text = tostring(label or "")
  put(text, x + floor((w - Font.width(text)) / 2), y + floor((h - 12) / 2), INK.dark)
end

function BW:drawTouch()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local base = self:hgImg("base")
  if base then g.draw(base, 0, 0) else g.setColor(0.94, 0.94, 0.94, 1); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  local paper = self:wallpaperId()
  local wall = self:hgImg("wall_" .. paper)
  if wall then g.draw(wall, 0, 8) end
  local frame = self:hgImg("frame")
  if frame then g.draw(frame, 0, 0) end
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
  if self.menu then
    local first = math.max(1, math.min(self.action - 5, #self.menu - 5))
    self.menuTop = first
    for i = 0, 5 do
      local row = self.menu[first + i]
      if row then
        local label = row.label
        if row.mark then label = ({ "●", "▲", "■", "♥", "★", "◆" })[row.mark + 1] or "" end
        self:drawButton(MENU_X, MENU_Y + i * MENU_PITCH, MENU_W, MENU_H, label, first + i == self.action)
      end
    end
  elseif self.partyOpen then
    local party = self:hgImg("party")
    if party then g.draw(party, PARTY_AT[1], PARTY_AT[2]) end
    for i, p in ipairs(PARTY_SLOTS) do
      local m = self.game.save.party[i]
      if m then self:drawIcon(m, p[1], p[2], self:iconFaded(m) and PC.XLU or 1) end
    end
  end
  -- the foot: PARTY PKMN, (x), back
  self:drawButton(PARTY_BUTTON[3], PARTY_BUTTON[1] + 1, PARTY_BUTTON[4] - PARTY_BUTTON[3], 18, self:label("PARTY"), self.partyOpen)
  local bag = (self.game.data or {}).gen5_bag_art or {}
  for key, at in pairs({ button_0 = { 196, 164 }, button_1 = { 226, 164 } }) do
    local rec = bag[key]
    local img = type(rec) == "table" and self:image(rec.path)
    if img then g.setColor(1, 1, 1, 1); g.draw(img, at[1], at[2]) end
  end
  -- the hand
  local hx, hy
  if self.partyOpen then
    local p = PARTY_SLOTS[self.partyIndex]
    if p then hx, hy = p[1], p[2] - 12 else hx, hy = 40, 176 end
  elseif self.row == 0 then hx, hy = NAME_CENTRE, 16
  elseif self.row >= 1 and self.row <= 5 then hx, hy = ICON_X + (self.col - 1) * PITCH, ICON_Y + (self.row - 1) * PITCH - 12
  else hx, hy = 40, 176 end
  if self.held then self:drawIcon(self.held.mon, hx, hy + 4) end
  if not self:hgSprite(self.held and "hand_9" or "hand_8", hx, hy) then
    g.setColor(0.9, 0.2, 0.2, 1); g.polygon("fill", hx - 4, hy - 8, hx + 4, hy - 8, hx, hy)
  end
  g.setColor(1, 1, 1, 1)
end

function BW:drawTop()
  local g = love.graphics
  g.setColor(0.35, 0.35, 0.36, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local preview = self:hgImg("preview")
  if preview then g.draw(preview, 0, 0) end
  local mode = self.opts and self.opts.mode
  local title = self:text(10, mode == "deposit" and 37 or mode == "withdraw" and 38 or mode == "items" and 40 or 39) or "MOVE POKÉMON"
  if self.message and self.message ~= "" then title = self.message end
  put((tostring(title):gsub("\n", " ")), 8, 6, INK.dark)
  local mon = self:previewMon()
  if not mon then return end
  local data = self.game.data
  local def = data.pokemon and data.pokemon[mon.species]
  local egg = mon.egg or mon.isEgg
  local num = tonumber(def and (def.dex or def.id)) or tonumber(mon.species) or 0
  put((self:label("NO") or "No.") .. ("%03d"):format(num), 8, 33)
  put(egg and "Egg" or (def and def.name) or tostring(mon.species), 8, 49)
  local types = def and def.types
  if type(types) == "table" and not egg then
    self:drawTypeIcon(types[1], 86, 55)
    if types[2] and types[2] ~= types[1] then self:drawTypeIcon(types[2], 120, 55) end
  end
  put(self:nameOf(mon), 8, 80)
  if not egg then
    local gender = require("src.pokemon.DayCare").gender(data, mon)
    if gender == "male" then put("♂", 74, 80, INK.blue) elseif gender == "female" then put("♀", 74, 80, INK.red) end
    put((self:label("LV") or "Lv.") .. tostring(mon.level or 1), 86, 80)
  end
  put(self:label("NATURE"), 8, 96)
  local natures = (data.constants or {}).natureOrder or {}
  local nat = mon.nature or (mon.personality and natures[mon.personality % 25 + 1])
  if nat then put(tostring(nat):sub(1, 1):upper() .. tostring(nat):sub(2):lower(), 15, 112) end
  put(self:label("ABILITY"), 8, 128)
  local ability = require("src.pokemon.AbilityOf").pick(mon, def and def.abilityIds)
  local aid = tonumber(ability)
  local aname = aid and (data.text or {})[("TEXT_G5S_0182_%05d"):format(aid)] or (ability and tostring(ability))
  if aname then put(aname, 15, 144) end
  put(self:label("ITEMLABEL"), 8, 160)
  local held = mon.heldItem or mon.item
  local item = held and data.items and data.items[held]
  put((item and item.name) or self:label("NONE"), 15, 176)
  put(self:label("MOVES"), 151, 107)
  for i = 1, 4 do
    local e = (mon.moves or {})[i]
    local id = type(e) == "table" and (e.id or e.move) or e
    local mv = id and (data.moves or {})[id]
    put(mv and mv.name or "-----", 152, 124 + (i - 1) * 16)
  end
  local Sprites = require("src.pokemon.Sprites")
  local path = Sprites.path(data, mon.species, "front", { mon = mon, kind = "summary" })
  local img = path and self:image(path)
  if img then
    local w, h = img:getDimensions()
    g.setColor(1, 1, 1, 1)
    g.draw(img, 199, 58, 0, 1, 1, w / 2, h / 2)
  end
end

return BW
