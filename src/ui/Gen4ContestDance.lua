-- PLATINUM'S DANCE COMPETITION, played (overlay017, ov17_0223DAD0.c's states;
-- the rules are src/pokemon/Gen4ContestDance.lua). In the cartridge's art
-- (src/import/Gen4ContestArt.lua) and bank 206's words.
--
-- THE TOP SCREEN: the stage for the song's measure layout (contest_bg 13 with
-- map 14 or 15); the lead at (128, 96) and the three behind at x 48 / 128 /
-- 208, y 40, each on its shadow, the player marked by the arrow; the lead lit
-- in the first half and the back row in the second. The bar along the bottom
-- (row 19): the playhead running across a measure, the beat ball bouncing 10
-- px a step at y 144, a note for each move at margin + its half step, in the
-- dancer's row (y 176 / 168 / 176 / 184 by slot) -- yours in your colour, the
-- others' in theirs, and the lead's moves ghosted into your row for the
-- second half when you follow. A move tints the stage its colour (JUMP red,
-- FRONT blue, LEFT green, RIGHT yellow; a miss black) and the dancer hops,
-- steps or sways: fully when leading, 40% behind, the measure's last move
-- twice as far. Each verdict rises over its dancer in its bubble.
--
-- THE BOTTOM SCREEN, when there is one: the dance pad (contest_bg 18, maps 17
-- and 28) with JUMP / FRONT / LEFT / RIGHT -- "UP" for Diglett and Dugtrio,
-- who cannot jump -- dimmed while you cannot move; between rounds the
-- contest's own logo screen.
--
-- THE BUTTONS (ov17_022492DC): UP or X is JUMP, DOWN or B is FRONT, LEFT or Y
-- is LEFT, RIGHT or A is RIGHT.
--
-- Not drawn: the 3D particles and fireworks. The
-- sound effects wait on the contest's SE table.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")
local Art = require("src.ui.Gen4ContestArt")
local Contest = require("src.pokemon.Gen4Contest")
local Dance = require("src.pokemon.Gen4ContestDance")

local UI = {}
UI.__index = UI

UI.POS = { { 128, 96, 1.0 }, { 48, 40, 0.75 }, { 128, 40, 0.75 }, { 208, 40, 0.75 } }
UI.BUBBLE = { { 128, 88 }, { 48, 32 }, { 128, 32 }, { 208, 32 } }
UI.NOTE_Y = { 176, 168, 176, 184 }
UI.TINT = { { 1, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 }, { 1, 1, 0.3 } }
UI.KEYS = { up = Dance.JUMP, x = Dance.JUMP, down = Dance.FRONT, b = Dance.FRONT,
            left = Dance.LEFT, y = Dance.LEFT, right = Dance.RIGHT, a = Dance.RIGHT }

function UI.new(game, c, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, c = c, onDone = opts.onDone,
    d = Dance.new(c), frame = -1, acc = 0, mode = "intro", events = {}, notes = {}, bubbles = {},
    anims = {}, sprites = {} }, UI)
  local practice = Contest.isPractice(c.competition)
  local nick = self:name(0)
  T.buffer(game, nick)
  self:say(T.resolve(game.data, Dance.BANK, practice and 20 or 8, game))
  return self
end

-- a cartridge line split into its pages, as the contest screen's are
local function pages(text)
  local out = {}
  for page in (tostring(text or "") .. "\f"):gmatch("([^\v\f\r]*)[\v\f\r]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then out[#out + 1] = page end
  end
  return out
end

function UI:say(text)
  self.pages = pages(text)
  self.message = self.pages[1]
end

-- A / B: the next page; true when the last has gone
function UI:nextPage()
  if self.pages and #self.pages > 1 then
    table.remove(self.pages, 1)
    self.message = self.pages[1]
    return false
  end
  self.pages, self.message = nil, nil
  return true
end

function UI:name(id)
  local e = self.c.contestants[id]
  if e.mon and e.mon.nickname then return e.mon.nickname end
  local def = self.data.pokemon and self.data.pokemon[e.mon and e.mon.species]
  return def and def.name or "?"
end

function UI:slotOf(id, r)
  for k, who in ipairs(Dance.order(r)) do if who == id then return k end end
  return 1
end

-- the round now, from the clock: r, and the measure (nil before it starts)
function UI:where(f)
  local d = self.d
  for r = 3, 0, -1 do
    local s = Dance.roundStart(d, r)
    if f >= s then
      local m = math.floor((f - s) / d.measure)
      if m < d.song.measures then return r, m end
      return r, nil
    end
  end
  return 0, nil
end

function UI:startDance()
  self.mode, self.frame, self.message = "dance", 0, nil
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.play then pcall(Music.play, self.data, self.d.song.seq) end
end

function UI:instruction(r)
  if Dance.leader(r) == 0 then
    T.buffer(self.game, tostring(self.d.moves))
    return T.resolve(self.data, Dance.BANK, 9, self.game)
  end
  return T.resolve(self.data, Dance.BANK, 10, self.game)
end

-- a move made: the verdict's bubble, the dancer's step, the stage's tint
function UI:moved(move, isLead, slot, ms, row)
  local f = self.frame
  self.bubbles[#self.bubbles + 1] = { slot = slot, quality = move.quality, from = f }
  local last = (ms.counts[move.id] or 0) >= self.d.moves
  self.anims[move.id] = { dir = move.dir, from = f, amp = (isLead and 1 or 0.4) * (last and 2 or 1) }
  if isLead then self.tint = { colour = UI.TINT[move.dir], from = f } end
  if move.quality == Dance.MISS and not isLead then self.tint = { colour = { 0, 0, 0 }, from = f } end
  self.notes[#self.notes + 1] = { grid = move.grid, dir = move.dir, row = row, own = move.id == 0, ms = ms }
end

function UI:beginMeasure(r, m)
  local d = self.d
  local ms = Dance.newMeasure(d, r, m)
  self.ms, self.notes, self.events = ms, {}, {}
  self.cool = { [0] = -999, -999, -999, -999 }
  if ms.lead ~= 0 then
    for _, e in ipairs(Dance.npcLead(d, ms.lead)) do
      self.events[#self.events + 1] = { t = e.t, dir = e.dir, id = ms.lead, lead = true }
    end
  end
  self.copiesPlanned = false
  self.instructionText = nil
end

-- the second half: the computer dancers' copies of what the lead did
function UI:planCopies()
  local ms, d = self.ms, self.d
  self.copiesPlanned = true
  for _, id in ipairs(Dance.order(ms.round)) do
    if id ~= ms.lead and id ~= 0 then
      for _, e in ipairs(Dance.npcCopy(d, id, ms.leadMoves)) do
        self.events[#self.events + 1] = { t = e.t, dir = e.dir, id = id }
      end
    end
  end
end

function UI:act(id, t, dir, isLead)
  local ms, d = self.ms, self.d
  local r = ms.round
  local slot = self:slotOf(id, r)
  local move
  if isLead then
    if not Dance.canLead(d, t, ms.counts[id]) then return end
    move = Dance.leadMove(d, ms, t, dir)
  else
    if not Dance.canCopy(d, t, ms.counts[id]) then return end
    move = Dance.copyMove(d, ms, id, t, dir)
  end
  self.cool[id] = t
  self:moved(move, isLead, slot, ms, slot)
end

function UI:tick()
  local input = self.game.input
  if self.mode == "intro" then
    if (input:wasPressed("a") or input:wasPressed("b")) and self:nextPage() then self:startDance() end
    return
  end
  if self.mode == "end" then
    if self.message and (input:wasPressed("a") or input:wasPressed("b")) then
      if self:nextPage() then return self:finish() end
      return
    end
    self.endFrames = self.endFrames + 1
    if self.endFrames == 60 then
      if Contest.isPractice(self.c.competition) then return self:finish() end
      local id = Dance.leading(self.d)
      local e = self.c.contestants[id]
      T.buffer(self.game, e.trainer or "", self:name(id))
      self:say(T.resolve(self.data, Dance.BANK, 18, self.game))
    end
    return
  end
  self.frame = self.frame + 1
  local f, d = self.frame, self.d
  if f >= Dance.finish(d) + 30 then
    Dance.record(d)
    self.mode, self.endFrames, self.ms = "end", 0, nil
    local ok, Music = pcall(require, "src.core.Music")
    if ok and Music.stop then pcall(Music.stop) end
    return
  end
  local r, m = self:where(f)
  self.round = r
  if m and (not self.ms or self.ms.round ~= r or self.ms.measure ~= m) then self:beginMeasure(r, m) end
  if not m then
    self.instructionText = self.instructionText or self:instruction(math.min(3, f < Dance.roundStart(d, 0) and 0 or r + 1))
  end
  local ms = self.ms
  if not (ms and m) then return end
  local t = f - ms.start
  if t >= d.half and not self.copiesPlanned then self:planCopies() end
  -- the computer dancers, on their frames
  for i = #self.events, 1, -1 do
    local e = self.events[i]
    if t >= e.t then
      table.remove(self.events, i)
      self:act(e.id, t, e.dir, e.lead)
    end
  end
  -- the player
  if t - self.cool[0] > Dance.cooldown(d) then
    for key, dir in pairs(UI.KEYS) do
      if input:wasPressed(key) then
        self:act(0, t, dir, ms.lead == 0)
        self.press = { dir = dir, from = self.frame }
        break
      end
    end
  end
end

function UI:finish()
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone() end
end

function UI:update(dt)
  self.acc = self.acc + (dt or 1 / 60) * 60
  while self.acc >= 1 do
    self.acc = self.acc - 1
    self:tick()
    if self.done then return end
  end
end

-- ------------------------------------------------------------------ draw --

function UI:monSprite(id)
  if self.sprites[id] == nil then
    local mon = self.c.contestants[id].mon
    local path = require("src.pokemon.Sprites").path(self.data, mon.species, "front", { mon = mon, kind = "contest" })
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    self.sprites[id] = ok and img or false
  end
  return self.sprites[id] or nil
end

-- ov17_0224B5F0's moves, 12 frames each
function UI:offset(id)
  local a = self.anims[id]
  if not a then return 0, 0, 0 end
  local k = (self.frame - a.from) / 12
  if k < 0 or k >= 1 then return 0, 0, 0 end
  local s = math.sin(k * math.pi) * a.amp
  if a.dir == Dance.JUMP then return 0, -16 * s, 0
  elseif a.dir == Dance.FRONT then return 0, 16 * s, 0
  elseif a.dir == Dance.LEFT then return -16 * s, 0, -math.rad(5) * s
  else return 16 * s, 0, math.rad(5) * s end
end

function UI:drawDancers(r)
  local g = love.graphics
  local secondHalf = self.ms and (self.frame - self.ms.start) >= self.d.half
  local order = Dance.order(r)
  for slot = 4, 1, -1 do
    local id = order[slot]
    local p = UI.POS[slot]
    Art.draw(self.game, "dance_shadow", p[1], p[2] + 28 * p[3])
    local img = self:monSprite(id)
    if img then
      local lit = (slot == 1) ~= (secondHalf and true or false)
      if self.mode ~= "dance" or not self.ms then lit = true end
      local v = lit and 1 or 0.55
      g.setColor(v, v, v, 1)
      local dx, dy, rot = self:offset(id)
      local w, h = img:getDimensions()
      g.draw(img, p[1] + dx, p[2] + dy, rot, p[3], p[3], w / 2, h / 2)
      g.setColor(1, 1, 1, 1)
      if id == 0 then Art.draw(self.game, "dance_arrow", p[1], p[2] - 40 * p[3]) end
    end
  end
end

function UI:drawBar()
  local d, ms = self.d, self.ms
  local L = Dance.LAYOUTS[d.layout]
  local barW = L.barTiles * 8
  local margin = (256 - barW) / 2
  local per = barW / (2 * d.steps)
  if ms then
    local t = self.frame - ms.start
    local x = margin + barW * math.max(0, math.min(1, t / d.measure))
    Art.draw(self.game, "dance_playhead", x, 176)
    local beat = math.abs(math.sin(math.pi * t / d.step))
    Art.draw(self.game, "dance_ball", x, 144 - 10 * beat)
    -- the lead's moves ghosted into your row, to copy
    local mine = self:slotOf(0, ms.round)
    if ms.lead ~= 0 and t >= d.half then
      for _, l in ipairs(ms.leadMoves) do
        Art.draw(self.game, ("dance_note_%d_2"):format(l.dir), margin + per * (l.grid + d.steps) + per / 2, UI.NOTE_Y[mine])
      end
    end
  end
  for _, n in ipairs(self.notes) do
    Art.draw(self.game, ("dance_note_%d_%d"):format(n.dir, n.own and 0 or 1),
      margin + per * n.grid + per / 2, UI.NOTE_Y[n.row])
  end
end

function UI:drawBubbles()
  local words = { [0] = 5, 6, 7 }
  for i = #self.bubbles, 1, -1 do
    local b = self.bubbles[i]
    local age = self.frame - b.from
    if age > 20 then table.remove(self.bubbles, i)
    else
      local p = UI.BUBBLE[b.slot]
      local y = p[2] - 4 * math.min(5, age)
      Art.draw(self.game, "dance_judge_" .. b.quality, p[1], y)
      local word = T.resolve(self.data, Dance.BANK, words[b.quality], self.game) or ""
      Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 1, 1, 1 } })
      Font.draw(word, p[1] - math.floor(Font.width(word) / 2), y - 6)
      Font.popStyle()
    end
  end
end

function UI:drawMessage(text, instruction)
  if not text then return end
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  if instruction then
    -- Window[1]: tile (2, 11), 27 x 2
    Font.drawBox(1, 10, 29, 4)
    Font.draw(text, 16, 88)
  else
    -- Window[0]: tile (2, 19), 27 x 4
    Font.drawDialogueBox(1, 18, 29, 6)
    local y = 152
    for l in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
  end
  Font.popStyle()
end

function UI:drawPad()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if not ((mode == "display" or mode == "inset") and not SS.stowed(self.game)) then return end
  SS.draw(self.game, function()
    local g = love.graphics
    local ms = self.ms
    if self.mode ~= "dance" or not ms then
      Art.draw(self.game, "sub_logo_" .. (self.c.type or 0), 0, 0)
      return
    end
    -- the pressed button's frames (ov17_02249DA0): its tiles pushed in, then
    -- half back, then at rest, three frames each, its label down 16, up 4,
    -- then home
    local pressed, frame, drop = nil, nil, 0
    if self.press then
      local k = self.frame - self.press.from
      if k < 3 then frame, drop = 0, 16 elseif k < 6 then frame, drop = 1, 12 elseif k < 9 then frame = 2 end
      if frame then pressed = self.press.dir end
    end
    if not (pressed and Art.draw(self.game, ("dance_pad_%d_%d"):format(pressed, frame), 0, 0)) then
      Art.draw(self.game, "dance_pad", 0, 0)
    end
    local species = self.c.contestants[0].mon and self.c.contestants[0].mon.species
    local cantJump = species == 50 or species == 51
    local labels = { { cantJump and 1 or 0, 128, 24 }, { 2, 128, 120 }, { 3, 48, 64 }, { 4, 208, 64 } }
    Font.pushStyle({ text = { 1, 1, 1 }, shadow = { 0.3, 0.3, 0.3 } })
    for move, l in ipairs(labels) do
      local s = T.resolve(self.data, Dance.BANK, l[1], self.game) or ""
      Font.draw(s, l[2] - math.floor(Font.width(s) / 2), l[3] + (move == pressed and drop or 0))
    end
    Font.popStyle()
    -- dimmed while you cannot move (PaletteData_Blend at 6/16)
    local t = self.frame - ms.start
    local d = self.d
    local open = t - self.cool[0] > Dance.cooldown(d)
        and ((ms.lead == 0 and Dance.canLead(d, t, ms.counts[0])) or (ms.lead ~= 0 and Dance.canCopy(d, t, ms.counts[0])))
    if not open then
      g.setColor(0, 0, 0, 6 / 16)
      g.rectangle("fill", 0, 0, 256, 192)
      g.setColor(1, 1, 1, 1)
    end
  end)
end

function UI:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  Art.draw(self.game, "dance_stage_" .. self.d.layout, 0, 0)
  if self.tint then
    local age = self.frame - self.tint.from
    if age < 16 then
      local c = self.tint.colour
      g.setColor(c[1], c[2], c[3], 7 / 16 * (1 - age / 16))
      g.rectangle("fill", 0, 0, 256, 192)
      g.setColor(1, 1, 1, 1)
    end
  end
  self:drawDancers(self.round or 0)
  if self.mode == "dance" then
    self:drawBar()
    self:drawBubbles()
    if not (self.ms and self.frame < self.ms.start + self.d.measure) or self.frame < Dance.roundStart(self.d, 0) then
      self:drawMessage(self.instructionText, true)
    end
  end
  self:drawMessage(self.message)
  self:drawPad()
end

return UI
