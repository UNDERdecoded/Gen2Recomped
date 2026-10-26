-- POKE TRANSFER'S SCREEN (src/world/Gen5PokeTransfer.lua has the rules).
--
--   source   which Generation IV save is the "other DS" (skipped when the
--            Monster Walker's Transfer page already chose the six)
--   pick     six from its PC; the Monster Walker's catches are one more box
--   shoot    the six hop about the field; aim the slingshot (LEFT / RIGHT)
--            and fire (A). One hit catches. Whatever is left when the
--            clock runs out is caught anyway, for no points.
--   done     the score, the six into the PC, and back to the lab's script
--
-- The field, slingshot and balls are drawn by the port; the Pokemon are the
-- game's own front pictures.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local S = {}
S.__index = S
S.isOpaque = true

local W, H = 256, 192
S.ROWS = 9
S.SLING = { x = 128, y = 178 }
S.AIM_RATE = math.rad(90)        -- per second, held
S.AIM_LIMIT = math.rad(70)
S.BALL_SPEED = 260               -- px / s
S.HIT = 18                       -- px from a Pokemon's centre
S.RELOAD = 0.35

function S:uiSize() return W, H end
function S:wantsFillScale() return true end

local function T() return require("src.world.Gen5PokeTransfer") end

function S.new(game, onDone)
  local self = setmetatable({ game = game, onDone = onDone, phase = "source",
                              index = 1, scroll = 0, box = 1, picks = {} }, S)
  local st = T().store(game.save)
  if st and type(st.pending) == "table" and #st.pending >= T().MONS then
    for i, mon in ipairs(st.pending) do self.picks[i] = { mon = mon, species = mon.species } end
    self:startShoot()
  else
    self.sources = T().sources()
  end
  return self
end

function S:say(text, after)
  self.game.stack:push(TextBox.new(self.game, text, after))
end

function S:ask(text, onYes, onNo)
  self.game.stack:push(TextBox.new(self.game, text, nil, { choice = function(yes)
    if yes then onYes() elseif onNo then onNo() end
  end }))
end

function S:close(status, score)
  if status then
    local st = T().store(self.game.save)
    st.last = { status = status, score = score or 0 }
  end
  for i = #self.game.stack.states, 1, -1 do
    if self.game.stack.states[i] == self then table.remove(self.game.stack.states, i) break end
  end
  if self.onDone then local f = self.onDone; self.onDone = nil; f() end
end

-- ---------------------------------------------------------------- picking

function S:loadSource(src)
  local Link = require("src.pokewalker.WalkerLink")
  local CG = require("src.pokemon.CrossGen")
  local mons, why = Link.boxMons(src.version, src.slot)
  if not mons then return self:say(Strings(tostring(why))) end
  self.src = src
  self.srcData = CG.sourceData(src.version)
  self.boxes, self.boxOrder = {}, {}
  for _, e in ipairs(mons) do
    local b = e.source.box
    if not self.boxes[b] then self.boxes[b] = {}; self.boxOrder[#self.boxOrder + 1] = b end
    local def = self.game.data.pokemon[e.species]
    e.label = (e.raw.nickname and e.raw.nickname ~= "" and e.raw.nickname) or (def and def.name) or e.name
    table.insert(self.boxes[b], e)
  end
  table.sort(self.boxOrder)
  local walker = CG.walkerEntries(self.game)
  if #walker > 0 then
    self.boxes.walker = walker
    self.boxOrder[#self.boxOrder + 1] = "walker"
  end
  self.box, self.index, self.scroll = 1, 1, 0
  self.phase = "pick"
end

function S:current()
  local b = self.boxOrder and self.boxOrder[self.box]
  return b and self.boxes[b] or {}, b
end

function S:picked(e)
  for i, p in ipairs(self.picks) do if p == e then return i end end
end

local function refusal(reason)
  if reason == "egg" then return Strings("An Egg cannot be transferred.") end
  if reason == "item" then return Strings("A Pokémon holding an item cannot\nbe transferred.") end
  if reason == "hm" then return Strings("This Pokémon knows a hidden move.\nIt cannot be transferred.") end
  return Strings("This Pokémon cannot be transferred.")
end

function S:toggle(e)
  local at = self:picked(e)
  if at then table.remove(self.picks, at) return end
  if #self.picks >= T().MONS then return end
  if not e.walker then
    local why = T().refusal(self.srcData, e.raw)
    if why then return self:say(refusal(why)) end
  end
  self.picks[#self.picks + 1] = e
  if #self.picks == T().MONS then
    self:ask(Strings("Once you bring a Pokémon here, you\ncan't send it back. Transfer these six?"),
      function() self:startShoot() end, function() table.remove(self.picks) end)
  end
end

-- ---------------------------------------------------------------- shooting

local function frontImage(game, species)
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  if not okS then return nil end
  local okP, path = pcall(Sprites.path, game.data, species, "front", { kind = "battle" })
  if not (okP and path) then return nil end
  local okI, img = pcall(require("src.render.Assets").image, path)
  return okI and img or nil
end

function S:startShoot()
  self.phase = "shoot"
  self.time = T().SECONDS
  self.aim = 0
  self.ball = nil
  self.reload = 0
  self.byHand = 0
  self.targets = {}
  for i, p in ipairs(self.picks) do
    local species = p.species or (p.mon and p.mon.species) or (p.entry and p.entry.species)
    self.targets[i] = {
      pick = p, image = frontImage(self.game, tonumber(species) or species),
      x = 30 + (i - 1) * 39, y = 52 + (i % 3) * 22, vx = (i % 2 == 0) and 34 or -30, vy = 0,
      hop = math.random() * 6, turn = 0.6 + math.random() * 1.4,
    }
  end
end

function S:catch(t, byHand)
  t.caught = true
  t.wobble = 0.6
  if byHand then self.byHand = self.byHand + 1 end
  pcall(function() require("src.core.Sound").play(self.game.data, "Caught_Mon") end)
end

function S:loose()
  local n = 0
  for _, t in ipairs(self.targets) do if not t.caught then n = n + 1 end end
  return n
end

function S:endShoot()
  if self.phase ~= "shoot" then return end
  local left = self.time
  for _, t in ipairs(self.targets) do if not t.caught then self:catch(t, false) end end
  self.phase = "done"
  local score = T().score(self.byHand, left)
  self.score = score
  local status = T().STATUS.caught
  local ok, why = T().finish(self.game, self.picks, status, score)
  if not ok then
    return self:say(Strings("The transfer failed (%s).", tostring(why)), function()
      self:close(T().STATUS.error, 0)
    end)
  end
  self:say(Strings("Transfer complete!\nScore: %d", score), function() self:close() end)
end

function S:updateShoot(dt)
  local input = self.game.input
  self.time = math.max(0, self.time - dt)
  if input then
    if input:isDown("left") then self.aim = math.max(-S.AIM_LIMIT, self.aim - S.AIM_RATE * dt) end
    if input:isDown("right") then self.aim = math.min(S.AIM_LIMIT, self.aim + S.AIM_RATE * dt) end
    self.reload = math.max(0, self.reload - dt)
    if input:wasPressed("a") and not self.ball and self.reload <= 0 then
      self.ball = { x = S.SLING.x, y = S.SLING.y - 8, dx = math.sin(self.aim), dy = -math.cos(self.aim), t = 0 }
      pcall(function() require("src.core.Sound").play(self.game.data, "Ball_Toss") end)
    end
  end
  for _, t in ipairs(self.targets) do
    if t.caught then
      t.wobble = math.max(0, (t.wobble or 0) - dt)
    else
      t.hop = t.hop + dt * 6
      t.turn = t.turn - dt
      if t.turn <= 0 then
        t.vx = (math.random() < 0.5 and -1 or 1) * (24 + math.random() * 36)
        t.vy = (math.random() - 0.5) * 30
        t.turn = 0.5 + math.random() * 1.5
      end
      t.x = t.x + t.vx * dt
      t.y = t.y + t.vy * dt
      if t.x < 20 then t.x, t.vx = 20, math.abs(t.vx) end
      if t.x > W - 20 then t.x, t.vx = W - 20, -math.abs(t.vx) end
      if t.y < 44 then t.y, t.vy = 44, math.abs(t.vy) end
      if t.y > 128 then t.y, t.vy = 128, -math.abs(t.vy) end
    end
  end
  local b = self.ball
  if b then
    b.t = b.t + dt
    b.x = b.x + b.dx * S.BALL_SPEED * dt
    b.y = b.y + b.dy * S.BALL_SPEED * dt
    for _, t in ipairs(self.targets) do
      if not t.caught then
        local cy = t.y - math.abs(math.sin(t.hop)) * 6
        if (b.x - t.x) ^ 2 + (b.y - cy) ^ 2 <= S.HIT ^ 2 then
          self:catch(t, true)
          self.ball, self.reload = nil, S.RELOAD
          break
        end
      end
    end
    if self.ball and (b.y < 20 or b.x < -8 or b.x > W + 8) then self.ball, self.reload = nil, S.RELOAD end
  end
  if self:loose() == 0 or self.time <= 0 then self:endShoot() end
end

-- ---------------------------------------------------------------- update

function S:update(dt)
  dt = dt or 1 / 60
  local input = self.game.input
  if self.phase == "shoot" then return self:updateShoot(dt) end
  if not input then return end
  if self.phase == "source" then
    local n = #self.sources + 1
    if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1 end
    if input:wasPressed("down") and self.index < n then self.index = self.index + 1 end
    if input:wasPressed("a") then
      local src = self.sources[self.index]
      if src then self:loadSource(src) else self:close(T().STATUS.cancelled) end
    elseif input:wasPressed("b") then
      self:close(T().STATUS.cancelled)
    end
  elseif self.phase == "pick" then
    local list = self:current()
    if input:wasPressed("left") and self.box > 1 then self.box, self.index, self.scroll = self.box - 1, 1, 0 end
    if input:wasPressed("right") and self.box < #self.boxOrder then self.box, self.index, self.scroll = self.box + 1, 1, 0 end
    if input:wasPressed("up") and self.index > 1 then self.index = self.index - 1 end
    if input:wasPressed("down") and self.index < #list then self.index = self.index + 1 end
    if self.index < self.scroll + 1 then self.scroll = self.index - 1 end
    if self.index > self.scroll + S.ROWS then self.scroll = self.index - S.ROWS end
    if input:wasPressed("a") and list[self.index] then self:toggle(list[self.index]) end
    if input:wasPressed("b") then
      if #self.picks > 0 then table.remove(self.picks) else self.phase, self.index = "source", 1 end
    end
  end
end

-- ---------------------------------------------------------------- draw

local function window(x, y, w, h)
  local g = love.graphics
  g.setColor(0.97, 0.97, 0.97, 1); g.rectangle("fill", x, y, w, h, 3, 3)
  g.setColor(0.25, 0.3, 0.38, 1); g.setLineWidth(2); g.rectangle("line", x + 1, y + 1, w - 2, h - 2, 3, 3)
  g.setLineWidth(1)
end

local function ink() love.graphics.setColor(0.2, 0.2, 0.2, 1) end

function S:drawSource()
  window(8, 6, 240, 22); ink()
  Font.draw(Strings("Transfer from which game?"), 16, 11)
  window(8, 32, 240, 154)
  for i = 1, #self.sources + 1 do
    local y = 38 + (i - 1) * 16
    if y > 172 then break end
    if i == self.index then love.graphics.setColor(0.55, 0.75, 1, 0.6); love.graphics.rectangle("fill", 12, y - 2, 232, 15) end
    ink()
    local s = self.sources[i]
    Font.draw(s and (tostring(s.title) .. "  " .. tostring(s.label or s.name or s.slot)) or Strings("CANCEL"), 18, y)
  end
end

function S:drawPick()
  local list, b = self:current()
  window(8, 6, 240, 22); ink()
  Font.draw(b == "walker" and Strings("MONSTER WALKER") or Strings("BOX %d", b or 0), 16, 11)
  local count = ("%d/6"):format(#self.picks)
  Font.draw(count, 240 - (Font.width and Font.width(count) or 24), 11)
  window(8, 32, 240, 154)
  for row = 1, S.ROWS do
    local i = self.scroll + row
    local e = list[i]
    if not e then break end
    local y = 38 + (row - 1) * 16
    if i == self.index then love.graphics.setColor(0.55, 0.75, 1, 0.6); love.graphics.rectangle("fill", 12, y - 2, 232, 15) end
    ink()
    if self:picked(e) then Font.draw("*", 18, y) end
    Font.draw(tostring(e.label or "?"), 30, y)
    Font.draw(Strings("Lv.%d", tonumber(e.level) or 1), 196, y)
  end
end

function S:drawShoot()
  local g = love.graphics
  -- sky, hills, the meadow
  g.setColor(0.55, 0.8, 1, 1); g.rectangle("fill", 0, 0, W, 40)
  g.setColor(0.42, 0.72, 0.38, 1); g.ellipse("fill", 60, 44, 90, 18); g.ellipse("fill", 200, 46, 100, 16)
  g.setColor(0.48, 0.8, 0.4, 1); g.rectangle("fill", 0, 40, W, H - 40)
  g.setColor(0.4, 0.7, 0.33, 1)
  for i = 0, 9 do g.ellipse("fill", 14 + i * 26, 140 + (i % 2) * 4, 16, 6) end
  -- the six, back to front
  local order = {}
  for _, t in ipairs(self.targets) do order[#order + 1] = t end
  table.sort(order, function(a, b) return a.y < b.y end)
  for _, t in ipairs(order) do
    local lift = t.caught and 0 or math.abs(math.sin(t.hop)) * 6
    local s = 0.5 + (t.y - 44) / 84 * 0.25
    if t.caught then
      if (t.wobble or 0) > 0 then
        local wob = math.sin((t.wobble or 0) * 30) * 3
        g.setColor(0.9, 0.15, 0.15, 1); g.circle("fill", t.x + wob, t.y - 6, 6)
        g.setColor(1, 1, 1, 1); g.rectangle("fill", t.x + wob - 6, t.y - 6, 12, 2)
      end
    else
      g.setColor(0, 0, 0, 0.2); g.ellipse("fill", t.x, t.y + 2, 12 * s * 2, 4)
      g.setColor(1, 1, 1, 1)
      if t.image then
        local iw, ih = t.image:getDimensions()
        g.draw(t.image, t.x, t.y - lift, 0, s, s, iw / 2, ih)
      else
        g.setColor(0.9, 0.5, 0.2, 1); g.circle("fill", t.x, t.y - 10 - lift, 10)
      end
    end
  end
  -- the ball in flight
  if self.ball then
    g.setColor(0.9, 0.15, 0.15, 1); g.circle("fill", self.ball.x, self.ball.y, 4)
    g.setColor(1, 1, 1, 1); g.arc("fill", self.ball.x, self.ball.y, 4, 0, math.pi)
  end
  -- the slingshot and its aim
  local sx, sy = S.SLING.x, S.SLING.y
  g.setColor(1, 1, 1, 0.5)
  for k = 1, 6 do
    g.circle("fill", sx + math.sin(self.aim) * k * 10, sy - 8 - math.cos(self.aim) * k * 10, 1.5)
  end
  g.setColor(0.45, 0.28, 0.15, 1)
  g.setLineWidth(3)
  g.line(sx, sy + 12, sx, sy); g.line(sx, sy, sx - 8, sy - 10); g.line(sx, sy, sx + 8, sy - 10)
  g.setLineWidth(1)
  if not self.ball and self.reload <= 0 then
    g.setColor(0.9, 0.15, 0.15, 1); g.circle("fill", sx, sy - 8, 4)
  end
  -- the clock and the count
  window(4, 4, 92, 18); ink()
  Font.draw(Strings("TIME %02d", math.ceil(self.time)), 10, 8)
  window(W - 96, 4, 92, 18); ink()
  Font.draw(Strings("CAUGHT %d/6", T().MONS - self:loose()), W - 90, 8)
end

function S:draw()
  local g = love.graphics
  g.setColor(0.3, 0.5, 0.9, 1)
  g.rectangle("fill", 0, 0, W, H)
  if self.phase == "source" then self:drawSource()
  elseif self.phase == "pick" then self:drawPick()
  elseif self.phase == "shoot" or self.phase == "done" then self:drawShoot() end
  g.setColor(1, 1, 1, 1)
end

return S
