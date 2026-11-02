-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S UNOWN REPORT -- key item 469, fieldUseFunc 25
-- (ItemMenuUseFunc_UnownReport from the bag, ItemFieldUseFunc_UnownReport
-- from the registered button) -> UnownReport_LaunchApp, overlay 113. The
-- overlay is undecompiled; this follows pokeheartgold asm/overlay_113.s.
-- Art: src/import/Gen4HgssUnownReportArt.lua (gen4_hgss_unown_report).
--
-- THE BOOK (ov113_021E5A7C). The letters are the CAUGHT order
-- (Pokedex_GetSeenFormByIdx_Unown(.., TRUE), src/pokemon/Gen4UnownOrder.lua);
-- once VAR_UNOWN_REPORT_LEVEL (0x403E) is 4 or more the report has sorted
-- them -- A..Z, then ! / ? as caught -- still Pokedex_GetSeenFormNum_Unown of
-- them. Pages: the cover, ceil(n / 14) letter pages, then one spread per
-- report entry whose left half's level the var has reached (ov113_021E5D80).
--
--   cover   top: msg 1 "UNOWN Report" centred at y 56 and the player's name
--           right-aligned to x 176 at y 72 (window 1: BG5 tile (2, 3), 24 x
--           20); bottom: msg 3 at y 60 and msg 4 "Current Kinds: nn" at y 76
--           (window 2: BG1 tile (2, 1))
--   letters 14 a page: rows 0..6 on the top screen, 7..13 on the bottom, 24
--           px apart; the icon (GetMonIconNaixEx(UNOWN, 0, form), frame 0)
--           at x 40, and the letter's word (msg 20 + form) at window x 48
--   report  left half on the top, right on the bottom, msg start..start+n-1
--           at (4, 24) -- each line's {CURSOR_Y} placing it -- msg 15 in
--           FONT_UNOWN at (4, 0)
--   always  the page number (msg 5, "p/total") in window 3 (BG1 tile (28, 9),
--           3 x 2) in MAKE_TEXT_COLOR(15, 2, 0); CANCEL (msg 0, window 0 at
--           tile (25, 21), 6 x 2, centred) in (7, 15, 0) over the button
--
-- INPUT (ov113_021E5D60): a touch on sHitboxes first -- CANCEL y 160..191 x
-- 192..255, up y 16..36 x 220..243, down y 120..140 x 220..243 -- else B
-- (exit), UP (back), DOWN (forward). A page turn plays SE 0x5DC and the
-- arrow's pressed sequence, wipes both screens out (bottom FADE_TYPE_UPWARD_
-- OUT, top DOWNWARD_OUT, 6 steps), redraws and wipes back in (bottom
-- DOWNWARD_IN, top type 5). CANCEL plays SE 0x5DD and its pressed sequence;
-- when that has played out, both screens fade to black and the app ends --
-- back to the bag (Task_ReturnToMenuFromAppItem) or the field (registered).
-- It opens with a 6-step brightness fade in. No music change.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local R = {}
R.__index = R
R.isOpaque = true

local W, H = 256, 192
function R:uiSize() return W, H end
function R:wantsFillScale() return true end

R.TEXT_BANK = 1
R.VAR_LEVEL = 0x403E
R.PER_PAGE = 14
R.FADE = 6
R.SE_PAGE, R.SE_EXIT = "SEQ_SE_DP_SELECT", "SEQ_SE_DP_DECIDE"   -- 0x5DC / 0x5DD

-- the spread table when the cache has none (ov113_021E6BD0)
local SPREADS = {
  { left = { start = 6, count = 1, level = 1 }, right = { start = 7, count = 1, level = 1 } },
  { left = { start = 8, count = 1, level = 2 }, right = { start = 9, count = 1, level = 3 } },
  { left = { start = 10, count = 1, level = 4 }, right = { start = 11, count = 1, level = 4 } },
  { left = { start = 12, count = 1, level = 5 }, right = { start = 13, count = 1, level = 6 } },
  { left = { start = 14, count = 3, level = 7 }, right = { start = 17, count = 1, level = 7 } },
  { left = { start = 18, count = 1, level = 8 }, right = { start = 19, count = 1, level = 8 } },
}

-- the buttons (UnmanagedSpriteTemplate ov113_021E6CF8, main OBJ)
local BUTTONS = {
  cancel = { x = 224, y = 176, idle = 0, pressed = 1 },
  up = { x = 236, y = 28, idle = 2, pressed = 3, off = 4 },
  down = { x = 236, y = 132, idle = 5, pressed = 6, off = 7 },
}
-- ov113_021E6B82: top, bottom, left, right
local HITBOXES = { { 160, 192, 192, 256, "cancel" }, { 16, 37, 220, 244, "up" }, { 120, 141, 220, 244, "down" } }

local function se(self, name)
  local data = self.game and self.game.data
  pcall(function() require("src.core.Sound").playSe(data, name) end)
end

function R.available(game)
  local rec = game and game.data and game.data.gen4_hgss_unown_report
  return type(rec) == "table" and type(rec.top) == "table" and type(rec.bottom) == "table" and rec.top.base ~= nil
end

local function varLevel(save)
  local ok, v = pcall(function() return require("src.script.Gen4Commands").getVar(save, R.VAR_LEVEL) end)
  return ok and tonumber(v) or 0
end

-- ov113_021E5A7C: the letters, the page count
function R.book(save, spreads)
  local level = varLevel(save)
  local caught = require("src.pokemon.Gen4UnownOrder").caught(save)
  local letters = {}
  if level >= 4 then
    for f = 0, 25 do letters[#letters + 1] = f end
    for _, f in ipairs(caught) do if f == 26 or f == 27 then letters[#letters + 1] = f end end
  else
    for _, f in ipairs(caught) do letters[#letters + 1] = f end
  end
  local count = #caught
  local unownPages = math.floor(count / R.PER_PAGE) + ((count % R.PER_PAGE ~= 0) and 1 or 0)
  local reportPages = 0
  for i = 1, math.min(6, #spreads) do
    if spreads[i].left.level > level then break end
    reportPages = i
  end
  return { level = level, letters = letters, count = count, unownPages = unownPages,
           reportPages = reportPages, total = unownPages + reportPages + 1 }
end

function R.new(game, onDone)
  local rec = game.data.gen4_hgss_unown_report or {}
  local self = setmetatable({ game = game, rec = rec, onDone = onDone, images = {}, quads = {},
                              state = "fadein", t = 0, page = 0, anim = {} }, R)
  self.spreads = (type(rec.spreads) == "table" and #rec.spreads > 0) and rec.spreads or SPREADS
  self.book = R.book(game.save, self.spreads)
  local save = game.save or {}
  self.player = save.player and save.player.name or "PLAYER"
  self:setButton("cancel", "idle")
  self.single, self.half = true, "top"   -- one-screen reading (R:showingBottom)
  self:arrows()
  return self
end

function R:text(n)
  local t = self.game.data and self.game.data.text
  local s = t and t[("TEXT_B%04d_%05d"):format(R.TEXT_BANK, n)]
  return type(s) == "string" and s or ""
end

function R:img(entry)
  local path = type(entry) == "table" and entry.path or entry
  if type(path) ~= "string" then return nil end
  local hit = self.images[path]
  if hit == nil then
    local ok, i = pcall(Assets.image, path)
    if ok and i then i:setFilter("nearest", "nearest") end
    hit = (ok and i) or false
    self.images[path] = hit
  end
  return hit or nil
end

-- --------------------------------------------------------------- buttons

function R:setButton(name, look)
  local b = BUTTONS[name]
  self.anim[name] = { seq = b[look] or b.idle, t = 0 }
end

-- ov113_021E6B1C. One screen (below): UP is live past the first half-page,
-- DOWN until the last one.
function R:arrows()
  local bk = self.book
  if self.single and not self:dualScreen() then
    local first = self.page == 0 and self.half ~= "bottom"
    local last = self.page == bk.total - 1 and self.half == "bottom"
    self:setButton("up", first and "off" or "idle")
    self:setButton("down", last and "off" or "idle")
    return
  end
  self:setButton("up", (bk.total == 1 or self.page == 0) and "off" or "idle")
  self:setButton("down", (bk.total == 1 or self.page == bk.total - 1) and "off" or "idle")
end

function R:seqLength(seq)
  local an = self.rec.buttons and self.rec.buttons.anims and self.rec.buttons.anims[seq + 1]
  if not an then return 0 end
  local n = 0
  for _, f in ipairs(an.frames or {}) do n = n + math.max(1, f.duration or 1) end
  return n
end

-- Sprite_IsAnimated: a one-shot sequence still playing
function R:animating(name)
  local a = self.anim[name]
  return a ~= nil and a.t < self:seqLength(a.seq)
end

function R:cellOf(name)
  local a = self.anim[name]
  local an = a and self.rec.buttons and self.rec.buttons.anims and self.rec.buttons.anims[a.seq + 1]
  if not (an and an.frames and #an.frames > 0) then return nil end
  local t = a.t
  for _, f in ipairs(an.frames) do
    local d = math.max(1, f.duration or 1)
    if t < d then return f.cell end
    t = t - d
  end
  return an.frames[#an.frames].cell
end

-- ------------------------------------------------------------------ input

function R:dualScreen()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  local mode = SS.mode(self.game)
  return SS.separateMode(mode) and not SS.stowed(self.game), SS
end

-- ONE SCREEN IN THE WINDOW (SecondScreen swap / off, or the second screen
-- stowed) -- INFERRED, the cartridge always has both: every spread is read as
-- two half-pages, the top screen's and then the bottom one's. DOWN turns to
-- the next half (the bottom of this spread, then the top of the next), UP
-- back; the buttons (CANCEL, the arrows, the page number) are drawn on the top
-- half too, so a touch works on either half. `self.half` is the half on show.
function R:showingBottom()
  local dual = self:dualScreen()
  if dual then return true end
  return self.half == "bottom"
end

function R:point(px, py)
  local dual, SS = self:dualScreen()
  if dual then return SS.toLocal(self.game, px, py) end
  local r = require("src.render.Renderer").uiPresentation
  if not r or px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return nil end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

function R:touchpressed(id, px, py)
  local x, y = self:point(px, py)
  if not x then return false end
  self.tap = { x = x, y = y }
  return true
end
function R:mousepressed(x, y, button)
  if button == 1 then return self:touchpressed("mouse", x, y) end
end

-- TouchscreenHitbox_FindHitboxAtTouchNew
function R.hitbox(x, y)
  for _, h in ipairs(HITBOXES) do
    if y >= h[1] and y < h[2] and x >= h[3] and x < h[4] then return h[5] end
  end
  return nil
end

-- ov113_021E5ED0: 0 exit, 1 back, 2 forward
function R:act(what)
  local bk = self.book
  if what == "cancel" then
    se(self, R.SE_EXIT)
    self:setButton("cancel", "pressed")
    self.state, self.t = "exit", 0
  elseif what == "up" and not self:dualScreen() then
    if self.page == 0 and self.half ~= "bottom" then return end
    if self.half == "bottom" then self.nextPage, self.nextHalf = self.page, "top"
    else self.nextPage, self.nextHalf = self.page - 1, "bottom" end
    self:setButton("up", "pressed")
    se(self, R.SE_PAGE)
    self.state, self.t = "pageout", 0
  elseif what == "down" and not self:dualScreen() then
    if self.page >= bk.total - 1 and self.half == "bottom" then return end
    if self.half ~= "bottom" then self.nextPage, self.nextHalf = self.page, "bottom"
    else self.nextPage, self.nextHalf = self.page + 1, "top" end
    self:setButton("down", "pressed")
    se(self, R.SE_PAGE)
    self.state, self.t = "pageout", 0
  elseif what == "up" then
    if self.page == 0 then return end
    self.nextPage = self.page - 1
    self:setButton("up", "pressed")
    se(self, R.SE_PAGE)
    self.state, self.t = "pageout", 0
  elseif what == "down" then
    if self.page >= bk.total - 1 then return end
    self.nextPage = self.page + 1
    self:setButton("down", "pressed")
    se(self, R.SE_PAGE)
    self.state, self.t = "pageout", 0
  end
end

-- --------------------------------------------------------- the main loop

function R:update()
  for _, a in pairs(self.anim) do a.t = a.t + 1 end
  local tap = self.tap
  self.tap = nil
  self.t = self.t + 1
  local s = self.state
  if s == "fadein" then
    if self.t >= R.FADE then self.state, self.t = "input", 0 end
  elseif s == "input" then
    local hit = tap and R.hitbox(tap.x, tap.y)
    if hit then
      self:act(hit)
    else
      local input = self.game.input
      local function pressed(k) return input and input.wasPressed and input:wasPressed(k) end
      if pressed("b") then self:act("cancel")
      elseif pressed("up") then self:act("up")
      elseif pressed("down") then self:act("down") end
    end
  elseif s == "pageout" then
    if self.t >= R.FADE then
      -- the new page is drawn once the old one is wiped away (ov113_021E5DA4)
      self.page, self.nextPage = self.nextPage or self.page, nil
      if self.nextHalf then self.half, self.nextHalf = self.nextHalf, nil end
      self:arrows()
      self.state, self.t = "pagein", 0
    end
  elseif s == "pagein" then
    if self.t >= R.FADE then self.state, self.t = "input", 0 end
  elseif s == "exit" then
    if not self:animating("cancel") then self.state, self.t = "fadeout", 0 end
  elseif s == "fadeout" then
    if self.t >= R.FADE then self:finish() end
  end
end

function R:finish()
  if self.finished then return end
  self.finished = true
  local stack = self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone() end
end

-- ----------------------------------------------------------------- drawing

local function setInk(c)
  if c then love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  else love.graphics.setColor(0.32, 0.32, 0.35, 1) end
end

local function shadowed(s, x, y, ink)
  if ink and ink[2] then
    setInk(ink[2]); Font.draw(s, x + 1, y); Font.draw(s, x, y + 1); Font.draw(s, x + 1, y + 1)
  end
  setInk(ink and ink[1]); Font.draw(s, x, y)
end

-- {STRVAR_1 kind, slot, 0} -> the slot's buffer
local function expand(raw, buffers)
  return (raw:gsub("{STRVAR_1 %d+,? (%d+),? %d+}", function(slot) return buffers[tonumber(slot) + 1] or "" end))
end

-- a message into a window: lines 16 px apart, {ALN_CENTER} centred in the
-- window's width, {CURSOR_Y n} moving the pen; ox / oy the window on screen
function R:print(raw, wx, wy, ww, x, y, ink, buffers, face)
  for line in (tostring(raw) .. "\n"):gmatch("(.-)\n") do
    local cy = line:match("{CURSOR_Y (%d+)}")
    if cy then y = tonumber(cy) end
    local centre = line:find("{ALN_CENTER}", 1, true) ~= nil
    local s = expand(line, buffers or {}):gsub("{[^}]*}", "")
    if face then
      self:unownLine(s, wx + x, wy + y, ink)
    else
      local px = centre and math.floor((ww - Font.width(s)) / 2) or x
      shadowed(s, wx + px, wy + y, ink)
    end
    y = y + 16
  end
end

-- FONT_UNOWN (font 3 of /a/0/1/6, the font record's `unown` face), the way
-- HgssAlphInscription draws it
local reverse
local function codes(text)
  if not reverse then
    reverse = {}
    for code, ch in pairs(require("src.import.Gen4Text").CHARS or {}) do
      if type(ch) == "string" and reverse[ch] == nil then reverse[ch] = code end
    end
  end
  local out = {}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = reverse[ch] or reverse[" "] or 0x1DE
  end
  return out
end

function R:unownLine(s, x, y, ink)
  local f = ((self.game.data.font or {}).faces or {}).unown
  local sheet = f and self:img(f.image)
  if not (f and sheet) then shadowed(s, x, y, ink); return end
  local g = love.graphics
  local gw, gh, cols = f.glyphWidth or 16, f.glyphHeight or 16, f.glyphsPerRow or 32
  local widths, base = f.widths or {}, f.base or 1
  local sw, sh = sheet:getDimensions()
  setInk(ink and ink[1])
  for _, c in ipairs(codes(s)) do
    local glyph = c - base
    local key = "u" .. glyph
    local q = self.quads[key]
    if not q then
      q = g.newQuad((glyph % cols) * gw, math.floor(glyph / cols) * gh, gw, gh, sw, sh)
      self.quads[key] = q
    end
    g.draw(sheet, q, x, y)
    local w = widths[c - base + 1]
    x = x + ((w and w > 0) and w or (f.advance or gw))
  end
end

function R:screenImage(entry)
  local img = self:img(entry)
  if not img then return end
  local key = "s" .. tostring(entry.path)
  local q = self.quads[key]
  if not q then
    local iw, ih = img:getDimensions()
    q = love.graphics.newQuad(0, 0, math.min(W, iw), math.min(H, ih), iw, ih)
    self.quads[key] = q
  end
  love.graphics.draw(img, q, 0, 0)
end

-- the kind of page on show (ov113_021E5DA4)
function R:pageKind()
  local bk = self.book
  if self.page == 0 then return "cover" end
  if self.page - 1 < bk.unownPages then return "list", self.page - 1 end
  return "report", self.page - (bk.unownPages + 1)
end

function R:icon(form, cx, cy)
  local icons = self.game.data.icons
  local idx = (form == 0) and 201 or (500 + form - 1)    -- member 507 + form - 1, less 7
  local entry = icons and icons.bySpecies and icons.bySpecies[idx]
  local path = type(entry) == "table" and entry.image or entry
  local img = self:img(path)
  if not img then return end
  local key = "i" .. tostring(path)
  local q = self.quads[key]
  if not q then
    local iw, ih = img:getDimensions()
    local fh = (type(entry) == "table" and tonumber(entry.frameHeight)) or 32
    -- icongra animation bank 1, sequence 0: one still frame (cell 0)
    local frame = (self.rec.iconFrames and self.rec.iconFrames[1] and self.rec.iconFrames[1].cell) or 0
    if (frame + 1) * fh > ih then frame = 0 end
    q = love.graphics.newQuad(0, frame * fh, iw, fh, iw, ih)
    self.quads[key] = q
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, cx - 16, cy - 16)
end

-- black wipes: `down` covers from the top edge, `up` from the bottom edge;
-- k = 0..1 of the screen covered
local function wipe(from, k)
  if k <= 0 then return end
  local h = math.floor(H * math.min(1, k) + 0.5)
  love.graphics.setColor(0, 0, 0, 1)
  if from == "top" then love.graphics.rectangle("fill", 0, 0, W, h)
  else love.graphics.rectangle("fill", 0, H - h, W, h) end
  love.graphics.setColor(1, 1, 1, 1)
end

function R:veil(screen)
  local s, k = self.state, math.min(1, self.t / R.FADE)
  local g = love.graphics
  if s == "fadein" or s == "fadeout" then
    local a = (s == "fadein") and (1 - k) or k
    if a > 0 then
      g.setColor(0, 0, 0, a); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1)
    end
  elseif s == "pageout" then
    -- top FADE_TYPE_DOWNWARD_OUT, bottom FADE_TYPE_UPWARD_OUT
    wipe(screen == "top" and "top" or "bottom", k)
  elseif s == "pagein" then
    -- bottom FADE_TYPE_DOWNWARD_IN (uncovered from the top down), top type 5
    -- (uncovered from the bottom up)
    wipe(screen == "top" and "top" or "bottom", 1 - k)
  end
end

function R:drawTop()
  local g = love.graphics
  local rec, bk = self.rec, self.book
  local top = rec.top or {}
  local bd = top.backdrop
  g.clear(bd and bd[1] / 255 or 0, bd and bd[2] / 255 or 0, bd and bd[3] / 255 or 0, 1)
  g.setColor(1, 1, 1, 1)
  self:screenImage(top.base)
  local kind, n = self:pageKind()
  self:screenImage(top[kind])
  local ink = rec.inks and rec.inks.text
  local WX, WY, WW = 16, 24, 192          -- window 1
  if kind == "cover" then
    self:print(self:text(1), WX, WY, WW, 0, 56, ink)
    shadowed(self.player, WX + 176 - Font.width(self.player), WY + 72, ink)
  elseif kind == "list" then
    for i = 0, 6 do
      local f = bk.letters[n * R.PER_PAGE + i + 1]
      if f and n * R.PER_PAGE + i < bk.count then
        self:icon(f, 40, 29 + 24 * i)
        self:print(self:text(20 + f), WX, WY, WW, 48, 24 * i, ink)
      end
    end
  else
    self:printSpread(n, "left", WX, WY, WW, ink)
  end
  g.setColor(1, 1, 1, 1)
end

function R:printSpread(n, side, wx, wy, ww, ink)
  local sp = self.spreads[n + 1]
  local half = sp and sp[side]
  if not half or half.level > self.book.level then return end
  for i = 0, half.count - 1 do
    local m = half.start + i
    if m == 15 then
      self:print(self:text(m), wx, wy, ww, 4, 0, ink, nil, "unown")
    else
      self:print(self:text(m), wx, wy, ww, 4, 24, ink)
    end
  end
end

function R:drawButton(name)
  local b = BUTTONS[name]
  local cell = self:cellOf(name)
  local set = self.rec.buttons and self.rec.buttons.cells
  local entry = cell and set and set[cell + 1]
  local img = entry and self:img(entry)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, b.x - (entry.ox or 0), b.y - (entry.oy or 0))
end

function R:drawBottom()
  local g = love.graphics
  local rec, bk = self.rec, self.book
  local bot = rec.bottom or {}
  local bd = bot.backdrop
  g.clear(bd and bd[1] / 255 or 0, bd and bd[2] / 255 or 0, bd and bd[3] / 255 or 0, 1)
  g.setColor(1, 1, 1, 1)
  self:screenImage(bot.base)
  local kind, n = self:pageKind()
  self:screenImage(bot[kind])
  local inks = rec.inks or {}
  local ink = inks.text
  local WX, WY, WW = 16, 8, 192           -- window 2
  -- the buttons (OBJ priority 2) under the BG1 text
  self:drawButton("cancel"); self:drawButton("up"); self:drawButton("down")
  if kind == "cover" then
    self:print(self:text(3), WX, WY, WW, 4, 60, ink)
    self:print(self:text(4), WX, WY, WW, 4, 76, ink, { ("%2d"):format(bk.count) })
  elseif kind == "list" then
    for i = 7, 13 do
      local f = bk.letters[n * R.PER_PAGE + i + 1]
      if f and n * R.PER_PAGE + i < bk.count then
        self:icon(f, 40, 24 * i - 155)
        self:print(self:text(20 + f), WX, WY, WW, 48, 24 * i - 168, ink)
      end
    end
  else
    self:printSpread(n, "right", WX, WY, WW, ink)
  end
  -- window 3, the page number; window 0, CANCEL
  self:print(self:text(5), 224, 72, 24, 0, 0, inks.page, { tostring(self.page + 1), tostring(bk.total) })
  local cancel = self:text(0)
  shadowed(cancel, 200 + math.floor((48 - Font.width(cancel)) / 2), 168, inks.cancel)
  g.setColor(1, 1, 1, 1)
end

function R:draw()
  local dual, SS = self:dualScreen()
  if dual then
    love.graphics.push("all")
    love.graphics.setScissor()
    self:drawTop(); self:veil("top")
    love.graphics.pop()
    SS.draw(self.game, function() self:drawBottom(); self:veil("bottom") end)
  elseif self:showingBottom() then
    self:drawBottom(); self:veil("bottom")
  else
    self:drawTop()
    -- one screen: the bottom's buttons and page number over the top half
    local bk = self.book
    self:drawButton("cancel"); self:drawButton("up"); self:drawButton("down")
    local inks = self.rec.inks or {}
    self:print(self:text(5), 224, 72, 24, 0, 0, inks.page, { tostring(self.page + 1), tostring(bk.total) })
    local cancel = self:text(0)
    shadowed(cancel, 200 + math.floor((48 - Font.width(cancel)) / 2), 168, inks.cancel)
    love.graphics.setColor(1, 1, 1, 1)
    self:veil("top")
  end
end

return R
