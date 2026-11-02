-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S SAFARI ZONE AREA CUSTOMIZER -- ScrCmd_716,
-- SafariAreaCustomizer_LaunchApp (overlay 108; pokeheartgold
-- asm/overlay_108.s, undecompiled). Baoba's desk in the gate
-- (scr_seq_0119 D47R0101 005) clears FLAG_UNK_99D, runs this, and shakes the
-- screen when the flag comes back set.
--
-- READ FROM THE ASM:
--   * ov108_021E59E4: area set 0 copied into a working copy
--     (SafariZone_CopyAreaSet); the object counts shown only when Baoba's
--     unlock level is above 0 (0x184E3).
--   * ov108_021E5A48 (exit): the copy written back to set 0
--     (SafariZone_SetAreaSet), ChangeFlag99D(changed).
--   * THE GRID (ov108_021E62B4): the six slots 3 x 2, a third row the Quit
--     button; left / right wrap the column (rows 0..1 only), up / down the
--     row (mod 3). B, or A on the third row, ends the app (SE 0x5DC). A on a
--     slot opens "Do what with this Area?" (msg_0429 0) with Switch / Sort /
--     Return (msg 7 / 8 / 4) (ov108_021E5DB8: 0 Switch, 1 Sort).
--   * SWITCH (ov108_021E64C0, "Which will you Switch?" msg 1): the twelve
--     areas, six a page ("n/2", msg 9), a third row Return. Left / right step
--     through the twelve in order, turning the page at its edge (SE 0x5E1);
--     up / down the row (mod 3). A on the slot's own area does nothing; on
--     another, with objects unlocked, "All placed objects will be removed. Is
--     this OK?" (msg 3, ov108_021E5F38) and Yes -> SafariZone_InitAreaInSet
--     (the slot's objects cleared), changed; without objects unlocked the
--     area is set at once (ov108_021E6450), changed. B / Return: back.
--   * SORT (ov108_021E6894, "Where will you move it?" msg 2): a second
--     cursor on the grid from the slot; A on another slot ->
--     SafariZone_SwapAreasInSet (objects travel with their areas), changed,
--     the cursor to the target (SE 0x69C); A on the slot itself, on the Quit
--     row, or B: back.
--   * THE AREA WINDOW (ov108_021E7CD8): the cursor slot's area name (msg 16 +
--     area) and, objects unlocked, five counts of its objects by type --
--     plains, forest, rocks, water (types 1..4) and the rest (type 0), with
--     their captions msg 10..14.
--
--   * THE TOUCH SCREEN (ov108_021E63B8 / 66AC / 69A0): the hitboxes
--     ov108_021EA760 (the board: slots y 24 + 72 row, x 24 + 72 col, 64 x 64;
--     Quit y 168..191 x 192..255) and ov108_021EA7D0 (the picker: slots x
--     16 + 80 col; Return; the page arrows y 6..25 at x 64..95 / 160..191 --
--     the left one only on page 2, back to position 5; the right one only on
--     page 1, to position 0). A touched slot acts as A on it.
--   * THE SCREENS (Gen4HgssSafariAppArt): the bottom is the main engine --
--     BG3 the picker page (member 7) under BG2 the board (member 10), which
--     slides away while switching; the top is the sub engine -- the board
--     (member 4) with each slot's area picture (member 18 + area, sub BG1 at
--     tile (3 + 9 col, 3 + 9 row)) over the objects page (2) or the plain one
--     (3); the area name (msg 16 + area) in the top's window (1, 21) 30 x 3.
--     The cursors are the OBJ bank's sequences (ov108_021E78F4): 0 the slot
--     cursor at (56 + 72 col, 56 + 72 row) -- (48 + 80 col, ...) in the
--     picker, on the top board at y + 192 -- 1 the Quit cursor at (224, 180),
--     2 the picked slot and 3 the flashing target while sorting. Messages go
--     in the frames of member 8 (ov108_021E767C: one line at tile row 21,
--     two at row 18, 24 tiles wide) in MAKE_TEXT_COLOR(13, 12, 14); the Quit /
--     Return label in window (25, 21) 6 x 3, (3, 1, 2); the page "n/2" in
--     (13, 0) 6 x 2. Yes / No is YesNoPrompt at tile (26, 16) on main BG0.
--   * THE MUSIC: Sound_SetSceneAndPlayBGM(0x43, 0, 0) is a sub-scene with no
--     BGM of its own -- the field's plays on (src/ui/HgssSafariScreen.lua).
--
--   * THE ACTION MENU (ov108_021E6A58): TouchscreenListMenu_Create on main
--     BG0 at the slot's corner (ov108_021EA748 / 74A: x 12 / 21 / 10, y 2 /
--     9 tiles), wrapping, labels centred (template ov108_021EA72C), drawn the
--     touchscreen_list_menu.c way from NARC_data_sbox_gra.
--   * THE SLIDE (ov108_021E5E68 -> 7F7C / 80F4, the scrolls 0x184E4 /
--     0x184E6 set in the vblank by ov108_021E6BA0): the board leaves the
--     bottom for the top in 8 frames of 24 px when Switch is chosen, and comes
--     back the same way. So the TOP shows the board only while switching;
--     otherwise it shows the objects page (member 2, unlocked) or the plain
--     page (3) with the cursor slot's counts (ov108_021E7CD8). While
--     switching, the top's name window holds the slot's area and the picked
--     one in two 96 px halves (ov108_021E7EB0).
--   * THE AREA PICTURES on the bottom are 64 x 64 OBJs whose characters
--     ov108_021E84F8 replaces with member 18 + area (palette member 15, the
--     same colours as the top's BG copy); a page turn slides them 32 px a
--     frame for 8 frames (ov108_021E81A8 / 8270). The picker arrows
--     (ov108_021E77D4): left sequence 6 (off) on page 1 else 4, right 7 on
--     page 2 else 5, a touched one playing its sequence.
--
-- INFERRED: the count rows' exact places on the objects page (the windows
-- ov108_021E7CD8 prints into come from a template not transcribed); where
-- the picker's pictures stand during the board's slide (shown once it ends).

local S = require("src.ui.HgssSafariScreen")

local C = {}
C.__index = C
C.isOpaque = true

C.BANK = 429
C.FLAG_CHANGED = 0x99D
C.AREAS = 12

function C:uiSize() return S.W, S.H end
function C:wantsFillScale() return true end

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepCopy(v) end
  return out
end

function C.new(game, onDone)
  local Zone = require("src.world.HgssSafariZone")
  local Obj = require("src.world.HgssSafariObjects")
  local st = Zone.state(game.save)
  local self = setmetatable({
    game = game, onDone = onDone, st = st,
    work = deepCopy(st.sets[0]),
    objectsShown = Obj.unlockLevel(st) > 0,
    changed = false,
    state = "fadein", t = 0,
    cursor = 0, menu = 0, page = 0, pick = 0, target = 0, yes = 1,
  }, C)
  return self
end

function C:text(n, fallback) return S.line(self.game, C.BANK, n, fallback) end

function C:areaName(no)
  local Zone = require("src.world.HgssSafariZone")
  return self:text(16 + (tonumber(no) or 0), Zone.AREA_NAMES[no] or "?")
end

-- ov108_021E7CD8's five counts: types 1..4, then 0
function C:counts(slot)
  local Obj = require("src.world.HgssSafariObjects")
  local n = { 0, 0, 0, 0, 0 }
  local area = self.work.areas[slot + 1]
  for _, o in ipairs(area and area.objects or {}) do
    local t = Obj.config(o.id).type
    if t == 0 then n[5] = n[5] + 1 else n[t] = n[t] + 1 end
  end
  return n
end

-- ------------------------------------------------------------- the rules

function C:setArea(slot, no)
  -- SafariZone_InitAreaInSet: the area, no objects
  self.work.areas[slot + 1] = { area = no, objects = {} }
  self.changed = true
end

function C:swap(a, b)
  local areas = self.work.areas
  areas[a + 1], areas[b + 1] = areas[b + 1], areas[a + 1]
  self.changed = true
end

local function gridMove(cursor, game, wrapColumns)
  local col, row = cursor % 3, math.floor(cursor / 3)
  if row > 2 then row = 2 end
  local moved = false
  if row < 2 and wrapColumns then
    if S.pressed(game, "right") then col = (col + 1) % 3; moved = true
    elseif S.pressed(game, "left") then col = (col + 2) % 3; moved = true end
  end
  if S.pressed(game, "up") then row = (row + 2) % 3; moved = true
  elseif S.pressed(game, "down") then row = (row + 1) % 3; moved = true end
  return row * 3 + col, moved
end

function C:finish()
  if self.finished then return end
  self.finished = true
  -- ov108_021E5A48
  self.st.sets[0] = self.work
  local save = self.game.save
  save.flags = save.flags or {}
  local key = ("FLAG_G4_%04X"):format(C.FLAG_CHANGED)
  save.flags[key] = self.changed and true or nil
  pcall(function() require("src.world.HgssSafariProps").changed(self.game) end)
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone(self.changed) end
end

-- a tap on the bottom screen -> the same actions as the buttons
function C:touchpressed(_, px, py)
  local x, y = S.point(self.game, px, py)
  if not x then return false end
  self.tap = { x = x, y = y }
  return true
end
function C:mousepressed(x, y, button)
  if button == 1 then return self:touchpressed("mouse", x, y) end
end

-- ov108_021EA760 / ov108_021EA7D0: { top, bottom, left, right }
C.BOARD_RECTS = {
  { 24, 88, 24, 88 }, { 24, 88, 96, 160 }, { 24, 88, 168, 232 },
  { 96, 160, 24, 88 }, { 96, 160, 96, 160 }, { 96, 160, 168, 232 },
  { 168, 192, 192, 0 },
}
C.PICKER_RECTS = {
  { 24, 88, 16, 80 }, { 24, 88, 96, 160 }, { 24, 88, 176, 240 },
  { 96, 160, 16, 80 }, { 96, 160, 96, 160 }, { 96, 160, 176, 240 },
  { 168, 192, 192, 0 }, { 6, 26, 64, 96 }, { 6, 26, 160, 192 },
}
C.YESNO_TILE = { 26, 16 }

-- the fallback's boxes (no imported art)
local CELL_W, CELL_H = 78, 46
local function cellRect(i)
  local col, row = i % 3, math.floor(i / 3)
  return 6 + col * 83, 34 + row * 52, CELL_W, CELL_H
end
local BUTTON = { 176, 146, 74, 24 }
local MENU = { 168, 60, 82, 76 }

local function hit(r, x, y) return x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4] end

function C:tapGrid()
  local tap = self.tap
  if not tap then return nil end
  local rects = (self.state == "switch") and C.PICKER_RECTS or C.BOARD_RECTS
  return S.hitbox(rects, tap.x, tap.y)
end

-- ov108_021E5E68 -> 7F7C / 80F4: the board and the picker trade places in
-- eight frames of 24 px. Going to the picker (mode 0 -> 1) the bottom's BG1 /
-- BG2 scroll 0 -> 192 (0x184E4) and the top's BG0 / BG1 / BG2 -192 -> 0
-- (0x184E6, ov108_021E6BA0 writes both in the vblank), the board's pictures
-- rising with it; coming back, the reverse, the pictures dropping in from 192
-- above their slots.
C.SLIDE_FRAMES, C.SLIDE_STEP = 8, 24
-- ov108_021E81A8 / 8270: a page turn slides the twelve pictures 32 px a frame
-- for eight frames, the new page from 256 px off
C.PAGE_FRAMES, C.PAGE_STEP = 8, 32
-- ov108_021E6A58: the action menu's corner by slot (ov108_021EA748 x /
-- ov108_021EA74A y, tiles), TouchscreenListMenu on main BG0
C.MENU_AT = { [0] = { 12, 2 }, { 21, 2 }, { 10, 2 }, { 12, 9 }, { 21, 9 }, { 10, 9 } }

function C:slideTo(after)
  self.state = "slide"
  self.slide = { k = 0, toPicker = (after == "switch"), after = after }
end

-- the bottom / top BG scroll the slide has reached (0x184E4 / 0x184E6)
function C:scrolls()
  local sl = self.slide
  if self.state == "slide" and sl then
    local d = C.SLIDE_STEP * sl.k
    if sl.toPicker then return d, -192 + d end
    return 192 - d, -d
  end
  if self.state == "switch" or self.state == "confirm" then return 192, 0 end
  return 0, -192
end

function C:turnPage(page, pick, side)
  if page == self.page then return end
  self.pageSlide = { from = self.page, dir = page > self.page and 1 or -1, k = 0 }
  self.page, self.pick = page, pick
  self.arrowPress = { side = side, t = self.t }
  S.se(self.game, "page")
end

function C:menuLabels()
  return { self:text(7, "Switch"), self:text(8, "Sort"), self:text(4, "Return") }
end

-- TouchscreenListMenu_CreateInternal / _CreateWindows: the width is the
-- widest label (font 4) in tiles, item i's window at (x + 1, y + 1 + 3 i)
function C:menuGeometry()
  local at = C.MENU_AT[math.min(5, self.cursor)] or C.MENU_AT[0]
  local w = 0
  for _, l in ipairs(self:menuLabels()) do w = math.max(w, S.width(l)) end
  local width = math.ceil(w / 8)
  return at[1], at[2], width
end

function C:menuHit(px, py)
  local x, y, width = self:menuGeometry()
  for i = 0, 2 do
    local top, left = (y + 1) * 8 + 24 * i, (x + 1) * 8
    if py >= top and py < top + 16 and px >= left and px < left + width * 8 then return i end
  end
  return nil
end

function C:update()
  self.t = self.t + 1
  local game = self.game
  local s = self.state
  local A, B = S.pressed(game, "a"), S.pressed(game, "b")
  local tapped = self:tapGrid()
  local tap = self.tap
  self.tap = nil
  if self.pageSlide then
    self.pageSlide.k = self.pageSlide.k + 1
    if self.pageSlide.k >= C.PAGE_FRAMES then self.pageSlide = nil end
    return
  end
  if s == "fadein" then
    if self.t >= S.FADE then self.state, self.t = "main", 0 end
  elseif s == "slide" then
    local sl = self.slide
    sl.k = sl.k + 1
    if sl.k >= C.SLIDE_FRAMES then self.state, self.slide = sl.after, nil end
  elseif s == "main" then
    if tapped then self.cursor = tapped; A = true end
    if B or (A and self.cursor >= 6) then
      S.se(game, "select")
      self.state, self.t = "fadeout", 0
    elseif A then
      S.se(game, "select")
      self.state, self.menu = "menu", 0
    else
      local c, moved = gridMove(self.cursor, game, true)
      if moved then
        if c ~= self.cursor then S.se(game, "cursor") end
        self.cursor = c
      end
    end
  elseif s == "menu" then
    -- TouchscreenListMenu_HandleInput: wrapAround on (the template's bit 0)
    if tap then
      local i = self:menuHit(tap.x, tap.y)
      if i then self.menu = i; A = true end
    end
    if S.pressed(game, "up") then self.menu = (self.menu + 2) % 3; S.se(game, "cursor")
    elseif S.pressed(game, "down") then self.menu = (self.menu + 1) % 3; S.se(game, "cursor") end
    if B or (A and self.menu == 2) then
      S.se(game, "select")
      self.state = "main"
    elseif A and self.menu == 0 then
      S.se(game, "select")
      -- 0x184E0 = 0; the page is kept from the last visit
      self.pick = 0
      self:slideTo("switch")
    elseif A and self.menu == 1 then
      S.se(game, "select")
      self.state, self.target = "sort", self.cursor
    end
  elseif s == "switch" then
    if tapped == 7 then
      tapped = nil
      if self.page ~= 0 then self:turnPage(0, 5, 0) end
      return
    elseif tapped == 8 then
      tapped = nil
      if self.page ~= 1 then self:turnPage(1, 0, 1) end
      return
    end
    if tapped then
      if tapped >= 6 then self.pick = 6 else self.pick = tapped end
      A = true
    end
    local current = self.work.areas[self.cursor + 1].area
    if B or (A and self.pick >= 6) then
      S.se(game, "select")
      self:slideTo("main")
    elseif A then
      local no = self.page * 6 + self.pick
      if no ~= current then
        S.se(game, "select")
        if self.objectsShown then
          self.state, self.yes, self.confirmArea = "confirm", 1, no
        else
          self:setArea(self.cursor, no)
          self:slideTo("main")
        end
      end
    else
      local col, row = self.pick % 3, math.floor(self.pick / 3)
      if row > 2 then row = 2 end
      if row < 2 and (S.pressed(game, "right") or S.pressed(game, "left")) then
        local n = self.page * 6 + row * 3 + col
        local step = S.pressed(game, "right") and 1 or -1
        local m = n + step
        if m >= 0 and m < C.AREAS then
          local page = math.floor(m / 6)
          if page ~= self.page then self:turnPage(page, m % 6, step > 0 and 1 or 0)
          else S.se(game, "cursor"); self.pick = m % 6 end
        end
      elseif S.pressed(game, "up") or S.pressed(game, "down") then
        row = S.pressed(game, "up") and (row + 2) % 3 or (row + 1) % 3
        self.pick = row * 3 + col
        S.se(game, "cursor")
      end
    end
  elseif s == "confirm" then
    if tap then
      if S.art(game) then
        local hitYes = S.yesNoHit(tap.x, tap.y, C.YESNO_TILE[1], C.YESNO_TILE[2])
        if hitYes then self.yes = hitYes; A = true end
      else
        for i = 1, 2 do
          if hit({ 184, 88 + (i - 1) * 26, 64, 22 }, tap.x, tap.y) then self.yes = i; A = true end
        end
      end
    end
    if S.pressed(game, "up") or S.pressed(game, "down") then self.yes = 3 - self.yes; S.se(game, "cursor") end
    if A and self.yes == 1 then
      S.se(game, "select")
      if self.confirmArea ~= self.work.areas[self.cursor + 1].area then
        self:setArea(self.cursor, self.confirmArea)
      end
      self:slideTo("main")
    elseif B or A then
      S.se(game, "select")
      self.state = "switch"
    end
  elseif s == "sort" then
    if tapped then self.target = tapped; A = true end
    if B then
      S.se(game, "select")
      self.state = "main"
    elseif A then
      if self.target >= 6 or self.target == self.cursor then
        S.se(game, "select")
        self.state = "main"
      else
        S.se(game, "pick")
        self:swap(self.cursor, self.target)
        self.cursor = self.target
        self.state = "main"
      end
    else
      local c, moved = gridMove(self.target, game, true)
      if moved then
        if c ~= self.target then S.se(game, "cursor") end
        self.target = c
      end
    end
  elseif s == "fadeout" then
    if self.t >= S.FADE then self:finish() end
  end
end

-- ----------------------------------------------------------------- drawing

local TYPE_INK = { { 112, 184, 72 }, { 40, 128, 64 }, { 152, 120, 88 }, { 64, 136, 216 }, { 144, 144, 152 } }
local TYPE_TAG = { "P", "F", "R", "W", "O" }

function C:veilAmount()
  if self.state == "fadein" then return 1 - self.t / S.FADE end
  if self.state == "fadeout" then return self.t / S.FADE end
  return 0
end

function C:prompt()
  local s = self.state
  if s == "menu" then return self:text(0, "Do what with this Area?") end
  if s == "switch" then return self:text(1, "Which will you Switch?") end
  if s == "confirm" then return self:text(3, "All placed objects will be\nremoved. Is this OK?") end
  if s == "sort" then return self:text(2, "Where will you move it?") end
  return nil
end

function C:slotFocus()
  if self.state == "sort" then return self.target end
  return self.cursor
end

-- the top screen: the area window for the slot under the cursor
function C:drawTop()
  S.backdrop({ 168, 216, 152 }, { 96, 168, 104 })
  local slot = self:slotFocus()
  local g = love.graphics
  S.box(16, 12, S.W - 32, 34, { 248, 248, 240 }, { 72, 120, 72 })
  if slot >= 6 then
    S.centred(self:text(6, "Quit"), 16, S.W - 32, 21)
  else
    local area = self.work.areas[slot + 1]
    S.centred(self:areaName(area.area), 16, S.W - 32, 21)
  end
  -- the 3 x 2 map of the arrangement
  for i = 0, 5 do
    local col, row = i % 3, math.floor(i / 3)
    local x, y = 64 + col * 44, 56 + row * 32
    S.color(i == slot and { 255, 232, 160 } or { 224, 236, 216 })
    g.rectangle("fill", x, y, 42, 30)
    S.color({ 72, 112, 72 }); g.rectangle("line", x + 0.5, y + 0.5, 41, 29)
    local name = self:areaName(self.work.areas[i + 1].area)
    S.text(name:sub(1, 4), x + 4, y + 8, nil, false)
  end
  if self.objectsShown and slot < 6 then
    local n = self:counts(slot)
    for i = 1, 5 do
      local y = 124 + (i - 1) * 13
      S.color(TYPE_INK[i]); g.rectangle("fill", 20, y + 2, 8, 8)
      -- the caption's last line ("be liked by Pokemon on Plains"): one
      -- line of window here
      local raw = self:text(9 + i, "")
      local caption = raw:match("([^\n]*)$") or raw
      S.text(caption, 34, y - 2, nil, false)
      S.text(("%2d"):format(n[i]), 228, y - 2, nil, false)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function C:drawCell(i, label, selected, mark, counts)
  local x, y, w, h = cellRect(i)
  S.box(x, y, w, h, selected and { 255, 236, 168 } or { 240, 248, 232 },
        selected and { 224, 120, 40 } or (mark and { 64, 104, 200 } or { 88, 136, 88 }))
  S.centred(label, x, w, y + 8)
  if counts then
    for k = 1, 5 do
      local cx = x + 4 + (k - 1) * 15
      S.color(TYPE_INK[k]); love.graphics.rectangle("fill", cx, y + 30, 4, 8)
      S.text(tostring(counts[k]), cx + 5, y + 27, nil, false)
    end
  end
end

-- the bottom screen: the slots (or the areas, while switching), the
-- buttons and the prompt
function C:drawBottom(single)
  S.backdrop({ 216, 236, 200 }, { 152, 200, 144 })
  local s = self.state
  if s == "switch" or s == "confirm" then
    local current = self.work.areas[self.cursor + 1].area
    for i = 0, 5 do
      local no = self.page * 6 + i
      self:drawCell(i, self:areaName(no), s == "switch" and self.pick == i, no == current)
    end
    if s == "switch" then
      S.text(tostring(self.page + 1) .. "/2", 8, 150)
      S.box(BUTTON[1], BUTTON[2], BUTTON[3], BUTTON[4], self.pick >= 6 and { 255, 236, 168 } or { 240, 240, 240 })
      S.centred(self:text(4, "Return"), BUTTON[1], BUTTON[3], BUTTON[2] + 5)
    end
  else
    for i = 0, 5 do
      local sel = (s == "sort" and self.target == i) or (s ~= "sort" and self.cursor == i)
      local counts = self.objectsShown and self:counts(i) or nil
      self:drawCell(i, self:areaName(self.work.areas[i + 1].area), sel,
                    s == "sort" and i == self.cursor, counts)
    end
    local q = (s == "sort" and self.target >= 6) or (s ~= "sort" and self.cursor >= 6)
    S.box(BUTTON[1], BUTTON[2], BUTTON[3], BUTTON[4], q and { 255, 236, 168 } or { 240, 240, 240 })
    S.centred(self:text(6, "Quit"), BUTTON[1], BUTTON[3], BUTTON[2] + 5)
  end
  -- the header: the prompt, or the slot's area name on one screen
  local prompt = self:prompt()
  if prompt and prompt:find(string.char(10), 1, true) then
    -- a two-line prompt (msg 3) takes the message window at the foot
    S.message(prompt, 146)
    S.box(4, 2, S.W - 8, 30, { 248, 248, 248 }, { 88, 104, 136 })
    S.text(self:areaName(self.confirmArea or 0), 10, 9)
  elseif prompt then
    S.box(4, 2, S.W - 8, 30, { 248, 248, 248 }, { 88, 104, 136 })
    S.text((prompt:gsub("\n", " ")), 10, 9)
  elseif single then
    S.box(4, 2, S.W - 8, 30, { 248, 248, 248 }, { 88, 104, 136 })
    local slot = self.cursor
    S.text(slot < 6 and self:areaName(self.work.areas[slot + 1].area) or self:text(6, "Quit"), 10, 9)
  end
  if s == "menu" then
    S.box(MENU[1], MENU[2], MENU[3], MENU[4], { 248, 248, 248 }, { 88, 104, 136 })
    local labels = { self:text(7, "Switch"), self:text(8, "Sort"), self:text(4, "Return") }
    for i = 0, 2 do
      local y = MENU[2] + 4 + i * 24
      if self.menu == i then
        S.color({ 255, 228, 150 }); love.graphics.rectangle("fill", MENU[1] + 4, y, MENU[3] - 8, 22)
      end
      S.text(labels[i + 1], MENU[1] + 14, y + 4)
    end
  elseif s == "confirm" then
    S.yesNo(self.yes, 88)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------- the cartridge's art

local function ink3(c, fallback) return c or fallback end

-- a message in member 8's frame: one line at tile row 21, two at row 18
function C:frameMessage(art, text)
  local two = text:find(string.char(10), 1, true) ~= nil
  local fy = two and 18 * 8 or 21 * 8
  local sy = two and 3 * 8 or 0
  S.draw(art.frames, 0, fy, 0, sy, 24 * 8, two and 48 or 24)
  local inks = art.inks and art.inks.message or {}
  S.lines(text, 10, (two and 19 or 21) * 8 + 4, ink3(inks[1], S.INK), ink3(inks[2], S.SHADOW))
end

-- one sbox_gra tile at tile (tx, ty), `h` tiles tall
local function sboxTile(lm, n, tx, ty, w, h)
  local img = S.image(lm and lm.tiles)
  if not img then return end
  local q = love.graphics.newQuad(n * 8, 0, 8, 8, img:getDimensions())
  for dy = 0, (h or 1) - 1 do
    for dx = 0, (w or 1) - 1 do love.graphics.draw(img, q, (tx + dx) * 8, (ty + dy) * 8) end
  end
end

-- TouchscreenListMenu_DrawButtons / _PrintOptions / _ToggleButtonPalette
function C:drawListMenu(all)
  local lm = all and all.listMenu
  if not (lm and lm.tiles) then return false end
  local x, y, width = self:menuGeometry()
  local n, cur, last = 3, self.menu, 2
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local top = (cur == 0) and 12 or 0
  sboxTile(lm, top, x, y); sboxTile(lm, top + 1, x + 1, y, width, 1); sboxTile(lm, top + 2, x + width + 1, y)
  local bot = 9 + ((cur == last) and 12 or 0)
  sboxTile(lm, bot, x, y + n * 3); sboxTile(lm, bot + 1, x + 1, y + n * 3, width, 1)
  sboxTile(lm, bot + 2, x + width + 1, y + n * 3)
  for i = 0, n - 2 do
    local t = 6
    if (cur == 0 and i == 0) or cur == i then t = t + 12
    elseif (cur == last and i == last - 1) or cur == i + 1 then t = t + 18 end
    sboxTile(lm, t, x, y + i * 3 + 3); sboxTile(lm, t + 1, x + 1, y + i * 3 + 3, width, 1)
    sboxTile(lm, t + 2, x + width + 1, y + i * 3 + 3)
  end
  local col = lm.colours or {}
  local labels = self:menuLabels()
  for i = 0, n - 1 do
    local sel = cur == i
    local t = 3 + (sel and 12 or 0)
    sboxTile(lm, t, x, y + i * 3 + 1, 1, 2)
    sboxTile(lm, t + 2, x + width + 1, y + i * 3 + 1, 1, 2)
    -- the window: filled 3 / 6, the label centred in (1, 2, 3) / (4, 5, 6)
    local fill = col[sel and 6 or 3] or { 248, 248, 248 }
    S.color(fill)
    g.rectangle("fill", (x + 1) * 8, (y + 1 + 3 * i) * 8, width * 8, 16)
    local l = labels[i + 1]
    S.text(l, (x + 1) * 8 + math.floor((width * 8 - S.width(l)) / 2), (y + 1 + 3 * i) * 8,
           col[sel and 4 or 1] or S.INK, col[sel and 5 or 2] or S.SHADOW)
  end
  g.setColor(1, 1, 1, 1)
  return true
end

-- the picker's twelve pictures: the page's six at (16 + 80 col, 24 + 72 row),
-- during a page turn the old page leaving and the new one arriving
function C:drawPickerPictures(art)
  local function page(p, dx)
    for i = 0, 5 do
      S.draw(art.areas and art.areas[p * 6 + i], 16 + 80 * (i % 3) + dx, 24 + 72 * math.floor(i / 3))
    end
  end
  local ps = self.pageSlide
  if ps then
    local d = C.PAGE_STEP * ps.k
    page(ps.from, -ps.dir * d)
    page(self.page, ps.dir * (256 - d))
  else
    page(self.page, 0)
  end
end

function C:drawTopArt(art)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local all = S.art(self.game)
  local _, topScroll = self:scrolls()
  S.draw(self.objectsShown and art.topObjects or art.topPlain, 0, 0, 0, 0, 256, 192)
  local inks = art.inks and art.inks.area or {}
  local i1, i2 = ink3(inks[1], S.INK), ink3(inks[2], S.SHADOW)
  local boardShown = topScroll > -192
  local slot = self:slotFocus()
  if self.objectsShown and topScroll < 0 then
    -- the objects page under the board (ov108_021E7CD8): five counts for the
    -- slot under the cursor
    local n = self:counts(math.min(5, slot))
    if slot < 6 then
      for i = 1, 5 do
        local y = 8 + (i - 1) * 32
        S.lines(self:text(9 + i, ""), 12, y, i1, i2)
        S.text(("%2d"):format(n[i]), 224, y + 8, i1, i2)
      end
    end
  end
  if boardShown then
    local oy = -topScroll
    g.setScissor()
    S.draw(art.topBoard, 0, oy, 0, 0, 256, 168)
    for i = 0, 5 do
      local area = self.work.areas[i + 1].area
      S.draw(art.areas and art.areas[area], (3 + 9 * (i % 3)) * 8, (3 + 9 * math.floor(i / 3)) * 8 + oy)
    end
    -- the top board's cursor on the slot being switched (kind 2)
    if self.state ~= "slide" then
      S.sprite(art.sprites, 0, self.t, 56 + 72 * (self.cursor % 3), 56 + 72 * math.floor(self.cursor / 3) + oy)
    end
  end
  -- the name window (1, 21) 30 x 3: the slot's area centred (ov108_021E7CD8),
  -- or, switching, the slot's area and the picked one in two 96 px halves
  -- (ov108_021E7EB0, the second at + 0x90)
  if self.state == "switch" or self.state == "confirm" then
    local a = self:areaName(self.work.areas[self.cursor + 1].area)
    S.centred(a, 8, 96, 21 * 8 + 4, i1, i2)
    if self.pick < 6 then S.centred(self:areaName(self.page * 6 + self.pick), 8 + 0x90, 96, 21 * 8 + 4, i1, i2) end
  elseif self.state ~= "slide" and slot < 6 then
    S.centred(self:areaName(self.work.areas[slot + 1].area), 8, 240, 21 * 8 + 4, i1, i2)
  end
  g.setColor(1, 1, 1, 1)
end

function C:drawBottomArt(art, single)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local all = S.art(self.game)
  local s = self.state
  local bottomScroll = self:scrolls()
  local picking = s == "switch" or s == "confirm"
  S.draw(art.picker, 0, 0, 0, 0, 256, 192)
  local bink = art.inks and art.inks.button or {}
  local i1, i2 = ink3(bink[1], S.INK), ink3(bink[2], S.SHADOW)
  if picking then
    self:drawPickerPictures(art)
    local current = self.work.areas[self.cursor + 1].area
    if not self.pageSlide then
      for i = 0, 5 do
        if self.page * 6 + i == current then
          S.sprite(art.sprites, 2, self.t, 48 + 80 * (i % 3), 56 + 72 * math.floor(i / 3))
        end
      end
    end
    -- the page "n/2" in (13, 0) 6 x 2, (3, 1, 2); the arrows (ov108_021E77D4):
    -- left 6 on page 1 else 4, right 7 on page 2 else 5; a touched one runs
    -- its sequence (4: 4, 6, 4 / 5: 5, 7, 5)
    S.centred(("%d/2"):format(self.page + 1), 13 * 8, 48, 4, i1, i2)
    local press = self.arrowPress and (self.t - self.arrowPress.t) < 7 and self.arrowPress.side or nil
    local pt = press and (self.t - self.arrowPress.t) or 0
    if self.page == 0 then S.sprite(art.sprites, 6, 0, 80, 16)
    else S.sprite(art.sprites, 4, press == 0 and pt or 0, 80, 16) end
    if self.page == 1 then S.sprite(art.sprites, 7, 0, 176, 16)
    else S.sprite(art.sprites, 5, press == 1 and pt or 0, 176, 16) end
    S.centred(self:text(4, "Return"), 25 * 8, 48, 21 * 8 + 4, i1, i2)
    if s == "switch" and not self.pageSlide then
      if self.pick >= 6 then S.sprite(art.sprites, 1, self.t, 224, 180)
      else S.sprite(art.sprites, 0, self.t, 48 + 80 * (self.pick % 3), 56 + 72 * math.floor(self.pick / 3)) end
    end
  else
    -- the board (main BG2) and its six pictures, scrolled by 0x184E4
    local oy = -bottomScroll
    S.draw(art.board, 0, oy, 0, 0, 256, 168)
    for i = 0, 5 do
      local area = self.work.areas[i + 1].area
      S.draw(art.areas and art.areas[area], 24 + 72 * (i % 3), 24 + 72 * math.floor(i / 3) + oy)
    end
    S.centred(self:text(s == "slide" and 4 or 6, "Quit"), 25 * 8, 48, 21 * 8 + 4, i1, i2)
    if s ~= "slide" then
      local c = (s == "sort") and self.target or self.cursor
      if s == "sort" then
        S.sprite(art.sprites, 2, self.t, 56 + 72 * (self.cursor % 3), 56 + 72 * math.floor(self.cursor / 3))
      end
      if c >= 6 then S.sprite(art.sprites, 1, self.t, 224, 180)
      else S.sprite(art.sprites, s == "sort" and 3 or 0, self.t, 56 + 72 * (c % 3), 56 + 72 * math.floor(c / 3)) end
    end
  end
  local prompt = self:prompt()
  if prompt then
    self:frameMessage(art, prompt)
  elseif single and s == "main" and self.cursor < 6 then
    self:frameMessage(art, self:areaName(self.work.areas[self.cursor + 1].area))
  end
  if s == "menu" then
    if not self:drawListMenu(all) then
      S.box(MENU[1], MENU[2], MENU[3], MENU[4], { 248, 248, 248 }, { 88, 104, 136 })
      local labels = self:menuLabels()
      for i = 0, 2 do
        local y = MENU[2] + 4 + i * 24
        if self.menu == i then S.color({ 255, 228, 150 }); g.rectangle("fill", MENU[1] + 4, y, MENU[3] - 8, 22) end
        S.text(labels[i + 1], MENU[1] + 14, y + 4)
      end
    end
  elseif s == "confirm" then
    S.yesNoArt(all, self.yes, C.YESNO_TILE[1], C.YESNO_TILE[2])
  end
  g.setColor(1, 1, 1, 1)
end

function C:draw()
  local all = S.art(self.game)
  local art = all and all.customizer
  if art and art.board then
    S.present(self.game, function() self:drawTopArt(art) end,
              function(single) self:drawBottomArt(art, single) end, self:veilAmount())
    return
  end
  S.present(self.game, function() self:drawTop() end,
            function(single) self:drawBottom(single) end, self:veilAmount())
end


return C
