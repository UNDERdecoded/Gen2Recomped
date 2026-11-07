-- src/ui/Gen5MusicalDressUp.lua -- the Musical's Dress Up (overlay 133,
-- dup_fitting.c, on the cartridge a touch-screen drag and drop).
--
-- The Pokemon stands on the left in what it wears; the Prop Case's props
-- (the save's, src/script/Gen5Musical.lua) fill a grid on the right with
-- their own pictures and names. A prop goes where its table entry allows
-- (the position mask, byte 6 of /a/0/4/5 member 101: ears, head, eyes, face,
-- body, waist, hand -- two ears and two hands make the nine slots); A puts
-- the chosen prop on at its first free position, A on a worn prop takes it
-- off, B takes off the last one put on, and FINISH (or START) ends it.
--
-- TOUCH / MOUSE: a prop is dragged out of the case and dropped on the
-- Pokemon -- it goes on the nearest of the species' points (Gen5MusicalArt's
-- decoded pose) it may take, within 12 px (READ: ov133 0x021B7F54 calls the
-- search 0x021B8BB4 with range 12, which keeps the nearest of the nine points
-- -- each the prop's offset added to the point -- whose squared distance is
-- under 12 * 12, the touch taken relative to the Pokemon's origin at
-- (128, 112)); dropped elsewhere it goes back in the case. A worn prop can be
-- dragged off again (its pick-up radius here the same 12, INFERRED).
-- The FINISH button is the cartridge's own place on the touch screen's
-- bottom-left (READ: ov133 0x021B940C hit-tests the rects at 0x021BA594 --
-- y 136..192 x 0..48 FINISH, x 216..255 the case's other button); here it
-- keeps the stand-in's spot.
--
-- NO TIME LIMIT offline (READ: the fitting loop 0x021B940C ends only on the
-- FINISH touch; the one per-frame countdown, +0x18C2, is a 30-frame guard on
-- SE 0x624; the wireless end comes from the link, 0x0200FB24, not ported).
-- The points the show scores are each prop's TYPE against the show's
-- weights (Gen5Musical.score); the Dress Up adds nothing of its own.

local Font = require("src.render.Font")
local Art = require("src.ui.Gen5MusicalArt")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local COLS, ROWS, CELL = 5, 4, 26
local GRID_X, GRID_Y = 118, 26
local lg = love and love.graphics

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

function Screen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Screen)
  self.game, self.mon, self.show, self.onDone = game, opts.mon, opts.show, opts.onDone
  local M = require("src.script.Gen5Musical")
  local s = M.save(game.save)
  self.rec = M.rec(game.data)
  self.owned = {}
  for p = 0, 99 do if s.props[p] then self.owned[#self.owned + 1] = p end end
  self.outfit, self.worn = {}, {}
  self.page, self.index = 0, opts.startOnFinish and -1 or 1
  -- with no props or in the story's first visit the cursor starts on FINISH
  if #self.owned == 0 then self.index = -1 end
  self.t = 0
  pcall(function() require("src.core.Music").play(game.data, "SEQ_BGM_MSL_DRESSUP") end)
  return self
end

function Screen:pressed(key)
  local input = self.game.input
  return input and input.wasPressed and input:wasPressed(key)
end

local function se(self, name) pcall(function() require("src.core.Sound").play(self.game.data, name) end) end

-- may prop `p` go on `slot` (its kind's slots, then its position mask)
local KIND_SLOTS = { [0] = { 0, 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7, 8 } }
function Screen:allows(p, slot)
  local M = require("src.script.Gen5Musical")
  for _, s in ipairs(KIND_SLOTS[p.kind] or {}) do if s == slot then return true end end
  local mask = (p.mask or 0) % 128
  if (p.mask or 0) >= 0x80 and slot == 5 then mask = mask + 0x10 end
  return math.floor(mask / M.SLOT_BIT[slot]) % 2 == 1
end

function Screen:slotFor(id)
  local p = self.rec and self.rec.props and self.rec.props[id]
  if not p then return nil end
  local M = require("src.script.Gen5Musical")
  -- its own kind's position first (byte 8: 0 ears .. 6 hand), then any other
  -- its mask allows
  local KIND_SLOTS = { [0] = { 0, 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7, 8 } }
  -- (only where the species' Musical pose has a point: Gen5MusicalArt)
  local sp = self.mon and tonumber(self.mon.species)
  local function free(slot) return not self.outfit[slot] and Art.hasPoint(self.game.data, sp, slot) end
  for _, slot in ipairs(KIND_SLOTS[p.kind] or {}) do
    if free(slot) then return slot end
  end
  for slot = 0, M.SLOTS - 1 do
    local bit = M.SLOT_BIT[slot]
    local mask = (p.mask or 0) % 128
    -- bit 7 (back) wears on the body
    if (p.mask or 0) >= 0x80 and slot == 5 then mask = mask + 0x10 end
    if math.floor(mask / bit) % 2 == 1 and free(slot) then return slot end
  end
  return nil
end

function Screen:toggle(id)
  for slot, item in pairs(self.outfit) do
    if item.id == id then
      self.outfit[slot] = nil
      for k, s in ipairs(self.worn) do if s == slot then table.remove(self.worn, k) break end end
      se(self, "SEQ_SE_CANCEL1")
      return
    end
  end
  local slot = self:slotFor(id)
  if slot then
    self.outfit[slot] = { id = id }
    self.worn[#self.worn + 1] = slot
    se(self, "SEQ_SE_DECIDE1")
  else
    se(self, "SEQ_SE_BEEP")
  end
end

-- ------------------------------------------------------ touch / mouse --

local MON_X, MON_Y, DROP_R = 59, 150, 12
local function toUi(px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not rect then return px, py end
  return (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
end

-- a point of the Pokemon on the screen (nil when its pose has none)
function Screen:pointAt(slot)
  local pose = self.mon and Art.pose(self.game.data, tonumber(self.mon.species))
  local a = pose and Art.anchorsAt(pose, self.t)[slot]
  if not a then return nil end
  return MON_X + a.x, MON_Y + a.y, a.rot or 0
end

function Screen:touchpressed(id, px, py)
  local x, y = toUi(px, py)
  if x >= 182 and x < 248 and y >= 160 and y < 182 then se(self, "SEQ_SE_DECIDE1") self:finish() return true end
  local per = COLS * ROWS
  for k = 1, per do
    local pid = self.owned[self.page * per + k]
    if not pid then break end
    local cx = GRID_X + ((k - 1) % COLS) * CELL
    local cy = GRID_Y + math.floor((k - 1) / COLS) * CELL
    if x >= cx and x < cx + CELL and y >= cy and y < cy + CELL then
      self.index = k
      for slot, item in pairs(self.outfit) do if item.id == pid then self:takeOff(slot) end end
      self.held = { id = pid, x = x, y = y, touch = id }
      return true
    end
  end
  -- a worn prop, picked up by its point
  local best, bestD
  for slot in pairs(self.outfit) do
    local ax, ay = self:pointAt(slot)
    if ax then
      local d = (ax - x) ^ 2 + (ay - y) ^ 2
      if d <= DROP_R * DROP_R and (not bestD or d < bestD) then best, bestD = slot, d end
    end
  end
  if best then
    local pid = self.outfit[best].id
    self:takeOff(best)
    self.held = { id = pid, x = x, y = y, touch = id }
  end
  return true
end

function Screen:touchmoved(id, px, py)
  local h = self.held
  if not (h and h.touch == id) then return false end
  h.x, h.y = toUi(px, py)
  return true
end

function Screen:touchreleased(id)
  local h = self.held
  if not (h and h.touch == id) then return true end
  self.held = nil
  local p = self.rec and self.rec.props and self.rec.props[h.id]
  local best, bestD
  for slot = 0, 8 do
    local ax, ay, rot = self:pointAt(slot)
    if ax and p and self:allows(p, slot) then
      -- the point plus the prop's own offset, as drawn (Gen5MusicalArt)
      local dx, dy = (p.dx or 0) * ((slot == 1 or slot == 8) and -1 or 1), -(p.dy or 0)
      ax, ay = ax + math.cos(rot) * dx - math.sin(rot) * dy, ay + math.sin(rot) * dx + math.cos(rot) * dy
      local d = (ax - h.x) ^ 2 + (ay - h.y) ^ 2
      if d <= DROP_R * DROP_R and (not bestD or d < bestD) then best, bestD = slot, d end
    end
  end
  if best then
    if self.outfit[best] then self:takeOff(best) end
    self.outfit[best] = { id = h.id }
    self.worn[#self.worn + 1] = best
    se(self, "SEQ_SE_DECIDE1")
  else
    se(self, "SEQ_SE_CANCEL1")
  end
  return true
end

function Screen:takeOff(slot)
  self.outfit[slot] = nil
  for k, s in ipairs(self.worn) do if s == slot then table.remove(self.worn, k) break end end
end

function Screen:finish()
  require("src.core.Logger").debug("bw musical: Dress Up finished after %d frame(s)", self.t)
  pcall(function() require("src.core.Music").restoreMap(self.game.data) end)
  self.game.stack:pop()
  if self.onDone then self.onDone(self.outfit) end
end

function Screen:pageCount() return math.max(1, math.ceil(#self.owned / (COLS * ROWS))) end

function Screen:update()
  self.t = self.t + 1
  -- BW_MUSICAL_AUTODRESS="0,10,59": a harness dresses with these and finishes
  local auto = os.getenv and os.getenv("BW_MUSICAL_AUTODRESS")
  if auto and self.t == 2 then
    for id in auto:gmatch("%d+") do
      id = tonumber(id)
      local owned = false
      for _, o in ipairs(self.owned) do if o == id then owned = true end end
      if owned then self:toggle(id) end
    end
  end
  if auto then
    if self.t >= tonumber(os.getenv("BW_MUSICAL_AUTODRESS_FRAMES") or 30) then return self:finish() end
    return
  end
  local per = COLS * ROWS
  local onPage = math.min(per, #self.owned - self.page * per)
  if self:pressed("start") then return self:finish() end
  if self.index == -1 then
    if self:pressed("a") then se(self, "SEQ_SE_DECIDE1") return self:finish() end
    if (self:pressed("up") or self:pressed("left")) and onPage > 0 then self.index = onPage end
    return
  end
  local i = self.index
  if self:pressed("right") then
    if i % COLS == 0 or i == onPage then
      if self.page + 1 < self:pageCount() then self.page, self.index = self.page + 1, 1 end
    else self.index = i + 1 end
  elseif self:pressed("left") then
    if (i - 1) % COLS == 0 then
      if self.page > 0 then self.page, self.index = self.page - 1, 1 end
    else self.index = i - 1 end
  elseif self:pressed("down") then
    if i + COLS <= onPage then self.index = i + COLS else self.index = -1 end
  elseif self:pressed("up") then
    if i - COLS >= 1 then self.index = i - COLS end
  elseif self:pressed("a") then
    local id = self.owned[self.page * per + i]
    if id then self:toggle(id) end
  elseif self:pressed("b") then
    local slot = table.remove(self.worn)
    if slot then self.outfit[slot] = nil se(self, "SEQ_SE_CANCEL1") end
  end
end

local TYPE_INK = { [0] = { 0.35, 0.55, 0.95 }, { 0.95, 0.55, 0.75 }, { 0.65, 0.45, 0.85 }, { 0.95, 0.75, 0.3 } }

function Screen:draw()
  if not lg then return end
  local data = self.game.data
  lg.push("all")
  lg.setColor(0.98, 0.93, 0.85)
  lg.rectangle("fill", 0, 0, W, H)
  -- the fitting room's mirror
  lg.setColor(0.86, 0.78, 0.92)
  lg.rectangle("fill", 6, 18, 106, 150, 6, 6)
  lg.setColor(1, 1, 1)
  if self.mon then Art.drawMon(data, tonumber(self.mon.species), self.outfit, 59, 150, 1, { tick = self.t }) end
  -- the Prop Case
  lg.setColor(0.93, 0.86, 0.74)
  lg.rectangle("fill", GRID_X - 4, GRID_Y - 4, COLS * CELL + 8, ROWS * CELL + 8, 4, 4)
  local per = COLS * ROWS
  local wornIds = {}
  for _, item in pairs(self.outfit) do wornIds[item.id] = true end
  for k = 1, per do
    local id = self.owned[self.page * per + k]
    if not id then break end
    local cx = GRID_X + ((k - 1) % COLS) * CELL + CELL / 2
    local cy = GRID_Y + math.floor((k - 1) / COLS) * CELL + CELL / 2
    local p = self.rec and self.rec.props and self.rec.props[id]
    local ink = TYPE_INK[p and p.type or 0] or TYPE_INK[0]
    lg.setColor(ink[1], ink[2], ink[3], wornIds[id] and 0.95 or 0.35)
    lg.rectangle("fill", cx - CELL / 2 + 1, cy - CELL / 2 + 1, CELL - 2, CELL - 2, 3, 3)
    lg.setColor(1, 1, 1)
    Art.drawProp(data, id, cx, cy, CELL - 4)
    if k == self.index then
      lg.setColor(0.9, 0.2, 0.2)
      lg.setLineWidth(2)
      lg.rectangle("line", cx - CELL / 2, cy - CELL / 2, CELL, CELL, 3, 3)
    end
  end
  -- FINISH
  lg.setColor(self.index == -1 and 0.95 or 0.75, self.index == -1 and 0.4 or 0.55, 0.35)
  lg.rectangle("fill", 182, 160, 66, 22, 5, 5)
  lg.setColor(1, 1, 1)
  Font.draw("FINISH", 194, 165)
  -- the chosen prop's name and kind
  local id = self.index > 0 and self.owned[self.page * per + self.index]
  local p = id and self.rec and self.rec.props and self.rec.props[id]
  lg.setColor(0.2, 0.15, 0.1)
  if p then
    local words = self.rec.words or {}
    Font.draw(p.name or "", 118, 136)
    Font.draw((words[4 + (p.type or 0)] or ""), 118, 148)
  end
  Font.draw(("%d/%d"):format(self.page + 1, self:pageCount()), 118, 166)
  -- the prop being dragged
  if self.held then
    lg.setColor(1, 1, 1)
    Art.drawProp(data, self.held.id, self.held.x, self.held.y, 30)
  end
  Font.draw("DRESS UP", 8, 4)
  lg.pop()
end

return Screen
