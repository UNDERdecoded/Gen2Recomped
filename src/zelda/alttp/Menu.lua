-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ITEM MENU (round 8), ported from the GBA's own code (RomMap.menu):
-- the cartridge's pre-rendered menu map on the HUD layer, its item, name,
-- equipment, ability and pendant word tables, its cursor and its states:
--
--   0 load the map (0x080AABC0)         4 nothing to choose: any key closes
--   1 draw the boxes (0x080AAC24)       5 choose (0x080AA4F8): the d-pad
--   2 pick an owned item, draw it         moves over the 6 x 4 grid to the
--     (0x080A9EA8 / 0x080A9FCC)           next owned item, A/B/SELECT close
--   3 slide down 8 px a frame           6/7 slide back up (0x080AA688)
--
-- Inventory bytes are the GBA's (offsets from 0x02002300; the item bytes
-- 0x20-0x37 are in grid order: slot n is byte 0x1F + n). Menu.inventory()
-- builds them from the port's own progress table.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local R = require("src.zelda.alttp.RomMap")

local M = {}
M.__index = M

-- SNES receipt item (what our chests give) -> GBA grid slot and value
M.RECEIPT_SLOT = {
  [0x0B] = { 1, 1 },  -- bow
  [0x0C] = { 2, 1 },  -- boomerang
  [0x0A] = { 3, 1 },  -- hookshot
  [0x12] = { 13, 1 }, -- lamp
  [0x29] = { 5, 1 },  -- mushroom
  [0x0D] = { 5, 2 },  -- magic powder
  [0x07] = { 7, 1 },  -- fire rod
  [0x08] = { 8, 1 },  -- ice rod
  [0x09] = { 14, 1 }, -- hammer
  [0x14] = { 15, 1 }, -- flute
  [0x13] = { 19, 1 }, -- shovel
  [0x21] = { 16, 1 }, -- bug net
  [0x1D] = { 17, 1 }, -- book
  [0x15] = { 20, 1 }, -- cane of somaria
  [0x18] = { 21, 1 }, -- cane of byrna
  [0x19] = { 22, 1 }, -- magic cape
  [0x1A] = { 23, 1 }, -- magic mirror
}

-- the GBA inventory bytes for the port's progress
function M.inventory(game)
  local inv = {}
  local p = game.progress or {}
  if p.sword then inv[0x3D] = 1; inv[0x3E] = 1 end   -- the uncle's sword and shield
  for _, id in ipairs(p.items or {}) do
    local s = M.RECEIPT_SLOT[id]
    if s then inv[0x1F + s[1]] = math.max(inv[0x1F + s[1]] or 0, s[2]) end
  end
  if p.inv then for k, v in pairs(p.inv) do inv[tonumber(k)] = v end end
  -- round 18: the bomb byte is the count (link_item_bombs); the bow is 1
  -- without arrows, 2 with (Hud: link_item_bow = arrows ? 2 : 1)
  local st = game.stats or {}
  if (st.bombs or 0) > 0 then inv[0x1F + 4] = st.bombs end
  if inv[0x1F + 1] == 1 and (st.arrows or 0) > 0 then inv[0x1F + 1] = 2 end
  return inv
end

function M.new(game)
  local self = setmetatable({ game = game, data = game.data }, M)
  self.t = game.data.menus
  return self
end

function M.available(data)
  return data and data.menus and data.ui and data.uiChr and true or false
end

-- ------------------------------------------------------------------ map

local function idx(pos) return (pos - 0x1000) / 2 + 1 end   -- map word index

function M:put(pos, w) self.words[idx(pos)] = w end

function M:loadMap()
  local map = self.t:get("itemMap")
  local w = {}
  for i = 0, 1023 do w[i + 1] = map:byte(i * 2 + 1) + map:byte(i * 2 + 2) * 256 end
  self.words = w
  -- 0x080A7B24: the box titles for the cartridge language
  for _, l in ipairs(R.menu.labels[R.ui.lang] or {}) do
    if type(l[2]) == "table" then
      for k, wd in ipairs(l[2]) do self:put(l[1] + (k - 1) * 2, wd) end
    else
      for k = 0, l[3] - 1 do self:put(l[1] + k * 2, l[2] + k) end
    end
  end
end

-- 4 words of a 2x2 icon (table + level * 8) at pos
function M:icon(pos, tab, level)
  local t = self.t
  local a = tab + level * 8
  self:put(pos, t:u16(a)); self:put(pos + 2, t:u16(a + 2))
  self:put(pos + 0x40, t:u16(a + 4)); self:put(pos + 0x42, t:u16(a + 6))
end

function M:gridPos(slot) return self.t:u16(R.menu.gridPos + (slot - 1) * 2) end

function M:owned(slot) return (self.inv[0x1F + slot] or 0) ~= 0 end

-- 0x080A8178: the 24 grid icons
function M:drawItems()
  local m = R.menu
  for s = 1, 24 do
    local v = self.inv[0x1F + s] or 0
    local tab = m.gridTab[s]
    if m.bottleSlots[s] then tab = m.bottleTab end
    if s == m.bombsSlot and v > 0 then v = 1 end
    self:icon(self:gridPos(s), tab, v)
  end
end

-- 0x080A97F8 (sword, shield, mail), 0x080A8D70 (the ability box),
-- 0x080A93B8 (pendants)
function M:drawBoxes()
  local m = R.menu
  for _, e in ipairs(m.equip) do self:icon(e[3], e[2], self.inv[e[1]] or 0) end
  local gl = self.inv[0x38] or 0
  if gl > 0 then self:put(m.glovesWord[1], m.glovesWord[2] + gl) end
  for _, e in ipairs(m.ability) do self:icon(e[3], e[2], self.inv[e[1]] or 0) end
  local pb = self.inv[m.pendants[1]] or 0
  for k = 2, 4 do
    local e = m.pendants[k]
    self:icon(e[2], e[1], band(rshift(pb, k - 2), 1))
  end
end

-- 0x080A9E38: keep the chosen item if it is owned, else the next owned one
function M:anyItem()
  for b = 0x20, 0x33 do if (self.inv[b] or 0) ~= 0 then return true end end
  return false
end

function M:nextOwned()
  local c = self.cur
  for _ = 1, 24 do
    c = c + 1
    if c > 24 then c = 1 end
    if self:owned(c) then break end
  end
  self.cur = c
end

function M:searchEquipped()
  if not self:anyItem() then self.cur = 0; return end
  if self.cur == 0 then self.cur = 1 end
  if not self:owned(self.cur) then self:nextOwned() end
end

-- 0x080A9FCC: the chosen item's icon and name in the top-right box
function M:drawSelected()
  local m, t = R.menu, self.t
  local s = self.cur
  if s < 1 then return end
  local p = self:gridPos(s)
  self:put(m.selIcon, self.words[idx(p)]); self:put(m.selIcon + 2, self.words[idx(p + 2)])
  self:put(m.selIcon + 0x40, self.words[idx(p + 0x40)]); self:put(m.selIcon + 0x42, self.words[idx(p + 0x42)])
  local lang = R.ui.lang
  local base = t:ptr(m.names + lang * 4) + (s - 1) * 32
  local v = self.inv[0x1F + s] or 0
  for _, e in ipairs(m.nameAlt) do
    if e[1] == s and v >= e[3] then base = t:ptr(e[2] + lang * 4) + (v - e[3]) * 32; break end
  end
  for k = 0, 7 do
    self:put(m.nameAt[1] + k * 2, t:u16(base + k * 2))
    self:put(m.nameAt[2] + k * 2, t:u16(base + 16 + k * 2))
  end
end

-- 0x080AA3EC: the blinking brackets round the chosen slot
function M:drawCursor(old)
  local m = R.menu
  if old and old >= 1 and old ~= self.cur then
    local p = self:gridPos(old)
    for _, o in ipairs({ -2, 0x3E, 4, 0x44 }) do self:put(p + o, 0x80F5) end
  end
  if self.cur < 1 then return end
  local p = self:gridPos(self.cur)
  local on = band(self.timer, 0x10) ~= 0
  local c = m.cursor
  self:put(p - 2, on and c[1] or 0x80F5); self:put(p + 0x3E, on and c[2] or 0x80F5)
  self:put(p + 4, on and c[3] or 0x80F5); self:put(p + 0x44, on and c[4] or 0x80F5)
end

-- --------------------------------------------------------------- states

function M:open()
  local g = self.game
  self.inv = M.inventory(g)
  g.progress.curItem = g.progress.curItem or 0
  self.cur = g.progress.curItem
  self.state, self.vofs, self.timer, self.done = 0, R.menu.vofsStart, 0, false
end

-- one GBA frame; input: wasPressed(b) / isDown(b)
function M:update(input)
  local st = self.state
  local function pressed(b) return input and input.wasPressed(b) end
  if st == 0 then
    self:loadMap(); self.state = 1
  elseif st == 1 then
    self:searchEquipped()
    self:drawItems(); self:drawBoxes()
    self.state = 2
  elseif st == 2 then
    if self:anyItem() then
      if not self:owned(self.cur) then self:nextOwned() end
      self:drawSelected()
      self.timer = 0x10
    end
    self.state = 3
  elseif st == 3 then
    self.vofs = self.vofs - 8
    if self.vofs == R.menu.vofsOpen + 4 then self.vofs = R.menu.vofsOpen; self.state = 4 end
  elseif st == 4 then
    if self:anyItem() then self.state = 5
    else
      for _, b in ipairs({ "a", "b", "select", "start", "l", "r", "up", "down", "left", "right" }) do
        if input and input.isDown(b) then self.state = 6 end
      end
    end
  elseif st == 5 then
    self.timer = (self.timer + 1) % 256
    if pressed("a") or pressed("b") or pressed("select") then
      self.state = 6
      return
    end
    local old = self.cur
    local c = self.cur
    local moved = true
    if pressed("up") then
      repeat
        local n = c - 6
        if n <= 0 then n = (n == -5) and 24 or (c + 17) end
        c = n
      until self:owned(c)
    elseif pressed("down") then
      repeat
        local n = c + 6
        if n > 24 then n = (n == 30) and 1 or (c - 17) end
        c = n
      until self:owned(c)
    elseif pressed("left") then
      repeat
        local n = c - 1
        if n <= 0 then n = c + 23 end
        c = n
      until self:owned(c)
    elseif pressed("right") then
      repeat
        local n = c + 1
        if n > 24 then n = c - 23 end
        c = n
      until self:owned(c)
    else
      moved = false
    end
    if moved then
      self.cur = c
      self:drawSelected()
      if c ~= old then self.timer = 0x10 end
    end
    self:drawCursor(old)
  elseif st == 6 then
    self.state = 7
  elseif st == 7 then
    self.vofs = self.vofs + 8
    if self.vofs >= 0 then
      self.vofs = R.menu.vofsStart
      self.done = true
      self.game.progress.curItem = self.cur
    end
  end
end

-- the BG3 picture: 32x32 map words, y scroll vofs, x scroll 8 (the HUD's)
function M:draw(view, pal)
  if not self.words then return false end
  local im = view:hudImage(self.words, 32, 32, pal, self.t:get("itemLang"))
  local y = -((self.vofs % 256))
  love.graphics.draw(im, -8, y)
  love.graphics.draw(im, -8, y + 256)
  return true
end

return M
