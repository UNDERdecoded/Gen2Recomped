-- The HUD's floating elements (src/ui.c): the A / B / R buttons, the items
-- on A and B, the R action label, the beating heart -- each a sprite the
-- cartridge draws with DrawDirect from gUIElementDefinitions
-- (0x080C8F8C, 16 bytes: _4, _6, VRAM tile, sprite, update, button id,
-- ?, static gfx flag).  Dynamic elements copy their frame's tiles from
-- sprite 322 to their VRAM tile (sub_0801CB20 / sub_0801C25C).
--
-- Buttons glide to gHUD.buttonX/Y at most 4 px a frame and drop 40 px
-- out of view while hidden or while a message is up
-- (ButtonUIElement_Action1).  Menus re-lay the buttons with a
-- KeyButtonLayout (sub_080A70AC).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local Ui = {}
Ui.__index = Ui

local T = { BUTTON_A = 0, BUTTON_B = 1, BUTTON_R = 2, ITEM_A = 3, ITEM_B = 4, TEXT_R = 5,
            HEART = 6, EZLONAG_START = 7, EZLONAG_ACTIVE = 8, TEXT_A = 9, TEXT_B = 10 }
Ui.T = T
-- R_ACTION_* (player.h)
Ui.R = { none = 0, cancel = 1, drop = 2, throw = 3, read = 4, check = 5, open = 6, speak = 7,
         grab = 8, lift = 9, grow = 10, shrink = 11, roll = 12 }
local TEXT_BASE = 0x92 -- gUnk_080C9044[language 1]

function Ui.new(ppu)
  local self = setmetatable({ ppu = ppu, A = ppu.A, elements = {}, hideFlags = 0 }, Ui)
  self.buttonX = { [0] = 0xD0, 0xB8, 0xD8 }
  self.buttonY = { [0] = 0x1C, 0x1C, 0x0E }
  self.buttonText = { [0] = 0, 0, 0 }
  local t = ppu:table("uiDefs")
  self.defs = {}
  for i = 0, 10 do
    local a = t.base + 16 * i
    self.defs[i] = { _4 = t.u16(a), _6 = t.u16(a + 2), tile = t.u16(a + 4), sprite = t.u16(a + 6),
                     button = t.u8(a + 12), static = t.u8(a + 14) ~= 0 }
  end
  return self
end

-- CreateUIElement
function Ui:create(type, type2)
  local d = self.defs[type]
  self.elements[#self.elements + 1] = { type = type, type2 = type2 or 0, frame = 0xFF, action = 0,
                                        tile = d.tile, button = d.button, pal = 0, x = 0, y = 0, shown = false }
end

-- InitUI's elements, in its order
function Ui:initField()
  self.elements = {}
  self.buttonX = { [0] = 0xD0, 0xB8, 0xD8 }
  self.buttonY = { [0] = 0x1C, 0x1C, 0x0E }
  for _, e in ipairs({ { T.TEXT_R, 9 }, { T.ITEM_A }, { T.ITEM_B }, { T.BUTTON_R }, { T.BUTTON_B },
                       { T.BUTTON_A }, { T.EZLONAG_START }, { T.HEART } }) do
    self:create(e[1], e[2])
  end
end

-- sub_080A70AC(KeyButtonLayout): button places / labels, then the list of
-- {type, type2} pairs
function Ui:layout(l)
  self.elements = {}
  self.buttonX = { [0] = l[1], l[4], l[7] }
  local function s8(v) return v >= 128 and v - 256 or v end
  self.buttonY = { [0] = s8(l[2]), s8(l[5]), s8(l[8]) }
  self.buttonText = { [0] = l[3], l[6], l[9] }
  for _, e in ipairs(l.elements or {}) do self:create(e[1], e[2]) end
end

function Ui:find(type)
  for _, e in ipairs(self.elements) do if e.type == type then return e end end
end

-- sub_0801CAFC / sub_0801CB20: a new frame copies its tiles (dynamic ones)
function Ui:setFrame(e, f)
  if f == e.frame then return end
  e.frame = f
  local d = self.defs[e.type]
  if d.static then return end
  local s = self.A:sprite(d.sprite)
  local fr = s and s.frames[f]
  if fr and fr[1] > 0 and s.gfxRaw then
    self.ppu:write(0x06010000 + e.tile * 32, s.gfxRaw, fr[3] * 32, fr[1] * 32)
  end
end

local function animStart(self, e, keys)
  e.keys, e.k = keys, 1
  e.dur = keys[1][2]
  self:setFrame(e, keys[1][1])
end

local function animStep(self, e)
  if not e.keys then return end
  e.dur = e.dur - 1
  if e.dur <= 0 then
    local k = e.k
    if band(e.keys[k][4] or 0, 0x80) ~= 0 then k = k + 1 - (e.keys.loopBack or 0) else k = k + 1 end
    if not e.keys[k] then k = 1 end
    e.k = k
    e.dur = e.keys[k][2]
    if e.dur == 0 then e.dur = 1 end
    self:setFrame(e, e.keys[k][1])
  end
end

-- st: { equipped = {a=, b=}, health =, messageActive =, rAction = R_ACTION id,
--       counts = {[item] = {have, max}} }
function Ui:update(st)
  local sign = function(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
  for _, e in ipairs(self.elements) do
    local t = e.type
    if t <= T.BUTTON_R then
      if e.action == 0 then
        e.x, e.y = self.buttonX[t], self.buttonY[t] - 0x20
        e.action = 1; e.shown = true
        self:setFrame(e, t)
      else
        local maxMove = e.type2 == 0 and 4 or 8
        local ty = self.buttonY[t]
        if e.type2 == 0 and (band(rshift(self.hideFlags, t), 1) ~= 0 or st.messageActive) then ty = ty - 0x28 end
        local dy = ty - e.y
        e.y = e.y + math.min(math.abs(dy), maxMove) * sign(dy)
        local dx = self.buttonX[t] - e.x
        e.x = e.x + math.min(math.abs(dx), maxMove) * sign(dx)
      end
    elseif t == T.ITEM_A or t == T.ITEM_B then
      e.shown = false
      local item = (t == T.ITEM_A) and st.equipped.a or st.equipped.b
      if item and item ~= 0 then
        if e.item ~= item then
          e.item = item
          local s = self.A:sprite(0x142)
          local keys = s and s.anims[item]
          if keys then animStart(self, e, keys) end
        end
        local c = st.counts and st.counts[item]
        e.pal = (c and c[1] >= c[2]) and 4 or 3
        local b = self:find(t == T.ITEM_A and T.BUTTON_A or T.BUTTON_B)
        if b then e.x, e.y = b.x, b.y; e.shown = e.keys ~= nil; animStep(self, e) end
      end
    elseif t == T.TEXT_R or t == T.TEXT_A or t == T.TEXT_B then
      if e.type2 == 9 then self.buttonText[2] = st.rAction or 0 end
      local f = self.buttonText[e.button]
      e.shown = false
      if f and f ~= 0 then
        self:setFrame(e, f + TEXT_BASE)
        local b = self:find(e.button)
        if b then e.x, e.y = b.x, b.y; e.shown = true end
      end
    elseif t == T.HEART then
      e.shown = false
      local h = st.health or 0
      if band(self.hideFlags, 0x10) == 0 and not st.messageActive and h > 0 then
        e.shown = true
        local tmp = rshift(h + 3, 2) * 8
        e.x, e.y = tmp + 3, 0x0C
        if h > 0x28 then e.x, e.y = tmp - 0x4D, 0x14 end
        local q = band(h, 3)
        self:setFrame(e, (q == 0 and 4 or q) + 0x71)
      end
    end
  end
end

-- DrawUIElements
function Ui:draw()
  for _, e in ipairs(self.elements) do
    if e.shown and e.frame ~= 0xFF then
      local d = self.defs[e.type]
      self.ppu:drawDirect(d.sprite, e.frame, { x = e.x, y = e.y, _4 = d._4, _6 = d._6,
                                               _8 = e.pal * 0x1000 + e.tile })
    end
  end
end

return Ui
