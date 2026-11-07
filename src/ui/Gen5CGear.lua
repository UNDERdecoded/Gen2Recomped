-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S C-GEAR: the field's lower screen once it is given, in the
-- cartridge's own art (/a/0/3/0, src/import/Gen5CGearArt.lua ->
-- `gen5_cgear_art`). Offline: no link is ever made, so the buttons only say so.
--
-- READ FROM CODE (Black, no decomp; ov029 base 0x021EFEC0 is the live screen):
--   the save block (GetSaveBlock 0x20, 0x02009210; init 0x020090B4): 36 cell
--     bytes, column-major 9 x 4 -- low nibble the button group (1 IR, 2
--     WIRELESS, 3 ONLINE, 4 a plain cell, 0 empty; 0x02009110), bit 0x80 the
--     group's icon cell (0x02009134) -- copied from arm9 0x020A7174 on a new
--     save (DEFAULT_LAYOUT below); +0x27 set by script 0x19B (0x020090D8),
--     +0x28 the skin 0..4 (0x020090E8 / 0x020090F0)
--   the cells (0x021F13FC -> 0x021F1290 -> 0x021F0D14): column c has 3 rows
--     when even, 4 when odd (0x021F332C); its 4 x 4 tile block sits at tile x
--     4c - 2, y (6 even / 4 odd) + 4r (0x021F3344); the palette row is
--     0x021F323C[k * 5 + level], k = 0x021F31D4[type], level =
--     0x021F32B3[k * 9 + c] (the middle column's for an icon cell)
--   the OBJs (0x021F1950): x 0x021F3531, y 0x021F353C, anim 0x021F3526 --
--     AM/PM (63, 22, hidden by the clock), the clock 32/38/42/47/53 at y 22
--     (0x021F1F80: hour / 10 hidden when 0, hour % 10, the colon blinking on
--     the second, minute / 10, minute % 10 -- 24-hour), the battery (178, 22),
--     the logo (128, 22), help (198, 170), the wrench (174, 170), power
--     (222, 170); the group labels IR / WIRELESS / ONLINE (anims 8..10 =
--     cells 23..25) at the group's icon cell, tile x * 8 + 16, y * 8 + 15
--     (0x021F20AC), off-screen when the layout has none
--   the power: script 0x19B sets +0x27 and turns it on (task 0x02168B21 ->
--     0x02012158, bit 0x400 of the field's state halfword); 0x25E turns it
--     off (save.gen5CGearOn = false, src/script/Gen5MiscFieldOps.lua)
--   the words: bank 22 (#0 turn on?, #2 turn off?, #4 cannot be turned on,
--     #5 YES, #6 NO), bank 23 #12 "C-Gear Detected"
-- INFERRED: the OFF look (every cell drawn as an empty one, the labels gone,
--   help and wrench in their dim frames 53 / 27); the message screen's
--   placement (ov035's two windows: tiles (1, 1) 30 x 6 and (1, 13) 30 x 10
--   on member 3); the group buttons answering with bank 22 #4 (offline the
--   wireless is off, which is the cartridge's own reason it cannot connect);
--   the static frames of the animated OBJs (battery full, wrench / help /
--   power lit).

local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local Gen5CGear = {}
Gen5CGear.__index = Gen5CGear
Gen5CGear.isOpaque = false

local W, H = 256, 192
local floor = math.floor
local lg = love.graphics

function Gen5CGear:uiSize() return W, H end
function Gen5CGear:wantsFillScale() return true end
function Gen5CGear:wantsEdgeBleed() return false end

-- arm9 0x020A7174 (Black): the layout a new save starts with, column-major
Gen5CGear.DEFAULT_LAYOUT = {
  0x00, 0x04, 0x00, 0x00,  0x00, 0x04, 0x04, 0x00,  0x04, 0x04, 0x04, 0x00,
  0x04, 0x04, 0x04, 0x04,  0x81, 0x83, 0x82, 0x00,  0x04, 0x04, 0x04, 0x04,
  0x04, 0x04, 0x04, 0x00,  0x00, 0x04, 0x04, 0x00,  0x00, 0x04, 0x00, 0x00,
}
Gen5CGear.KIND = { [0] = 0, 1, 2, 3, 4, 4 }                    -- 0x021F31D4
Gen5CGear.LEVELS = { [0] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 } }     -- 0x021F32B3
for k = 1, 4 do Gen5CGear.LEVELS[k] = { 0, 1, 2, 3, 4, 3, 2, 1, 0 } end
Gen5CGear.PAL_ROW = { [0] = { 6, 5, 4, 3, 2 } }                -- 0x021F323C
for k = 1, 4 do Gen5CGear.PAL_ROW[k] = { 5, 4, 3, 2, 1 } end
Gen5CGear.LABEL_CELL = { 23, 24, 25 }
-- THE TOUCHED RING (READ: ov029 0x021EFF58, called from the touch handler
-- 0x021F30BE): a touched cell starts anim 10 + its type at the cell's centre,
-- tile x * 8 + 16, y * 8 + 16; anims 11..13 (/a/0/3/0 member 20, SRT frames):
-- { cell, frames, scale } -- the ring grows 1.06 -> 1.44 and fades, then the
-- empty cell 35 for 30 frames (not drawn)
Gen5CGear.RING = {
  { { 20, 2, 1.06 }, { 20, 1, 1.11 }, { 20, 1, 1.17 }, { 20, 1, 1.22 }, { 20, 1, 1.28 }, { 28, 1, 1.33 }, { 29, 2, 1.39 }, { 29, 2, 1.44 } },
  { { 21, 2, 1.06 }, { 21, 1, 1.11 }, { 21, 1, 1.17 }, { 21, 1, 1.22 }, { 21, 1, 1.28 }, { 30, 1, 1.33 }, { 31, 2, 1.39 }, { 31, 2, 1.44 } },
  { { 22, 2, 1.06 }, { 22, 1, 1.11 }, { 22, 1, 1.17 }, { 22, 1, 1.22 }, { 22, 1, 1.28 }, { 32, 1, 1.33 }, { 33, 2, 1.39 }, { 33, 2, 1.44 } },
}

-- the ring's frame `f` (60 Hz frames since it started), or nil once it is over
function Gen5CGear.ringFrame(group, f)
  local t = 0
  for _, fr in ipairs(Gen5CGear.RING[group] or {}) do
    t = t + fr[2]
    if f < t then return fr end
  end
  return nil
end

local INK = { { 248 / 255, 248 / 255, 248 / 255 }, { 72 / 255, 72 / 255, 80 / 255 } }
local INK_DIM = { { 120 / 255, 120 / 255, 128 / 255 }, { 40 / 255, 40 / 255, 48 / 255 } }

-- ------------------------------------------------------------------ state --

function Gen5CGear.owned(save)
  save = save or {}
  return save.gen5CGearOwned == true or save.gen5CGearOn ~= nil
end

function Gen5CGear.powered(save)
  return (save or {}).gen5CGearOn == true
end

function Gen5CGear.rows(col) return col % 2 == 0 and 3 or 4 end

-- the top-left tile of cell (col, row)
function Gen5CGear.cellTile(col, row)
  return col * 4 - 2, (col % 2 == 0 and 6 or 4) + row * 4
end

function Gen5CGear.cellAt(layout, col, row)
  local v = layout[col * 4 + row + 1] or 0
  return v % 16, v >= 0x80
end

-- the palette row a cell is drawn in
function Gen5CGear.paletteRow(kindOfType, col, icon)
  local k = Gen5CGear.KIND[kindOfType] or 0
  local level = Gen5CGear.LEVELS[k][icon and 5 or (col + 1)]
  return Gen5CGear.PAL_ROW[k][level + 1]
end

function Gen5CGear.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen5CGear)
  self.game = game
  self.onCancel = opts.onCancel
  self.art = (game.data or {}).gen5_cgear_art or {}
  self.cache = {}
  self.clock = 0
  self.prompt = nil
  return self
end

function Gen5CGear:layout() return Gen5CGear.DEFAULT_LAYOUT end

function Gen5CGear:gender()
  local save = self.game.save or {}
  local g = save.playerGender or save.gender or (save.player or {}).gender
  if g == 1 or g == "female" or g == "f" or g == "girl" then return "f" end
  return "m"
end

function Gen5CGear:skin()
  local s = tonumber((self.game.save or {}).gen5CGearSkin) or 0
  return math.max(0, math.min(4, floor(s)))
end

function Gen5CGear:image(path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen5CGear:art_(key)
  local rec = self.art[key]
  if type(rec) ~= "table" then return nil end
  return self:image(rec.path), rec
end

function Gen5CGear:text(bank, entry, fallback)
  local s = ((self.game.data or {}).text or {})[("TEXT_G5S_%04d_%05d"):format(bank, entry)]
  if type(s) ~= "string" or s == "" then return fallback end
  return (s:gsub("{[^}]*}", ""))
end

-- ------------------------------------------------------------------- draw --

function Gen5CGear:obj(cell, x, y)
  local img, rec = self:art_(("obj_%s_%d"):format(self:gender(), cell))
  if img then lg.draw(img, x + (rec.originX or 0), y + (rec.originY or 0)) end
end

function Gen5CGear:drawHoneycomb(on)
  local tag = ("%s_%d"):format(self:gender(), self:skin())
  local sheet = self:art_("hex_" .. tag)
  if not sheet then return end
  local layout = self:layout()
  self.quads = self.quads or {}
  for col = 0, 8 do
    for row = 0, Gen5CGear.rows(col) - 1 do
      local t, icon = Gen5CGear.cellAt(layout, col, row)
      if not on then t, icon = 0, false end
      local p = Gen5CGear.paletteRow(t, col, icon)
      local tx, ty = Gen5CGear.cellTile(col, row)
      -- 0x021F1290 writes only the tiles with 0 <= x < 32
      local first, last = math.max(0, -tx), math.min(3, 31 - tx)
      if last >= first then
        local key = ("%d_%d_%d_%d"):format(t, p, first, last)
        local q = self.quads[key]
        if not q then
          q = lg.newQuad(t * 32 + first * 8, p * 32, (last - first + 1) * 8, 32, sheet:getDimensions())
          self.quads[key] = q
        end
        lg.draw(sheet, q, (tx + first) * 8, ty * 8)
      end
    end
  end
end

function Gen5CGear:drawClock()
  local ok, t = pcall(os.date, "*t")
  if not ok or type(t) ~= "table" then return end
  local h, m = t.hour or 0, t.min or 0
  if floor(h / 10) ~= 0 then self:obj(floor(h / 10), 32, 22) end
  self:obj(h % 10, 38, 22)
  self:obj((t.sec or 0) % 2 == 0 and 10 or 11, 42, 22)
  self:obj(floor(m / 10), 47, 22)
  self:obj(m % 10, 53, 22)
end

function Gen5CGear:drawLabels()
  local layout = self:layout()
  for group = 1, 3 do
    for col = 0, 8 do
      for row = 0, Gen5CGear.rows(col) - 1 do
        local t, icon = Gen5CGear.cellAt(layout, col, row)
        if t == group and icon then
          local tx, ty = Gen5CGear.cellTile(col, row)
          self:obj(Gen5CGear.LABEL_CELL[group], tx * 8 + 16, ty * 8 + 15)
        end
      end
    end
  end
end

function Gen5CGear:drawPrompt()
  local p = self.prompt
  local g = self:gender()
  local img = self:art_("msg_" .. g)
  if img then lg.draw(img, 0, 0) else lg.setColor(0, 0.2, 0.3, 1); lg.rectangle("fill", 0, 0, W, H); lg.setColor(1, 1, 1, 1) end
  local y = 12
  for line in (p.text .. "\n"):gmatch("(.-)\n") do
    Font.pushStyle({ text = INK[1], shadow = INK[2] })
    Font.draw(line, 12, y)
    Font.popStyle()
    y = y + 16
  end
  if p.yesNo then
    local yes, no = self:text(22, 5, "YES"), self:text(22, 6, "NO")
    for i, word in ipairs({ yes, no }) do
      local wy = 112 + (i - 1) * 24
      if p.choice == i then
        lg.setColor(1, 1, 1, 0.25); lg.rectangle("fill", 16, wy - 4, 224, 20); lg.setColor(1, 1, 1, 1)
      end
      Font.pushStyle({ text = (p.choice == i and INK or INK_DIM)[1], shadow = (p.choice == i and INK or INK_DIM)[2] })
      Font.draw(word, 128 - floor(Font.width(word) / 2), wy)
      Font.popStyle()
    end
  end
end

-- the whole lower screen, in its own 256 x 192
function Gen5CGear:drawWatch()
  local save = self.game.save
  lg.setColor(0, 0, 0, 1)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, 1, 1, 1)
  if not Gen5CGear.owned(save) then return end
  if self.prompt then return self:drawPrompt() end
  local on = Gen5CGear.powered(save)
  local tag = ("%s_%d"):format(self:gender(), self:skin())
  local back = self:art_("back_" .. tag)
  if back then lg.draw(back, 0, 0) end
  self:drawHoneycomb(on)
  local bar = self:art_("bar_" .. tag)
  if bar then lg.draw(bar, 0, 0) end
  self:drawClock()
  self:obj(16, 178, 22)
  self:obj(36, 128, 22)
  self:obj(on and 26 or 27, 174, 170)
  self:obj(on and 52 or 53, 198, 170)
  self:obj(54, 222, 170)
  if on then self:drawLabels() end
  self:drawRing()
end

function Gen5CGear:drawRing()
  local r = self.ring
  if not r then return end
  local fr = Gen5CGear.ringFrame(r.group, floor(r.t * 60))
  if not fr then return end
  local img = self:art_(("obj_%s_%d"):format(self:gender(), fr[1]))
  if img then
    local w, h = img:getDimensions()
    lg.draw(img, r.x, r.y, 0, fr[3], fr[3], w / 2, h / 2)
  end
end

function Gen5CGear:draw()
  if SecondScreen.mode(self.game) == "off" then return self:drawWatch() end
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawWatch() end)
end

-- ------------------------------------------------------------------ input --

function Gen5CGear:sound(name)
  local ok, Sound = pcall(require, "src.core.Sound")
  local data = self.game and self.game.data
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, name) end
end

function Gen5CGear:ask(entry, onYes)
  self.prompt = { text = self:text(22, entry, ""), yesNo = true, choice = 2, onYes = onYes }
end

function Gen5CGear:tell(entry)
  self.prompt = { text = self:text(22, entry, "") }
end

function Gen5CGear:answer(yes)
  local p = self.prompt
  self.prompt = nil
  if yes and p and p.onYes then p.onYes() end
end

function Gen5CGear:powerPressed()
  local save = self.game.save
  if not save then return end
  if Gen5CGear.powered(save) then
    self:ask(2, function() save.gen5CGearOn = false end)
  else
    self:ask(0, function() save.gen5CGearOn = true; save.gen5CGearOwned = true end)
  end
end

-- which cell of the honeycomb (col, row) is under (x, y), by the nearest centre
function Gen5CGear.hitCell(x, y)
  local best, bc, br = 15 * 15, nil, nil
  for col = 0, 8 do
    for row = 0, Gen5CGear.rows(col) - 1 do
      local tx, ty = Gen5CGear.cellTile(col, row)
      local dx, dy = x - (tx * 8 + 16), y - (ty * 8 + 16)
      if dx * dx + dy * dy < best then best, bc, br = dx * dx + dy * dy, col, row end
    end
  end
  return bc, br
end

function Gen5CGear:tap(x, y)
  local save = self.game.save
  if not Gen5CGear.owned(save) then return false end
  if self.prompt then
    local p = self.prompt
    if not p.yesNo then self.prompt = nil return true end
    for i = 1, 2 do
      local wy = 112 + (i - 1) * 24
      if x >= 16 and x < 240 and y >= wy - 4 and y < wy + 16 then
        self:sound("decide")
        self:answer(i == 1)
        return true
      end
    end
    return true
  end
  if x >= 210 and x < 236 and y >= 158 and y < 184 then self:powerPressed() return true end
  if not Gen5CGear.powered(save) then self:powerPressed() return true end
  local col, row = Gen5CGear.hitCell(x, y)
  if col then
    local t = Gen5CGear.cellAt(self:layout(), col, row)
    if t >= 1 and t <= 3 then
      -- the ring first, then (offline) the reason it cannot connect
      local tx, ty = Gen5CGear.cellTile(col, row)
      self:sound("decide")
      self.ring = { group = t, x = tx * 8 + 16, y = ty * 8 + 16, t = 0, thenTell = 4 }
      return true
    end
  end
  return true
end

function Gen5CGear:touchpressed(id, px, py)
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x or x < 0 or y < 0 or x >= W or y >= H then return false end
  return self:tap(floor(x), floor(y))
end

function Gen5CGear:mousepressed(px, py, button)
  return self:touchpressed("mouse", px, py)
end

function Gen5CGear:updatePresentation(dt)
  self.clock = self.clock + (dt or 0)
  local r = self.ring
  if r then
    r.t = r.t + (dt or 0)
    if not Gen5CGear.ringFrame(r.group, floor(r.t * 60)) then
      self.ring = nil
      if r.thenTell then self:tell(r.thenTell) end
    end
  end
end

function Gen5CGear:close()
  self.prompt = nil
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen5CGear:update(dt)
  self:updatePresentation(dt)
  local input = self.game.input
  if not input then return end
  local p = self.prompt
  if p then
    if p.yesNo then
      if input:wasPressed("up") or input:wasPressed("down") then p.choice = 3 - p.choice; self:sound("select") end
      if input:wasPressed("a") then self:sound("decide"); self:answer(p.choice == 1) end
      if input:wasPressed("b") then self:answer(false) end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      self.prompt = nil
    end
    return
  end
  if input:wasPressed("b") or input:wasPressed("l") or input:wasPressed("start") then return self:close() end
  if input:wasPressed("a") then self:powerPressed() end
end

return Gen5CGear
