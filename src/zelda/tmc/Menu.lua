-- The pause menu (src/menu/pauseMenu.c, figurineMenu.c sub_080A4D34 /
-- sub_080A4DB8), drawn by the cartridge's own screens through Ppu.lua.
--
-- Opening: LoadGfxGroups (16, 23, item gfx 25 / 27), palette groups 11
-- and 12, palette group $B5 and the backdrop gfx group $56 + (2 when
-- health <= 8, else 1 when 9+ eighths are missing, else 0) on BG3
-- ($1E0B).  Each screen (gUnk_08128A38 -> gUnk_08128AD8) sets DISPCNT,
-- the BG1 / BG2 controls, a palette group and a gfx group, then its own
-- code draws OAM: the page tabs (sprite $1FB frames 0-2, sub_080A5128),
-- the cursor and the items (sprite 322 frames with their tiles copied to
-- OBJ VRAM, sub_080A5F48), and the HUD buttons through Ui.lua with the
-- screen's KeyButtonLayout.  The item description is ShowTextBox($04xx)
-- with the font at gUnk_08128FA8 into BG0.
--
-- START closes; L / R / B move between screens by the screen's
-- gMenu.field_0xc table ({START, L, R, B}); a screen change fades the
-- pages out and in by 2/16 a frame (PauseMenu_Variant3 / 5).

local bit = require("bit")
local band, bor = bit.band, bit.bor
local Ppu = require("src.zelda.tmc.Ppu")
local Ui = require("src.zelda.tmc.Ui")

local Menu = {}
Menu.__index = Menu

local SPRITE_MENU = 0x1FB   -- DRAW_DIRECT_SPRITE_INDEX (USA)
local SPRITE_ITEMS = 0x142
local ITEM_MAP, ITEM_KINSTONE_BAG, ITEM_SHELLS = 0x47, 0x67, 0x3F
local ITEM_TINGLE_TROPHY, ITEM_CARLOV_MEDAL = 0x3D, 0x3E
local SLOT_SAVE = 16

-- pauseData offsets (0x08128A38 ..)
local A = {
  screens = 0x08128A38, settings = 0x08128AD8, itemLayout = 0x08128B50, itemTable = 0x08128B64,
  itemKeys = 0x08128BF4, questKeys = 0x08128C00, questLayout = 0x08128C04, questTable = 0x08128C94,
  font = 0x08128FA8, kinKeys = 0x08128D51, kinLayout = 0x08128D60,
}

function Menu.new(field)
  return setmetatable({ field = field, open = false, screen = 1, cursors = {}, ticks = 0 }, Menu)
end

function Menu:toggle()
  if self.open then
    self.open = false
    self.field:sound(0x66) -- SFX_TEXTBOX_CLOSE
  else
    self:openMenu()
    self.field:sound(0x65) -- SFX_TEXTBOX_OPEN
  end
end

local function readLayout(t, a)
  local l = {}
  for i = 1, 9 do l[i] = t.u8(a + i - 1) end
  l.elements = {}
  local p = a + 9
  while t.u8(p) ~= 0xFF and #l.elements < 8 do
    l.elements[#l.elements + 1] = { t.u8(p), t.u8(p + 1) }
    p = p + 2
  end
  return l
end

function Menu:openMenu()
  local f = self.field
  local p = Ppu.new(f.assets)
  self.ppu = p
  self.data = p:table("pauseData")
  -- sub_080A4D34
  for _, g in ipairs({ 16, 23 }) do p:loadGfxGroup(g) end
  p:loadGfxGroup(f:inventory(0x08) ~= 0 and 24 or 25)
  p:loadGfxGroup(f:inventory(0x0C) ~= 0 and 28 or 27)
  p:loadPaletteGroup(11); p:loadPaletteGroup(12); p:setColor(0, 0)
  p:loadPaletteGroup(0xB5)
  local s = f.save.stats
  local v = 0
  if s.health <= 8 then v = 2 elseif s.maxHealth - s.health >= 9 then v = 1 end
  p:loadGfxGroup(0x56 + v)
  p.bg[3].control = 0x1E0B; p.bg[3].updated = true
  -- InitUI's BG0 (the HUD layer the descriptions draw into)
  p.bg[0].control = 0x1F0C
  self.ui = Ui.new(p)
  self.open = true
  self.state = 2         -- gPauseMenuOptions.unk11: 2 = live, 3 = fading out, 5 = fading in
  self.fade = 0          -- unk16
  self:setScreen(self.screen or 1)
end

-- sub_080A50A0: screen 15 is the map the area has
function Menu:resolve(n)
  if n == 15 then
    local info = self.field.room.areaInfo
    n = (info and (info.location or 0) >= 0x17) and 5 or 4
  end
  return n
end

-- sub_080A4DB8 + the screen's Init
function Menu:setScreen(n)
  local p, t = self.ppu, self.data
  self.screen = n
  p:clearBuffers({ [0] = true, true, true })
  self.textId = nil
  local idx = t.u8(A.screens + 8 * n)
  local a = A.settings + 8 * idx
  p.dispcnt = bor(t.u16(a + 2), 0x1940)
  for b = 0, 2 do p.bg[b].x, p.bg[b].y, p.bg[b].updated = 0, 0, true end
  p.bg[1].control = t.u16(a + 4)
  p.bg[2].control = t.u16(a + 6)
  p.bg[3].control = 0x1E0B
  if t.u8(a) ~= 0 then p:loadPaletteGroup(t.u8(a)) end
  if t.u8(a + 1) ~= 0 then p:loadGfxGroup(t.u8(a + 1)) end
  self.cursor = self.cursors[n] or 0
  self.keys = nil
  if n == 1 then self:itemsInit()
  elseif n == 2 then self:questInit()
  elseif n == 7 then self:kinstoneInit()
  elseif n >= 8 and n <= 11 then -- round 5: sword techniques, sleep, save (SaveMenu.lua)
    require('src.zelda.tmc.SaveMenu').init(self, n)
  elseif n >= 4 and n <= 6 then -- round 5: the map pages (MapMenu.lua)
    self.keys = { 14, 1, 2, 0 }
    self.ui:layout({ 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, elements = {} })
    require('src.zelda.tmc.MapMenu').init(self, n)
  else
    self.keys = { 14, 1, 2, 0 }
    self.ui:layout({ 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, elements = {} })
  end
end

-- ---------------------------------------------------------------------------
-- item graphics into OBJ VRAM (sub_080A5F48)
-- ---------------------------------------------------------------------------
function Menu:itemFrame(item)
  local s = self.field.assets:sprite(SPRITE_ITEMS)
  local keys = s and s.anims[item]
  return keys and keys[1] and keys[1][1]
end

function Menu:loadItemGfx(item, tile)
  local s = self.field.assets:sprite(SPRITE_ITEMS)
  local f = self:itemFrame(item)
  local fr = f and s.frames[f]
  if not (fr and s.gfxRaw) then return end
  self.ppu:write(0x06010000 + tile * 32, s.gfxRaw, fr[3] * 32, 0x100)
  local st = self.field.save.stats
  local ammo
  if item == 7 or item == 8 then ammo = st.bombCount elseif item == 9 or item == 10 then ammo = st.arrowCount end
  if ammo then
    local d = self.ppu:table("ammoDigits")
    local tens = math.min(9, math.floor(ammo / 10))
    self.ppu:write(0x06010000 + tile * 32, d.str(d.base + tens * 0x20, 0x20))
    self.ppu:write(0x06010000 + tile * 32 + 0x20, d.str(d.base + (ammo % 10 + 10) * 0x20, 0x20))
  end
end

-- sub_080A6F6C: the description box in BG0
function Menu:describe(text)
  local p = self.ppu
  if self.textId ~= text then
    self.textId = text
    p:fill(0x02034CB0 + 0x220 * 2, 0x100, 0)
    if band(text, 0xFF) ~= 0 then p:showTextBox(text, p:font("pauseFonts", A.font)) end
    p.bg[0].updated = true
  end
  p.bg[0].y = 2
end

-- ---------------------------------------------------------------------------
-- ITEMS (PauseMenu_ItemMenu_*)
-- ---------------------------------------------------------------------------
function Menu:itemEntry(slot)
  local t = self.data
  local a = A.itemTable + 8 * slot
  return { up = t.u8(a), down = t.u8(a + 1), left = t.u8(a + 2), right = t.u8(a + 3),
           type = t.u8(a + 4), x = t.u8(a + 6), y = t.u8(a + 7) }
end

function Menu:itemsInit()
  local f = self.field
  self.ui:layout(readLayout(self.data, A.itemLayout))
  self.items = {}
  local meta = f.assets.manifest.itemMeta or {}
  for item = 1, 0x1F do
    local m = meta[item]
    if f:inventory(item) == 1 and m and m.slot <= 17 then
      local it = item
      if it == 0x0F or it == 0x10 then
        local on = f:equipped("a") == 0x10 or f:equipped("b") == 0x10
        it = on and 0x10 or 0x0F -- gPauseMenuOptions.unk15
      end
      self.items[m.slot] = it
      self:loadItemGfx(it, m.slot * 8 + 0x360)
    end
  end
  self.keys = { self.data.u8(A.itemKeys), self.data.u8(A.itemKeys + 1), self.data.u8(A.itemKeys + 2), self.data.u8(A.itemKeys + 3) }
end

function Menu:itemsUpdate(input)
  local f = self.field
  local slot = self.cursor
  local e = self:itemEntry(slot)
  if input.pressed("a") and slot == SLOT_SAVE then
    -- sub_080A4E84($B): the save screen (SaveMenu.lua, screen 11)
    f:sound(0x6A)
    self.nextScreen, self.state = 11, 3
  elseif (input.pressed("a") or input.pressed("b")) and self.items[slot] then
    f:equip(input.pressed("a") and "a" or "b", self.items[slot])
    f:sound(0x6A) -- SFX_TEXTBOX_SELECT
  else
    if input.pressed("up") then slot = e.up
    elseif input.pressed("down") then slot = e.down
    elseif input.pressed("left") then slot = e.left
    elseif input.pressed("right") then slot = e.right end
  end
  if slot ~= self.cursor then self.cursor = slot; f:sound(0x69) end -- SFX_TEXTBOX_CHOICE
  local item = self.items[self.cursor] or 0
  if self.cursor == SLOT_SAVE then item = 0x73 end
  self:describe(0x400 + item)
end

function Menu:slotOf(item)
  if item and item ~= 0 then
    for i = 0, 17 do if self.items[i] == item then return i end end
  end
  return 17
end

function Menu:itemsDraw()
  local p, f = self.ppu, self.field
  local st = f.save.stats
  for i = 0, 17 do
    local item = self.items[i]
    if item then
      local e = self:itemEntry(i)
      local color = 3
      if (item == 7 or item == 8) and (st.bombCount or 0) >= (st.bombMax or 10) then color = 4 end
      if (item == 9 or item == 10) and (st.arrowCount or 0) >= (st.arrowMax or 30) then color = 4 end
      local fr = self:itemFrame(item)
      if fr then p:drawDirect(SPRITE_ITEMS, fr, { x = e.x, y = e.y, _4 = 0x400, _6 = 0, _8 = bor(0x800, color * 0x1000, i * 8 + 0x360) }) end
    end
  end
  local e = self:itemEntry(self.cursor)
  p:drawDirect(SPRITE_MENU, e.type + (band(self.ticks, 0x10) ~= 0 and 3 or 4), { x = e.x, y = e.y, _4 = 0x400, _6 = 0, _8 = 0x800 })
  e = self:itemEntry(SLOT_SAVE)
  p:drawDirect(SPRITE_MENU, 0x22, { x = e.x, y = e.y, _4 = 0x400, _6 = 0, _8 = 0x800 })
  for _, b in ipairs({ "a", "b" }) do
    local i = self:slotOf(f:equipped(b))
    if i < 17 then
      e = self:itemEntry(i)
      p:drawDirect(SPRITE_MENU, 3, { x = e.x, y = e.y, _4 = 0x400, _6 = 0, _8 = 0x800 })
    end
  end
end

-- ---------------------------------------------------------------------------
-- QUEST STATUS (sub_080A5594 / sub_080A56A0 / sub_080A57F4)
-- ---------------------------------------------------------------------------
function Menu:questEntry(i)
  local t = self.data
  local a = A.questTable + 8 * i
  return { t.u8(a), t.u8(a + 1), t.u8(a + 2), t.u8(a + 3), t.u8(a + 4), t.u8(a + 5), t.u8(a + 6), t.u8(a + 7) }
end

function Menu:questInit()
  local f = self.field
  self.ui:layout(readLayout(self.data, A.questLayout))
  local q = {}
  for i = 0, 15 do q[i] = 0 end
  local meta = f.assets.manifest.itemMeta or {}
  local nextFree = 6
  for item = 0x34, 0x46 do
    if f:inventory(item) == 1 then
      local slot = meta[item] and meta[item].slot or 99
      if slot == 3 and q[3] ~= 0 then slot = 99 end
      if slot ~= 99 then
        if slot == 1 then
          slot = nextFree
          if slot < 8 then nextFree = slot + 1 end
        end
        q[slot] = item
        self:loadItemGfx(item, slot * 8 + 0x380)
      end
    end
  end
  if f:inventory(ITEM_TINGLE_TROPHY) == 0 then
    local n = 0
    if f:inventory(ITEM_KINSTONE_BAG) ~= 0 then
      for _, t in ipairs(f.kinstone:pieces()) do n = n + f.kinstone:count(t) end
      n = n >= 0x50 and 4 or n >= 0x28 and 3 or n >= 10 and 2 or 1
    end
    q[0] = n
  end
  q[1] = (f.save.stats.heartPieces or 0) + 1
  local skills = 0
  for i = 0x48, 0x4F do if f:inventory(i) ~= 0 then skills = skills + 1 end end
  q[2] = skills
  if f:inventory(ITEM_CARLOV_MEDAL) == 0 and f:inventory(ITEM_SHELLS) ~= 0 then q[3] = ITEM_SHELLS end
  self.quest = q
  self.keys = { self.data.u8(A.questKeys), self.data.u8(A.questKeys + 1), self.data.u8(A.questKeys + 2), self.data.u8(A.questKeys + 3) }
end

function Menu:questUpdate(input)
  local f = self.field
  local e = self:questEntry(self.cursor)
  local to = 0xFF
  if input.pressed("up") then to = e[1] elseif input.pressed("down") then to = e[2]
  elseif input.pressed("left") then to = e[3] elseif input.pressed("right") then to = e[4] end
  if to ~= 0xFF then
    self.cursor = to; f:sound(0x69)
  elseif input.pressed("a") then
    local c = self.cursor
    local s = 0
    if (c == 0 or c == 2) and self.quest[c] ~= 0 then s = c == 0 and 7 or 8
    elseif c == 4 then s = 9 elseif c == 5 then s = 10 end
    if s ~= 0 then
      f:sound(0x6A)
      self.nextScreen = s
      self.state = 3
      return
    end
  end
  local q = self.quest
  local c = self.cursor
  self.ui.buttonY[0] = ((c == 0 or c == 2) and q[c] ~= 0) and 0x10 or -0x10
  local item = q[c]
  if item ~= 0 then
    if c == 0 then if item ~= 0x3D then item = 0x67 end
    elseif c == 1 then item = 99
    elseif c == 2 then item = 0x70
    elseif c == 4 then item = 0x74
    elseif c == 5 then item = 0x73 end
  end
  self:describe(0x400 + item)
end

function Menu:questDraw()
  local p, f = self.ppu, self.field
  local e = self:questEntry(self.cursor)
  local frame = e[5] + 9 + (band(self.ticks, 0x10) == 0 and 2 or 1)
  p:drawDirect(SPRITE_MENU, frame, { x = e[7], y = e[8], _4 = 0x400, _6 = 0, _8 = 0x800 })
  local q = self.quest
  for i = 0, 15 do
    local v = q[i]
    if v ~= 0 then
      local this = self:questEntry(i)
      local nxt = self:questEntry(i + 1) -- pbVar6 = entry i shifted by 5 bytes
      local x, y = this[7], this[8]
      if v < 0x34 then
        local fr = (i == 2) and (this[6] + 10) or (v + 9 + this[6])
        p:drawDirect(SPRITE_MENU, fr, { x = x, y = y, _4 = 0x400, _6 = 0, _8 = 0xE800 })
      else
        if v == 0x3E then y = y + 8 elseif v == 0x3D then y = y + 13 end
        local fr = self:itemFrame(v)
        if fr then p:drawDirect(SPRITE_ITEMS, fr, { x = x, y = y, _4 = 0x400, _6 = 0, _8 = i * 8 + 0xEB80 }) end
      end
      local _ = nxt
    end
  end
  if q[2] ~= 0 then
    local en = self:questEntry(2)
    p:drawDirect(0, 1, { x = en[7] + 9, y = en[8] + 7, _4 = 0x400, _6 = 0, _8 = q[2] + 0x800 })
  end
  if q[3] == ITEM_SHELLS then
    local en = self:questEntry(3)
    local x, shells = en[7] + 8, f.save.stats.shells or 0
    for _ = 1, 3 do
      p:drawDirect(0, 1, { x = x, y = en[8] + 8, _4 = 0x400, _6 = 0, _8 = shells % 10 + 0x800 })
      shells = math.floor(shells / 10)
      x = x - 8
    end
  end
end

-- ---------------------------------------------------------------------------
-- KINSTONE PIECES (sub_080A6024 / sub_080A6044, kinstoneMenu.c sub_080A42E0)
-- ---------------------------------------------------------------------------
function Menu:kinstoneInit()
  local t = self.data
  self.ui:layout(readLayout(t, A.kinLayout))
  self.keys = { t.u8(A.kinKeys), t.u8(A.kinKeys + 1), t.u8(A.kinKeys + 2), t.u8(A.kinKeys + 3) }
  self.kinSlots, self.kinCounts = {}, {}
end

-- sub_080A43A8: one of 16 OBJ slots (tile $300 + slot * 16) per piece art
function Menu:kinstoneSlot(gfx)
  for i = 0, 15 do if self.kinSlots[i] == gfx then return i end end
  for i = 0, 15 do
    if self.kinSlots[i] == nil then
      self.kinSlots[i] = gfx
      local A_ = self.field.assets
      local e = A_.manifest.kinstoneGfx and A_.manifest.kinstoneGfx[gfx]
      if e then
        A_.kinGfx = A_.kinGfx or A_.store:read("kinstonegfx.bin") or ""
        self.ppu:write(0x06010000 + (0x300 + i * 16) * 32, A_.kinGfx, e[1], math.min(e[2], 0x200))
      end
      return i
    end
  end
  return 0
end

function Menu:kinstoneDraw()
  local p, f = self.ppu, self.field
  local events = f.assets.manifest.kinstones and f.assets.manifest.kinstones.events or {}
  local digits = p:table("ammoDigits")
  local k = 0
  for _, t in ipairs(f.kinstone:pieces()) do
    if k > 10 then break end
    local x, y = (k % 4) * 0x30 + 0x2B, math.floor(k / 4) * 0x24 + 0x34
    local ev = events[t] or {}
    local slot = self:kinstoneSlot(ev.gfxPiece or 0)
    local n = f.kinstone:count(t)
    if n ~= 0 then
      if self.kinCounts[slot] ~= n then
        -- sub_0801C2F0: the two digit tiles at $2E0 + slot * 2
        self.kinCounts[slot] = n
        local tens = math.min(9, math.floor(n / 10))
        p:write(0x06010000 + (0x2E0 + slot * 2) * 32, digits.str(digits.base + tens * 0x20, 0x20))
        p:write(0x06010000 + (0x2E1 + slot * 2) * 32, digits.str(digits.base + (n % 10 + 10) * 0x20, 0x20))
      end
      p:drawDirect(0, 5, { x = x + 0x10, y = y + 9, _4 = 0, _6 = 0, _8 = slot * 2 + 0x3AE0 })
    end
    p:drawDirect(0, 3, { x = x, y = y, _4 = 0, _6 = 0,
                         _8 = bor((ev.objPalette or 0) * 0x1000, 0x800, slot * 16 + 0x300) })
    k = k + 1
  end
end

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------
function Menu:update(input)
  local f = self.field
  self.ticks = self.ticks + 1
  -- UpdateUIElements runs every frame of the subtask
  self.ui.hideFlags = 0
  self.ui:update({ equipped = { a = f:equipped("a"), b = f:equipped("b") }, health = f.save.stats.health })
  if self.state == 3 then
    self.fade = self.fade + 2
    if self.fade >= 16 then
      self.fade = 16
      self.cursors[self.screen] = self.cursor
      self:setScreen(self.nextScreen)
      self.state = 5
    end
    return
  elseif self.state == 5 then
    self.fade = self.fade - 2
    if self.fade <= 0 then self.fade = 0; self.state = 2 end
    return
  end
  -- PauseMenu_Variant2: START / L / R / B through the screen's table
  if self.keys then
    local which
    if input.pressed("start") then which = 1 elseif input.pressed("l") then which = 2
    elseif input.pressed("r") then which = 3 elseif input.pressed("b") and self.screen ~= 1 then which = 4 end
    local to = which and self.keys[which] or 0
    if to ~= 0 then
      if to == 14 then return self:toggle() end
      if (to >= 4 and to <= 6 or to == 15) and f:inventory(ITEM_MAP) == 0 and not self:inDungeon() then
        to = self.keys[which == 2 and 3 or 2]
      end
      to = self:resolve(to)
      if to ~= self.screen and to ~= 0 and to ~= 14 then
        f:sound(0x65)
        self.nextScreen = to
        self.state = 3
        return
      end
    end
  end
  if self.screen == 1 then self:itemsUpdate(input)
  elseif self.screen == 2 then self:questUpdate(input)
  elseif self.screen >= 4 and self.screen <= 6 then require('src.zelda.tmc.MapMenu').update(self, input)
  elseif self.screen >= 8 and self.screen <= 11 then require('src.zelda.tmc.SaveMenu').update(self, input) end
end

function Menu:inDungeon()
  local info = self.field.room.areaInfo
  return info and (info.location or 0) >= 0x17
end

-- sub_080A5128: the three page tabs
function Menu:drawTabs()
  local p = self.ppu
  local s = self.screen
  if s == 9 or s == 10 or s == 11 then return end
  local pos
  if s == 7 or s == 8 then
    pos = { { 0x60, 0x18 }, { -0x10, 0x48 }, { 0x100, 0x48 } }
  else
    local t = math.floor(self.fade / 3)
    pos = { { 0x40, 0x10 - self.fade * 2 }, { 0x10 - t, 0x48 }, { 0xE0 + t, 0x48 } }
  end
  for i = 1, 3 do
    p:drawDirect(SPRITE_MENU, i - 1, { x = pos[i][1], y = pos[i][2], _4 = 0, _6 = 0, _8 = 0x400 })
  end
end

function Menu:draw(font)
  if not self.ppu then return end
  local p, f = self.ppu, self.field
  p:flush()
  if self.screen == 1 then self:itemsDraw()
  elseif self.screen == 2 then self:questDraw()
  elseif self.screen == 7 then self:kinstoneDraw()
  elseif self.screen >= 4 and self.screen <= 6 then require('src.zelda.tmc.MapMenu').draw(self)
  elseif self.screen >= 8 and self.screen <= 11 then require('src.zelda.tmc.SaveMenu').draw(self) end
  self:drawTabs()
  self.ui:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.fade > 0 then
    -- the screen change: layerFXControl $E46, alpha (16 - t) / t -- BG1
    -- and BG2 blend into the layers under them
    local full = p.dispcnt
    p.dispcnt = band(full, bit.bnot(0x600))
    love.graphics.draw(p:render("under"), 0, 0)
    p.dispcnt = full
    love.graphics.setColor(1, 1, 1, (16 - self.fade) / 16)
    love.graphics.draw(p:render(), 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
  elseif self.screen >= 4 and self.screen <= 6 then
    require('src.zelda.tmc.MapMenu').compose(self)
  else
    love.graphics.draw(p:render(), 0, 0)
  end
  if self.screen == 9 then require('src.zelda.tmc.SaveMenu').overlay(self) end
end

return Menu
