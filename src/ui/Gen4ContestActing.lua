-- THE ACTING COMPETITION, PLAYED: the player's move and judge each turn, the
-- NPCs' own (Gen4ContestActing.chooseNpc), the performances and the end of
-- turn, told in the cartridge's lines -- bank 204 (contest_text) for the
-- running commentary, bank 211 for what each contest effect did, bank 210
-- for the move menu's two-line effect descriptions.
--
-- Drawn in the cartridge's own art (src/import/Gen4ContestArt.lua): the top
-- screen is BG3's audience and stage, the three judges at their podiums with
-- their Voltage stars and the head judge's heart, the performer, BG2's four
-- score panels with their hearts, and BG1's message window; the bottom screen
-- is overlay017's four pages -- the logo between choices, the four move
-- buttons in their types' colours, the three judges and EXIT. A cache
-- without the art falls back to plain drawing.
--
-- Controls: the d-pad moves over the 2x2 move buttons, A confirms; LEFT/RIGHT
-- pick a judge, DOWN reaches EXIT, A confirms, B (or EXIT) goes back to the
-- moves; A advances the messages.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")
local A = require("src.pokemon.Gen4ContestActing")

local Act = {}
Act.__index = Act

-- Contest_Text_TimeFor<Type>ActingCompetition, by contest type
local INTRO = { [0] = 40, 39, 35, 37, 38 }
local BEGIN_PRACTICE, NEXT_LOWEST, JUDGING_OVER = 71, 68, 69
local CHOOSE_JUDGE, WHICH_MOVE, LAST_MOVE = 0, 1, 2
local PERFORMED, ALREADY = 3, 4
local IMPRESSED = { 9, 6, 7, 8 }        -- one, two, three, four for the judge
local VOLT_UP, VOLT_DOWN, PRETTY_EXCITED, GOING_WILD = 11, 17, 24, 25

local function moveId(m) if type(m) == "table" then return tonumber(m.id or m.move) or 0 end return tonumber(m) or 0 end

function Act.new(game, contest, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, c = contest, data = game.data, queue = {}, cursor = 1, judge = 0 }, Act)
  self.s = A.new(contest, game.data, { hadDance = opts.hadDance })
  self.onDone = opts.onDone
  local practice = require("src.pokemon.Gen4Contest").isPractice(contest.competition)
  self:say(204, practice and BEGIN_PRACTICE or INTRO[contest.type])
  self.after = function() self:startTurn() end
  return self
end

function Act:name(id)
  local e = self.c.contestants[id]
  if e and e.mon and e.mon.nickname then return e.mon.nickname end
  local def = self.data.pokemon and self.data.pokemon[e and e.mon and e.mon.species]
  return def and def.name or "?"
end

function Act:judgeName(j)
  local rec = self.data.gen4_contest
  local idx = self.c.judges and self.c.judges[j + 1]
  local judge = rec and rec.judges and idx and rec.judges[idx]
  return judge and T.resolve(self.data, 207, judge.nameId) or ("Judge " .. (j + 1))
end

function Act:moveName(id)
  local m = self.data.moves and self.data.moves[id]
  return m and m.name or "-"
end

-- a cartridge line with its {STRVAR_1 kind slot pad} slots filled, split
-- into its pages
function Act:say(bank, index, slots)
  local raw = self.data.text and self.data.text[T.label(bank, index)]
  if type(raw) ~= "string" then return end
  local values = {}
  for slot = 0, 4 do values[slot + 1] = slots and slots[slot] or "" end
  T.buffer(self.game, (table.unpack or unpack)(values))
  local text = T.resolve(self.data, bank, index, self.game) or raw
  for page in (text .. "\f"):gmatch("([^\v\f]*)[\v\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then self.queue[#self.queue + 1] = page end
  end
end

-- the slot values a bank 211 effect line reads, by the kinds of its tokens
function Act:sayEffect(ev)
  local rec = self.data.gen4_contest.effects[ev.effect]
  local msg = rec and rec.msgs[ev.variant]
  if not msg or msg == 0xFFFF then return end
  local raw = self.data.text and self.data.text[T.label(A.EFFECT_TEXT, msg)]
  if type(raw) ~= "string" then return end
  local slots = {}
  for kind, slot in raw:gmatch("{STRVAR_1 (%d+),? (%d+)") do
    kind, slot = tonumber(kind), tonumber(slot)
    if kind == 1 then
      local who = slot == 0 and (ev.a or ev.id) or ev.b
      slots[slot] = who and self:name(who) or ""
    elseif kind == 6 then slots[slot] = self:moveName(ev.move or 0)
    elseif kind == 50 then slots[slot] = tostring(ev.num or 0) end
  end
  self:say(A.EFFECT_TEXT, msg, slots)
end

function Act:sayEvents(list)
  local c = self.c
  for _, ev in ipairs(list) do
    if ev.kind == "performed" then
      self:say(204, PERFORMED, { [0] = self:name(ev.id), self:judgeName(ev.judge), self:moveName(ev.move) })
      if ev.already then self:say(204, ALREADY) end
    elseif ev.kind == "effect" then
      self:sayEffect(ev)
    elseif ev.kind == "voltage" then
      local j = self:judgeName(ev.judge)
      if ev.delta > 0 then
        self:say(204, VOLT_UP + ev.mtype, { [0] = j })
        if math.floor(ev.level / 10) == 4 then self:say(204, PRETTY_EXCITED)
        elseif ev.level >= A.MAX_VOLTAGE then self:say(204, GOING_WILD, { [0] = tostring(math.floor(ev.bonus / 10)) }) end
      else
        self:say(204, VOLT_DOWN + ev.mtype, { [0] = j })
      end
    elseif ev.kind == "judge" then
      local slots = { [0] = self:judgeName(ev.judge) }
      for k, id in ipairs(ev.ids) do slots[k] = self:name(id) end
      self:say(204, IMPRESSED[ev.count], slots)
    elseif ev.kind == "lowestFirst" then
      self:say(204, NEXT_LOWEST)
    end
  end
  return c
end

function Act:playerMoves()
  local mon = self.c.contestants[0].mon or {}
  local out = {}
  for k = 1, 4 do
    local m = mon.moves and mon.moves[k]
    out[k] = moveId(m)
  end
  return out
end

function Act:startTurn()
  self.mode = "move"
  self.cursor = 1
  local moves = self:playerMoves()
  while self.cursor < 4 and not A.canUse(self.s, 0, moves[self.cursor]) do self.cursor = self.cursor + 1 end
  self.prompt = nil
  local last = self.s.turn == A.TURNS - 1
  local raw = self.data.text and self.data.text[T.label(204, last and LAST_MOVE or WHICH_MOVE)]
  if raw then
    T.buffer(self.game, tostring(self.s.turn + 1))
    self.prompt = T.resolve(self.data, 204, last and LAST_MOVE or WHICH_MOVE, self.game)
  end
end

function Act:runTurn()
  local s, c = self.s, self.c
  local choices = { [0] = { move = self.chosenMove, judge = self.judge } }
  for id = 1, 3 do
    local e = c.contestants[id]
    local moves = {}
    for k = 1, 4 do moves[k] = moveId(e.mon.moves[k]) end
    local mv, j = A.chooseNpc(s, id, moves, e.opponent and e.opponent.unk14 or 0, self.judge)
    choices[id] = { move = mv, judge = j }
  end
  A.beginTurn(s, choices)
  self.mode = "show"
  self.pos = 0
  self:nextPerformance()
end

function Act:nextPerformance()
  local s = self.s
  if self.pos < 4 then
    self.performer = s.order[self.pos + 1]
    local ev = A.perform(s, self.pos)
    self.pos = self.pos + 1
    self:sayEvents(ev)
    self.after = function() self:nextPerformance() end
    return
  end
  self.performer = nil
  self:sayEvents(A.endTurn(s))
  if A.done(s) then
    self:say(204, JUDGING_OVER)
    self.after = function() self:finish() end
  else
    self.after = function() self:startTurn() end
  end
end

function Act:finish()
  for id = 0, 3 do self.c.scores[id].acting = self.s.totals[id] end
  self.mode = "done"
  if self.onDone then self.onDone() end
end

function Act:update()
  local input = self.game.input
  if #self.queue > 0 then
    if input:wasPressed("a") or input:wasPressed("b") then table.remove(self.queue, 1) end
    if #self.queue == 0 and self.after then
      local f = self.after
      self.after = nil
      f()
    end
    return
  end
  if self.after then local f = self.after; self.after = nil; return f() end
  if self.mode == "move" then
    -- the four buttons are a 2x2 grid (Unk_ov17_022532D0)
    local moves = self:playerMoves()
    local c = self.cursor - 1
    if input:wasPressed("up") or input:wasPressed("down") then c = (c + 2) % 4 end
    if input:wasPressed("left") or input:wasPressed("right") then c = c - c % 2 + (1 - c % 2) end
    self.cursor = c + 1
    if input:wasPressed("a") and A.canUse(self.s, 0, moves[self.cursor]) then
      self.chosenMove = moves[self.cursor]
      self.mode = "judge"
    end
  elseif self.mode == "judge" then
    -- three judges over EXIT (Unk_ov17_022532A8); EXIT goes back to the moves
    if self.judge < 3 then self.lastJudge = self.judge end
    if input:wasPressed("left") and self.judge < 3 then self.judge = (self.judge + 2) % 3 end
    if input:wasPressed("right") and self.judge < 3 then self.judge = (self.judge + 1) % 3 end
    if input:wasPressed("down") then self.judge = 3 end
    if input:wasPressed("up") and self.judge == 3 then self.judge = self.lastJudge or 0 end
    local a, b = input:wasPressed("a"), input:wasPressed("b")
    if b or (a and self.judge == 3) then
      self.judge = self.lastJudge or 0
      self.mode = "move"
      return
    end
    if a then self:runTurn() end
  end
end

local Art = require("src.ui.Gen4ContestArt")
local PANEL_SLOTS = require("src.import.Gen4ContestArt").PANEL_SLOTS

local function hearts(points)
  local n = math.floor(math.abs(points) / 10)
  return (points < 0 and "-" or "") .. tostring(n)
end

-- ov17_02241720 / ov17_022418A4 (the seats) and Unk_ov17_022536D8 (the stars)
local JUDGE_X = { [0] = 96, 128, 160 }
local STAR_X = { [0] = 88, 120, 152 }

-- the main screen, as ov17_0223BBA8 builds it
function Act:drawStage()
  local g, game, s = love.graphics, self.game, self.s
  g.setColor(1, 1, 1, 1)
  Art.drawRegion(game, "acting_stage", 0, 0, 256, 192, 0, 0)
  -- the judges at their podiums, their Voltage, and the head judge's heart
  for k = 0, 2 do
    Art.draw(game, "podium_" .. k, JUDGE_X[k], 32)
    Art.draw(game, "judge_" .. k, JUDGE_X[k], 40)
    for i = 0, math.floor(s.voltage[k] / 10) - 1 do Art.draw(game, "voltage_star", STAR_X[k] + i * 5, 12) end
  end
  Art.draw(game, "head_heart", JUDGE_X[A.HEAD_JUDGE], 56)
  -- the performer, at (256 - 40, 104 + 8) (ov17_02241524)
  if self.performer then
    local img = self:monSprite(self.performer)
    if img then
      local w, h = img:getDimensions()
      g.draw(img, 216, 112, 0, 1, 1, w / 2, h / 2)
    end
  end
  -- BG1, the message window, under BG2 (ov17_0223BB14 gives BG2 priority 0)
  Art.drawRegion(game, "acting_window", 0, 144, 256, 48, 0, 144)
  -- the four score panels in this turn's order (BG2, ov17_02241428), each
  -- with its names (ov17_02242FE8) and up to 24 hearts, six to a row, the
  -- colour climbing every six (ov17_02241F34)
  for pos = 0, 3 do
    local id = s.order[pos + 1]
    local y = pos * 48
    Art.draw(game, "acting_panel_" .. PANEL_SLOTS[id], 0, y)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
    Font.draw(self:name(id), 1, y + 4)
    Font.draw(self.c.contestants[id].trainer or "", 1, y + 20)
    Font.popStyle()
    local n = math.min(24, math.max(0, math.floor(s.totals[id] / 10)))
    for slot = 0, 5 do
      if slot < n then
        local top = slot + 6 * math.floor((n - 1 - slot) / 6)
        Art.draw(game, "small_heart_" .. math.floor(top / 6), 5 + slot * 8, 43 + y)
      end
    end
  end
end

function Act:monSprite(id)
  self.sprites = self.sprites or {}
  if self.sprites[id] == nil then
    local mon = self.c.contestants[id].mon
    local path = require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon, kind = "contest" })
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    self.sprites[id] = ok and img or false
  end
  return self.sprites[id] or nil
end

local function centred(text, cx, y)
  text = text or ""
  Font.draw(text, cx - math.floor(Font.width(text) / 2), y)
end

-- the bottom screen (ov17_0223F7E4's pages)
function Act:drawBottom(page)
  local g, game = love.graphics, self.game
  g.setColor(1, 1, 1, 1)
  if page == "logo" then
    Art.draw(game, "sub_logo_" .. self.c.type, 0, 0)
    -- ov17_0223FBD4: the rank and the contest's name on the two plates
    local C = require("src.pokemon.Gen4Contest")
    Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.4, 0.4, 0.4 } })
    centred(C.isPractice(self.c.competition) and T.resolve(self.data, 204, 50) or T.resolve(self.data, 204, 46 + self.c.rank), 128, 119)
    centred(T.resolve(self.data, 204, 41 + self.c.type), 128, 151)
    Font.popStyle()
    return
  end
  Art.draw(game, "sub_hearts", 0, 0)
  if page == "moves" then
    local moves = self:playerMoves()
    for i = 0, 3 do
      local col, row = i % 2, math.floor(i / 2)
      local qx, qy = col * 128, row * 96
      local mv = moves[i + 1]
      local def = mv ~= 0 and self.data.moves and self.data.moves[mv]
      -- ov17_02240424: the button in its move's type colours, or greyed
      local key = (def and A.canUse(self.s, 0, mv)) and ("sub_moves_" .. (tonumber(def.contestType) or 0)) or "sub_moves_off"
      Art.drawRegion(game, key, qx, qy, 128, 96, qx, qy)
      if def then
        local eff = self.data.gen4_contest.effects[tonumber(def.contestEffect) or 0]
        -- Unk_ov17_02253278 / 02253314 (the text), 02253334 (the hearts)
        Font.pushStyle({ text = { 0.2, 0.2, 0.2 }, shadow = { 0.85, 0.85, 0.85 } })
        Font.draw(def.name or "", 19 + qx, 24 + qy)
        if eff then
          Font.draw(T.resolve(self.data, A.EFFECT_DESC, eff.line1) or "", 19 + qx, 56 + qy)
          Font.draw(T.resolve(self.data, A.EFFECT_DESC, eff.line2) or "", 19 + qx, 72 + qy)
        end
        Font.popStyle()
        local appeal = eff and eff.appeal or 0
        for k = 0, math.floor(math.abs(appeal) / 10) - 1 do
          Art.draw(game, appeal >= 0 and "sub_heart" or "sub_heart_minus", 63 + qx + 8 * k, 52 + qy)
        end
      end
      if self.cursor == i + 1 then
        g.setLineWidth(2)
        g.setColor(0.15, 0.15, 0.15, 1)
        g.rectangle("line", qx + 7, qy + 7, 114, 82)
        g.setColor(1, 1, 1, 1)
        g.rectangle("line", qx + 9, qy + 9, 110, 78)
        g.setLineWidth(1)
      end
    end
  elseif page == "judges" then
    Art.draw(game, "sub_judges", 0, 0)
    -- ov17_0223FF38: the names on the three buttons, EXIT, the head mark
    Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.35, 0.35, 0.35 } })
    local centres = { [0] = 40, 128, 216 }
    for j = 0, 2 do centred(self:judgeName(j), centres[j], 64) end
    centred(T.resolve(self.data, 204, 53) or "EXIT", 128, 160)
    Font.popStyle()
    Art.draw(game, "sub_head_mark", 40 + 88 * A.HEAD_JUDGE, 96)
    -- the touch rectangles (Unk_ov17_022532A8) as the cursor
    local rects = { [0] = { 0, 8, 80, 120 }, { 88, 8, 80, 120 }, { 176, 8, 80, 120 }, { 0, 136, 256, 56 } }
    local r = rects[self.judge]
    if r then
      g.setLineWidth(2)
      g.setColor(0.15, 0.15, 0.15, 1)
      g.rectangle("line", r[1] + 1, r[2] + 1, r[3] - 2, r[4] - 2)
      g.setColor(1, 1, 1, 1)
      g.rectangle("line", r[1] + 3, r[2] + 3, r[3] - 6, r[4] - 6)
      g.setLineWidth(1)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Act:message()
  local msg = self.queue[1]
  if not msg and self.mode == "move" then msg = self.prompt
  elseif not msg and self.mode == "judge" then msg = T.resolve(self.data, 204, CHOOSE_JUDGE) end
  return msg
end

-- the drawing for a cache without the contest art
function Act:drawPlain()
  local g = love.graphics
  local s = self.s
  for j = 0, 2 do
    local x = 8 + j * 82
    g.setColor(1, 1, 1, 1)
    Font.draw(self:judgeName(j) .. (j == A.HEAD_JUDGE and "*" or ""), x, 4)
    for k = 1, 5 do
      if s.voltage[j] >= k * 10 then g.setColor(1, 0.85, 0.2, 1) else g.setColor(0.35, 0.3, 0.45, 1) end
      g.rectangle("fill", x + (k - 1) * 12, 20, 10, 6)
    end
    if self.mode == "judge" and self.judge == j and #self.queue == 0 then
      g.setColor(1, 1, 1, 1)
      g.rectangle("line", x - 2, 2, 78, 28)
    end
  end
  for pos = 1, 4 do
    local id = s.order[pos]
    local y = 36 + (pos - 1) * 18
    g.setColor(id == 0 and 0.6 or 1, 1, id == 0 and 0.6 or 1, 1)
    Font.draw(("%d %s"):format(pos, self:name(id)), 8, y)
    g.setColor(1, 0.45, 0.6, 1)
    Font.draw(("<3 %s"):format(hearts(s.totals[id])), 176, y)
  end
  g.setColor(1, 1, 1, 1)
  if #self.queue == 0 and self.mode == "move" then
    local moves = self:playerMoves()
    for k = 1, 4 do
      local usable = A.canUse(s, 0, moves[k])
      g.setColor(usable and 1 or 0.5, usable and 1 or 0.5, usable and 1 or 0.5, 1)
      Font.draw((k == self.cursor and "> " or "  ") .. self:moveName(moves[k]), 8, 102 + (k - 1) * 13)
    end
  end
  local msg = self:message()
  if msg then
    g.setColor(0, 0, 0, 0.75)
    g.rectangle("fill", 0, 156, 256, 36)
    g.setColor(1, 1, 1, 1)
    local y = 158
    for l in (tostring(msg) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 8, y); y = y + 16 end
  end
  g.setColor(1, 1, 1, 1)
end

-- Where the bottom screen goes is the player's choice (src/ui/SecondScreen):
-- on a real second surface (a second panel, or the inset) it is always
-- there, the logo between choices; where it would cover the stage (swap, or
-- no second screen at all) it comes up only while a move or judge is chosen.
function Act:draw()
  local g = love.graphics
  if not Art.available(self.game) then return self:drawPlain() end
  self:drawStage()
  local msg = self:message()
  if msg then
    -- the window's text area: tile (11, 19), 20 x 4 (ov17_0223B140 Window_Add)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
    local y = 152
    for l in (tostring(msg) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 88, y); y = y + 16 end
    Font.popStyle()
  end
  local choosing = #self.queue == 0 and (self.mode == "move" or self.mode == "judge")
  local page = choosing and (self.mode == "move" and "moves" or "judges") or "logo"
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if ok and (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function() self:drawBottom(page) end)
  elseif choosing then
    if ok and mode == "swap" then SS.draw(self.game, function() self:drawBottom(page) end)
    else self:drawBottom(page) end
  end
  g.setColor(1, 1, 1, 1)
end

return Act
