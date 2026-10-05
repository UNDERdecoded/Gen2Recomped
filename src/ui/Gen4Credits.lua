-- PLATINUM'S END CREDITS (src/cutscenes/end_credits), in the cartridge's art
-- (ending.narc via src/import/Gen4EndingArt.lua) and staff roll (bank 548,
-- overlay 99's table, cache module `gen4_ending`).
--
-- On the DS the credits run with the screens swapped: the bike ride, the
-- memories and Twinleaf are the BOTTOM screen, the sky the top. Here the
-- bottom screen's picture is the main one and the top screen's goes to the
-- second screen when there is one. Frames are 60 a second; `framesElapsed`
-- is the cartridge's clock:
--
--   BIKE_MORNING  to 1830   morning backgrounds, the player cycling at
--                           (192, 160) with the scarf; Drifloon from 1590
--   MEMORIES_1    to 4815   memories 0-6, ~400 frames each, 32 out, 30 black
--   BIKE_DAY      to 6000   day backgrounds; Wingull
--   MEMORIES_2    to ~7000  memories 7-9, ~300 frames each
--   BIKE_NIGHT    to 7980   night backgrounds; Magnezone from 7440
--   TWINLEAF                four pictures cross-faded, then black
--   FIN                     "FIN" centred at y 80; to frame 10080, or A /
--                           START; a 45-frame fade
--
-- THE ROLL: two managers, the bottom one starting at y -240 and the top one
-- at -448, 1 pixel a frame. A line is printed when the bottom edge reaches its
-- y, at x 32 or centred, and erased when the top passes 16 below it; the
-- bottom 24 pixels of the bottom screen and the top 24 of the top hide it.
-- {COLOR n} picks text.NCLR's pair 2n+1 / 2n+2. START skips to FIN only when
-- the game had been cleared before (main.c:195).
--
-- Not drawn: the 3D trees, lampposts and the bike's eye-blink tiles.
-- Music: SEQ_BLD_ENDING (1186).

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local Credits = {}
Credits.__index = Credits
Credits.isOpaque = true
Credits.BANK = 548
Credits.MUSIC = 1186
Credits.END = 10080

-- memories' BG scroll (common.c:44-68): the picture is drawn at -offset
local SCROLL = { { 0, 0 }, { -32, -48 }, { -16, -30 }, { -42, -2 }, { -8, -20 },
                 { -50, -16 }, { -40, -34 }, { -16, -1 }, { -44, -15 }, { -30, -30 } }

function Credits:uiSize() return 256, 192 end
function Credits:wantsFillScale() return true end

function Credits.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, onDone = opts.onDone, images = {}, frame = 0, acc = 0,
    canSkip = opts.canSkip }, Credits)
  local player = game.save and game.save.player or {}
  self.who = player.gender == 1 and "dawn" or "lucas"
  self.roll = (game.data.gen4_ending or {}).roll or {}
  self.colours = (game.data.gen4_ending or {}).textColours or {}
  self:buildTimeline()
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.play then pcall(Music.play, game.data, Credits.MUSIC) end
  return self
end

function Credits:buildTimeline()
  local tl = {}
  tl[#tl + 1] = { kind = "bike", time = "morning", from = 0, to = 1830 }
  local t = 1830
  local each1 = math.floor((4815 - 1830) / 7)
  for i = 0, 6 do tl[#tl + 1] = { kind = "memory", n = i, from = t, to = t + each1 }; t = t + each1 end
  tl[#tl + 1] = { kind = "bike", time = "day", from = 4815, to = 6000 }
  t = 6000
  for i = 7, 9 do tl[#tl + 1] = { kind = "memory", n = i, from = t, to = t + 330 }; t = t + 330 end
  tl[#tl + 1] = { kind = "bike", time = "night", from = t, to = 7980 }
  tl[#tl + 1] = { kind = "twinleaf", from = 7980, to = 7980 + 4 * 43 + 60 }
  tl[#tl + 1] = { kind = "fin", from = 7980 + 4 * 43 + 60, to = Credits.END }
  self.timeline = tl
end

function Credits:scene()
  for _, s in ipairs(self.timeline) do
    if self.frame >= s.from and self.frame < s.to then return s end
  end
  return self.timeline[#self.timeline]
end

function Credits:art(key)
  local index = self.data and self.data.gen4_ending_art
  local rec = index and index[key]
  if not rec then return nil end
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil, rec
end

function Credits:sprite(key, x, y)
  local img, rec = self:art(key)
  if img then love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0)) end
end

function Credits:finish()
  if self.finished then return end
  self.finished = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Credits:update(dt)
  local input = self.game.input
  local s = self:scene()
  if input then
    if s.kind == "fin" and self.frame > s.from + 30 and (input:wasPressed("a") or input:wasPressed("start")) then
      self.fadeOut = self.fadeOut or 0
    elseif s.kind ~= "fin" and self.canSkip and input:wasPressed("start") then
      self.frame = self.timeline[#self.timeline].from
    end
  end
  self.acc = self.acc + (dt or 1 / 60) * 60
  while self.acc >= 1 do
    self.acc = self.acc - 1
    self.frame = self.frame + 1
    if self.fadeOut then
      self.fadeOut = self.fadeOut + 1
      if self.fadeOut >= 45 then return self:finish() end
    elseif self.frame >= Credits.END then
      self.fadeOut = 0
    end
  end
end

-- {COLOR n} runs -> segments, then drawn in their pairs
local function segments(text)
  local out, colour, at = {}, 0, 1
  for pre, n, nxt in text:gmatch("()%{COLOR (%d+)%}()") do
    if pre > at then out[#out + 1] = { text = text:sub(at, pre - 1), colour = colour } end
    colour, at = tonumber(n), nxt
  end
  if at <= #text then out[#out + 1] = { text = text:sub(at), colour = colour } end
  return out
end

function Credits:pair(n)
  local ink = self.colours[n * 2 + 1] or { 230, 230, 230 }
  local sh = self.colours[n * 2 + 2] or { 66, 66, 66 }
  return { text = { ink[1] / 255, ink[2] / 255, ink[3] / 255 }, shadow = { sh[1] / 255, sh[2] / 255, sh[3] / 255 } }
end

-- the roll for one screen: `topY` is that manager's position this frame
function Credits:drawRoll(topY, clipTop, clipBottom)
  local g = love.graphics
  g.setScissor(0, clipTop, 256, clipBottom - clipTop)
  for _, row in ipairs(self.roll) do
    if row.message ~= 236 then
      local y = row.y - topY
      if y > -16 and y < 192 then
        local raw = self.data.text and self.data.text[T.label(Credits.BANK, row.message)]
        if type(raw) == "string" then
          local parts = segments(raw)
          local plain = ""
          for _, p in ipairs(parts) do plain = plain .. p.text end
          local x = row.centred and math.floor((256 - Font.width(plain)) / 2) or 32
          for _, p in ipairs(parts) do
            Font.pushStyle(self:pair(p.colour))
            Font.draw(p.text, x, y)
            Font.popStyle()
            x = x + Font.width(p.text)
          end
        end
      end
    end
  end
  g.setScissor()
end

function Credits:drawBike(s)
  local g = love.graphics
  local img = self:art("credits_" .. s.time .. "_bottom")
  if img then
    local scroll = (self.frame * 64 / 4096) % 256
    g.draw(img, -scroll, 0)
    g.draw(img, 256 - scroll, 0)
  end
  local bob = math.floor(self.frame / 8) % 2
  self:sprite("credits_bike_" .. self.who, 192, 160 + bob)
  self:sprite("credits_scarf_" .. self.who, 192, 160 + bob)
end

function Credits:drawTop(s)
  local g = love.graphics
  local time = s.kind == "bike" and s.time or (self.frame < 4815 and "morning" or self.frame < 7000 and "day" or "night")
  g.setColor(1, 1, 1, 1)
  if s.kind ~= "twinleaf" and s.kind ~= "fin" then
    local img = self:art("credits_" .. time .. "_top")
    if img then
      local scroll = (self.frame * 64 / 4096) % 256
      g.draw(img, -scroll, 0)
      g.draw(img, 256 - scroll, 0)
    end
    if time == "morning" and self.frame >= 1590 then
      local k = (self.frame - 1590) * 0.4
      self:sprite("credits_object_0", 300 - k, 60 + math.sin(self.frame / 30) * 6)
    elseif time == "night" and self.frame >= 7440 then
      self:sprite("credits_object_2", 280 - (self.frame - 7440) * 0.5, 50)
    end
    self:drawRoll(self.frame - 448, 24, 192)
  end
end

function Credits:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local s = self:scene()
  local alpha = 1
  if s.kind == "bike" then
    self:drawBike(s)
    alpha = math.min(1, (self.frame - s.from) / 24, (s.to - self.frame) / 24)
  elseif s.kind == "memory" then
    local img = self:art(("credits_memory_%s_%d"):format(self.who, s.n))
    local held = s.to - s.from - 30
    local t = self.frame - s.from
    if img and t < held then
      local off = SCROLL[s.n + 1]
      g.draw(img, -off[1], -off[2])
      alpha = math.min(1, t / 32, (held - t) / 32)
    else
      alpha = 0
    end
  elseif s.kind == "twinleaf" then
    local t = self.frame - s.from
    local n = math.min(4, math.floor(t / 43) + 1)
    local k = math.min(1, (t % 43) / 16)
    local prev = n > 1 and self:art(("credits_twinleaf_%s_%d"):format(self.who, n - 1))
    local cur = self:art(("credits_twinleaf_%s_%d"):format(self.who, n))
    if prev then g.draw(prev, 0, 0) end
    if cur then g.setColor(1, 1, 1, prev and k or 1); g.draw(cur, 0, 0); g.setColor(1, 1, 1, 1) end
    if t > 4 * 43 then alpha = math.max(0, 1 - (t - 4 * 43) / 60) end
  elseif s.kind == "fin" then
    local text = self.data.text and self.data.text[T.label(Credits.BANK, 236)] or "FIN"
    Font.pushStyle(self:pair(0))
    local w = Font.width(text) + 3 * (#text - 1)
    local x = math.floor((256 - w) / 2)
    for i = 1, #text do
      local ch = text:sub(i, i)
      Font.draw(ch, x, 80)
      x = x + Font.width(ch) + 3
    end
    Font.popStyle()
    alpha = math.min(1, (self.frame - s.from) / 30)
  end
  if s.kind ~= "twinleaf" and s.kind ~= "fin" then self:drawRoll(self.frame - 240, 0, 168) end
  if self.fadeOut then alpha = math.min(alpha, 1 - self.fadeOut / 45) end
  if alpha < 1 then
    g.setColor(0, 0, 0, 1 - math.max(0, alpha))
    g.rectangle("fill", 0, 0, 256, 192)
  end
  g.setColor(1, 1, 1, 1)
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function()
      g.setColor(0, 0, 0, 1)
      g.rectangle("fill", 0, 0, 256, 192)
      g.setColor(1, 1, 1, 1)
      self:drawTop(s)
    end)
  end
end

return Credits
