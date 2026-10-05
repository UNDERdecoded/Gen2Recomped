-- PLATINUM'S POFFIN FEEDING CUTSCENE (src/applications/poffin_case/cutscene.c
-- and cutscene_sprite.c), in the cartridge's art (porudemo.narc, the Poffin
-- from poruact.narc) and bank 462's words.
--
-- The top screen: the Pokemon's front sprite at (128, 96), drawn by the 3D
-- engine so it can scale; the bottom screen a still picture. At 60 frames a
-- second, after a fade in from black:
--
--   APPROACH, 24 frames, four things at once:
--     the Poffin rises from (128, 224) to (128, 96) on an arc 64 high
--       (y += sin(t x 180/24) x -64), shrinking 1.0 -> 0.5, gone on the last
--     the Pokemon grows 1.0 -> 1.5 and comes forward to (128, 112), hopping
--       -(16 - (k - 4)^2) x 1.4 for k = 0..8 every nine frames, for 25
--       frames, then 5 still
--   THE CRY (the pinch cry when it dislikes the Poffin)
--   BACK, 8 frames: 1.5 -> 1.0 to (128, 96), a 6-pixel arc; 5 still
--   THE REACTION: three more hops if it liked it (27 frames), a 2-pixel
--     shake for 32 if it did not, nothing if neither
--   THE LINE: #0 "{name} happily ate the Poffin!", #1 "...disdainfully...",
--     #2 "{name} ate the Poffin.", in the message box at tile (2, 19); A or B,
--     or 90 frames after it has printed, closes it; a fade out.
--
-- On the cartridge the stat change is then shown on the summary's Condition
-- page; here the case's own line says what happened.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local Feed = {}
Feed.__index = Feed
Feed.isOpaque = true
Feed.BANK = 462

function Feed:uiSize() return 256, 192 end
function Feed:wantsFillScale() return true end

local function lerp(a, b, k) return a + (b - a) * k end

-- opts = { mon, poffin, taste = "like"|"dislike"|"neutral", onDone }
function Feed.new(game, opts)
  local self = setmetatable({ game = game, data = game.data, mon = opts.mon, poffin = opts.poffin,
    taste = opts.taste or "neutral", onDone = opts.onDone, images = {}, acc = 0, fade = 1 }, Feed)
  self.monX, self.monY, self.monScale = 128, 96, 1
  self.poffinX, self.poffinY, self.poffinScale, self.poffinShown = 128, 224, 1, true
  self.co = coroutine.create(function() self:script() end)
  return self
end

function Feed:art(key)
  local index = self.data and self.data.gen4_poffin_art
  local rec = index and index[key]
  if not rec then return nil end
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil
end

function Feed:monImage()
  if self.monImg == nil then
    local path = require("src.pokemon.Sprites").path(self.data, self.mon.species, "front", { mon = self.mon })
    local ok, img = false, nil
    if path then ok, img = pcall(require("src.render.Assets").image, path) end
    self.monImg = ok and img or false
  end
  return self.monImg or nil
end

local function wait(n) for _ = 1, n do coroutine.yield() end end
local function hop(k) return -(16 - (k - 4) ^ 2) * 1.4 end

function Feed:script()
  for f = 1, 6 do self.fade = 1 - f / 6; coroutine.yield() end
  self.fade = 0
  -- the approach
  for f = 1, 30 do
    if f <= 24 then
      local t = f / 24
      self.poffinX = 128
      self.poffinY = lerp(224, 96, t) + math.sin(math.rad(f * 180 / 24)) * -64
      self.poffinScale = lerp(1, 0.5, t)
      if f == 24 then self.poffinShown = false end
    end
    if f <= 25 then
      local t = math.min(1, f / 25)
      self.monScale = lerp(1, 1.5, math.min(1, f / 24))
      self.monY = lerp(96, 112, t) + hop((f - 1) % 9)
    else
      self.monY = 112
    end
    coroutine.yield()
  end
  -- the cry
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playCry then pcall(Sound.playCry, self.data, self.mon.species) end
  wait(45)
  -- back
  for f = 1, 8 do
    local t = f / 8
    self.monScale = lerp(1.5, 1, t)
    self.monY = lerp(112, 96, t) + math.sin(math.rad(f * 180 / 8)) * -6
    coroutine.yield()
  end
  self.monY = 96
  wait(5)
  -- the reaction
  if self.taste == "like" then
    for f = 0, 26 do self.monY = 96 + hop(f % 9); coroutine.yield() end
    self.monY = 96
  elseif self.taste == "dislike" then
    local steps = { 0, 90, 180, 270, 360 }
    for f = 0, 31 do self.shake = math.sin(math.rad(steps[f % 5 + 1])) * 2; coroutine.yield() end
    self.shake = 0
  end
  -- the line
  local n = self.taste == "like" and 0 or self.taste == "dislike" and 1 or 2
  local def = self.data.pokemon and self.data.pokemon[self.mon.species]
  T.buffer(self.game, self.mon.nickname or (def and def.name) or "?")
  self.message = T.resolve(self.data, Feed.BANK, n, self.game) or ""
  self.waitFrames = 0
  self.waiting = true
  while self.waiting do
    self.waitFrames = self.waitFrames + 1
    if self.waitFrames >= 90 then self.waiting = false end
    coroutine.yield()
  end
  self.message = nil
  for f = 1, 6 do self.fade = f / 6; coroutine.yield() end
  self.done = true
end

function Feed:update(dt)
  local input = self.game.input
  if self.waiting and input and (input:wasPressed("a") or input:wasPressed("b")) then self.waiting = false end
  self.acc = self.acc + (dt or 1 / 60) * 60
  while self.acc >= 1 do
    self.acc = self.acc - 1
    if coroutine.status(self.co) ~= "dead" then
      local okR, err = coroutine.resume(self.co)
      if not okR then require("src.core.Logger").warn("gen4 poffin feed: %s", tostring(err)); self.done = true end
    end
    if self.done then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
      return
    end
  end
end

function Feed:draw()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local top = self:art("feed_top")
  if top then g.draw(top, 0, 0) else g.setColor(1, 0.8, 0.95, 1); g.rectangle("fill", 0, 0, 256, 192); g.setColor(1, 1, 1, 1) end
  local img = self:monImage()
  if img then
    local w, h = img:getDimensions()
    g.draw(img, self.monX + (self.shake or 0), self.monY, 0, self.monScale, self.monScale, w / 2, h / 2)
  end
  if self.poffinShown then
    local p = self:art("poffin_" .. (tonumber(self.poffin and self.poffin.type) or 0))
    if p then
      local w, h = p:getDimensions()
      g.draw(p, self.poffinX, self.poffinY, 0, self.poffinScale, self.poffinScale, w / 2, h / 2)
    end
  end
  if self.message then
    Font.drawDialogueBox(1, 18, 29, 6)
    g.setColor(0, 0, 0, 1)
    local y = 152
    for l in (self.message .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    g.setColor(1, 1, 1, 1)
  end
  if self.fade > 0 then
    g.setColor(0, 0, 0, self.fade)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
  -- the bottom screen, when there is a second one
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  local mode = ok and SS.mode(self.game) or "off"
  if (mode == "display" or mode == "inset") and not SS.stowed(self.game) then
    SS.draw(self.game, function()
      local b = self:art("feed_bottom")
      if b then g.draw(b, 0, 0) end
    end)
  end
end

return Feed
