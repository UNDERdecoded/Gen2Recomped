-- PLATINUM'S HALL OF FAME (src/cutscenes/hall_of_fame.c), in the cartridge's
-- art (dendou_demo.narc via src/import/Gen4EndingArt.lua) and bank 351's words.
--
-- THE STAGE is BG3 (`hof_stage`); BG2 (`hof_overlay`) covers everything
-- outside a moving WINDOW, which is what reveals each Pokemon; the text is
-- BG1 on top. Every movement is linear over N frames (HallOfFameMovement),
-- positions are sprite centres, at 60 frames a second:
--
--   PER POKEMON (eggs skipped), side = index % 2:
--     slide in 28: sprite x 192->72 (even) / 64->184 (odd) at y 96, window
--       y 32..160, 96 wide, its left -96->24 / 352->136
--     wait 20; the cry; "Welcome to the / Hall of Fame!" at y 16 / 32
--     wait 20; nickname at 48, "{species} <gender> Lv.n" at 64
--     wait 20; "OT/name" at 96, the met line at 112 / 128
--     (each line centred in a 136-pixel column from x 120 even / 0 odd)
--     wait 30; out 28: the text scrolls up 256 while the window's top goes
--       32 -> -160; wait 30
--   THE PARTY: BG3 becomes `hof_party`; the player slides up x 128, y 232->104
--     in 28 as a window 88..168, 144 high, comes down from -144 to 24; wait
--     20; the window opens to the full width in 12 (y 24..168); "League
--     Champion! Congratulations!" centred at 4, "{player} ID: n Time: h:mm"
--     at 172; wait 20; the party slides in from -40 / 296 to x 160, 96, 192,
--     64, 224, 32 at y 96, 96, 88, 88, 80, 80, 8 frames each, 5 apart; wait
--     20; confetti; A or B to leave, the window closing to y 96 over 24.
--
-- The six spotlights and the confetti are BG0's 3D on the cartridge; here
-- they are drawn flat with the cartridge's angles, speeds and colours.
-- Music: SEQ_BLD_EV_DENDO2 (1171).

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local HoF = {}
HoF.__index = HoF
HoF.isOpaque = true
HoF.BANK = 351
HoF.MUSIC = 1171

function HoF:uiSize() return 256, 192 end
function HoF:wantsFillScale() return true end

local function lerp(a, b, k) return a + (b - a) * k end

function HoF.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, data = game.data, save = game.save, onDone = opts.onDone,
    images = {}, sprites = {}, lines = {}, scroll = 0, stage = "hof_stage", confetti = nil }, HoF)
  self.party = {}
  local Party = require("src.pokemon.Party")
  for _, mon in ipairs(opts.party or game.save.party or {}) do
    if not Party.isEgg(mon) then self.party[#self.party + 1] = mon end
  end
  self.window = { x0 = -96, y0 = 32, x1 = 0, y1 = 160 }
  -- the six spotlights (hall_of_fame.c spotlight setup)
  self.lights = {}
  local starts, offs = { 20, 60, 40, 140, 120, 160 }, { -0.714, -0.429, -0.143, 0.143, 0.429, 0.714 }
  local speeds = { 0.75, 0.6875, 0.625, 0.75, 0.6875, 0.625 }
  for i = 1, 6 do self.lights[i] = { angle = starts[i], speed = speeds[i], x = 128 + offs[i] * 128, dir = 1 } end
  local ok, Music = pcall(require, "src.core.Music")
  if ok and Music.play then pcall(Music.play, game.data, HoF.MUSIC) end
  self.co = coroutine.create(function() self:script() end)
  self.acc = 0
  return self
end

-- --------------------------------------------------------------- helpers --
function HoF:art(key)
  local index = self.data and self.data.gen4_ending_art
  local rec = index and index[key]
  if not rec then return nil end
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil
end

function HoF:image(path)
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.images[path] = ok and img or false
  end
  return self.images[path] or nil
end

function HoF:line(n, values)
  T.buffer(self.game, (table.unpack or unpack)(values or {}))
  return T.resolve(self.data, HoF.BANK, n, self.game) or ""
end

local function wait(n) for _ = 1, n do coroutine.yield() end end

-- a linear move over n frames (HallOfFameMovement), `set(k)` each frame
local function move(n, set)
  for f = 1, n do set(f / n); coroutine.yield() end
end

function HoF:monName(mon)
  local def = self.data.pokemon and self.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or "?", def and def.name or "?"
end

-- the met line's priority order (hall_of_fame.c)
function HoF:metLine(mon)
  local player = self.save.player or {}
  local otName = mon.otName or mon.ot
  local game = mon.metGame or mon.originGame
  if game == "ruby" or game == "sapphire" or game == "emerald" then return self:line(9) end
  if game == "firered" or game == "leafgreen" then return self:line(8) end
  if game == "colosseum" or game == "xd" then return self:line(10) end
  if mon.fateful then return self:line(11) end
  if (mon.otId and player.id and mon.otId ~= player.id) or (otName and player.name and otName ~= player.name) then
    return self:line(7)
  end
  -- the place name the area sign would show: the map's header, its row in
  -- the popup table, and that row's bank 433 entry
  local function place(loc)
    local map = type(loc) == "string" and (self.data.maps or {})[loc]
    local rows = (self.data.gen4_area_popup or {}).headers or {}
    local row = map and rows[tonumber(map.header) or -1]
    local name = row and self.data.text and self.data.text[("TEXT_B0433_%05d"):format(tonumber(row.text) or 0)]
    if type(name) == "string" then return (name:gsub("[\n\r\f\v]", " ")) end
    return map and (map.name or map.displayName) or tostring(loc or "")
  end
  if mon.hatched then return self:line(6, { place(mon.metLocation) }) end
  return self:line(5, { place(mon.metLocation) })
end

function HoF:setColumn(even, rows)
  -- each line centred in a 136-pixel column from x 120 (even) or 0 (odd)
  self.column = even and 120 or 0
  for _, r in ipairs(rows) do self.lines[#self.lines + 1] = r end
end

-- ----------------------------------------------------------------- script --
function HoF:script()
  local Sprites = require("src.pokemon.Sprites")
  for i, mon in ipairs(self.party) do
    local even = (i - 1) % 2 == 0
    local img = self:image(Sprites.path(self.data, mon.species, "front", { mon = mon }))
    local s = { img = img, x = even and 192 or 64, y = 96 }
    self.sprites = { s }
    self.lines, self.scroll = {}, 0
    local wx0 = even and -96 or 352
    local wx1 = even and 24 or 136
    move(28, function(k)
      s.x = lerp(even and 192 or 64, even and 72 or 184, k)
      local x = lerp(wx0, wx1, k)
      self.window = { x0 = x, y0 = 32, x1 = x + 96, y1 = 160 }
    end)
    wait(20)
    pcall(require("src.core.Sound").playCry, self.data, mon.species)
    local welcome = self:line(0)
    local w1, w2 = welcome:match("([^\n]*)\n?(.*)")
    self:setColumn(even, { { text = w1, y = 16 }, { text = w2, y = 32 } })
    wait(20)
    local nick, species = self:monName(mon)
    local gender = mon.gender == "male" and 1 or mon.gender == "female" and 2 or 3
    self:setColumn(even, { { text = nick, y = 48 },
      { text = self:line(gender, { species, tostring(mon.level or 1) }), y = 64 } })
    wait(20)
    local met = self:metLine(mon)
    local m1, m2 = met:match("([^\n]*)\n?(.*)")
    self:setColumn(even, { { text = self:line(4, { mon.otName or (self.save.player or {}).name or "" }), y = 96 },
      { text = m1, y = 112 }, { text = m2, y = 128 } })
    wait(30)
    local top = self.window
    move(28, function(k)
      self.scroll = 256 * k
      self.window = { x0 = top.x0, y0 = lerp(32, -160, k), x1 = top.x1, y1 = lerp(160, -32, k) }
    end)
    self.lines, self.sprites = {}, {}
    wait(30)
  end
  -- THE PARTY AND THE PLAYER
  self.stage, self.scroll, self.lines = "hof_party", 0, {}
  local gender = (self.save.player or {}).gender == 1 and 1 or 0
  local tr = ((self.data.gen4_trainer_sprites or {}).classes or {})[gender]
  local player = { img = self:image(tr and tr.path), x = 128, y = 232, front = true }
  self.sprites = { player }
  move(28, function(k)
    player.y = lerp(232, 104, k)
    self.window = { x0 = 88, y0 = lerp(-144, 24, k), x1 = 168, y1 = lerp(0, 168, k) }
  end)
  wait(20)
  move(12, function(k) self.window = { x0 = lerp(88, 0, k), y0 = 24, x1 = lerp(168, 256, k), y1 = 168 } end)
  local p = self.save.player or {}
  local secs = math.floor(tonumber(self.save.playTime or self.save.playSeconds or 0) or 0)
  self.column = nil
  self.lines = {
    { text = self:line(12), y = 4, full = true },
    { text = self:line(13, { p.name or "", ("%05d"):format((tonumber(p.id) or 0) % 65536),
        tostring(math.floor(secs / 3600)), ("%02d"):format(math.floor(secs / 60) % 60) }), y = 172, full = true },
  }
  wait(20)
  local endX, ys = { 160, 96, 192, 64, 224, 32 }, { 96, 96, 88, 88, 80, 80 }
  local Sprites2 = require("src.pokemon.Sprites")
  local slides = {}
  for i, mon in ipairs(self.party) do
    local even = (i - 1) % 2 == 0
    local s = { img = self:image(Sprites2.path(self.data, mon.species, "front", { mon = mon })), x = even and -40 or 296,
                y = ys[i], from = even and -40 or 296, to = endX[i], start = (i - 1) * 5 }
    table.insert(self.sprites, 1, s)
    slides[#slides + 1] = s
  end
  local frames = (#slides - 1) * 5 + 8
  for f = 1, frames do
    for _, s in ipairs(slides) do
      local k = math.max(0, math.min(1, (f - s.start) / 8))
      s.x = lerp(s.from, s.to, k)
    end
    coroutine.yield()
  end
  wait(20)
  self:startConfetti()
  self.waitingForButton = true
  while self.waitingForButton do coroutine.yield() end
  move(24, function(k) self.window = { x0 = 0, y0 = lerp(24, 96, k), x1 = 256, y1 = lerp(168, 96, k) } end)
  self.done = true
end

function HoF:startConfetti()
  self.confetti = {}
  local colours = { { 1, 0.3, 0.3 }, { 1, 0.8, 0.2 }, { 0.3, 1, 0.4 }, { 0.3, 0.6, 1 },
                    { 1, 0.5, 1 }, { 1, 1, 1 }, { 0.5, 1, 1 }, { 1, 0.6, 0.2 } }
  for i = 1, 48 do
    self.confetti[i] = { x = math.random(0, 255), y = -math.random(0, 192), vy = 0.6 + math.random() * 0.8,
                         phase = math.random() * 6.28, colour = colours[(i - 1) % 8 + 1] }
  end
end

-- ---------------------------------------------------------------- update --
function HoF:update(dt)
  local input = self.game.input
  if self.waitingForButton and input and (input:wasPressed("a") or input:wasPressed("b")) then
    self.waitingForButton = false
  end
  self.acc = self.acc + (dt or 1 / 60) * 60
  while self.acc >= 1 do
    self.acc = self.acc - 1
    for _, l in ipairs(self.lights) do
      l.angle = l.angle + l.speed * l.dir
      if l.angle >= 170 then l.angle, l.dir = 170, -1 elseif l.angle <= 10 then l.angle, l.dir = 10, 1 end
    end
    for _, c in ipairs(self.confetti or {}) do
      c.y = c.y + c.vy
      c.phase = c.phase + 0.1
      if c.y > 196 then c.y = -4 end
    end
    if coroutine.status(self.co) ~= "dead" then
      local ok, err = coroutine.resume(self.co)
      if not ok then
        require("src.core.Logger").warn("gen4 hall of fame: %s", tostring(err))
        self.done = true
      end
    end
    if self.done then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
      return
    end
  end
end

-- ------------------------------------------------------------------ draw --
function HoF:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local stage = self:art(self.stage)
  if stage then g.draw(stage, 0, 0) end
  -- the spotlights
  g.setColor(1, 1, 0.55, 0.18)
  for _, l in ipairs(self.lights) do
    local a = math.rad(l.angle)
    local len = 260
    local dx, dy = math.cos(a), math.sin(a)
    local spread = math.rad(5)
    local ax, ay = math.cos(a - spread), math.sin(a - spread)
    local bx, by = math.cos(a + spread), math.sin(a + spread)
    g.polygon("fill", l.x, -8, l.x + ax * len, -8 + ay * len, l.x + bx * len, -8 + by * len)
    local _ = dx + dy
  end
  g.setColor(1, 1, 1, 1)
  for _, s in ipairs(self.sprites) do
    if s.img then
      local w, h = s.img:getDimensions()
      g.draw(s.img, math.floor(s.x), math.floor(s.y), 0, 1, 1, math.floor(w / 2), math.floor(h / 2))
    end
  end
  -- BG2 over everything outside the window
  local overlay = self:art("hof_overlay")
  local w = self.window
  local x0, y0 = math.max(0, math.floor(w.x0)), math.max(0, math.floor(w.y0))
  local x1, y1 = math.min(256, math.floor(w.x1)), math.min(192, math.floor(w.y1))
  local function cover(x, y, ww, hh)
    if ww <= 0 or hh <= 0 then return end
    if overlay then
      g.setScissor(x, y, ww, hh)
      g.draw(overlay, 0, 0)
      g.setScissor()
    else
      g.setColor(0, 0, 0, 1); g.rectangle("fill", x, y, ww, hh); g.setColor(1, 1, 1, 1)
    end
  end
  if x1 <= x0 or y1 <= y0 then cover(0, 0, 256, 192)
  else
    cover(0, 0, 256, y0)
    cover(0, y1, 256, 192 - y1)
    cover(0, y0, x0, y1 - y0)
    cover(x1, y0, 256 - x1, y1 - y0)
  end
  for _, c in ipairs(self.confetti or {}) do
    g.setColor(c.colour[1], c.colour[2], c.colour[3], 1)
    g.rectangle("fill", c.x + math.sin(c.phase) * 3, c.y, 3, math.abs(math.cos(c.phase)) * 3 + 1)
  end
  -- BG1, the text
  local colours = (self.data.gen4_ending or {}).hofText
  local ink = colours and { colours.ink[1] / 255, colours.ink[2] / 255, colours.ink[3] / 255 } or { 0.87, 0.87, 0.9 }
  local shadow = colours and { colours.shadow[1] / 255, colours.shadow[2] / 255, colours.shadow[3] / 255 } or { 0.29, 0.29, 0.32 }
  Font.pushStyle({ text = ink, shadow = shadow })
  for _, l in ipairs(self.lines) do
    local width = Font.width(l.text or "")
    local x = l.full and math.floor((256 - width) / 2) or ((self.column or 0) + math.floor((136 - width) / 2))
    Font.draw(l.text or "", x, l.y - math.floor(self.scroll))
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

return HoF
