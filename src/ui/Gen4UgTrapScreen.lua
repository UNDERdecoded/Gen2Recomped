-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- A SPRUNG UNDERGROUND TRAP, single player (pokeplatinum src/underground/
-- traps.c; src/comm_player_manager.c "CPM").
--
-- READ FROM CODE:
--   * every trap opens with SEQ_SE_DP_UG_007, "!" and common 70 "Oops!
--     <trap>!" (traps.c 1708, 1735, 2140-2152), the field paused; it ends
--     with common 98 "<player> escaped from the Trap." -- not for the alerts
--     (2623-2631);
--   * MOVE / HURL (2007-2051; CPM 1102-1187, 666-675): after 28 frames the
--     player slides away facing back where they came from, up to 25 / 43
--     tiles, stopping before anything solid, 2 frames a tile while 10 or more
--     are left, 4 while 5..9, 8 below (SEQ_SE_DP_F007);
--   * HOLE / PIT (3160-3170, CPM 757-779): only turning works; each turn to
--     another direction counts; 8 / 18 turns climb out (SEQ_SE_DP_BOX02 a
--     turn, SEQ_SE_DP_DANSA out);
--   * REVERSE / CONFUSE (1979-1989, CPM 793-801, communication_system.c
--     1081-1139): the d-pad reversed / a random direction held for
--     Rand(16) frames, until 30 steps have been taken;
--   * SMOKE / BIG SMOKE (2295-2452): rubbing adds 3 to the 8x8 tile under
--     the stylus, 2 to its four neighbours, 1 to the diagonals; a tile past 5
--     is clear; out when fewer than 13 tiles are left (SEQ_SE_DP_UG_025);
--   * ROCK / ROCKFALL (4040-4293): the boulder falls to y 65; a tap within
--     48 px adds a point (SEQ_SE_DP_UG_023) from 5 / -1; past 15 it breaks
--     (SEQ_SE_DP_UG_026) -- 11 / 17 taps; its look every 3 points;
--   * FOAM / BUBBLE (3583-3880): 7 / 20 bubbles (radius 32 / 28 / 24) drift
--     about a pixel a frame and bounce; a tap pops one (SEQ_SE_DP_UG_022);
--   * ALERT 1..4 (4722-4737): its message (117..120), 30 frames, over;
--   * LEAF / FLOWER, EMBER / FIRE are blown away with the MICROPHONE
--     (3336-3516, 4453-4486): 16 leaves / 32 petals pushed out from the
--     centre; a flame of 2 / 4 that drops a step every 10 frames of steady
--     blowing and comes back when the blowing stops.
-- The pictures are gen4_ug_trap_art's (src/import/Gen4UgTrapArt.lua).
-- INFERRED / THE PORT'S OWN:
--   * there is no microphone here: A (or a held touch) is the breath;
--   * the hole, the boulder's shadow and the smoke are drawn with the
--     imported pictures where there are some (underground/*), flat shapes
--     otherwise; the smoke's starting tiles are the opaque cells of the
--     pattern picture.

local Font = require("src.render.Font")
local Pockets = require("src.ui.Gen4UgPockets")

local S = {}
S.__index = S
S.isOpaque = false
function S:uiSize() return 256, 192 end

local function W() return require("src.world.Gen4UgWorld") end

S.KIND = {
  [1] = "move", [2] = "move", [3] = "move", [4] = "move",
  [5] = "hurl", [6] = "hurl", [7] = "hurl", [8] = "hurl",
  [11] = "hole", [12] = "pit", [13] = "reverse", [14] = "confuse",
  [18] = "smoke", [19] = "bigsmoke", [20] = "rock", [21] = "rockfall",
  [22] = "foam", [23] = "bubble", [24] = "alert", [25] = "alert", [26] = "alert", [27] = "alert",
  [28] = "leaf", [29] = "flower", [30] = "ember", [31] = "fire",
}
S.SLIDE_DIR = { [1] = "up", [2] = "right", [3] = "down", [4] = "left",
                [5] = "up", [6] = "right", [7] = "down", [8] = "left" }

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

local function rand(n)
  if n <= 0 then return 0 end
  if love and love.math then return love.math.random(0, n - 1) end
  return math.random(0, n - 1)
end

function S.new(game, ow, trapId, onDone)
  local self = setmetatable({ game = game, ow = ow, id = trapId, kind = S.KIND[trapId] or "alert",
    onDone = onDone, t = 0, phase = "oops", images = {} }, S)
  local name = Pockets.trapName(game, trapId)
  self.oops = Pockets.text(game, W().BANK.common, 70, { [0] = name })
  se(self, "SEQ_SE_DP_UG_007")
  return self
end

-- a picture: gen4_ug_trap_art first (Gen4UgTrapArt, the right palettes),
-- else the generic archive pass's underground/<name>
function S:art() return (self.game.data or {}).gen4_ug_trap_art end
function S:img(name)
  if self.images[name] == nil then
    local art = self:art()
    local own = art and art.sprites and art.sprites[name]
    local rec = own or (((self.game.data or {}).gen4_graphics or {}).screens or {})["underground/" .. name]
    local path = type(rec) == "table" and rec.path or rec
    local ok, im = false, nil
    if type(path) == "string" then ok, im = pcall(require("src.render.Assets").image, path) end
    if ok and im then im:setFilter("nearest", "nearest") end
    self.images[name] = ok and im or false
  end
  return self.images[name] or nil
end

function S:playerName()
  local s = self.game.save or {}
  return (s.player and s.player.name) or s.playerName or ""
end

-- the end: 98 (not for an alert), then the field
function S:escape()
  if self.phase == "escaped" or self.phase == "done" then return end
  if self.kind == "alert" then return self:finish() end
  self.phase = "escaped"
  self.msg = Pockets.text(self.game, W().BANK.common, 98, { [0] = self:playerName() })
  self.t = 0
end

function S:finish()
  if self.phase == "done" then return end
  self.phase = "done"
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

-- --------------------------------------------------------------- setups --

function S:start()
  local k = self.kind
  self.phase = "play"
  self.t = 0
  if k == "move" or k == "hurl" then return self:slide() end
  if k == "hole" or k == "pit" then
    self.turnsLeft = (k == "hole") and 8 or 18
    self.msg = nil
  elseif k == "reverse" or k == "confuse" then
    W().altered(self.game, k, 30)
    return self:finish()
  elseif k == "smoke" or k == "bigsmoke" then
    self:initSmoke(k == "bigsmoke")
    self.msg = Pockets.text(self.game, W().BANK.common, 77)
  elseif k == "rock" or k == "rockfall" then
    self.damage = (k == "rock") and 5 or -1
    self.rockY, self.rockV = 0, 5
    self.msg = Pockets.text(self.game, W().BANK.common, 77)
    se(self, "SEQ_SE_DP_FW466")
  elseif k == "foam" or k == "bubble" then
    self:initBubbles(k == "bubble")
    self.msg = Pockets.text(self.game, W().BANK.common, 77)
    se(self, "SEQ_SE_DP_FAWA")
  elseif k == "leaf" or k == "flower" then
    self.bits = {}
    for i = 1, (k == "leaf") and 16 or 32 do
      self.bits[i] = { x = rand(240) + 8, y = rand(176) + 8, frame = rand(3) }
    end
    self.msg = Pockets.text(self.game, W().BANK.common, 76)
  elseif k == "ember" or k == "fire" then
    self.flame = (k == "ember") and 2 or 4
    self.flameMax = self.flame
    self.blow = 0
    self.msg = Pockets.text(self.game, W().BANK.common, 76)
  elseif k == "alert" then
    self.msg = Pockets.text(self.game, W().BANK.common, 117 + (self.id - 24), { [0] = self:playerName() })
  end
end

-- MOVE / HURL: a scripted walk, facing locked the other way
function S:slide()
  local ow = self.ow
  local p = ow and ow.player
  local dir = S.SLIDE_DIR[self.id]
  if not (p and dir) then return self:escape() end
  local maxTiles = (self.kind == "hurl") and 43 or 25
  local start = (self.kind == "hurl") and 45 or 27
  local d = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local back = { up = 1, down = 0, left = 3, right = 2 }    -- face actions (N S W E)
  local base = { up = 0, down = 1, left = 2, right = 3 }
  local x, y = p.cellX, p.cellY
  local steps = { { action = back[dir], count = 1 }, { action = 71, count = 1 } }
  local n = 0
  for k = 1, maxTiles do
    local nx, ny = x + d[dir][1], y + d[dir][2]
    local walk = ow.map.isWalkableCell and ow.map:isWalkableCell(nx, ny)
    if not walk or W().blockedTile(self.game, ow, nx, ny) then break end
    x, y = nx, ny
    n = k
    local left = start - k
    local speed = left >= 10 and 20 or (left >= 5 and 16 or 12)
    steps[#steps + 1] = { action = speed + base[dir], count = 1 }
    if W().trapAt(self.game.save, x, y) then break end      -- traps chain (traps.c 1636-1641)
  end
  steps[#steps + 1] = { action = 72, count = 1 }
  se(self, "SEQ_SE_DP_F007")
  self:finish()
  local game = self.game
  local name = self:playerName()
  if ow.runner and n > 0 then
    ow.runner:run({
      { "g4_move", 255, steps },
      { "g4_wait_movement" },
      { "g4_ug_after_slide", name },
    }, { mapId = ow.map.id })
  end
  return
end

-- SMOKE: a 32 x 24 grid of 8 px tiles, a value per smoky tile
function S:initSmoke(big)
  local which = big and "big" or tostring(rand(4) + 1)
  local art = self:art()
  local grid = art and art.smoke and art.smoke[which]
  if grid then
    -- the map's own tile numbers are the starting smoke (traps.c 2472-2488)
    self.smoke = {}
    for ty = 0, 23 do
      local tx = 0
      for v in tostring(grid[ty + 1] or ""):gmatch("[^,]+") do
        local n = tonumber(v) or 0
        if n > 0 and n <= 5 then self.smoke[ty * 32 + tx] = n end
        tx = tx + 1
      end
    end
    self.smokeStrip = self:img("smoke_tiles")
    return
  end
  local key = big and "big_smoke_pattern" or ("smoke_pattern_" .. which)
  self.smokeImg = self:img(key)
  self.smoke = {}
  local data
  local rec = (((self.game.data or {}).gen4_graphics or {}).screens or {})["underground/" .. key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) == "string" then
    local ok, d = pcall(require("src.render.Assets").imageData, path)
    data = ok and d or nil
  end
  for ty = 0, 23 do
    for tx = 0, 31 do
      local on
      if data then
        local _, _, _, a = data:getPixel(math.min(data:getWidth() - 1, tx * 8 + 4), math.min(data:getHeight() - 1, ty * 8 + 4))
        on = a > 0
      else
        on = big or ((tx + ty) % 3 ~= 0)
      end
      if on then self.smoke[ty * 32 + tx] = 1 end
    end
  end
end

function S:smokeLeft()
  local n = 0
  for _, v in pairs(self.smoke) do if v > 0 then n = n + 1 end end
  return n
end

local function addSmoke(self, tx, ty, by)
  if tx < 0 or ty < 0 or tx > 31 or ty > 23 then return end
  local i = ty * 32 + tx
  local v = self.smoke[i]
  if not v or v == 0 then return end
  v = v + by
  if v > 5 then v = 0 end
  self.smoke[i] = v
end

function S:rub(x, y)
  local fromX, fromY = self.lastRub and self.lastRub[1] or x, self.lastRub and self.lastRub[2] or y
  self.lastRub = { x, y }
  local steps = math.max(1, math.floor(math.max(math.abs(x - fromX), math.abs(y - fromY))))
  for s = 0, steps do
    local px = fromX + (x - fromX) * s / steps
    local py = fromY + (y - fromY) * s / steps
    local tx, ty = math.floor(px / 8), math.floor(py / 8)
    addSmoke(self, tx, ty, 3)
    addSmoke(self, tx - 1, ty, 2); addSmoke(self, tx + 1, ty, 2); addSmoke(self, tx, ty - 1, 2); addSmoke(self, tx, ty + 1, 2)
    addSmoke(self, tx - 1, ty - 1, 1); addSmoke(self, tx + 1, ty - 1, 1); addSmoke(self, tx - 1, ty + 1, 1); addSmoke(self, tx + 1, ty + 1, 1)
  end
  se(self, "SEQ_SE_DP_UG_025")
  if self:smokeLeft() < 13 then self:escape() end
end

function S:initBubbles(big)
  self.bubbles = {}
  local n = big and 20 or 7
  local large = big and (rand(2) + 1) or 0
  local medium = rand(3) + large + 5
  for i = 1, n do
    local r = (i <= large) and 32 or (i <= medium and 28 or 24)
    local a = rand(360) * math.pi / 180
    self.bubbles[i] = { x = rand(256 - 2 * r) + r, y = rand(192 - 2 * r) + r, r = r, dx = math.cos(a), dy = math.sin(a) }
  end
end

-- a tap at (x, y)
function S:tap(x, y)
  if self.phase ~= "play" then return end
  local k = self.kind
  if k == "rock" or k == "rockfall" then
    if self.rockY < 65 or self.broken then return end
    local dx, dy = x - 128, y - self.rockY
    if dx * dx + dy * dy <= 48 * 48 then
      self.damage = self.damage + 1
      self.shake = 4
      se(self, "SEQ_SE_DP_UG_023")
      if self.damage > 15 then
        se(self, "SEQ_SE_DP_UG_026")
        self.broken = 75
      end
    end
  elseif k == "foam" or k == "bubble" then
    for i, b in ipairs(self.bubbles) do
      local dx, dy = x - b.x, y - b.y
      if dx * dx + dy * dy <= b.r * b.r then
        table.remove(self.bubbles, i)
        se(self, "SEQ_SE_DP_UG_022")
        break
      end
    end
    if #self.bubbles == 0 then self:escape() end
  elseif k == "smoke" or k == "bigsmoke" then
    self.lastRub = nil
    self:rub(x, y)
  end
end

-- a breath (the microphone's stand-in)
function S:breathe(on)
  local k = self.kind
  if k == "leaf" or k == "flower" then
    if not on then return end
    local push = (k == "leaf") and 4 or 3
    local keep = {}
    for _, b in ipairs(self.bits) do
      local dx, dy = b.x - 128, b.y - 96
      local len = math.max(1, math.sqrt(dx * dx + dy * dy))
      b.x, b.y = b.x + dx / len * push, b.y + dy / len * push
      if b.x > -16 and b.x < 272 and b.y > -16 and b.y < 208 then keep[#keep + 1] = b end
    end
    self.bits = keep
    if #keep == 0 then self:escape() end
  elseif k == "ember" or k == "fire" then
    if on then
      self.blow = self.blow + 1
      if self.blow % 10 == 9 then
        self.flame = self.flame - 1
        se(self, "SEQ_SE_DP_UG_024")
      end
      if self.flame <= 0 then self:escape() end
    else
      -- the state resets: the flame comes back (traps.c 4462-4486)
      self.blow = 0
      self.flame = self.flameMax
    end
  end
end

-- ------------------------------------------------------------------ loop --

local DIRS = { "up", "down", "left", "right" }

function S:update()
  local input = self.game.input
  self.t = self.t + 1
  if self.phase == "oops" then
    -- the field stays paused through the message (about 30 frames; 28 for a slide)
    if self.t >= ((self.kind == "move" or self.kind == "hurl") and 28 or 30) then self:start() end
    return
  end
  if self.phase == "escaped" then
    if input:wasPressed("a") or input:wasPressed("b") or self.t > 90 then self:finish() end
    return
  end
  if self.phase ~= "play" then return end
  local k = self.kind
  if k == "hole" or k == "pit" then
    local p = self.ow and self.ow.player
    for _, d in ipairs(DIRS) do
      if input:wasPressed(d) and p and p.facing ~= d then
        p.facing = d
        se(self, "SEQ_SE_DP_BOX02")
        self.turnsLeft = self.turnsLeft - 1
        if self.turnsLeft <= 0 then se(self, "SEQ_SE_DP_DANSA"); return self:escape() end
      end
    end
  elseif k == "rock" or k == "rockfall" then
    if self.rockY < 65 then
      self.rockY = self.rockY + self.rockV
      self.rockV = self.rockV + 3
      if self.rockY >= 65 then self.rockY = 65; se(self, "SEQ_SE_DP_FW452") end
    end
    if self.shake and self.shake > 0 then self.shake = self.shake - 1 end
    if self.broken then
      self.broken = self.broken - 1
      if self.broken <= 0 then return self:escape() end
    end
    if input:wasPressed("a") then self:tap(128, self.rockY) end
  elseif k == "foam" or k == "bubble" then
    for _, b in ipairs(self.bubbles) do
      b.x, b.y = b.x + b.dx, b.y + b.dy
      if b.x < b.r or b.x > 256 - b.r then b.dx = -b.dx end
      if b.y < b.r or b.y > 192 - b.r then b.dy = -b.dy end
    end
    if input:wasPressed("a") and self.bubbles[1] then self:tap(self.bubbles[1].x, self.bubbles[1].y) end
  elseif k == "smoke" or k == "bigsmoke" then
    if input:wasPressed("a") then
      -- a pad's rub: across the smokiest row (the port's own)
      for ty = 0, 23 do
        for tx = 0, 31 do
          if (self.smoke[ty * 32 + tx] or 0) > 0 then self.lastRub = nil; return self:rub(tx * 8 + 4, ty * 8 + 4) end
        end
      end
    end
  elseif k == "leaf" or k == "flower" or k == "ember" or k == "fire" then
    self:breathe(input:isDown("a") or self.touching or false)
  elseif k == "alert" then
    if self.t >= 30 then return self:escape() end
  end
end

local function toUi(px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not rect then return px, py end
  return (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
end

function S:touchpressed(id, px, py)
  local x, y = toUi(px, py)
  self.touching = true
  self:tap(x, y)
  return true
end
function S:touchmoved(id, px, py)
  if self.kind == "smoke" or self.kind == "bigsmoke" then
    local x, y = toUi(px, py)
    if self.phase == "play" then self:rub(x, y) end
  end
  return true
end
function S:touchreleased() self.touching = false; self.lastRub = nil; return true end

-- ------------------------------------------------------------------ draw --

local function ink() Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } }) end

function S:draw()
  local g = love.graphics
  local k = self.kind
  if self.phase == "play" then
    if k == "hole" or k == "pit" then
      g.setColor(0, 0, 0, 0.85)
      g.ellipse("fill", 128, 104, k == "hole" and 14 or 20, k == "hole" and 6 or 9)
    elseif k == "smoke" or k == "bigsmoke" then
      for i, v in pairs(self.smoke) do
        if v > 0 then
          local tx, ty = i % 32, math.floor(i / 32)
          if self.smokeStrip then
            self.stripQuads = self.stripQuads or {}
            local q = self.stripQuads[v]
            if not q then
              q = love.graphics.newQuad(v * 8, 0, 8, 8, self.smokeStrip:getDimensions())
              self.stripQuads[v] = q
            end
            g.setColor(1, 1, 1, 1)
            g.draw(self.smokeStrip, q, tx * 8, ty * 8)
          elseif self.smokeImg then
            self.smokeQuads = self.smokeQuads or {}
            local q = self.smokeQuads[i]
            if not q then
              q = love.graphics.newQuad(tx * 8, ty * 8, 8, 8, self.smokeImg:getDimensions())
              self.smokeQuads[i] = q
            end
            g.setColor(1, 1, 1, 1 - (v - 1) * 0.15)
            g.draw(self.smokeImg, q, tx * 8, ty * 8)
          else
            g.setColor(0.85, 0.85, 0.85, 1 - (v - 1) * 0.15)
            g.rectangle("fill", tx * 8, ty * 8, 8, 8)
          end
        end
      end
    elseif k == "rock" or k == "rockfall" then
      g.setColor(0, 0, 0, 0.4)
      g.ellipse("fill", 128, 110, 30, 8)
      g.setColor(1, 1, 1, 1)
      local stage = math.max(0, math.floor(self.damage / 3))
      local name = stage == 0 and "boulder_00" or ("boulder_damaged_" .. math.min(6, stage) .. "_00")
      local im = self:img(name)
      local sx = (self.shake and self.shake > 0) and ((self.shake % 2 == 0) and 3 or -3) or 0
      if not self.broken then
        if im then g.draw(im, 128 - im:getWidth() / 2 + sx, self.rockY - im:getHeight() / 2)
        else g.setColor(0.5, 0.4, 0.3, 1); g.circle("fill", 128 + sx, self.rockY, 40) end
      end
    elseif k == "foam" or k == "bubble" then
      local im = self:img("bubble_00")
      for _, b in ipairs(self.bubbles) do
        g.setColor(1, 1, 1, 1)
        if im then local s = b.r / 32; g.draw(im, b.x, b.y, 0, s, s, 32, 32)
        else g.setColor(0.7, 0.9, 1, 0.7); g.circle("fill", b.x, b.y, b.r) end
      end
    elseif k == "leaf" or k == "flower" then
      for _, b in ipairs(self.bits) do
        local im = (k == "leaf") and (self:img("leaf_00") or self:img("leaf"))
                   or (self:img("petal_s0_00") or self:img("petal_0" .. b.frame))
        g.setColor(1, 1, 1, 1)
        if im then g.draw(im, b.x - 8, b.y - 8) else g.setColor(0.3, 0.8, 0.3, 1); g.rectangle("fill", b.x - 4, b.y - 4, 8, 8) end
      end
    elseif k == "ember" or k == "fire" then
      local art = self:art()
      local frames = (art and art.counts and art.counts[k]) or 6
      if frames < 1 then frames = 1 end
      local im = self:img(("%s_%02d"):format(k, math.floor(self.t / 6) % frames))
      local scale = 0.5 * self.flame
      g.setColor(1, 1, 1, 1)
      if im then g.draw(im, 128, 100, 0, scale, scale, im:getWidth() / 2, im:getHeight() / 2)
      else g.setColor(1, 0.4, 0.1, 1); g.circle("fill", 128, 100, 8 * self.flame) end
    end
  end
  g.setColor(1, 1, 1, 1)
  local text = (self.phase == "oops") and self.oops or self.msg
  if text and text ~= "" then
    Font.drawDialogueBox(1, 18, 29, 6)
    ink()
    local y = 152
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    Font.popStyle()
  end
  g.setColor(1, 1, 1, 1)
end

return S
