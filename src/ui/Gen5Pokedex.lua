-- BLACK AND WHITE'S POKEDEX: the list and the INFO page, in the cartridge's own
-- art (/a/1/5/9, src/import/Gen5DexArt.lua -> `gen5_dex_art`) and words.
--
-- SOURCES. The layout is MEASURED from Bulbapedia's two captures of the
-- cartridge (Pokedex_BW.png, the list; Pokedex_entry_BW.png, the INFO page),
-- sampled pixel by pixel in the browser. The words are the ROM's: bank 276
-- (UNOVA POKeDEX, NATIONAL POKeDEX, SEEN, OBTAINED, ?????), bank 234 (INFO /
-- AREA / CRY / FORMS, HT, WT), and per species bank 259 (name, 0 = "-----"),
-- 260 (category, 0 = "????? Pokemon"), 245 (height, 0 = ???'??"), 268 (weight,
-- 0 = ????.? lbs.). The entry text is the species' own `dexEntry`.
--
-- THE LIST is one strip of 24-pixel rows running through BOTH screens: on the
-- touch screen rows sit at y 1 + 24k (k 0..6), the cursor's at k = 2 beside
-- the grey band the chosen Pokemon stands in, and the strip carries on up the
-- top screen (y 169 - 24j) fading into the grid -- each row blended at its
-- own measured strength (the capture's 058..063 rows: 26, 42, 52, 58, 65, 75%)
-- under the title strip and the SEEN / OBTAINED bar. A row is S66 (caught: a
-- ball), S67 (seen: a ring) or S68 (unseen: "?????"), x 96, the box icon in its
-- brackets, the number at x 152 and the name at x 180; the cursor's row is the
-- same map in palette row 2 (olive) with light-green ink. The Unova Dex
-- numbers national 494..649 as 000..155 (Victini 000); with the National Dex
-- the list is national 1..649. Like Platinum's, the list stops at the last
-- Pokemon seen. Scrollbar: x 250, 8..159, its thumb 8 pixels tall.
--
-- THE INFO PAGE (touch): the panel (S40) with the Pokemon at its place (the
-- 96 x 96 sprite at -3, -1), the hex at (88, 8) turned into a Poke Ball when
-- caught, "No. 025" and the name, the category, the type badges at (152, 54),
-- HT / WT right-aligned at x 243, the entry in white at x 20 from y 119 on 16-
-- pixel lines; the foot ^^ vv INFO AREA CRY FORMS, the box, (x) and back. The
-- top screen is the grid under the INFO title strip.
--
-- KEYS. List: up/down a row, left/right seven rows, A the INFO page, B or the
-- back button closes; START switches Unova / National once the National Dex is
-- had (THE CARTRIDGE'S START OPENS THE SEARCH, NOT DONE -- an approximation).
-- INFO: up/down the previous / next Pokemon seen, A the cry, B back to the list.
-- SELECT shows the other screen when only one is on the display. Touch: a row
-- (twice to open), the panel, << >>, ^^ vv, CRY, (x), back.
--
-- MEASURED vs FOUND vs NOT DONE. Found in the ROM: every picture named in
-- Gen5DexArt. Measured: every position and ink above, the row fades, the
-- foot's black gradient (its art was not found; drawn from the capture's rows).
-- Chosen: the cursor kept on row 2 (the capture's position) while the list
-- scrolls; the name centred on x 195 and the category on 187 (each capture
-- shows one Pokemon); a seen-only Pokemon's page showing the "?" words of entry
-- 0 and no entry text. AREA / FORMS: see drawAreaTop / drawFormsTop (a BW
-- alternate form's own picture is not imported, so it shows the base one).
-- NOT DONE: the search screen, the
-- footprint, the scroll animation, the list's scanner sweep, sounds beyond the
-- shared select / decide.

local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local Gen5Pokedex = {}
Gen5Pokedex.__index = Gen5Pokedex
Gen5Pokedex.isOpaque = true

local W, H = 256, 192
local floor = math.floor
local lg = love.graphics

local ROW_X, ROW_PITCH, CURSOR_ROW = 96, 24, 2
local TOP_FADE = { 0.75, 0.65, 0.58, 0.52, 0.42, 0.26 }
local NUM_X, NAME_X = 152, 180
local INK = {
  row = { { 216 / 255, 216 / 255, 216 / 255 }, { 128 / 255, 128 / 255, 128 / 255 } },
  rowSel = { { 208 / 255, 248 / 255, 120 / 255 }, { 104 / 255, 168 / 255, 56 / 255 } },
  title = { { 216 / 255, 216 / 255, 216 / 255 }, { 128 / 255, 128 / 255, 128 / 255 } },
  bar = { { 48 / 255, 48 / 255, 48 / 255 }, { 136 / 255, 136 / 255, 136 / 255 } },
  box = { { 88 / 255, 80 / 255, 80 / 255 }, { 160 / 255, 160 / 255, 168 / 255 } },
  entry = { { 248 / 255, 248 / 255, 248 / 255 }, { 160 / 255, 160 / 255, 168 / 255 } },
}
-- the foot's black gradient, rows 168..191 (the capture's values)
local FOOT = { 0, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 16, 8 }

-- where the font's glyph tops land below the y it is drawn at
local TEXT_DY = 1

function Gen5Pokedex:uiSize() return W, H end

function Gen5Pokedex.new(game, opts)
  local self = setmetatable({}, Gen5Pokedex)
  opts = opts or {}
  self.game = game
  self.onCancel = opts.onCancel
  self.bw = (game.data or {}).gen5_dex_art or {}
  self.cache = {}
  self.mode = "list"
  local dex = (game.save or {}).pokedex or {}
  self.national = false
  self.hasNational = dex.national and true or false
  self.cursor = 1
  self:rebuild()
  self.repeatKey, self.repeatT = nil, 0
  return self
end

-- ------------------------------------------------------------------ data --

function Gen5Pokedex:text(bank, entry)
  local s = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(bank, entry)]
  if type(s) ~= "string" or s == "" then return nil end
  return (s:gsub("{[^}]*}", ""))
end

function Gen5Pokedex:status(id)
  local dex = (self.game.save or {}).pokedex or {}
  local function has(t) t = t or {}; return t[id] or t[tostring(id)] or t["SPECIES_" .. id] end
  if has(dex.owned) or has(dex.caught) then return "caught" end
  if has(dex.seen) then return "seen" end
  return nil
end

function Gen5Pokedex:rebuild()
  local mons = (self.game.data or {}).pokemon or {}
  local first, last = 494, 649
  if self.national then first = 1 end
  local list = {}
  for id = first, last do
    if mons[id] then list[#list + 1] = id end
  end
  local lastSeen = 0
  for i, id in ipairs(list) do if self:status(id) then lastSeen = i end end
  for i = #list, math.max(lastSeen, 1) + 1, -1 do list[i] = nil end
  if lastSeen == 0 then list = { list[1] } end
  self.entries = list
  self.cursor = math.max(1, math.min(self.cursor or 1, #list))
end

function Gen5Pokedex:number(id)
  if not id then return "" end
  return ("%03d"):format(self.national and id or (id - 494))
end

function Gen5Pokedex:name(id)
  local def = ((self.game.data or {}).pokemon or {})[id] or {}
  return self:text(259, id) or def.name or "?"
end

function Gen5Pokedex:counts()
  local seen, caught = 0, 0
  local mons = (self.game.data or {}).pokemon or {}
  local first = self.national and 1 or 494
  for id = first, 649 do
    if mons[id] then
      local s = self:status(id)
      if s then seen = seen + 1 end
      if s == "caught" then caught = caught + 1 end
    end
  end
  return seen, caught
end

-- -------------------------------------------------------------- pictures --

function Gen5Pokedex:image(path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen5Pokedex:bwImg(key)
  local rec = self.bw[key]
  if type(rec) ~= "table" then return nil end
  return self:image(rec.path), rec
end

-- a piece placed by its opaque box's corner (the measured position)
function Gen5Pokedex:put(key, x, y)
  local img, rec = self:bwImg(key)
  if not img then return false end
  lg.draw(img, x - (rec.bx or 0), y - (rec.by or 0))
  return true
end

function Gen5Pokedex:icon(id)
  local data = self.game.data or {}
  local icons = data.icons or (data.gen4_species_sprites or {}).icons or {}
  local rec = (icons.bySpecies or {})[id]
  local img = rec and self:image(rec.image)
  if not img then return nil end
  self.quads = self.quads or {}
  local q = self.quads[img]
  if not q then
    q = lg.newQuad(0, 0, 32, rec.frameHeight or 32, img:getDimensions())
    self.quads[img] = q
  end
  return img, q
end

function Gen5Pokedex:front(id)
  local def = ((self.game.data or {}).pokemon or {})[id] or {}
  -- the first gender seen picks the picture, as Platinum's / HGSS's dex
  -- (Pokedex_DisplayedGender; INFERRED for Black / White): the female sheet
  -- where the species has its own (Gen5BattleSprites +1)
  local okR, Rec = pcall(require, "src.pokemon.Gen45DexRecord")
  if okR and def.spriteFemaleFront and Rec.displayGender(self.game, id, 0) == "female" then
    return self:image(def.spriteFemaleFront)
  end
  return self:image(def.spriteFront)
end

local function ink(pair, text, x, y)
  Font.pushStyle({ text = pair[1], shadow = pair[2] })
  Font.draw(text, x, y - TEXT_DY)
  Font.popStyle()
end

local function inkRight(pair, text, right, y) ink(pair, text, right + 1 - Font.width(text), y) end
local function inkCentre(pair, text, centre, y) ink(pair, text, centre - floor(Font.width(text) / 2), y) end

-- ---------------------------------------------------------------- input --

function Gen5Pokedex:bottomOnSecond()
  return SecondScreen.mode(self.game) ~= "off" and not SecondScreen.stowed(self.game)
end

function Gen5Pokedex:sound(name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if data and ok and type(Sound) == "table" and Sound.playSe then pcall(Sound.playSe, data, name) end
end

function Gen5Pokedex:cry(id)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playCry and id and self:status(id) then
    pcall(Sound.playCry, self.game.data, id, { isolated = true })
  end
end

function Gen5Pokedex:close()
  self:sound("SEQ_SE_CANCEL1")
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen5Pokedex:move(delta)
  local n = #self.entries
  local to = math.max(1, math.min(n, self.cursor + delta))
  if to ~= self.cursor then
    self.cursor = to
    self:sound("SEQ_SE_SELECT1")
  end
end

-- the previous / next Pokemon that has been seen (the INFO page's ^^ vv)
function Gen5Pokedex:step(delta)
  local i = self.cursor + delta
  while self.entries[i] do
    if self:status(self.entries[i]) then
      self.cursor = i
      self:sound("SEQ_SE_SELECT1")
      return
    end
    i = i + delta
  end
end

function Gen5Pokedex:openInfo()
  local id = self.entries[self.cursor]
  if not (id and self:status(id)) then return end
  self.mode = "info"
  self:sound("SEQ_SE_DECIDE1")
  self:cry(id)
end

function Gen5Pokedex:held(input, key)
  if input:wasPressed(key) then
    self.repeatKey, self.repeatT = key, -0.35
    return true
  end
  if self.repeatKey == key and input.isDown and input:isDown(key) then
    if self.repeatT >= 0.08 then self.repeatT = 0; return true end
  end
  return false
end

local function inBox(x, y, x0, y0, x1, y1) return x >= x0 and x <= x1 and y >= y0 and y <= y1 end

function Gen5Pokedex:update(dt)
  dt = dt or 1 / 60
  self.repeatT = (self.repeatT or 0) + dt
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  if tap then return self:touch(tap.x, tap.y) end
  if not input then return end
  if self.repeatKey and not (input.isDown and input:isDown(self.repeatKey)) then self.repeatKey = nil end
  if input:wasPressed("select") then self.showTop = not self.showTop; return end
  if self.mode == "list" then
    if self:held(input, "up") then self:move(-1)
    elseif self:held(input, "down") then self:move(1)
    elseif self:held(input, "left") then self:move(-7)
    elseif self:held(input, "right") then self:move(7)
    elseif input:wasPressed("a") then self:openInfo()
    elseif input:wasPressed("start") then
      if self.hasNational then
        local id = self.entries[self.cursor]
        self.national = not self.national
        self:rebuild()
        for i, e in ipairs(self.entries) do if e == id then self.cursor = i end end
        self:sound("SEQ_SE_DECIDE1")
      end
    elseif input:wasPressed("b") then self:close()
    end
  else
    if self:held(input, "up") then self:step(-1)
    elseif self:held(input, "down") then self:step(1)
    elseif input:wasPressed("left") or input:wasPressed("right") then
      -- INFO -> AREA -> FORMS (INFERRED keys; the cartridge's tabs are touched)
      local order = { "info", "area", "forms" }
      local at = 1
      for i, m in ipairs(order) do if m == self.mode then at = i end end
      at = (at - 1 + (input:wasPressed("right") and 1 or -1)) % 3 + 1
      self.mode = order[at]
      self:sound("SEQ_SE_SELECT1")
    elseif input:wasPressed("a") then self:cry(self.entries[self.cursor])
    elseif input:wasPressed("b") then self.mode = "list"; self:sound("SEQ_SE_CANCEL1")
    end
  end
end

function Gen5Pokedex:touch(x, y)
  -- the foot's shared (x) and back
  if inBox(x, y, 211, 170, 228, 189) then return self:close() end
  if inBox(x, y, 235, 170, 252, 189) then
    if self.mode ~= "list" then self.mode = "list"; self:sound("SEQ_SE_CANCEL1"); return end
    return self:close()
  end
  if self.mode == "list" then
    if inBox(x, y, 137, 170, 157, 189) then return self:move(-7) end
    if inBox(x, y, 162, 170, 182, 189) then return self:move(7) end
    if inBox(x, y, 0, 16, 94, 100) then return self:openInfo() end
    for k = 0, 6 do
      local ry = 1 + ROW_PITCH * k
      if inBox(x, y, ROW_X, ry, 248, ry + 20) then
        local i = self.cursor + k - CURSOR_ROW
        if self.entries[i] then
          if k == CURSOR_ROW then return self:openInfo() end
          self.cursor = i
          self:sound("SEQ_SE_SELECT1")
        end
        return
      end
    end
  else
    if inBox(x, y, 3, 169, 20, 189) then return self:step(-1) end
    if inBox(x, y, 27, 169, 44, 189) then return self:step(1) end
    if inBox(x, y, 112, 170, 142, 190) then return self:cry(self.entries[self.cursor]) end
    if inBox(x, y, 48, 170, 79, 190) and self.mode ~= "info" then self.mode = "info"; return self:sound("SEQ_SE_SELECT1") end
    if inBox(x, y, 80, 170, 111, 190) and self.mode ~= "area" then self.mode = "area"; return self:sound("SEQ_SE_SELECT1") end
    if inBox(x, y, 144, 170, 175, 190) and self.mode ~= "forms" then self.mode = "forms"; return self:sound("SEQ_SE_SELECT1") end
  end
end

function Gen5Pokedex:touchpressed(id, px, py)
  local x, y
  if self:bottomOnSecond() then
    x, y = SecondScreen.toLocal(self.game, px, py)
  else
    if self.showTop then return false end
    local rect = require("src.render.Renderer").uiPresentation
    x, y = px, py
    if rect then x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY end
  end
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  self.tapAt = { x = floor(x), y = floor(y) }
  return true
end
function Gen5Pokedex:touchmoved() return false end
function Gen5Pokedex:touchreleased() return false end

-- ----------------------------------------------------------------- draw --

function Gen5Pokedex:drawFoot()
  for i = 0, 23 do
    local v = (FOOT[i + 1] or 0) / 255
    lg.setColor(v, v, v, 1)
    lg.rectangle("fill", 0, 168 + i, W, 1)
  end
  lg.setColor(1, 1, 1, 1)
  if self.mode == "list" then
    self:put("obj_0", 3, 170)
    self:put("button_4", 139, 173)
    self:put("button_5", 164, 173)
    self:put("button_6", 188, 172)
  else
    self:put("button_3", 5, 171)
    self:put("button_2", 29, 172)
    for i = 0, 3 do
      local on = (i == 0 and self.mode == "info") or (i == 1 and self.mode == "area")
        or (i == 3 and self.mode == "forms")
      self:put(("page_%d"):format(i * 2 + (on and 2 or 1)), 48 + i * 32, 170)
    end
    self:put("button_6", 184, 172)
  end
  self:put("button_0", 213, 173)
  self:put("button_1", 237, 173)
end

-- one list row at (ROW_X, y): its map, icon, number and name
function Gen5Pokedex:drawIconRow(id, y, selected)
  local state = self:status(id) or "unseen"
  local img = self:bwImg("row_" .. state .. (selected and "_sel" or ""))
  lg.setColor(1, 1, 1, 1)
  if img then lg.draw(img, ROW_X, y - 1) end
  if state ~= "unseen" then
    local icon, q = self:icon(id)
    if icon and q then lg.draw(icon, q, ROW_X - 1, y - 12) end
  end
  local pair = selected and INK.rowSel or INK.row
  ink(pair, self:number(id), NUM_X, y + 4)
  ink(pair, state == "unseen" and (self:text(276, 7) or "?????") or self:name(id), NAME_X, y + 4)
end

function Gen5Pokedex:drawListTouch()
  lg.setColor(1, 1, 1, 1)
  local back = self:bwImg("list_touch")
  if back then lg.draw(back, 0, 0) else lg.setColor(0.03, 0.69, 0.47, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  local id = self.entries[self.cursor]
  if id and self:status(id) then
    local front = self:front(id)
    if front then lg.draw(front, 0, 0) end
  end
  self:put("obj_6", 3, 0)
  for k = 6, 0, -1 do
    local e = self.entries[self.cursor + k - CURSOR_ROW]
    if e then self:drawIconRow(e, 1 + ROW_PITCH * k, k == CURSOR_ROW) end
  end
  -- the scrollbar
  self:put("obj_3", 250, 8)
  local n = #self.entries
  local t = n > 1 and floor(143 * (self.cursor - 1) / (n - 1)) or 0
  self:put("obj_2", 250, 8 + t)
  self:drawFoot()
end

function Gen5Pokedex:drawListTop()
  lg.setColor(1, 1, 1, 1)
  local back = self:bwImg("list_top")
  if back then lg.draw(back, 0, 0) else lg.setColor(0.03, 0.69, 0.47, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  -- the strip carries on up the top screen, fading into the grid
  if not self.rowCanvas then
    local ok, c = pcall(lg.newCanvas, W, 40)
    self.rowCanvas = ok and c or false
  end
  for j = 0, 5 do
    local e = self.entries[self.cursor - CURSOR_ROW - 1 - j]
    if e then
      local y = 169 - ROW_PITCH * j
      if self.rowCanvas then
        lg.push("all")
        lg.setCanvas(self.rowCanvas)
        lg.clear(0, 0, 0, 0)
        lg.origin()
        self:drawIconRow(e, 13, false)
        lg.pop()
        lg.setColor(1, 1, 1, TOP_FADE[j + 1])
        lg.draw(self.rowCanvas, 0, y - 13)
        lg.setColor(1, 1, 1, 1)
      else
        self:drawIconRow(e, y, false)
      end
    end
  end
  local header = self:bwImg("list_header")
  if header then lg.draw(header, 0, 0) end
  ink(INK.title, self:text(276, self.national and 1 or 0) or "UNOVA POKéDEX", 8, 7)
  local seen, caught = self:counts()
  ink(INK.bar, self:text(276, 2) or "SEEN", 64, 30)
  inkRight(INK.bar, tostring(seen), 118, 30)
  ink(INK.bar, self:text(276, 3) or "OBTAINED", 168, 30)
  inkRight(INK.bar, tostring(caught), 245, 30)
end

function Gen5Pokedex:drawInfoTouch()
  lg.setColor(1, 1, 1, 1)
  local back = self:bwImg("info_touch")
  if back then lg.draw(back, 0, 0) else lg.setColor(0.03, 0.69, 0.47, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  local id = self.entries[self.cursor]
  local state = id and self:status(id)
  local def = ((self.game.data or {}).pokemon or {})[id] or {}
  local front = id and self:front(id)
  if front then lg.draw(front, -3, -1) end
  local caught = state == "caught"
  if caught then
    local hex = self:bwImg("ball_hex")
    if hex then lg.draw(hex, 88, 8) end
  end
  -- "No." and the number, the name
  lg.setColor(INK.box[1][1], INK.box[1][2], INK.box[1][3], 1)
  lg.rectangle("fill", 136, 19, 2, 2)
  lg.setColor(1, 1, 1, 1)
  ink(INK.box, self:number(id), 141, 15)
  inkCentre(INK.box, self:name(id), 195, 15)
  local key = caught and id or 0
  inkCentre(INK.box, self:text(260, key) or def.category or "", 187, 32)
  -- the types
  local objects = ((self.game.data or {}).gen4_graphics or {}).battleObjects or {}
  for i, t in ipairs(def.types or {}) do
    local name = tostring(t):lower()
    local rec = objects["type_icons_" .. name]
    local img = rec and self:image(rec.path)
    if img then lg.draw(img, 152 + (i - 1) * 34, 54 - 2) end
  end
  ink(INK.box, self:text(234, 195) or "HT", 144, 78)
  inkRight(INK.box, self:text(245, key) or "???", 243, 78)
  ink(INK.box, self:text(234, 202) or "WT", 144, 94)
  inkRight(INK.box, self:text(268, key) or "???", 243, 94)
  if caught then
    local entry = tostring(def.dexEntry or "")
    local y = 119
    for line in (entry:gsub("[\r\f\v]", "\n") .. "\n"):gmatch("([^\n]*)\n") do
      if y > 152 then break end
      ink(INK.entry, line, 20, y)
      y = y + 16
    end
  end
  self:drawFoot()
end

function Gen5Pokedex:drawInfoTop()
  lg.setColor(1, 1, 1, 1)
  local back = self:bwImg("info_top")
  if back then lg.draw(back, 0, 0) else lg.setColor(0.03, 0.69, 0.47, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  local header = self:bwImg("info_header")
  if header then lg.draw(header, 0, 0) end
  ink(INK.entry, self:text(234, 178) or "INFO", 25, 7)
end

-- THE AREA PAGE (top screen; the touch screen keeps the INFO panel, its AREA
-- tab lit). READ (ov208): the region and roads are the Town Map's own
-- (/a/0/8/5 palette 0, chars 5 / 7, screens 17 / 16 -- 0x021C0090; here
-- gen5_town_map's composed image); one marker per place (0x021C0450): the
-- dex's cell bank 28 in the anim the place's town-map cursor shape names, at
-- the cursor's x, y (record u16 24 / 25 / 26); the AREA record of /a/1/7/8
-- for the season (src/import/Gen5DexArt.lua: one block for all, else the
-- current season's); "Area Unknown" (bank 234 #128) when the block says so.
-- A place's value is three bit groups (READ: ov208 0x021C2238 lights three
-- 4 x 3-tile boxes of the touch screen's BG3 at tiles (7 / 14 / 21, 28),
-- palette [5,2] / [6,0] / [7,4] off / on, from value & 0x07, & 0x18, & 0x60
-- of the place under the cursor); INFERRED: the groups are walking / surfing /
-- fishing (Gen5Pokedex.areaKinds). NOT DONE: that place cursor and the three
-- boxes. INFERRED: every place with a non-zero value marked the same way, no blink, the title "{name}'s AREA"
-- (bank 234 #189) in the INFO header strip, the unknown box's placement.
function Gen5Pokedex:areaLocation(place)
  local r = (self.game.data or {}).gen5_town_map
  local zones = self.bw.areaZones
  if not (r and r.locations and zones) then return nil end
  self.areaLocs = self.areaLocs or {}
  if self.areaLocs[place] == nil then
    local found = false
    for _, loc in ipairs(r.locations) do
      if loc.zone == zones[place] then found = loc break end
    end
    self.areaLocs[place] = found
  end
  return self.areaLocs[place] or nil
end

-- a place value's three groups (READ masks, INFERRED names)
function Gen5Pokedex.areaKinds(v)
  local b = require("bit")
  return { walk = b.band(v, 0x07) ~= 0, surf = b.band(v, 0x18) ~= 0, fish = b.band(v, 0x60) ~= 0 }
end

function Gen5Pokedex:areaBlock(id)
  local rec = self.bw.area and self.bw.area[id]
  if not rec then return nil end
  if rec.same then return rec[1] end
  local Rules = require("src.world.Gen5FieldRules")
  return rec[Rules.season(self.game.save) + 1] or rec[1]
end

function Gen5Pokedex:drawAreaTop()
  lg.setColor(0, 0, 0, 1)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, 1, 1, 1)
  local r = (self.game.data or {}).gen5_town_map
  local map = r and r.image and self:image(r.image.path)
  if map then lg.draw(map, 0, 0) end
  local id = self.entries[self.cursor]
  local block = id and self:areaBlock(id)
  local any = false
  if block and not block.unknown then
    local cells = self.bw.areaSeqCell or {}
    for place in pairs(block.places or {}) do
      local loc = self:areaLocation(place)
      local cell = loc and cells[loc.cursorShape or 0]
      local img, rec = self:bwImg(("area_%d"):format(cell or 0))
      if loc and img and loc.cursor then
        lg.draw(img, loc.cursor[1] + (rec.originX or 0), loc.cursor[2] + (rec.originY or 0))
        any = true
      end
    end
  end
  local header = self:bwImg("info_header")
  if header then lg.draw(header, 0, 0) end
  local raw = id and ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(234, 189)]
  local title = self:text(234, 179) or "AREA"
  if type(raw) == "string" and raw ~= "" then
    title = (raw:gsub("{VAR1}", self:name(id)):gsub("{[^}]*}", ""))
  end
  ink(INK.entry, title, 25, 7)
  -- a record kept per season names the season (bank 234 #190..193; READ:
  -- ov208 0x021C1B2E picks the block by the season when byte 0 is clear)
  local rec = id and self.bw.area and self.bw.area[id]
  if rec and not rec.same then
    local Rules = require("src.world.Gen5FieldRules")
    local s = Rules.season(self.game.save)
    inkRight(INK.entry, self:text(234, 190 + s) or Rules.SEASONS[s], 247, 7)
  end
  if not any then
    local word = self:text(234, 128) or "Area Unknown"
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("fill", 48, 84, 160, 24)
    lg.setColor(1, 1, 1, 1)
    inkCentre(INK.entry, word, 128, 90)
  end
  lg.setColor(1, 1, 1, 1)
end

-- THE FORMS PAGE (top screen; the touch screen keeps the INFO panel, its
-- FORMS tab lit). READ: the words -- bank 234 #184 FORMS SEEN, #185 SHINY
-- SEEN, #114 / #115 Male / Female, #188 (Shiny). The record: the genders seen
-- in first-seen order (Gen45DexRecord.gendersSeen), the forms seen
-- (dex.gen5FormsSeen, INFERRED layout), the shiny bits of dex.gen5Seen
-- (2 male, 3 female). INFERRED: the layout (three pictures a row, the label
-- under each), a form other than 0 labelled by its def.forms name or number.
function Gen5Pokedex:formEntries(id)
  local out = {}
  local dex = (self.game.save or {}).pokedex or {}
  local Rec = require("src.pokemon.Gen45DexRecord")
  local def = ((self.game.data or {}).pokemon or {})[id] or {}
  local function word(g)
    if g == "female" then return self:text(234, 115) or "Female" end
    if g == "male" then return self:text(234, 114) or "Male" end
    return ""
  end
  local genders = Rec.gendersSeen(self.game, id)
  if #genders == 0 then genders = { "none" } end
  for _, g in ipairs(genders) do
    out[#out + 1] = { mon = { species = id, form = 0, gender = g ~= "none" and g or nil }, label = word(g) }
  end
  for _, fi in ipairs((dex.gen5FormsSeen or {})[id] or {}) do
    if fi ~= 0 then
      local f = type(def.forms) == "table" and def.forms[fi] or nil
      local name = type(f) == "table" and (f.name or f.formName) or tostring(fi)
      out[#out + 1] = { mon = { species = id, form = fi }, label = tostring(name) }
    end
  end
  local bits = tonumber((dex.gen5Seen or {})[id]) or 0
  for k, g in ipairs({ "male", "female" }) do
    if math.floor(bits / 2 ^ (k + 1)) % 2 == 1 then
      out[#out + 1] = { mon = { species = id, form = 0, gender = g, shiny = true },
                        label = (self:text(234, 188) or "(Shiny)"), shiny = true }
    end
  end
  return out
end

function Gen5Pokedex:drawFormsTop()
  lg.setColor(1, 1, 1, 1)
  local back = self:bwImg("info_top")
  if back then lg.draw(back, 0, 0) else lg.setColor(0.1, 0.1, 0.1, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  local header = self:bwImg("info_header")
  if header then lg.draw(header, 0, 0) end
  ink(INK.entry, self:text(234, 184) or "FORMS SEEN", 25, 7)
  local id = self.entries[self.cursor]
  if not id then return end
  local S = require("src.pokemon.Sprites")
  for i, e in ipairs(self:formEntries(id)) do
    if i > 6 then break end
    local cx = 43 + ((i - 1) % 3) * 85
    local y = 26 + math.floor((i - 1) / 3) * 82
    local ok, path = pcall(S.path, self.game.data, id, "front", { mon = e.mon })
    local img = ok and self:image(path) or nil
    if img then
      local w, h = img:getDimensions()
      local s = math.min(1, 64 / math.max(w, h))
      lg.draw(img, cx - floor(w * s / 2), y, 0, s, s)
    end
    inkCentre(INK.entry, e.label, cx, y + 66)
  end
end

function Gen5Pokedex:drawTouch()
  if self.mode ~= "list" then self:drawInfoTouch() else self:drawListTouch() end
end

function Gen5Pokedex:drawTop()
  if self.mode == "info" then self:drawInfoTop()
  elseif self.mode == "area" then self:drawAreaTop()
  elseif self.mode == "forms" then self:drawFormsTop()
  else self:drawListTop() end
end

function Gen5Pokedex:draw()
  if self:bottomOnSecond() then
    self:drawTop()
    SecondScreen.draw(self.game, function() self:drawTouch() end)
  elseif self.showTop then
    self:drawTop()
  else
    self:drawTouch()
  end
  lg.setColor(1, 1, 1, 1)
end

return Gen5Pokedex
