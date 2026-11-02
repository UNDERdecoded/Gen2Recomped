-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- THE SECRET BASE'S SCREENS, single player: the prompts (drill, enter,
-- leave), the base PC (pc.c), decorating (decoration_menu.c,
-- base_decoration.c), CHECK FLAGS and the TRAINER record (records.c), and the
-- PC's radars (pc.c 727-785, mining.c 2939-3036, spheres.c 522-582,
-- traps.c 2709-2774). The state is src/world/Gen4UgBase.lua.
--
-- READ FROM CODE (messages: common 634, pc 639, decoration 637, records 640,
-- goods 626):
--   * PC: DECORATE / STORE GOODS / RECEIVE GOODS / CHECK FLAGS / USE RADAR
--     (only at flag rank >= Gold, pc.c 366) / EXIT, descriptions 6-11; STORE
--     moves a good from the bag to the PC (37, 38 full); RECEIVE back (36,
--     55 on display, 39 bag full); DECORATE needs goods in the PC (60) and the
--     door closed (56), and sets FLAG_DECORATED_SECRET_BASE when it ends
--     (pc.c 613-657);
--   * DECOR: DECORATE / PUT AWAY / MOVE GOODS / CANCEL (1-8). DECORATE: none
--     in the PC 19, the limit 20, already out 21; the good appears at (16,13),
--     the d-pad moves it inside the play area, A places it (11, SE BOWA) or
--     12 (SE WALL_HIT2), B drops it. PUT AWAY: a cursor from (16,13); the PC
--     22; a boulder 15 / 18 / 14 + 17 or 25 by the rank's unremovable count;
--     a good 13. MOVE GOODS: the PC 23, a boulder 16, a good is lifted and
--     placed by the same rule, B puts it back;
--   * DECORATING'S CAMERA (pc.c 597-657): SE PC_LOGIN, a fade to black, the
--     player hidden and the camera moved to the room's (15, 17); at the end
--     the camera back on the player, a fade in;
--   * CHECK FLAGS: "{name}'s Base" 12, "Flags obtained:" 13 with the count,
--     "Most recent Flag:" 15, five rows "-------" / "ID:-------" (51, 52);
--   * TRAINER (records.c 125-233): NAME / ID, BASE FLAG (20 + rank), SCORE,
--     people met, gifts given, flags obtained, spheres dug, fossils dug, trap
--     hits (6-12);
--   * RADARS (pc.c 716-787): the menu goes, the radar runs on the top screen
--     (Gen4UgTopScreen), the field dims (brightness -6 on BG0), 48/49/50
--     "booted up"; A or B after it restores the plain radar and returns to
--     the radar menu; in a closed base only 57/58/59 "Nothing showed up".
-- THE WINDOWS, pixel for pixel (Window_Add x, y, w, h in tiles; the standard
-- frame one tile outside; ListMenu text 8 px in, the arrow at 0, 16 px rows):
--   message box (2,19,27,4) text_printer.c 149; YES/NO (25,13,6,4) pc.c 136 /
--   secret_bases.c 309, Menu text at +8; door choice (16,13,15,4)
--   secret_bases.c 319; the PC and radar menus (17,3,14,2n) pc.c 375 / 415;
--   the goods lists (19,3,12,12), 6 rows, menus.c 1585, with "Goods on hand" /
--   "Goods in PC" in (1,1,7,4) at (1,1) vendors.c 581; DECOR (19,3,12,8) with
--   "DECOR" in (1,1,7,2), the decoration goods list (19,3,12,2n), n <= 7, with
--   "Goods Set" / "n/m" in (1,1,8,4) (decoration_menu.c 135-404); a placed
--   good's name in colour 2; the trainer case / flags (4,2,24,19) records.c
--   376 with the offsets of records.c 22-35.
-- The decoration cursor is the cartridge's model data/ug_base_cur.nsbmd
-- (Gen4UgTopArt), shown while PUT AWAY / MOVE GOODS pick a good; a cache
-- without it shows a sparkle. INFERRED: text appears at once.

local Font = require("src.render.Font")
local Pockets = require("src.ui.Gen4UgPockets")

local M = {}

local function B() return require("src.world.Gen4UgBase") end
local function W() return require("src.world.Gen4UgWorld") end
local function UG() return require("src.world.Gen4Underground") end
local function Top() return require("src.ui.Gen4UgTopScreen") end
local BANK = { common = 634, pc = 639, deco = 637, records = 640, goods = 626 }
M.BANK = BANK
-- a message with its markers kept, as Gen4Text gives them (TextBox's own):
-- \v waits and scrolls one line up (0x25BC), \f waits and clears (0x25BD)
local function txt(game, bank, idx, slots)
  local T = require("src.import.Gen4Text")
  local values = {}
  for i = 0, 6 do values[i + 1] = slots and slots[i] or "" end
  T.buffer(game, (table.unpack or unpack)(values))
  local s = T.resolve(game.data, bank, idx, game) or ""
  s = s:gsub("\r", "\v")
  return s
end
M.txt = txt
local function ink() Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } }) end
local function dimInk() Font.pushStyle({ text = { 0.8, 0.8, 0.8 }, shadow = { 0.8, 0.8, 0.8 } }) end
local function se(game, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, game.data, name) end
end
local function playerName(game)
  local s = game.save or {}
  return (s.player and s.player.name) or s.playerName or ""
end
local function cursorAt(x, y) Font.drawCode(require("src.ui.Theme").cursor, x, y) end

-- a window as Window_Add places it, its standard frame a tile outside
local function win(x, y, w, h) Font.drawBox(x - 1, y - 1, w + 2, h + 2) end
M.win = win

-- the Underground text printers' message box (2, 19, 27, 4)
-- `rise`: a view that has just scrolled is drawn that many pixels low and
-- slides up under the window's clip (render_text.c 240-252: Window_Scroll 4
-- px a frame until one line, 16 px, has gone)
local function drawText(text, rise)
  if not text or text == "" then return end
  Font.drawDialogueBox(1, 18, 29, 6)
  local g = love.graphics
  g.setScissor(2 * 8, 19 * 8, 27 * 8, 4 * 8)
  ink()
  local y = 19 * 8 + (rise or 0)
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 2 * 8, y); y = y + 16 end
  Font.popStyle()
  g.setScissor()
end
M.drawText = drawText
M.SCROLL_PX, M.SCROLL_STEP = 16, 4
-- THE VIEWS OF THE TWO-LINE BOX, as render_text.c prints into it: \n moves
-- the pen down a line; \f waits and clears the box, the pen back at the top
-- (RENDER_STATE_CLEAR); \v waits and scrolls the window one line up with the
-- pen's line unchanged (RENDER_STATE_START_SCROLL / SCROLL) -- so after one
-- line the next text starts on the top line, after two on the bottom one,
-- under the line that was there. Answers the views (strings) and, beside
-- them, which ones came in by a scroll.
local function pages(text)
  local out, scrolled = {}, {}
  local rows, r, viaScroll = { "" }, 1, false
  local function snapshot()
    local l = {}
    for k = 1, math.max(#rows, r) do l[k] = rows[k] or "" end
    while #l > 0 and l[#l] == "" do l[#l] = nil end
    out[#out + 1] = table.concat(l, "\n")
    scrolled[#out] = viaScroll
  end
  for chunk in (text or ""):gmatch("[^\n\v\f]*[\n\v\f]?") do
    if chunk == "" then break end
    local body, mark = chunk:match("^([^\n\v\f]*)([\n\v\f]?)$")
    rows[r] = (rows[r] or "") .. body
    if mark == "\n" then
      r = r + 1
      rows[r] = rows[r] or ""
    elseif mark == "\v" then
      snapshot()
      table.remove(rows, 1)
      for k = 1, r do rows[k] = rows[k] or "" end
      rows[r] = ""
      viaScroll = true
    elseif mark == "\f" then
      snapshot()
      rows, r, viaScroll = { "" }, 1, false
    end
  end
  local any = false
  for _, v in ipairs(rows) do if v ~= "" then any = true end end
  if any then snapshot() end
  local keep, keepScroll = {}, {}
  for i, v in ipairs(out) do
    if v:gsub("\n", "") ~= "" then keep[#keep + 1] = v; keepScroll[#keep] = scrolled[i] end
  end
  return keep, keepScroll
end
M.pages = pages

-- a number right-aligned in a `width`-digit field (STRVAR ..., PADDING_MODE_SPACES)
local function numberAt(n, x, y, width)
  local s = tostring(n)
  local w = Font.width and Font.width(s) or #s * 6
  Font.draw(s, x + (width or 6) * 6 - w, y)
end

-- ------------------------------------------------------------- a prompt --
-- lines, then (optionally) a choice menu; onDone(choiceIndex or nil)
-- opts.menu = { x, y, w } (tiles), YES/NO's (25, 13, 6) by default
local Prompt = {}
Prompt.__index = Prompt
Prompt.isOpaque = false
function Prompt:uiSize() return 256, 192 end
function M.prompt(game, text, choices, onDone, opts)
  local views, scrolled = pages(text)
  local p = setmetatable({ game = game, pages = views, scrolled = scrolled, viewT = 0, choices = choices, onDone = onDone, index = 1,
                           opts = opts or {} }, Prompt)
  if #p.pages == 0 then p.pages = { "" } end
  game.stack:push(p)
  return p
end
function Prompt:finish(choice)
  if self.done then return end
  self.done = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone(choice) end
end
function Prompt:update()
  local input = self.game.input
  if self.opts.tick then self.opts.tick(self) end
  self.viewT = (self.viewT or 0) + 1
  if #self.pages > 1 then
    if input:wasPressed("a") or input:wasPressed("b") then
      table.remove(self.pages, 1)
      table.remove(self.scrolled, 1)
      self.viewT = 0
    end
    return
  end
  if not self.choices then
    if input:wasPressed("a") or input:wasPressed("b") then self:finish(nil) end
    return
  end
  -- Menu: loopAround FALSE
  local n = #self.choices
  if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1; se(self.game, "SEQ_SE_CONFIRM") end
  if input:wasPressed("down") and self.index < n then self.index = self.index + 1; se(self.game, "SEQ_SE_CONFIRM") end
  if input:wasPressed("a") then se(self.game, "SEQ_SE_CONFIRM"); return self:finish(self.index) end
  if input:wasPressed("b") then se(self.game, "SEQ_SE_CONFIRM"); return self:finish(self.opts.cancel or n) end
end
function Prompt:draw()
  if self.opts.under then self.opts.under(self) end
  drawText(self.pages[1], (self.scrolled and self.scrolled[1]) and math.max(0, M.SCROLL_PX - M.SCROLL_STEP * self.viewT) or 0)
  if self.choices and #self.pages == 1 then
    local m = self.opts.menu or { 25, 13, 6 }
    win(m[1], m[2], m[3], #self.choices * 2)
    ink()
    for i, c in ipairs(self.choices) do
      local y = m[2] * 8 + (i - 1) * 16
      Font.draw(c, m[1] * 8 + 8, y)
      if i == self.index then cursorAt(m[1] * 8, y) end
    end
    Font.popStyle()
  end
end
local function yesNo(game) local S = require("src.core.Strings"); return { S("YES"), S("NO") } end
function M.say(game, text, onDone) return M.prompt(game, text, nil, onDone) end

-- ------------------------------------------------------------ the drill --

-- a message that goes on by itself after `ticks` (a printer the task does not
-- wait on a button for)
local Timed = {}
Timed.__index = Timed
Timed.isOpaque = false
function Timed:uiSize() return 256, 192 end
function Timed:update()
  self.t = self.t + 1
  if self.t < self.ticks then return end
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end
function Timed:draw() drawText((pages(self.text))[1]) end
function M.timed(game, text, ticks, onDone)
  local s = setmetatable({ game = game, text = text, ticks = ticks, onDone = onDone, t = 0 }, Timed)
  game.stack:push(s)
  return s
end

-- SecretBases_DiggerDrillTask (secret_bases.c 1789-1914): SE DORIRU, the
-- drill in front of the player and 33 "The Digger Drill was used!"; 30 frames
-- once it is printed, 34 with the entrance and the smoke on the wall; when
-- that is printed, 35 / 36 and YES/NO -- no button before it. NO closes the
-- hole again (56, the smoke once more); YES makes the base and goes in.
-- INFERRED: a printed message is held 30 frames (the text speed's time).
M.DRILL_WAIT, M.PRINT_TICKS = 60, 30
function M.drill(game, ow, slot)
  local p = ow and ow.player
  if not p then return end
  local fx, fy = p:facingCell()
  local refusal = B().drillRefusal(game.save, ow.map, fx, fy, p.facing)
  if refusal then return M.say(game, txt(game, BANK.common, refusal)) end
  se(game, "SEQ_SE_DP_DORIRU")
  B().startFx(ow, "drill", fx, fy)
  local drillName = Pockets.trapName(game, 33)
  local had = B().base(game.save).active
  local dir = B().OPP[p.facing] or "down"
  M.timed(game, txt(game, BANK.common, 33, { [3] = drillName }), M.PRINT_TICKS + M.DRILL_WAIT, function()
    -- DRILL_STATE_CREATE_ENTRANCE: the entrance prop and the smoke
    ow.ugDrillHole = { x = fx, z = fy, dir = dir }
    ow.ugBaseKey = nil
    B().startFx(ow, "smoke", fx, fy)
    se(game, "SEQ_SE_DP_WIN_OPEN2")
    M.timed(game, txt(game, BANK.common, 34), M.PRINT_TICKS, function()
      M.prompt(game, txt(game, BANK.common, had and 36 or 35), yesNo(game), function(c)
        if c ~= 1 then
          ow.ugDrillHole = nil
          ow.ugBaseKey = nil
          B().startFx(ow, "smoke", fx, fy)
          se(game, "SEQ_SE_DP_WIN_OPEN2")
          return M.say(game, txt(game, BANK.common, 56))
        end
        ow.ugDrillHole = nil
        local traps = UG().traps(game.save)
        if traps[slot] == 33 then table.remove(traps, slot) end
        B().create(game.save, fx, fy, dir)
        pcall(function() require("src.pokemon.Gen4GameRecords").score(game.save, 24) end)
        game.ugPendingMsg = txt(game, BANK.common, 68)
        B().enter(game, ow, true)
      end)
    end)
  end)
end

-- --------------------------------------------------- the door, in and out --

function M.enterPrompt(game, ow)
  M.prompt(game, txt(game, BANK.common, 41), yesNo(game), function(c)
    if c ~= 1 then return end
    M.prompt(game, txt(game, BANK.common, 37), { txt(game, BANK.common, 38), txt(game, BANK.common, 39) }, function(k)
      if not k then return end
      B().enter(game, ow, k == 2)
    end, { menu = { 16, 13, 15 }, cancel = false })
  end)
end

function M.exitPrompt(game, ow)
  local closed = B().base(game.save).closed
  M.prompt(game, txt(game, BANK.common, closed and 47 or 50), yesNo(game), function(c)
    if c == 1 then B().leave(game, ow) end
  end)
end

-- ------------------------------------------------------------- a list --

-- a ListMenu in a window: opts.win = { x, y, w } tiles, opts.maxDisplay rows,
-- opts.corner = { x, y, w, h, lines = function() -> { {text, dx, dy} } },
-- opts.description(i) for the message box, opts.onPick(i) (nil = cancel),
-- opts.cancelRow: the last row answers as B does
local List = {}
List.__index = List
List.isOpaque = false
function List:uiSize() return 256, 192 end
function M.list(game, rows, opts)
  opts = opts or {}
  local l = setmetatable({ game = game, rows = rows, opts = opts, index = 1, top = 1 }, List)
  -- UndergroundMan_GetStoredCursorPos: a menu opens where it was left
  if opts.key then
    game.ugListPos = game.ugListPos or {}
    l.index = math.max(1, math.min(#rows, game.ugListPos[opts.key] or 1))
  end
  game.stack:push(l)
  return l
end
function List:close(i)
  if self.closed then return end
  self.closed = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.opts.onPick then self.opts.onPick(i) end
end
function List:maxDisplay() return math.min(#self.rows, self.opts.maxDisplay or #self.rows) end
function List:update()
  local input = self.game.input
  local n = #self.rows
  if n == 0 then return self:close(nil) end
  -- ListMenu: no wrap; the window scrolls at its edge
  local was = self.index
  if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1 end
  if input:wasPressed("down") and self.index < n then self.index = self.index + 1 end
  if was ~= self.index then se(self.game, "SEQ_SE_CONFIRM") end
  if self.opts.key then self.game.ugListPos[self.opts.key] = self.index end
  if input:wasPressed("a") then
    se(self.game, "SEQ_SE_CONFIRM")
    if self.opts.cancelRow and self.index == n then return self:close(nil) end
    return self:close(self.index)
  end
  if input:wasPressed("b") then se(self.game, "SEQ_SE_CONFIRM"); return self:close(nil) end
end
function List:draw()
  local n = #self.rows
  local vis = self:maxDisplay()
  if self.index < self.top then self.top = self.index end
  if self.index >= self.top + vis then self.top = self.index - vis + 1 end
  local w = self.opts.win or { 17, 3, 14 }
  win(w[1], w[2], w[3], vis * 2)
  for row = 0, vis - 1 do
    local i = self.top + row
    local r = self.rows[i]
    if not r then break end
    local y = w[2] * 8 + row * 16
    if r.dim then dimInk() else ink() end
    Font.draw(r.label or "?", w[1] * 8 + 8, y)
    Font.popStyle()
    if i == self.index then ink(); cursorAt(w[1] * 8, y); Font.popStyle() end
  end
  -- the scroll arrows (ScrollPrompts) while rows are out of view
  if n > vis then
    local g = love.graphics
    local cx = w[1] * 8 + w[3] * 4
    g.setColor(0.35, 0.35, 0.35, 1)
    if self.top > 1 then g.polygon("fill", cx - 4, w[2] * 8 - 2, cx + 4, w[2] * 8 - 2, cx, w[2] * 8 - 7) end
    if self.top + vis - 1 < n then
      local by = (w[2] + vis * 2) * 8 + 2
      g.polygon("fill", cx - 4, by, cx + 4, by, cx, by + 5)
    end
    g.setColor(1, 1, 1, 1)
  end
  local c = self.opts.corner
  if c then
    win(c[1], c[2], c[3], c[4])
    ink()
    for _, l in ipairs(c.lines()) do Font.draw(l[1], c[1] * 8 + (l[2] or 0), c[2] * 8 + (l[3] or 0)) end
    Font.popStyle()
  end
  local d = self.opts.description and self.opts.description(self.index)
  drawText(d and (pages(d))[1])
end

-- ------------------------------------------------------------- the PC --

local function goodName(game, id) return Pockets.goodName(game, id) end
-- UNDERGROUND_GOOD_DESCRIPTIONS_START + good - 1 (139 the CLOSE row's)
local function goodDescription(game, id) return txt(game, BANK.goods, 139 + id - 1) end

function M.openPC(game, ow)
  se(game, "SEQ_SE_DP_PC_ON")
  local save = game.save
  local ids = { "decorate", "store", "receive", "flags" }
  if B().rank(save) >= 3 then ids[#ids + 1] = "radar" end
  ids[#ids + 1] = "exit"
  local ENTRY = { decorate = 0, store = 1, receive = 2, flags = 3, radar = 4, exit = 5 }
  local rows = {}
  for i, id in ipairs(ids) do rows[i] = { label = txt(game, BANK.pc, ENTRY[id]), id = id } end
  M.list(game, rows, { win = { 17, 3, 14 }, key = "pc",
    description = function(i) return txt(game, BANK.pc, 6 + ENTRY[rows[i].id]) end,
    onPick = function(i)
      local id = i and rows[i].id or "exit"
      if id == "exit" then se(game, "SEQ_SE_DP_PC_LOGOFF") return end
      local back = function() M.openPC(game, ow) end
      if id == "store" then return M.storeGoods(game, back) end
      if id == "receive" then return M.receiveGoods(game, back) end
      if id == "flags" then return M.flagsScreen(game, back) end
      if id == "radar" then return M.radarMenu(game, ow, back) end
      if id == "decorate" then
        if #UG().goodsPC(save) == 0 then return M.say(game, txt(game, BANK.pc, 60), back) end
        if not B().base(save).closed then return M.say(game, txt(game, BANK.pc, 56), back) end
        se(game, "SEQ_SE_DP_PC_LOGIN")
        return M.decorate(game, ow, function()
          W().setFlag(save, B().FLAG_DECORATED)
          back()
        end)
      end
    end })
end

-- the goods lists of STORE / RECEIVE (UndergroundMenu_InitGoodsMenu)
local function goodsList(game, list, label, dimOf, onPick, key)
  local rows = {}
  for i, g in ipairs(list) do rows[i] = { label = goodName(game, g), dim = dimOf and dimOf(i) } end
  rows[#rows + 1] = { label = txt(game, BANK.goods, 0) }
  M.list(game, rows, { win = { 19, 3, 12 }, maxDisplay = 6, cancelRow = true, key = key,
    corner = { 1, 1, 7, 4, lines = function()
      local out, y = {}, 1
      for l in (label .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = { l, 1, y }; y = y + 16 end
      return out
    end },
    description = function(i)
      if i > #list then return txt(game, BANK.goods, 139) end
      return goodDescription(game, list[i])
    end,
    onPick = onPick })
end

function M.storeGoods(game, back)
  local save = game.save
  local bag = W().goodsBag(save)
  goodsList(game, bag, txt(game, BANK.pc, 28), nil, function(i)
    if not i or i > #bag then return back() end
    local g = bag[i]
    if not UG().addGoodToPC(save, g) then return M.say(game, txt(game, BANK.pc, 38), function() M.storeGoods(game, back) end) end
    table.remove(bag, i)
    M.say(game, txt(game, BANK.pc, 37, { [2] = goodName(game, g) }), function() M.storeGoods(game, back) end)
  end, "store")
end

function M.receiveGoods(game, back)
  local save = game.save
  local pc = UG().goodsPC(save)
  local shown = B().displayed(save)
  goodsList(game, pc, txt(game, BANK.pc, 32), function(i) return shown[i] ~= nil end, function(i)
    if not i or i > #pc then return back() end
    local again = function() M.receiveGoods(game, back) end
    if shown[i] then return M.say(game, txt(game, BANK.pc, 55), again) end
    local g = pc[i]
    if not W().addGoodBag(save, g) then return M.say(game, txt(game, BANK.pc, 39), again) end
    table.remove(pc, i)
    B().pcRemoved(save, i)
    M.say(game, txt(game, BANK.pc, 36, { [2] = goodName(game, g) }), again)
  end, "receive")
end

-- CHECK FLAGS / the trainer case: the window (4, 2, 24, 19) (records.c 376)
local Card = {}
Card.__index = Card
Card.isOpaque = false
function Card:uiSize() return 256, 192 end
function Card:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    if self.game.stack:top() == self then self.game.stack:pop() end
    if self.onDone then self.onDone() end
  end
end
function Card:draw()
  win(4, 2, 24, 19)
  ink()
  for _, l in ipairs(self.lines) do
    if l.num then numberAt(l.num, l[1], l[2], l.width) else Font.draw(l[3], l[1], l[2]) end
  end
  Font.popStyle()
end
local function card(game, lines, onDone)
  se(game, "SEQ_SE_DP_WIN_OPEN")
  game.stack:push(setmetatable({ game = game, lines = lines, onDone = onDone }, Card))
end
M.CARD_X, M.CARD_Y = 4 * 8, 2 * 8   -- the window's pixel origin

-- records.c 317-365: ENTRIES_BASE_X 2, rows of FLAGS_SCREEN_LINE_HEIGHT 17,
-- the numbers FLAGS_SCREEN_NUM_X_OFFSET 100 in
function M.flagsScreen(game, onDone)
  local save = game.save
  local X, Y = M.CARD_X + 2, M.CARD_Y + 1
  local lines = {
    { X, Y, txt(game, BANK.pc, 12, { [1] = playerName(game) }) },
    { X, Y + 17, txt(game, BANK.pc, 13) },
    { X + 100, Y + 17, num = B().record(save).capturedFlags or 0, width = 6 },
    { X, Y + 17 * 3, txt(game, BANK.pc, 15) },
  }
  for k = 0, 4 do
    lines[#lines + 1] = { X, Y + 17 * (4 + k), txt(game, BANK.pc, 51) }
    lines[#lines + 1] = { X + 100, Y + 17 * (4 + k), txt(game, BANK.pc, 52) }
  end
  card(game, lines, onDone)
end

-- the Underground menu's TRAINER row (records.c 125-174: NAME at (2, 1), the
-- name at 57, ID at 132, its number at 148; BASE FLAG at (2, 17), the rank at
-- 57; seven rows from y 39, 16 apart, numbers at 148)
function M.trainerCard(game, onDone)
  local save = game.save
  local r = B().record(save)
  local tid = tonumber(save.player and (save.player.id or save.player.trainerId)) or 0
  local X, Y = M.CARD_X + 2, M.CARD_Y
  local lines = {
    { X, Y + 1, txt(game, BANK.records, 0) },
    { X + 55, Y + 1, playerName(game) },
    { X + 130, Y + 1, txt(game, BANK.records, 2) },
    { X + 146, Y + 1, ("%05d"):format(tid % 65536) },
    { X, Y + 17, txt(game, BANK.records, 1) },
    { X + 55, Y + 17, txt(game, BANK.records, 20 + B().rank(save)) },
  }
  local vals = { B().recordValue(save, "score"), r.peopleMet, r.giftsGiven, r.capturedFlags, r.spheresDug, r.fossilsDug, r.trapHits }
  for k = 0, 6 do
    lines[#lines + 1] = { X, Y + 39 + k * 16, txt(game, BANK.records, 6 + k) }
    lines[#lines + 1] = { X + 146, Y + 39 + k * 16, num = math.min(999999, vals[k + 1] or 0), width = 6 }
  end
  card(game, lines, onDone)
end

-- ----------------------------------------------------------- decorating --

local Deco = {}
Deco.__index = Deco
Deco.isOpaque = false
function Deco:uiSize() return 256, 192 end
Deco.FADE = 12          -- engine ticks a fade takes (StartScreenFade .., 6, 1)
Deco.CAMERA_X, Deco.CAMERA_Z = 15, 17

function M.decorate(game, ow, onDone)
  local d = setmetatable({ game = game, ow = ow, onDone = onDone, mode = "menu", index = 1, t = 0,
                           fade = "out", fadeT = 0 }, Deco)
  game.stack:push(d)
  return d
end

-- UndergroundPC_MoveCamera: the view on the room's (15, 17), the player hidden
function Deco:camera(on)
  local ow = self.ow
  if not (ow and ow.player) then return end
  if on then
    local cx, cz = B().ROOM_X + Deco.CAMERA_X, B().ROOM_Z + Deco.CAMERA_Z
    self.prevCamera = ow.gen4Camera
    ow.gen4Camera = { cellX = cx, cellY = cz, px = cx * 16, py = cz * 16, hidden = true, ugDecoCamera = true }
    ow.player.hidden = true
  else
    if ow.gen4Camera and ow.gen4Camera.ugDecoCamera then ow.gen4Camera = self.prevCamera end
    ow.player.hidden = nil
  end
  if ow.followCamera then pcall(ow.followCamera, ow) end
end

function Deco:limit() return B().GOOD_LIMIT[B().rank(self.game.save)] end

function Deco:say(text) self.msg = text end

function Deco:setHeld(h)
  self.held = h
  self.ow.ugBaseHeld = h
  if h then h.v = (h.v or 0) + 1; h.live = h.live or {} end
  self.ow.ugBaseKey = nil
end

function Deco:finish()
  self:setHeld(nil)
  self.mode = "leaving"
  self.fade, self.fadeT = "out", 0
end

local OPTIONS = { "decorate", "putaway", "move", "cancel" }

-- DecorationGoodsMenu (decoration_menu.c 334-404)
function Deco:openGoodsList()
  local game, save = self.game, self.game.save
  local pc = UG().goodsPC(save)
  if #pc == 0 then return self:say(txt(game, BANK.deco, 19)) end
  if #B().base(save).goods + 1 > self:limit() then return self:say(txt(game, BANK.deco, 20)) end
  local shown = B().displayed(save)
  local rows = {}
  for i, g in ipairs(pc) do rows[i] = { label = goodName(game, g), dim = shown[i] ~= nil } end
  rows[#rows + 1] = { label = txt(game, BANK.goods, 277) }
  M.list(game, rows, { win = { 19, 3, 12 }, maxDisplay = 7, cancelRow = true,
    corner = { 1, 1, 8, 4, lines = function()
      return { { txt(game, BANK.deco, 9), 0, 0 },
               { txt(game, BANK.deco, 10, { [0] = ("%2d"):format(#B().base(save).goods),
                                             [1] = ("%2d"):format(self:limit()) }), 0, 16 } }
    end },
    description = function(i)
      if i > #pc then return txt(game, BANK.goods, 278) end
      return goodDescription(game, pc[i])
    end,
    onPick = function(i)
      if not i or i > #pc then return end
      if shown[i] then return self:say(txt(game, BANK.deco, 21)) end
      self.mode = "place"
      self:setHeld({ good = pc[i], pcSlot = i, x = B().DEFAULT_GOOD_X, z = B().DEFAULT_GOOD_Z })
    end })
end

function Deco:moveHeld(dx, dz)
  local h = self.held
  if not h then return end
  local good = h.good or B().BOULDER
  if B().inside(h.x + dx, h.z + dz, good) then
    h.x, h.z = h.x + dx, h.z + dz
    h.v = h.v + 1
    self.ow.ugBaseKey = nil
  end
end

function Deco:cursorObject() return B().objectAt(self.game.save, self.cx, self.cz) end

function Deco:pressA()
  local game, save = self.game, self.game.save
  if self.mode == "menu" then
    local id = OPTIONS[self.index]
    if id == "cancel" then return self:finish() end
    if id == "decorate" then return self:openGoodsList() end
    self.mode = (id == "putaway") and "putaway" or "pick"
    self.cx, self.cz = B().DEFAULT_GOOD_X, B().DEFAULT_GOOD_Z
    self:setHeld({ blink = nil, v = 0 })
    return
  end
  if self.mode == "place" then
    local h = self.held
    if B().canPlace(save, h.good, h.x, h.z) then
      B().placeGood(save, h.pcSlot, h.x, h.z)
      se(game, "SEQ_SE_DP_BOWA")
      self:say(txt(game, BANK.deco, 11, { [0] = goodName(game, h.good) }))
      self:setHeld(nil)
      self.mode = "menu"
    else
      se(game, "SEQ_SE_DP_WALL_HIT2")
      self:say(txt(game, BANK.deco, 12))
    end
    return
  end
  if self.mode == "moving" then
    local h = self.held
    if B().canPlace(save, h.ref.good, h.x, h.z, h.ref) then
      h.ref.x, h.ref.z = h.x, h.z
      B().bump(save)
      se(game, "SEQ_SE_DP_BOWA")
      self:setHeld(nil)
      self.mode = "menu"
    else
      se(game, "SEQ_SE_DP_WALL_HIT2")
      self:say(txt(game, BANK.deco, 12))
    end
    return
  end
  local o = self:cursorObject()
  if not o then return end
  if self.mode == "putaway" then
    if o.kind == "pc" then return self:say(txt(game, BANK.deco, 22)) end
    if o.kind == "boulder" then
      local unremovable = B().UNREMOVABLE[B().rank(save)]
      local count = #B().base(save).boulders
      if unremovable >= 16 then return self:say(txt(game, BANK.deco, 15)) end
      if count - 1 < unremovable then return self:say(txt(game, BANK.deco, 18)) end
      B().removeObject(save, o)
      se(game, "SEQ_SE_DP_F017")
      local left = count - 1 - unremovable
      return self:say(txt(game, BANK.deco, 14) .. "\f" .. txt(game, BANK.deco, left == 1 and 17 or 25, { [0] = tostring(left) }))
    end
    B().removeObject(save, o)
    se(game, "SEQ_SE_DP_BOX02")
    self.ow.ugBaseKey = nil
    return self:say(txt(game, BANK.deco, 13, { [0] = goodName(game, o.good) }))
  end
  if self.mode == "pick" then
    if o.kind == "pc" then return self:say(txt(game, BANK.deco, 23)) end
    if o.kind == "boulder" then return self:say(txt(game, BANK.deco, 16)) end
    se(game, "SEQ_SE_DP_BOX02")
    self.mode = "moving"
    self:setHeld({ ref = o.ref, good = o.good, x = o.x, z = o.z })
  end
end

-- the fades either side (pc.c 618-655)
function Deco:updateFade()
  self.fadeT = self.fadeT + 1
  if self.fadeT < Deco.FADE then return true end
  if self.fade == "out" then
    self:camera(self.mode ~= "leaving")
    self.fade, self.fadeT = "in", 0
    return true
  end
  -- faded in
  self.fade = nil
  if self.mode == "leaving" then
    if self.game.stack:top() == self then self.game.stack:pop() end
    if self.onDone then self.onDone() end
    return true
  end
  return false
end

function Deco:update()
  local input = self.game.input
  self.t = self.t + 1
  -- DecorateCursor_Show only while PUT AWAY / MOVE GOODS pick a good
  if self.mode ~= "putaway" and self.mode ~= "pick" then B().setCursor(self.ow, nil) end
  if self.fade then
    if self:updateFade() then return end
  end
  if self.msg then
    local pg = pages(self.msg)
    if input:wasPressed("a") or input:wasPressed("b") then
      if #pg > 1 then self.msg = table.concat(pg, "\f", 2) else self.msg = nil end
    end
    return
  end
  -- blinking (every 4 frames held, every 8 under the cursor)
  local h = self.held
  if h and h.live then
    local period = (self.mode == "place" or self.mode == "moving") and 4 or 8
    h.live.hidden = (math.floor(self.t / period) % 2 == 1) or nil
  end
  if self.mode == "menu" then
    -- ListMenu: no wrap
    local was = self.index
    if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1 end
    if input:wasPressed("down") and self.index < #OPTIONS then self.index = self.index + 1 end
    if was ~= self.index then se(self.game, "SEQ_SE_CONFIRM") end
    if input:wasPressed("a") then se(self.game, "SEQ_SE_CONFIRM"); return self:pressA() end
    if input:wasPressed("b") then se(self.game, "SEQ_SE_CONFIRM"); return self:finish() end
    return
  end
  local dx, dz = 0, 0
  if input:wasPressed("left") then dx = -1 elseif input:wasPressed("right") then dx = 1 end
  if input:wasPressed("up") then dz = -1 elseif input:wasPressed("down") then dz = 1 end
  if self.mode == "place" or self.mode == "moving" then
    if dx ~= 0 or dz ~= 0 then self:moveHeld(dx, dz) end
  else
    if dx ~= 0 or dz ~= 0 then
      local nx, nz = self.cx + dx, self.cz + dz
      local P = B().PLAY
      if nx >= P.x0 and nx <= P.x1 and nz >= P.z0 and nz <= P.z1 then
        self.cx, self.cz = nx, nz
        se(self.game, "SEQ_SE_DP_BUTTON3")
      end
    end
    local o = self:cursorObject()
    if self.held then
      local blink = o and o.ref or nil
      if self.held.blink ~= blink then self.held.blink = blink; self.held.v = self.held.v + 1; self.ow.ugBaseKey = nil end
    end
    -- the cursor model (DecorateCursor); a sparkle on a cache without it
    B().setCursor(self.ow, self.cx, self.cz)
    local ground = self.ow.map and self.ow.map.renderer and self.ow.map.renderer.gen4Ground
    if not B().cursorModel(ground) and self.t % 16 == 0 and self.ow.startSparkle then
      self.ow:startSparkle(B().ROOM_X + self.cx, B().ROOM_Z + self.cz)
    end
  end
  if input:wasPressed("a") then return self:pressA() end
  if input:wasPressed("b") then
    se(self.game, "SEQ_SE_CONFIRM")
    self:setHeld(nil)
    self.mode = "menu"
  end
end

function Deco:draw()
  local g = love.graphics
  if self.mode == "menu" and not (self.fade and self.fade == "out" and self.fadeT == 0) then
    -- DecorationMenu_InitMenu: (19, 3, 12, 8) and "DECOR" in (1, 1, 7, 2)
    win(19, 3, 12, #OPTIONS * 2)
    win(1, 1, 7, 2)
    ink()
    Font.draw(txt(self.game, BANK.deco, 0), 8, 8)
    for i = 1, #OPTIONS do
      local y = 3 * 8 + (i - 1) * 16
      Font.draw(txt(self.game, BANK.deco, i), 19 * 8 + 8, y)
      if i == self.index then cursorAt(19 * 8, y) end
    end
    Font.popStyle()
    drawText((pages(self.msg or txt(self.game, BANK.deco, 4 + self.index)))[1])
  else
    drawText(self.msg and (pages(self.msg))[1])
  end
  if self.fade then
    local k = math.min(1, self.fadeT / Deco.FADE)
    local a = (self.fade == "out") and k or (1 - k)
    g.setColor(0, 0, 0, a)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

-- --------------------------------------------------------------- radars --

-- UndergroundPC_InitRadarMenu: (17, 3, 14, 8), TREASURE / SPHERE / TRAP
-- SEARCH / CANCEL with descriptions 44-47
function M.radarMenu(game, ow, back)
  local rows = {}
  for k = 0, 3 do rows[k + 1] = { label = txt(game, BANK.pc, 40 + k) } end
  M.list(game, rows, { win = { 17, 3, 14 }, cancelRow = true, key = "radar",
    description = function(i) return txt(game, BANK.pc, 44 + i - 1) end,
    onPick = function(i)
      if not i then return back() end
      local again = function() M.radarMenu(game, ow, back) end
      local kind = ({ "treasure", "sphere", "trap" })[i]
      local closed = B().base(game.save).closed
      if closed then return M.say(game, txt(game, BANK.pc, 57 + i - 1), again) end
      M.runRadar(game, ow, kind, txt(game, BANK.pc, 48 + i - 1), again)
    end })
end

-- UG_PC_MENU_STATE_START_*_RADAR .. EXIT_RADAR_ON_BUTTON_PRESS: the radar on
-- the top screen, the field at brightness -6, the boot message; A or B after
-- it: the plain radar again (none in a closed base), back to the radar menu
function M.runRadar(game, ow, kind, text, onDone)
  Top().setRadar(game, kind)
  return M.prompt(game, text, nil, function()
    Top().setRadar(game, B().base(game.save).closed and "none" or "normal")
    if onDone then onDone() end
  end, {
    under = function()
      local g = love.graphics
      if Top().onOtherScreen(game) then
        g.setColor(0, 0, 0, 6 / 16)
        g.rectangle("fill", 0, 0, 256, 192)
        g.setColor(1, 1, 1, 1)
      else
        -- one screen: the top screen is shown in the field's place
        Top().draw(game)
      end
    end,
  })
end

-- the points a PC radar knows: { {x, z} } (kept for the checks)
function M.radarPoints(save, kind)
  local out = {}
  if kind == "treasure" then
    for i, s in ipairs((save.underground or {}).spots or {}) do
      if (i - 1) % 3 == 0 then out[#out + 1] = { s.x, s.z } end
    end
  elseif kind == "sphere" then
    for _, b in ipairs(W().buried(save)) do out[#out + 1] = { b.x, b.z } end
  else
    for _, t in ipairs(W().placedTraps(save)) do out[#out + 1] = { t.x, t.z } end
    for _, t in ipairs(W().spawnedTraps(save)) do out[#out + 1] = { t.x, t.z } end
  end
  return out
end

return M
